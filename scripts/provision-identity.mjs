/**
 * Closed-test identity provisioning (PROV-001…012, Amendment 1).
 *
 * Binds a pre-created, email-confirmed Auth identity to exactly one existing
 * gym row (`members.user_id` or `staff.user_id`), refusing every ambiguous
 * case. Pure decision sequence lives in {@link provisionIdentity}; the
 * service-role Supabase adapter is {@link createSupabaseProvisionPort}; the
 * CLI is {@link main}. No password is issued and no product surface is touched.
 */
import { pathToFileURL } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { PROVISION_IDENTITY_LIMITS } from '../packages/shared/src/config/constants.ts';
import { provisioningEnv } from '../packages/shared/src/config/env.ts';

const GYM_CODE_PATTERN = /^[A-Z0-9]{6}$/;
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const LIKE_ESCAPE = /[\\%_]/g;
const FAILURE_MESSAGE = 'Identity provisioning failed.';
const { flagValueStride: FLAG_VALUE_STRIDE, cliArgsStart: CLI_ARGS_START } = PROVISION_IDENTITY_LIMITS;

/** One `@`, non-empty local part, dotted domain, no whitespace (PROV-002). */
function isPlausibleEmail(value) {
  return typeof value === 'string' && EMAIL_PATTERN.test(value.trim());
}

function normalizeEmail(value) {
  return typeof value === 'string' ? value.trim().toLowerCase() : '';
}

/** `a***@example.com` — the only form of an address that ever leaves this tool. */
function redactEmail(value) {
  if (typeof value !== 'string') return null;
  const trimmed = value.trim();
  const at = trimmed.lastIndexOf('@');
  if (at <= 0 || at === trimmed.length - 1) return null;
  const local = trimmed.slice(0, at);
  const domain = trimmed.slice(at + 1);
  if (local.length === 0 || domain.length === 0) return null;
  return `${local[0].toLowerCase()}***@${domain.toLowerCase()}`;
}

function normalizeTarget(value) {
  if (value === null || typeof value !== 'object') return null;
  const { kind, id } = value;
  if ((kind !== 'member' && kind !== 'staff') || typeof id !== 'string') return null;
  return { kind, id };
}

function provisionResult({ ok, code, target, authUser, authUserId, email }) {
  return { ok, code, target, authUser, authUserId, email };
}

function failure(code, target, email, extra = {}) {
  return provisionResult({
    ok: false,
    code,
    target,
    authUser: extra.authUser ?? 'none',
    authUserId: extra.authUserId ?? null,
    email,
  });
}

/** Sum of member/staff/platform bindings; missing fields count as zero. */
function totalBindings(bindings) {
  return Number(bindings?.members ?? 0)
    + Number(bindings?.staff ?? 0)
    + Number(bindings?.platform ?? 0);
}

/** Coerce a port bind result to rows changed (number | boolean | row array | { count }). */
function rowsChanged(changed) {
  if (Array.isArray(changed)) return changed.length;
  if (changed !== null && typeof changed === 'object' && typeof changed.count === 'number') {
    return changed.count;
  }
  return Number(changed);
}

/** PROV-006a: operator-provisioned, or Google-verified with no password identity. */
function isVerifiedIdentity(auth) {
  return auth.provisioned === true
    || (auth.googleVerified === true && auth.hasEmailIdentity === false);
}

function isEligibleMember(row) {
  return row.status !== 'cancelled' && row.status !== 'blocked' && row.erasedAt == null;
}

function isEligibleStaff(row) {
  return row.isActive !== false && row.role !== 'gym_owner';
}

function isEligible(kind, row) {
  return kind === 'member' ? isEligibleMember(row) : isEligibleStaff(row);
}

async function deleteCreatedUser(port, userId, state) {
  if (userId === null || state.deleted) return;
  state.deleted = true;
  try {
    await port.deleteAuthUser(userId);
  } catch {
    // Compensation is best-effort and exactly once; never surface its error.
  }
}

/**
 * Apply phase (PROV-007, PROV-007a, PROV-008, PROV-011). Never throws:
 * create/bind failures become `bind_conflict` after compensation; a failed
 * post-bind verification unbinds this row and compensates before reporting
 * `bind_conflict` (never `linked`).
 */
