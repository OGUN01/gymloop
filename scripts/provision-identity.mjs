/**
 * Closed-test identity provisioning (PROV-001…010).
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

function safeFailure() {
  return new Error(FAILURE_MESSAGE);
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
 * Pure decision + effect sequence over an injected port. Never reads env.
 * Validation runs before any port call (PROV-002). Dry run never writes
 * (PROV-001). Apply performs at most one create and exactly one bind, and
 * deletes only a user this run created (PROV-007, PROV-008).
 */
export async function provisionIdentity(port, request) {
  const email = redactEmail(request?.email);
  const target = normalizeTarget(request?.target);
  const valid = isPlausibleEmail(request?.email)
    && typeof request?.gymCode === 'string'
    && GYM_CODE_PATTERN.test(request.gymCode)
    && target !== null
    && UUID_PATTERN.test(target.id);
  if (!valid) return failure('invalid_request', target, email);

  const requestEmail = request.email.trim();
  const compensate = { deleted: false };
  let createdUserId = null;

  try {
    const gym = await port.findGymByCode(request.gymCode);
    if (!gym) return failure('gym_not_found', target, email);

    const tenantId = gym.id;
    const row = target.kind === 'member'
      ? await port.findMember(tenantId, target.id)
      : await port.findStaff(tenantId, target.id);
    if (!row) return failure('target_not_found', target, email);

    // PROV-004: the row must name this person (trimmed, case-insensitive).
    if (normalizeEmail(row.email) !== normalizeEmail(requestEmail)) {
      return failure('email_mismatch', target, email);
    }

    // PROV-005: eligibility.
    if (target.kind === 'member') {
      if (row.status === 'cancelled' || row.status === 'blocked' || row.erasedAt != null) {
        return failure('target_ineligible', target, email);
      }
    } else if (row.isActive !== true || row.role === 'gym_owner') {
      return failure('target_ineligible', target, email);
    }

    // PROV-006: one identity, one gym row.
    const auth = await port.findAuthUserByEmail(requestEmail);
    if (row.userId != null) {
      if (auth && auth.id === row.userId) {
        return provisionResult({
          ok: true,
          code: 'already_linked',
          target,
          authUser: 'reused',
          authUserId: auth.id,
          email,
        });
      }
      return failure('target_already_linked', target, email);
    }

    let authUserId = null;
    let authPlan = 'would_create';
    if (auth) {
      const bindings = await port.countBindings(auth.id);
      const bound = bindings.members + bindings.staff + bindings.platform;
      if (bound > 0) {
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

    // PROV-007 / PROV-008: apply exactly one binding; compensate a created user.
    try {
      if (authUserId === null) {
        const created = await port.createConfirmedAuthUser(requestEmail);
        createdUserId = created.id;
        authUserId = created.id;
        authPlan = 'created';
      } else {
        authPlan = 'reused';
      }

      const changed = target.kind === 'member'
        ? await port.bindMember(tenantId, target.id, authUserId)
        : await port.bindStaff(tenantId, target.id, authUserId);

      if (changed !== 1) {
        await deleteCreatedUser(port, createdUserId, compensate);
        return failure('bind_conflict', target, email, { authUser: authPlan, authUserId });
      }

      return provisionResult({
        ok: true,
        code: 'linked',
        target,
        authUser: authPlan,
        authUserId,
        email,
      });
    } catch {
      await deleteCreatedUser(port, createdUserId, compensate);
      throw safeFailure();
    }
  } catch (error) {
    await deleteCreatedUser(port, createdUserId, compensate);
    if (error instanceof Error && error.message === FAILURE_MESSAGE) throw error;
    throw safeFailure();
  }
}

function portFailure() {
  return new Error(FAILURE_MESSAGE);
}

function rowOrThrow(result, map) {
  if (result.error) throw portFailure();
  return result.data == null ? null : map(result.data);
}

/**
 * Adapter from a service-role supabase-js client to the port. Every query
 * error becomes a generic message — never DB detail, never an email.
 */
export function createSupabaseProvisionPort(adminClient) {
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
        const users = data?.users ?? [];
        for (const user of users) {
          if (typeof user.email === 'string' && normalizeEmail(user.email) === needle) {
            return { id: user.id, email: user.email };
          }
        }
        if (users.length < perPage) return null;
      }
      return null;
    },

    async countBindings(userId) {
      const tables = ['members', 'staff', 'platform_users'];
      const counts = await Promise.all(tables.map(async (table) => {
        const { count, error } = await adminClient
          .from(table)
          .select('id', { count: 'exact', head: true })
          .eq('user_id', userId);
        if (error) throw portFailure();
        return count ?? 0;
      }));
      return { members: counts[0], staff: counts[1], platform: counts[2] };
    },

    async createConfirmedAuthUser(email) {
      const { data, error } = await adminClient.auth.admin.createUser({
        email,
        email_confirm: true,
      });
      if (error || !data?.user?.id) throw portFailure();
      return { id: data.user.id };
    },

    async deleteAuthUser(userId) {
      const { error } = await adminClient.auth.admin.deleteUser(userId);
      if (error) throw portFailure();
    },

    async bindMember(tenantId, memberId, userId) {
      const result = await adminClient
        .from('members')
        .update({ user_id: userId })
        .eq('tenant_id', tenantId)
        .eq('id', memberId)
        .is('user_id', null)
        .select('id');
      if (result.error) throw portFailure();
      return Array.isArray(result.data) ? result.data.length : 0;
    },

    async bindStaff(tenantId, staffId, userId) {
      const result = await adminClient
        .from('staff')
        .update({ user_id: userId })
        .eq('tenant_id', tenantId)
        .eq('id', staffId)
        .is('user_id', null)
        .select('id');
      if (result.error) throw portFailure();
      return Array.isArray(result.data) ? result.data.length : 0;
    },
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
    writeResult(failure('bind_conflict', normalizeTarget(request.target), email));
    return 1;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = await main(process.argv.slice(CLI_ARGS_START));
}