async function applyProvision(port, { tenantId, target, requestEmail, email, authUserId, authPlan }) {
  const compensate = { deleted: false };
  let createdUserId = null;
  let userId = authUserId;
  let plan = authPlan;

  try {
    if (userId === null) {
      const created = await port.createConfirmedAuthUser(requestEmail);
      createdUserId = created.id;
      userId = created.id;
      plan = 'created';
    } else {
      plan = 'reused';
    }

    const rawChanged = target.kind === 'member'
      ? await port.bindMember(tenantId, target.id, userId, requestEmail)
      : await port.bindStaff(tenantId, target.id, userId, requestEmail);

    if (rowsChanged(rawChanged) !== 1) {
      await deleteCreatedUser(port, createdUserId, compensate);
      return failure('bind_conflict', target, email, { authUser: plan, authUserId: userId });
    }
  } catch {
    await deleteCreatedUser(port, createdUserId, compensate);
    return failure('bind_conflict', target, email, { authUser: plan, authUserId: userId });
  }

  // PROV-011: re-assert uniqueness after the write. Exactly one binding is the
  // success signal. A created identity that shows zero still means the write did
  // not stick — conflict. A reused identity showing zero is not proof of a
  // concurrent second row (that case is total > 1); the bind already reported
  // exactly one row changed, so only extra bindings force the unwind.
  let unique;
  try {
    const post = await port.countBindings(userId);
    const total = totalBindings(post);
    unique = plan === 'created' ? total === 1 : total <= 1;
  } catch {
    unique = false;
  }
  if (!unique) {
    try {
      if (target.kind === 'member') await port.unbindMember(tenantId, target.id, userId);
      else await port.unbindStaff(tenantId, target.id, userId);
    } catch {
      // Unbind is best-effort; PROV-011 still refuses `linked`.
    }
    await deleteCreatedUser(port, createdUserId, compensate);
    return failure('bind_conflict', target, email, { authUser: plan, authUserId: userId });
  }

  return provisionResult({
    ok: true,
    code: 'linked',
    target,
    authUser: plan,
    authUserId: userId,
    email,
  });
}

/**
 * Pure decision + effect sequence over an injected port. Never reads env.
 * Validation runs before any port call (PROV-002). Dry run never writes
 * (PROV-001). Lookup failures are `lookup_failed` with zero writes (PROV-012).
 * Invalid requests never echo the target (P2).
 */
export async function provisionIdentity(port, request) {
  const email = redactEmail(request?.email);
  const target = normalizeTarget(request?.target);
  const valid = isPlausibleEmail(request?.email)
    && typeof request?.gymCode === 'string'
    && GYM_CODE_PATTERN.test(request.gymCode)
    && target !== null
    && UUID_PATTERN.test(target.id);
  if (!valid) return failure('invalid_request', null, email);

  const requestEmail = request.email.trim();

  // PROV-012: any thrown lookup during checks fails closed with zero writes.
  let tenantId;
  let authUserId = null;
  let authPlan = 'would_create';
  try {
    const gym = await port.findGymByCode(request.gymCode);
    if (!gym) return failure('gym_not_found', target, email);
    tenantId = gym.id;

    const row = target.kind === 'member'
      ? await port.findMember(tenantId, target.id)
      : await port.findStaff(tenantId, target.id);
    if (!row) return failure('target_not_found', target, email);

    // PROV-004: the row must name this person (trimmed, case-insensitive).
    if (normalizeEmail(row.email) !== normalizeEmail(requestEmail)) {
      return failure('email_mismatch', target, email);
    }

    // PROV-005: eligibility.
    if (!isEligible(target.kind, row)) {
      return failure('target_ineligible', target, email);
    }

    // PROV-006 / 006a / 006b: one identity, one gym row; verified identities only.
    const auth = await port.findAuthUserByEmail(requestEmail);

    if (row.userId != null) {
      if (!auth || auth.id !== row.userId) {
        return failure('target_already_linked', target, email);
      }
      if (!isVerifiedIdentity(auth)) {
        return failure('identity_unverified', target, email);
      }
      const bindings = await port.countBindings(auth.id);
      if (totalBindings(bindings) !== 1) {
        return failure('identity_bound_elsewhere', target, email, {
          authUser: 'reused',
          authUserId: auth.id,
        });
      }
      return provisionResult({
        ok: true,
        code: 'already_linked',
        target,
        authUser: 'reused',
        authUserId: auth.id,
        email,
      });
    }

    if (auth) {
      if (!isVerifiedIdentity(auth)) {
        return failure('identity_unverified', target, email);
      }
      const bindings = await port.countBindings(auth.id);
      if (totalBindings(bindings) > 0) {
        return failure('identity_bound_elsewhere', target, email, {
          authUser: 'reused',
          authUserId: auth.id,
        });
      }
      authUserId = auth.id;
      authPlan = 'would_reuse';
    }

    // PROV-001: dry run never writes.
    if (request.apply !== true) {
      return provisionResult({
        ok: true,
        code: 'planned',
        target,
        authUser: authPlan,
        authUserId,
        email,
      });
    }
  } catch {
    return failure('lookup_failed', target, email);
  }

  return applyProvision(port, {
    tenantId,
    target,
    requestEmail,
    email,
    authUserId,
    authPlan,
  });
}

function portFailure() {
  return new Error(FAILURE_MESSAGE);
}

function rowOrThrow(result, map) {
  if (result.error) throw portFailure();
  return result.data == null ? null : map(result.data);
}

/** Escape `\`, `%` and `_` so ILIKE cannot treat them as wildcards (PROV-007a). */
function escapeLike(value) {
  return value.replace(LIKE_ESCAPE, (ch) => `\\${ch}`);
}

function mapAuthUser(user, email) {
  const needle = normalizeEmail(email);
  const identities = Array.isArray(user.identities) ? user.identities : [];
  const googleVerified = identities.some((identity) => {
    if (identity?.provider !== 'google') return false;
    const fromIdentityData = identity.identity_data?.email;
    const fromIdentity = identity.email;
    return (typeof fromIdentityData === 'string' && normalizeEmail(fromIdentityData) === needle)
      || (typeof fromIdentity === 'string' && normalizeEmail(fromIdentity) === needle);
  });
  const hasEmailIdentity = identities.some((identity) => identity?.provider === 'email');
  const provisioned = user.app_metadata?.gymloop_provisioned === true;
  return {
    id: user.id,
    email: typeof user.email === 'string' ? user.email : '',
    provisioned,
    googleVerified,
    hasEmailIdentity,
  };
}

function bindRow(adminClient, table, eligibility) {
  return async (tenantId, rowId, userId, expectedEmail) => {
    const result = await eligibility(adminClient.from(table))
      .update({ user_id: userId })
      .eq('tenant_id', tenantId)
      .eq('id', rowId)
      .is('user_id', null)
      .ilike('email', escapeLike(String(expectedEmail).trim()))
      .select('id');
    if (result.error) throw portFailure();
    return Array.isArray(result.data) ? result.data.length : 0;
  };
}

function unbindRow(adminClient, table) {
  return async (tenantId, rowId, userId) => {
    const result = await adminClient
      .from(table)
      .update({ user_id: null })
      .eq('tenant_id', tenantId)
      .eq('id', rowId)
      .eq('user_id', userId)
      .select('id');
    if (result.error) throw portFailure();
    return Array.isArray(result.data) ? result.data.length : 0;
  };
}

/**
 * Adapter from a service-role supabase-js client to the port. Every query
 * error becomes a generic message — never DB detail, never an email.
 */
export function createSupabaseProvisionPort(adminClient) {
  const bindMember = bindRow(adminClient, 'members', (query) => query
    .not('status', 'in', '(cancelled,blocked)')
    .is('erased_at', null));
  const bindStaff = bindRow(adminClient, 'staff', (query) => query
    .eq('is_active', true)
    .neq('role', 'gym_owner'));
  const unbindMember = unbindRow(adminClient, 'members');
  const unbindStaff = unbindRow(adminClient, 'staff');

  return {
    async findGymByCode(code) {
      const result = await adminClient
        .from('organizations')
        .select('id, gym_code')
        .eq('gym_code', code)
        .maybeSingle();
      return rowOrThrow(result, (row) => ({ id: row.id, gymCode: row.gym_code }));
    },

    async findMember(tenantId, memberId) {
      const result = await adminClient
        .from('members')
        .select('id, tenant_id, email, user_id, status, erased_at')
        .eq('tenant_id', tenantId)
        .eq('id', memberId)
        .maybeSingle();
      return rowOrThrow(result, (row) => ({
        id: row.id,
        tenantId: row.tenant_id,
        email: row.email,
        userId: row.user_id,
        status: row.status,
        erasedAt: row.erased_at,
      }));
    },

    async findStaff(tenantId, staffId) {
      const result = await adminClient
        .from('staff')
        .select('id, tenant_id, email, user_id, role, is_active')
        .eq('tenant_id', tenantId)
        .eq('id', staffId)
        .maybeSingle();
      return rowOrThrow(result, (row) => ({
        id: row.id,
        tenantId: row.tenant_id,
        email: row.email,
        userId: row.user_id,
        role: row.role,
        isActive: row.is_active,
      }));
    },

    async findAuthUserByEmail(email) {
      const needle = normalizeEmail(email);
      const { authListUsersPerPage: perPage, authListUsersMaxPages: maxPages } = PROVISION_IDENTITY_LIMITS;
      for (let page = 1; page <= maxPages; page += 1) {
        const { data, error } = await adminClient.auth.admin.listUsers({ page, perPage });
        if (error) throw portFailure();
        const users = Array.isArray(data?.users) ? data.users : [];
        for (const user of users) {
          if (typeof user.email === 'string' && normalizeEmail(user.email) === needle) {
            return mapAuthUser(user, email);
          }
        }
        if (users.length < perPage) return null;
      }
      // Page cap reached with a full last page: the directory may not be fully searched.
      throw portFailure();
    },

    async countBindings(userId) {
      const tables = ['members', 'staff', 'platform_users'];
      const counts = await Promise.all(tables.map(async (table) => {
        const { count, error } = await adminClient
          .from(table)
          .select('user_id', { count: 'exact', head: true })
          .eq('user_id', userId);
        if (error || typeof count !== 'number') throw portFailure();
        return count;
      }));
      return { members: counts[0], staff: counts[1], platform: counts[2] };
    },

    async createConfirmedAuthUser(email) {
      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        email_confirm: true,
        app_metadata: { gymloop_provisioned: true },
      });
      if (error || !data?.user?.id) throw portFailure();
      return { id: data.user.id };
    },

    async deleteAuthUser(userId) {
      const { error } = await adminClient.auth.admin.deleteUser(userId);
      if (error) throw portFailure();
    },

    bindMember,
    bindStaff,
    unbindMember,
    unbindStaff,
  };
}

const FLAG_KEYS = new Set(['email', 'gym', 'member', 'staff']);

function parseArgv(argv) {
  const values = { email: undefined, gym: undefined, member: undefined, staff: undefined };
  let apply = false;
  const seen = new Set();

  if (!Array.isArray(argv)) return { ok: false, email: null };

  for (let index = 0; index < argv.length; ) {
    const arg = argv[index];
    if (arg === '--apply') {
      if (seen.has('apply')) return { ok: false, email: values.email };
      seen.add('apply');
      apply = true;
      index += 1;
      continue;
    }
    if (typeof arg === 'string' && arg.startsWith('--') && FLAG_KEYS.has(arg.slice('--'.length))) {
      const key = arg.slice('--'.length);
      if (seen.has(key)) return { ok: false, email: values.email };
      const value = argv[index + 1];
      if (typeof value !== 'string' || value.startsWith('--')) return { ok: false, email: values.email };
      seen.add(key);
      values[key] = value;
      index += FLAG_VALUE_STRIDE;
      continue;
    }
    return { ok: false, email: values.email };
  }

  if (values.email === undefined || values.gym === undefined) {
    return { ok: false, email: values.email };
  }
  const hasMember = values.member !== undefined;
  const hasStaff = values.staff !== undefined;
  if (hasMember === hasStaff) return { ok: false, email: values.email };

  return {
    ok: true,
    request: {
      email: values.email,
      gymCode: values.gym,
      target: { kind: hasMember ? 'member' : 'staff', id: hasMember ? values.member : values.staff },
      apply,
    },
  };
}

function writeResult(result) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

/**
 * CLI entry: parses argv, builds the service-role client from env, prints one
 * JSON line. Returns 0 when `ok` is true, 1 otherwise (PROV-010).
 */
export async function main(argv) {
  const parsed = parseArgv(argv);
  if (!parsed.ok) {
    writeResult(failure('invalid_request', null, redactEmail(parsed.email)));
    return 1;
  }

  const request = parsed.request;
  const email = redactEmail(request.email);
  try {
    const { SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY } = provisioningEnv();
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const result = await provisionIdentity(createSupabaseProvisionPort(adminClient), request);
    writeResult(result);
    return result.ok ? 0 : 1;
  } catch {
    writeResult(failure('bind_conflict', null, email));
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(CLI_ARGS_START));
}
