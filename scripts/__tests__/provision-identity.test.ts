import { afterEach, describe, expect, it, vi } from 'vitest';
import { PROVISION_IDENTITY_LIMITS } from '../../packages/shared/src/config/constants';
import { createSupabaseProvisionPort, main, provisionIdentity } from '../provision-identity.mjs';

const GYM_CODE = 'ABC123';
const TENANT_ID = '00000000-0000-4000-8000-000000000001';
const OTHER_TENANT_ID = '00000000-0000-4000-8000-000000000002';
const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = '22222222-2222-4222-8222-222222222222';
const AUTH_ID = '33333333-3333-4333-8333-333333333333';
const CREATED_AUTH_ID = '44444444-4444-4444-8444-444444444444';
const OTHER_AUTH_ID = '55555555-5555-4555-8555-555555555555';
const EMAIL = 'alice.test+play@example.com';
const REDACTED_EMAIL = 'a***@example.com';
const SECRET_MARKERS = [EMAIL, 'service-role-key-secret', 'access-token-secret', 'refresh-token-secret', 'password-secret'];

type Member = {
  id: string;
  tenantId: string;
  email: string | null;
  userId: string | null;
  status: string;
  erasedAt: string | null;
  privateNote?: string;
};
type Staff = {
  id: string;
  tenantId: string;
  email: string | null;
  userId: string | null;
  role: string;
  isActive: boolean;
};
type AuthUser = {
  id: string;
  email: string;
  provisioned: boolean;
  googleVerified: boolean;
  hasEmailIdentity: boolean;
  accessToken?: string;
  refreshToken?: string;
  password?: string;
};
type Bindings = { members: number; staff: number; platform: number };
type Call = { method: string; args: unknown[] };
type Lookup = 'findGymByCode' | 'findMember' | 'findStaff' | 'findAuthUserByEmail' | 'countBindings';
type FakeOptions = {
  gym?: { id: string; gymCode: string } | null;
  members?: Member[];
  staff?: Staff[];
  authUsers?: AuthUser[];
  bindings?: Record<string, Bindings>;
  countBindingsResponses?: Array<Partial<Bindings> | Error | null>;
  lookupErrors?: Partial<Record<Lookup, Error>>;
  beforeBindMember?: (row: Member | undefined) => void;
  beforeBindStaff?: (row: Staff | undefined) => void;
  bindMemberRows?: number;
  bindStaffRows?: number;
  createError?: Error;
  bindMemberError?: Error;
  bindStaffError?: Error;
  unbindMemberError?: Error;
  unbindStaffError?: Error;
  deleteError?: Error;
};

const member = (changes: Partial<Member> = {}): Member => ({
  id: MEMBER_ID, tenantId: TENANT_ID, email: EMAIL, userId: null,
  status: 'active', erasedAt: null, ...changes,
});
const staff = (changes: Partial<Staff> = {}): Staff => ({
  id: STAFF_ID, tenantId: TENANT_ID, email: EMAIL, userId: null,
  role: 'trainer', isActive: true, ...changes,
});
const authUser = (changes: Partial<AuthUser> = {}): AuthUser => ({
  id: AUTH_ID, email: EMAIL, provisioned: true, googleVerified: false, hasEmailIdentity: false, ...changes,
});
const request = (changes: Record<string, unknown> = {}) => ({
  email: EMAIL, gymCode: GYM_CODE, target: { kind: 'member', id: MEMBER_ID }, apply: false, ...changes,
});
const staffRequest = (changes: Record<string, unknown> = {}) => request({
  target: { kind: 'staff', id: STAFF_ID }, ...changes,
});

function fakePort(options: FakeOptions = {}) {
  const calls: Call[] = [];
  const record = (method: string, ...args: unknown[]) => { calls.push({ method, args }); };
  const failLookup = (method: Lookup) => { if (options.lookupErrors?.[method]) throw options.lookupErrors[method]; };
  const gym = options.gym === undefined ? { id: TENANT_ID, gymCode: GYM_CODE } : options.gym;
  // Keying by BOTH tenant and row id prevents a different gym's row from being returned.
  const members = new Map((options.members ?? [member()]).map((row) => [`${row.tenantId}:${row.id}`, { ...row }]));
  const staffRows = new Map((options.staff ?? [staff()]).map((row) => [`${row.tenantId}:${row.id}`, { ...row }]));
  let countCalls = 0;
  const port = {
    async findGymByCode(code: string) {
      record('findGymByCode', code);
      failLookup('findGymByCode');
      return gym?.gymCode === code ? gym : null;
    },
    async findMember(tenantId: string, id: string) {
      record('findMember', tenantId, id);
      failLookup('findMember');
      return members.get(`${tenantId}:${id}`) ?? null;
    },
    async findStaff(tenantId: string, id: string) {
      record('findStaff', tenantId, id);
      failLookup('findStaff');
      return staffRows.get(`${tenantId}:${id}`) ?? null;
    },
    async findAuthUserByEmail(email: string) {
      record('findAuthUserByEmail', email);
      failLookup('findAuthUserByEmail');
      return options.authUsers?.find((user) => user.email.trim().toLowerCase() === email.trim().toLowerCase()) ?? null;
    },
    async countBindings(userId: string) {
      record('countBindings', userId);
      failLookup('countBindings');
      const response = options.countBindingsResponses?.[countCalls++];
      if (response instanceof Error) throw response;
      if (response !== undefined) return response;
      if (options.bindings?.[userId]) return options.bindings[userId];
      const allMembers = [...members.values()].filter((row) => row.userId === userId).length;
      const allStaff = [...staffRows.values()].filter((row) => row.userId === userId).length;
      return { members: allMembers, staff: allStaff, platform: 0 };
    },
    async createConfirmedAuthUser(...args: unknown[]) {
      record('createConfirmedAuthUser', ...args);
      if (options.createError) throw options.createError;
      return { id: CREATED_AUTH_ID };
    },
    async deleteAuthUser(userId: string) {
      record('deleteAuthUser', userId);
      if (options.deleteError) throw options.deleteError;
    },
    async bindMember(tenantId: string, id: string, userId: string, expectedEmail: string) {
      record('bindMember', tenantId, id, userId, expectedEmail);
      if (options.bindMemberError) throw options.bindMemberError;
      const row = members.get(`${tenantId}:${id}`);
      options.beforeBindMember?.(row);
      const eligible = row && row.userId === null && row.email?.toLowerCase() === expectedEmail.trim().toLowerCase()
        && row.status !== 'cancelled' && row.status !== 'blocked' && row.erasedAt === null;
      const changed = options.bindMemberRows ?? (eligible ? 1 : 0);
      if (changed === 1 && row) row.userId = userId;
      return changed;
    },
    async bindStaff(tenantId: string, id: string, userId: string, expectedEmail: string) {
      record('bindStaff', tenantId, id, userId, expectedEmail);
      if (options.bindStaffError) throw options.bindStaffError;
      const row = staffRows.get(`${tenantId}:${id}`);
      options.beforeBindStaff?.(row);
      const eligible = row && row.userId === null && row.email?.toLowerCase() === expectedEmail.trim().toLowerCase()
        && row.isActive && row.role !== 'gym_owner';
      const changed = options.bindStaffRows ?? (eligible ? 1 : 0);
      if (changed === 1 && row) row.userId = userId;
      return changed;
    },
    async unbindMember(tenantId: string, id: string, userId: string) {
      record('unbindMember', tenantId, id, userId);
      if (options.unbindMemberError) throw options.unbindMemberError;
      const row = members.get(`${tenantId}:${id}`);
      if (!row || row.userId !== userId) return 0;
      row.userId = null;
      return 1;
    },
    async unbindStaff(tenantId: string, id: string, userId: string) {
      record('unbindStaff', tenantId, id, userId);
      if (options.unbindStaffError) throw options.unbindStaffError;
      const row = staffRows.get(`${tenantId}:${id}`);
      if (!row || row.userId !== userId) return 0;
      row.userId = null;
      return 1;
    },
  };
  return { port, calls };
}

const methodNames = (calls: Call[]) => calls.map((call) => call.method);
const writes = (calls: Call[]) => calls.filter((call) => [
  'createConfirmedAuthUser', 'deleteAuthUser', 'bindMember', 'bindStaff', 'unbindMember', 'unbindStaff',
].includes(call.method));
const assertReadOnly = (calls: Call[]) => {
  expect(writes(calls)).toEqual([]);
  expect(calls.every((call) => call.method.startsWith('find') || call.method === 'countBindings')).toBe(true);
};
const assertRedacted = (result: { email: string | null }, extraForbidden: string[] = []) => {
  expect(result.email).toBe(REDACTED_EMAIL);
  const json = JSON.stringify(result);
  for (const secret of [...SECRET_MARKERS, ...extraForbidden]) expect(json).not.toContain(secret);
};
const assertSafeFailure = async (operation: Promise<unknown>) => {
  let outcome: unknown;
  try {
    outcome = await operation;
  } catch (error) {
    outcome = error;
  }
  if (!(outcome instanceof Error)) expect(outcome).toMatchObject({ ok: false });
  const printed = outcome instanceof Error ? `${outcome.name}: ${outcome.message}` : JSON.stringify(outcome);
  for (const secret of SECRET_MARKERS) expect(printed).not.toContain(secret);
};

// Unlike a permissive chain mock, from(table) itself has no .eq/.is/.ilike: filters are
// available only after a query action. This mirrors supabase-js and detects illegal chains.
function strictSupabaseClient(options: {
  replies?: Array<{ data?: unknown; error?: unknown; count?: number | null }>;
  listPages?: Array<Array<Record<string, unknown>>>;
  adminErrors?: Partial<Record<'listUsers' | 'createUser' | 'deleteUser', unknown>>;
} = {}) {
  const calls: Call[] = [];
  const replies = [...(options.replies ?? [])];
  let pageIndex = 0;
  const record = (method: string, ...args: unknown[]) => { calls.push({ method, args }); };
  const result = (method: string, ...args: unknown[]) => {
    record(method, ...args);
    return replies.shift() ?? { data: [], error: null, count: 0 };
  };
  const filtered = () => {
    const builder = {
      eq(column: string, value: unknown) { record('eq', column, value); return builder; },
      neq(column: string, value: unknown) { record('neq', column, value); return builder; },
      is(column: string, value: unknown) { record('is', column, value); return builder; },
      not(column: string, operator: string, value: unknown) { record('not', column, operator, value); return builder; },
      in(column: string, values: unknown[]) { record('in', column, values); return builder; },
      ilike(column: string, pattern: string) { record('ilike', column, pattern); return builder; },
      match(values: Record<string, unknown>) { record('match', values); return builder; },
      limit(value: number) { record('limit', value); return builder; },
      select(...args: unknown[]) { record('select', ...args); return builder; },
      async maybeSingle() { return result('maybeSingle'); },
      async single() { return result('single'); },
      then(resolve: (value: unknown) => unknown, reject?: (error: unknown) => unknown) {
        return Promise.resolve(result('await')).then(resolve, reject);
      },
    };
    return builder;
  };
  const client = {
    from(table: string) {
      record('from', table);
      return {
        select(...args: unknown[]) { record('select', ...args); return filtered(); },
        insert(...args: unknown[]) { record('insert', ...args); return filtered(); },
        update(...args: unknown[]) { record('update', ...args); return filtered(); },
        upsert(...args: unknown[]) { record('upsert', ...args); return filtered(); },
        delete(...args: unknown[]) { record('delete', ...args); return filtered(); },
      };
    },
    auth: {
      admin: {
        async listUsers(args: { page: number; perPage: number }) {
          record('listUsers', args);
          const error = options.adminErrors?.listUsers ?? null;
          const users = options.listPages?.[pageIndex++] ?? [];
          return { data: { users }, error };
        },
        async createUser(args: unknown) {
          record('createUser', args);
          return { data: { user: { id: CREATED_AUTH_ID } }, error: options.adminErrors?.createUser ?? null };
        },
        async deleteUser(id: string) {
          record('deleteUser', id);
          return { data: { user: null }, error: options.adminErrors?.deleteUser ?? null };
        },
      },
    },
  };
  return { client, calls };
}

const fakeAdapter = (options: Parameters<typeof strictSupabaseClient>[0] = {}) => {
  const fake = strictSupabaseClient(options);
  // The port consumes this fake supabase-js client; TypeScript may not know its
  // dynamic query return type, but the runtime deliberately enforces that shape.
  const port = createSupabaseProvisionPort(fake.client as never);
  return { ...fake, port };
};
const assertAdapterCalls = (actual: Call[], required: Call[]) => {
  for (const call of required) expect(actual).toContainEqual(call);
};
const assertGenericError = async (operation: Promise<unknown>) => {
  let error: unknown;
  try { await operation; } catch (caught) { error = caught; }
  expect(error).toBeInstanceOf(Error);
  const message = String(error);
  for (const secret of SECRET_MARKERS) expect(message).not.toContain(secret);
};

describe('PROV-001 dry run', () => {
  it('plans creating a member identity without any write', async () => {
    const fake = fakePort();
    const result = await provisionIdentity(fake.port, request());
    expect(result).toMatchObject({ ok: true, code: 'planned', target: { kind: 'member', id: MEMBER_ID }, authUser: 'would_create', authUserId: null });
    expect(fake.calls).toContainEqual({ method: 'findGymByCode', args: [GYM_CODE] });
    expect(fake.calls).toContainEqual({ method: 'findMember', args: [TENANT_ID, MEMBER_ID] });
    expect(fake.calls.some((call) => call.method === 'findAuthUserByEmail')).toBe(true);
    assertReadOnly(fake.calls);
    assertRedacted(result);
  });

  it('plans reusing an unbound Auth user for staff without creating or binding', async () => {
    const fake = fakePort({ authUsers: [authUser()] });
    const result = await provisionIdentity(fake.port, staffRequest());
    expect(result).toMatchObject({ ok: true, code: 'planned', target: { kind: 'staff', id: STAFF_ID }, authUser: 'would_reuse', authUserId: AUTH_ID });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
  });

  it('keeps a dry-run refusal read-only as well', async () => {
    const fake = fakePort({ members: [member({ status: 'blocked' })] });
    expect(await provisionIdentity(fake.port, request())).toMatchObject({ ok: false, code: 'target_ineligible' });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-002 request validation', () => {
  it.each([
    'not-an-email', 'alice@@example.com', '@example.com', 'alice@example',
    'alice @example.com', 'alice@example.com extra',
  ])('rejects invalid email %j without even looking up the gym', async (email) => {
    const fake = fakePort();
    expect(await provisionIdentity(fake.port, request({ email }))).toMatchObject({ ok: false, code: 'invalid_request' });
    expect(fake.calls).toEqual([]);
  });

  it.each(['abc123', 'ABCDE', 'ABCDEFG', 'ABC-12'])('rejects invalid gym code %j without port calls', async (gymCode) => {
    const fake = fakePort();
    expect(await provisionIdentity(fake.port, request({ gymCode }))).toMatchObject({ ok: false, code: 'invalid_request' });
    expect(fake.calls).toEqual([]);
  });

  it.each(['not-a-uuid', '11111111-1111-1111-1111-11111111111z', ''])('rejects invalid target id %j without port calls', async (id) => {
    const fake = fakePort();
    expect(await provisionIdentity(fake.port, request({ target: { kind: 'member', id } }))).toMatchObject({ ok: false, code: 'invalid_request' });
    expect(fake.calls).toEqual([]);
  });

  it.each(['owner', '', null])('rejects target kind %j without port calls', async (kind) => {
    const fake = fakePort();
    expect(await provisionIdentity(fake.port, request({ target: { kind, id: MEMBER_ID } }))).toMatchObject({ ok: false, code: 'invalid_request' });
    expect(fake.calls).toEqual([]);
  });
});

describe('PROV-003 resolve gym and target within the gym', () => {
  it('refuses an unknown gym before looking up any row or identity', async () => {
    const fake = fakePort({ gym: null });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'gym_not_found' });
    expect(fake.calls).toEqual([{ method: 'findGymByCode', args: [GYM_CODE] }]);
  });

  it('does not find a member whose same id exists only in another tenant', async () => {
    const fake = fakePort({ members: [member({ tenantId: OTHER_TENANT_ID })] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_not_found' });
    expect(fake.calls).toContainEqual({ method: 'findMember', args: [TENANT_ID, MEMBER_ID] });
    expect(methodNames(fake.calls)).not.toContain('findStaff');
    assertReadOnly(fake.calls);
  });

  it('does not find staff whose same id exists only in another tenant', async () => {
    const fake = fakePort({ staff: [staff({ tenantId: OTHER_TENANT_ID })] });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'target_not_found' });
    expect(fake.calls).toContainEqual({ method: 'findStaff', args: [TENANT_ID, STAFF_ID] });
    expect(methodNames(fake.calls)).not.toContain('findMember');
    assertReadOnly(fake.calls);
  });

  it('refuses a missing member of the selected tenant', async () => {
    const fake = fakePort({ members: [] });
    expect(await provisionIdentity(fake.port, request())).toMatchObject({ ok: false, code: 'target_not_found' });
    assertReadOnly(fake.calls);
  });

  it('refuses missing staff of the selected tenant', async () => {
    const fake = fakePort({ staff: [] });
    expect(await provisionIdentity(fake.port, staffRequest())).toMatchObject({ ok: false, code: 'target_not_found' });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-004 target email agreement', () => {
  it.each([null, 'someone-else@example.com'])('refuses a member email of %j', async (email) => {
    const fake = fakePort({ members: [member({ email })] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'email_mismatch' });
    assertReadOnly(fake.calls);
  });

  it.each([null, 'someone-else@example.com'])('refuses a staff email of %j', async (email) => {
    const fake = fakePort({ staff: [staff({ email })] });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'email_mismatch' });
    assertReadOnly(fake.calls);
  });

  it('accepts a trimmed, case-insensitive member-row email', async () => {
    const fake = fakePort({ members: [member({ email: '  ALICE.TEST+PLAY@EXAMPLE.COM  ' })] });
    expect(await provisionIdentity(fake.port, request())).toMatchObject({ ok: true, code: 'planned' });
    assertReadOnly(fake.calls);
  });

  it('accepts a trimmed, case-insensitive staff-row email', async () => {
    const fake = fakePort({ staff: [staff({ email: '\tALICE.TEST+PLAY@EXAMPLE.COM\t' })] });
    expect(await provisionIdentity(fake.port, staffRequest())).toMatchObject({ ok: true, code: 'planned' });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-005 eligible targets only', () => {
  it.each(['cancelled', 'blocked'])('refuses a %s member', async (status) => {
    const fake = fakePort({ members: [member({ status })] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' });
    assertReadOnly(fake.calls);
  });

  it('refuses an erased member even when status still looks active', async () => {
    const fake = fakePort({ members: [member({ erasedAt: '2026-09-01T00:00:00Z' })] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' });
    assertReadOnly(fake.calls);
  });

  it('refuses inactive staff', async () => {
    const fake = fakePort({ staff: [staff({ isActive: false })] });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' });
    assertReadOnly(fake.calls);
  });

  it('refuses gym owners, who must use the audited platform path', async () => {
    const fake = fakePort({ staff: [staff({ role: 'gym_owner' })] });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-006 one identity, one gym row', () => {
  it('reports a target linked to the same email Auth user without any writes', async () => {
    const fake = fakePort({
      members: [member({ userId: AUTH_ID })], authUsers: [authUser()],
      bindings: { [AUTH_ID]: { members: 1, staff: 0, platform: 0 } },
    });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: true, code: 'already_linked', authUserId: AUTH_ID });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
  });

  it('refuses a target linked to a different Auth user even if this email has an Auth user', async () => {
    const fake = fakePort({ members: [member({ userId: OTHER_AUTH_ID })], authUsers: [authUser()] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_already_linked' });
    assertReadOnly(fake.calls);
  });

  it('refuses a bound staff row when no Auth user exists for the requested email', async () => {
    const fake = fakePort({ staff: [staff({ userId: OTHER_AUTH_ID })] });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'target_already_linked' });
    assertReadOnly(fake.calls);
  });

  it.each(['members', 'staff', 'platform'] as const)('refuses an Auth user with a %s binding elsewhere', async (binding) => {
    const fake = fakePort({
      authUsers: [authUser()],
      bindings: { [AUTH_ID]: { members: 0, staff: 0, platform: 0, [binding]: 1 } },
    });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'identity_bound_elsewhere' });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-006a reuse only a verified identity', () => {
  it.each([
    ['unprovisioned password-only user', { provisioned: false, googleVerified: false, hasEmailIdentity: true }],
    ['unprovisioned user without verified Google or email identity', { provisioned: false, googleVerified: false, hasEmailIdentity: false }],
    ['Google-verified user with an email identity too', { provisioned: false, googleVerified: true, hasEmailIdentity: true }],
  ])('refuses %s without ever writing, including in dry run', async (_label, identity) => {
    for (const apply of [false, true]) {
      const fake = fakePort({ authUsers: [authUser(identity)] });
      const result = await provisionIdentity(fake.port, request({ apply }));
      expect(result).toMatchObject({ ok: false, code: 'identity_unverified' });
      assertReadOnly(fake.calls);
      assertRedacted(result);
    }
  });

  it.each([
    ['operator-provisioned account, even with an email identity', { provisioned: true, googleVerified: false, hasEmailIdentity: true }],
    ['verified Google account without an email identity', { provisioned: false, googleVerified: true, hasEmailIdentity: false }],
  ])('allows reuse of %s in dry run and apply', async (_label, identity) => {
    for (const apply of [false, true]) {
      const fake = fakePort({ authUsers: [authUser(identity)] });
      const result = await provisionIdentity(fake.port, request({ apply }));
      expect(result).toMatchObject({ ok: true, code: apply ? 'linked' : 'planned', authUser: apply ? 'reused' : 'would_reuse' });
      if (apply) expect(writes(fake.calls)).toEqual([{ method: 'bindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL] }]);
      else assertReadOnly(fake.calls);
      assertRedacted(result);
    }
  });
});

describe('PROV-006b already linked requires exactly one total binding', () => {
  it.each([
    ['no bindings', { members: 0, staff: 0, platform: 0 }],
    ['two member bindings', { members: 2, staff: 0, platform: 0 }],
    ['another staff binding', { members: 1, staff: 1, platform: 0 }],
    ['a platform binding', { members: 1, staff: 0, platform: 1 }],
  ])('refuses already-linked target with %s', async (_label, bindingCount) => {
    const fake = fakePort({ members: [member({ userId: AUTH_ID })], authUsers: [authUser()], bindings: { [AUTH_ID]: bindingCount } });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'identity_bound_elsewhere' });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
  });
});

describe('PROV-007 apply exactly one binding', () => {
  it('creates a confirmed Auth user using ONLY the email, then binds a member once', async () => {
    const fake = fakePort();
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: true, code: 'linked', authUser: 'created', authUserId: CREATED_AUTH_ID });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
    ]);
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [CREATED_AUTH_ID] });
    assertRedacted(result);
  });

  it('reuses an unbound Auth user and binds staff without creating or deleting', async () => {
    const fake = fakePort({ authUsers: [authUser()] });
    const result = await provisionIdentity(fake.port, staffRequest({ apply: true }));
    expect(result).toMatchObject({ ok: true, code: 'linked', authUser: 'reused', authUserId: AUTH_ID });
    expect(fake.calls.filter((call) => call.method === 'countBindings')).toEqual([
      { method: 'countBindings', args: [AUTH_ID] },
      { method: 'countBindings', args: [AUTH_ID] },
    ]);
    expect(writes(fake.calls)).toEqual([{ method: 'bindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID, EMAIL] }]);
    assertRedacted(result);
  });

  it('binds a newly created user to staff, not to a member', async () => {
    const fake = fakePort();
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: true, code: 'linked', authUser: 'created' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindStaff', args: [TENANT_ID, STAFF_ID, CREATED_AUTH_ID, EMAIL] },
    ]);
  });

  it('binds an existing unbound user to a member, not to staff', async () => {
    const fake = fakePort({ authUsers: [authUser()] });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: true, code: 'linked', authUser: 'reused' });
    expect(writes(fake.calls)).toEqual([{ method: 'bindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL] }]);
  });
});

describe('PROV-007a bind re-asserts the target checks', () => {
  it('passes the requested email, not the target row email, to the member bind', async () => {
    const variant = EMAIL.toUpperCase();
    const fake = fakePort({ members: [member({ email: EMAIL })], authUsers: [authUser()] });
    expect(await provisionIdentity(fake.port, request({ email: variant, apply: true }))).toMatchObject({ ok: true, code: 'linked' });
    expect(writes(fake.calls)).toEqual([{ method: 'bindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID, variant] }]);
  });

  it('fails closed when the target row email has surrounding whitespace at bind time', async () => {
    const fake = fakePort({ members: [member({ email: `  ${EMAIL}  ` })] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
  });

  it.each([
    ['email', (row: Member | undefined) => { if (row) row.email = 'other@example.com'; }],
    ['eligibility', (row: Member | undefined) => { if (row) row.status = 'blocked'; }],
  ])('rejects a member whose %s changed between read and conditional bind', async (_label, beforeBindMember) => {
    const fake = fakePort({ beforeBindMember });
    expect(await provisionIdentity(fake.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
  });

  it.each([
    ['email', (row: Staff | undefined) => { if (row) row.email = 'other@example.com'; }],
    ['eligibility', (row: Staff | undefined) => { if (row) row.isActive = false; }],
  ])('rejects staff whose %s changed between read and conditional bind', async (_label, beforeBindStaff) => {
    const fake = fakePort({ authUsers: [authUser()], beforeBindStaff });
    expect(await provisionIdentity(fake.port, staffRequest({ apply: true }))).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([{ method: 'bindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID, EMAIL] }]);
  });
});

describe('PROV-008 bind races and compensation', () => {
  it.each([0, 2])('reports member bind count %i as conflict and deletes a created user exactly once', async (count) => {
    const fake = fakePort({ bindMemberRows: count });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it.each([0, 2])('reports staff bind count %i as conflict without deleting a reused user', async (count) => {
    const fake = fakePort({ authUsers: [authUser()], bindStaffRows: count });
    const result = await provisionIdentity(fake.port, staffRequest({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([{ method: 'bindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID, EMAIL] }]);
    assertRedacted(result);
  });

  it('deletes the just-created user once when bind throws, without rethrowing credentials or email', async () => {
    const fake = fakePort({ bindMemberError: new Error(`bind failed: ${SECRET_MARKERS.join(' ')}`) });
    await assertSafeFailure(provisionIdentity(fake.port, request({ apply: true })));
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
  });

  it('never deletes a reused user when bind throws', async () => {
    const fake = fakePort({ authUsers: [authUser()], bindStaffError: new Error(`bind failed: ${SECRET_MARKERS.join(' ')}`) });
    await assertSafeFailure(provisionIdentity(fake.port, staffRequest({ apply: true })));
    expect(writes(fake.calls)).toEqual([{ method: 'bindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID, EMAIL] }]);
  });

  it('cannot bind or delete a user when create throws before returning an id', async () => {
    const fake = fakePort({ createError: new Error(`create failed: ${SECRET_MARKERS.join(' ')}`) });
    await assertSafeFailure(provisionIdentity(fake.port, request({ apply: true })));
    expect(writes(fake.calls)).toEqual([{ method: 'createConfirmedAuthUser', args: [EMAIL] }]);
  });

  it('attempts deletion exactly once and keeps a delete error secret-safe', async () => {
    const fake = fakePort({
      bindStaffError: new Error(`bind failed: ${SECRET_MARKERS.join(' ')}`),
      deleteError: new Error(`delete failed: ${SECRET_MARKERS.join(' ')}`),
    });
    await assertSafeFailure(provisionIdentity(fake.port, staffRequest({ apply: true })));
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindStaff', args: [TENANT_ID, STAFF_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
  });
});

describe('PROV-011 verify unique binding after the write', () => {
  it('rechecks count after a created member is bound, then rolls that row back and deletes the new Auth user on a duplicate', async () => {
    const fake = fakePort({ countBindingsResponses: [{ members: 2, staff: 0, platform: 0 }] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(fake.calls.filter((call) => call.method === 'countBindings')).toEqual([
      { method: 'countBindings', args: [CREATED_AUTH_ID] },
    ]);
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it('rolls back a reused staff binding exactly once without deleting the preexisting user', async () => {
    const fake = fakePort({ authUsers: [authUser()], countBindingsResponses: [
      { members: 0, staff: 0, platform: 0 }, { members: 0, staff: 1, platform: 1 },
    ] });
    const result = await provisionIdentity(fake.port, staffRequest({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(fake.calls.filter((call) => call.method === 'countBindings')).toEqual([
      { method: 'countBindings', args: [AUTH_ID] }, { method: 'countBindings', args: [AUTH_ID] },
    ]);
    expect(writes(fake.calls)).toEqual([
      { method: 'bindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID, EMAIL] },
      { method: 'unbindStaff', args: [TENANT_ID, STAFF_ID, AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it('treats zero post-bind bindings as a conflict and compensates a created user', async () => {
    const fake = fakePort({ countBindingsResponses: [{ members: 0, staff: 0, platform: 0 }] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
  });

  it('treats zero post-bind bindings as a conflict even when reusing an Auth user', async () => {
    const fake = fakePort({ authUsers: [authUser()], countBindingsResponses: [
      { members: 0, staff: 0, platform: 0 }, { members: 0, staff: 0, platform: 0 },
    ] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(fake.calls.filter((call) => call.method === 'countBindings')).toEqual([
      { method: 'countBindings', args: [AUTH_ID] }, { method: 'countBindings', args: [AUTH_ID] },
    ]);
    expect(writes(fake.calls)).toEqual([
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it('never returns linked if post-bind counting throws and still compensates the newly created identity', async () => {
    const fake = fakePort({ countBindingsResponses: [new Error(`count failed: ${SECRET_MARKERS.join(' ')}`)] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it('never returns linked or leaks secrets if unbinding throws after a duplicate binding is detected', async () => {
    const fake = fakePort({
      authUsers: [authUser()],
      countBindingsResponses: [{ members: 0, staff: 0, platform: 0 }, { members: 2, staff: 0, platform: 0 }],
      unbindMemberError: new Error(`rollback failed: ${SECRET_MARKERS.join(' ')}`),
    });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it('compensates exactly once for a newly created identity even when unbinding fails', async () => {
    const fake = fakePort({
      countBindingsResponses: [{ members: 1, staff: 1, platform: 0 }],
      unbindStaffError: new Error(`rollback failed: ${SECRET_MARKERS.join(' ')}`),
    });
    const result = await provisionIdentity(fake.port, staffRequest({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindStaff', args: [TENANT_ID, STAFF_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'unbindStaff', args: [TENANT_ID, STAFF_ID, CREATED_AUTH_ID] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
    assertRedacted(result);
  });

  it.each([
    ['missing staff', { members: 1, platform: 0 }],
    ['null platform', { members: 1, staff: 0, platform: null }],
    ['non-numeric members', { members: '1', staff: 0, platform: 0 }],
  ])('unwinds a created member binding on %s after the bind', async (_label, badCount) => {
    const fake = fakePort({ countBindingsResponses: [badCount as Bindings] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [CREATED_AUTH_ID] });
    expect(writes(fake.calls)).toEqual([
      { method: 'createConfirmedAuthUser', args: [EMAIL] },
      { method: 'bindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID, EMAIL] },
      { method: 'unbindMember', args: [TENANT_ID, MEMBER_ID, CREATED_AUTH_ID] },
      { method: 'deleteAuthUser', args: [CREATED_AUTH_ID] },
    ]);
    assertRedacted(result);
  });
});

describe('PROV-009 redact all results', () => {
  it('redacts the request email even for an invalid request rejected before any lookup', async () => {
    const fake = fakePort();
    const result = await provisionIdentity(fake.port, request({ gymCode: 'invalid' }));
    expect(result.code).toBe('invalid_request');
    expect(fake.calls).toEqual([]);
    assertRedacted(result);
  });

  it('redacts planned creation and never copies private target-row data', async () => {
    const fake = fakePort({ members: [member({ privateNote: 'password-secret' })] });
    const result = await provisionIdentity(fake.port, request());
    assertRedacted(result);
    expect(Object.keys(result).sort()).toEqual(['authUser', 'authUserId', 'code', 'email', 'ok', 'target']);
  });

  it('redacts an already-linked identity, including sensitive extra Auth fields', async () => {
    const fake = fakePort({
      members: [member({ userId: AUTH_ID })],
      authUsers: [authUser({ accessToken: 'access-token-secret', refreshToken: 'refresh-token-secret', password: 'password-secret' })],
      bindings: { [AUTH_ID]: { members: 1, staff: 0, platform: 0 } },
    });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result.code).toBe('already_linked');
    assertRedacted(result);
  });

  it('redacts an email-mismatch refusal without echoing either complete address', async () => {
    const otherEmail = 'another-person@example.com';
    const fake = fakePort({ staff: [staff({ email: otherEmail })] });
    const result = await provisionIdentity(fake.port, staffRequest({ apply: true }));
    expect(result.code).toBe('email_mismatch');
    assertRedacted(result, [otherEmail]);
  });

  it('redacts an address supplied with different casing', async () => {
    const fake = fakePort();
    const result = await provisionIdentity(fake.port, request({ email: EMAIL.toUpperCase() }));
    expect(result.code).toBe('planned');
    expect(result.email).toBe(REDACTED_EMAIL);
    expect(JSON.stringify(result)).not.toContain(EMAIL.toUpperCase());
  });
});

describe('PROV-012 fail closed on lookup errors', () => {
  it.each([
    ['findGymByCode', request()],
    ['findMember', request()],
    ['findStaff', staffRequest()],
    ['findAuthUserByEmail', request()],
    ['countBindings', request()],
  ] as const)('reports a generic lookup_failed when %s throws before any write', async (lookup, input) => {
    const fake = fakePort({
      authUsers: [authUser()],
      lookupErrors: { [lookup]: new Error(`private lookup failed: ${SECRET_MARKERS.join(' ')}`) },
    });
    const result = await provisionIdentity(fake.port, { ...input, apply: true });
    expect(result).toMatchObject({ ok: false, code: 'lookup_failed' });
    expect(methodNames(fake.calls)).toContain(lookup);
    assertReadOnly(fake.calls);
    assertRedacted(result);
  });

  it('reports lookup_failed if counting bindings for an already-linked row throws', async () => {
    const fake = fakePort({
      members: [member({ userId: AUTH_ID })], authUsers: [authUser()],
      lookupErrors: { countBindings: new Error(`private lookup failed: ${SECRET_MARKERS.join(' ')}`) },
    });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'lookup_failed' });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
    assertRedacted(result);
  });

  it.each([
    ['missing members', { staff: 0, platform: 0 }],
    ['null staff', { members: 0, staff: null, platform: 0 }],
    ['non-numeric platform', { members: 0, staff: 0, platform: '0' }],
  ])('refuses a %s count during pre-bind checks without any writes', async (_label, badCount) => {
    const fake = fakePort({ authUsers: [authUser()], countBindingsResponses: [badCount as Bindings] });
    const result = await provisionIdentity(fake.port, request({ apply: true }));
    expect(result).toMatchObject({ ok: false, code: 'lookup_failed' });
    expect(fake.calls).toContainEqual({ method: 'countBindings', args: [AUTH_ID] });
    assertReadOnly(fake.calls);
    assertRedacted(result);
  });
});

afterEach(() => { vi.restoreAllMocks(); });

async function assertInvalidCli(argv: string[]) {
  const fetchSpy = vi.spyOn(globalThis, 'fetch').mockImplementation(() => { throw new Error('network must not be called'); });
  let printed = '';
  vi.spyOn(process.stdout, 'write').mockImplementation((chunk) => { printed += String(chunk); return true; });
  vi.spyOn(console, 'log').mockImplementation((...chunks) => { printed += `${chunks.join(' ')}\n`; });
  expect(await main(argv)).toBe(1);
  expect(fetchSpy).not.toHaveBeenCalled();
  expect(printed).toMatch(/^\{[^\r\n]*\}\r?\n?$/);
  const result = JSON.parse(printed) as { ok: boolean; code: string; email?: string | null };
  expect(result).toMatchObject({ ok: false, code: 'invalid_request' });
  if (result.email != null) expect(result.email).toBe(REDACTED_EMAIL);
  for (const secret of SECRET_MARKERS) expect(printed).not.toContain(secret);
}

describe('PROV-010 CLI invalid flags: JSON only, no network', () => {
  const complete = ['--email', EMAIL, '--gym', GYM_CODE, '--member', MEMBER_ID];

  it.each([
    ['email', ['--gym', GYM_CODE, '--member', MEMBER_ID]],
    ['gym', ['--email', EMAIL, '--member', MEMBER_ID]],
    ['target', ['--email', EMAIL, '--gym', GYM_CODE]],
    ['email value', ['--email']],
    ['gym value', ['--email', EMAIL, '--gym']],
  ])('refuses missing %s without fetching anything', async (_label, argv) => {
    await assertInvalidCli(argv);
  });

  it.each([
    ['email', [...complete, '--email', EMAIL]],
    ['gym', [...complete, '--gym', GYM_CODE]],
    ['member', [...complete, '--member', MEMBER_ID]],
    ['staff', ['--email', EMAIL, '--gym', GYM_CODE, '--staff', STAFF_ID, '--staff', STAFF_ID]],
    ['apply', [...complete, '--apply', '--apply']],
  ])('refuses duplicate --%s without fetching anything', async (_label, argv) => {
    await assertInvalidCli(argv);
  });

  it.each([
    ['both kinds', [...complete, '--staff', STAFF_ID]],
    ['neither kind', ['--email', EMAIL, '--gym', GYM_CODE]],
  ])('refuses %s and emits exactly one redacted JSON line', async (_label, argv) => {
    await assertInvalidCli(argv);
  });
});

describe('PROV-007a supabase-js adapter: conditional bind and unbind', () => {
  it('binds member through UPDATE before filtering by tenant, id, null user, escaped email and still-eligible status', async () => {
    const fake = fakeAdapter({ replies: [{ data: [{ id: MEMBER_ID }], error: null, count: 1 }] });
    const wildcardEmail = '  Alice_%\\+play@example.com  ';
    const rows = await fake.port.bindMember(TENANT_ID, MEMBER_ID, AUTH_ID, wildcardEmail);
    expect(rows).toBe(1);
    expect(fake.calls.slice(0, 2)).toEqual([
      { method: 'from', args: ['members'] },
      { method: 'update', args: [{ user_id: AUTH_ID }] },
    ]);
    assertAdapterCalls(fake.calls, [
      { method: 'eq', args: ['tenant_id', TENANT_ID] },
      { method: 'eq', args: ['id', MEMBER_ID] },
      { method: 'is', args: ['user_id', null] },
      { method: 'ilike', args: ['email', 'Alice\\_\\%\\\\+play@example.com'] },
      { method: 'is', args: ['erased_at', null] },
    ]);
    const statusCalls = fake.calls.filter((call) => call.args[0] === 'status');
    expect(statusCalls.some((call) => call.method === 'not' && call.args[1] === 'in'
      && String(call.args[2]).includes('cancelled') && String(call.args[2]).includes('blocked'))
      || statusCalls.some((call) => call.method === 'neq' && call.args[1] === 'cancelled')
      && statusCalls.some((call) => call.method === 'neq' && call.args[1] === 'blocked')).toBe(true);
    expect(fake.calls.some((call) => call.method === 'await' || call.method === 'single' || call.method === 'maybeSingle')).toBe(true);
  });

  it('binds staff only if active and not a gym owner, with an email predicate and exact count', async () => {
    const fake = fakeAdapter({ replies: [{ data: [], error: null, count: 0 }] });
    expect(await fake.port.bindStaff(TENANT_ID, STAFF_ID, AUTH_ID, EMAIL)).toBe(0);
    expect(fake.calls.slice(0, 2)).toEqual([
      { method: 'from', args: ['staff'] }, { method: 'update', args: [{ user_id: AUTH_ID }] },
    ]);
    assertAdapterCalls(fake.calls, [
      { method: 'eq', args: ['tenant_id', TENANT_ID] }, { method: 'eq', args: ['id', STAFF_ID] },
      { method: 'is', args: ['user_id', null] }, { method: 'ilike', args: ['email', EMAIL] },
      { method: 'eq', args: ['is_active', true] }, { method: 'neq', args: ['role', 'gym_owner'] },
    ]);
  });

  it.each([
    ['member', 'members', MEMBER_ID], ['staff', 'staff', STAFF_ID],
  ] as const)('unbinds a %s only where tenant, row and current user all agree', async (kind, table, id) => {
    const fake = fakeAdapter({ replies: [{ data: [{ id }], error: null, count: 1 }] });
    const affected = kind === 'member'
      ? await fake.port.unbindMember(TENANT_ID, id, AUTH_ID)
      : await fake.port.unbindStaff(TENANT_ID, id, AUTH_ID);
    expect(affected).toBe(1);
    expect(fake.calls.slice(0, 2)).toEqual([
      { method: 'from', args: [table] }, { method: 'update', args: [{ user_id: null }] },
    ]);
    assertAdapterCalls(fake.calls, [
      { method: 'eq', args: ['tenant_id', TENANT_ID] },
      { method: 'eq', args: ['id', id] },
      { method: 'eq', args: ['user_id', AUTH_ID] },
    ]);
  });

  it('keeps the bind email predicate and fails closed when the update affects no rows', async () => {
    const fake = fakeAdapter({ replies: [{ data: [], error: null, count: 0 }] });
    expect(await fake.port.bindMember(TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL)).toBe(0);
    expect(fake.calls).toContainEqual({ method: 'ilike', args: ['email', EMAIL] });
  });
});

describe('PROV-006 supabase-js adapter: complete binding counts', () => {
  it('counts user_id in all three tables with exact count, not row count or missing-count coercion', async () => {
    const fake = fakeAdapter({ replies: [
      { data: null, error: null, count: 1 }, { data: null, error: null, count: 2 },
      { data: null, error: null, count: 0 },
    ] });
    expect(await fake.port.countBindings(AUTH_ID)).toEqual({ members: 1, staff: 2, platform: 0 });
    expect(fake.calls.filter((call) => call.method === 'from')).toEqual([
      { method: 'from', args: ['members'] }, { method: 'from', args: ['staff'] },
      { method: 'from', args: ['platform_users'] },
    ]);
    expect(fake.calls.filter((call) => call.method === 'select')).toEqual([
      { method: 'select', args: ['user_id', { count: 'exact', head: true }] },
      { method: 'select', args: ['user_id', { count: 'exact', head: true }] },
      { method: 'select', args: ['user_id', { count: 'exact', head: true }] },
    ]);
    expect(fake.calls.filter((call) => call.method === 'eq')).toEqual([
      { method: 'eq', args: ['user_id', AUTH_ID] },
      { method: 'eq', args: ['user_id', AUTH_ID] },
      { method: 'eq', args: ['user_id', AUTH_ID] },
    ]);
  });

  it.each(['error', 'null-count'] as const)('throws generically for an %s from countBindings', async (failure) => {
    const fake = fakeAdapter({ replies: [{
      data: null,
      error: failure === 'error' ? { message: `private ${SECRET_MARKERS.join(' ')}` } : null,
      count: failure === 'error' ? 0 : null,
    }] });
    await assertGenericError(fake.port.countBindings(AUTH_ID));
  });
});

describe('PROV-006a supabase-js adapter: bounded Auth directory and verification flags', () => {
  it('pages until matching the address, maps only trusted metadata and matching Google identity', async () => {
    const otherUsers = Array.from({ length: PROVISION_IDENTITY_LIMITS.authListUsersPerPage }, (_, index) => ({
      id: `other-${index}`, email: `other${index}@example.com`,
    }));
    const fake = fakeAdapter({ listPages: [otherUsers, [{
      id: AUTH_ID, email: EMAIL.toUpperCase(), app_metadata: { gymloop_provisioned: true },
      identities: [
        { provider: 'google', identity_data: { email: `  ${EMAIL.toUpperCase()}  ` } },
        { provider: 'email', identity_data: { email: EMAIL } },
      ],
    }]] });
    expect(await fake.port.findAuthUserByEmail(EMAIL)).toMatchObject({
      id: AUTH_ID, provisioned: true, googleVerified: true, hasEmailIdentity: true,
    });
    expect(fake.calls.filter((call) => call.method === 'listUsers')).toEqual([
      { method: 'listUsers', args: [{ page: 1, perPage: PROVISION_IDENTITY_LIMITS.authListUsersPerPage }] },
      { method: 'listUsers', args: [{ page: 2, perPage: PROVISION_IDENTITY_LIMITS.authListUsersPerPage }] },
    ]);
  });

  it('maps false flags for a directory match with no metadata or identities', async () => {
    const fake = fakeAdapter({ listPages: [[{ id: AUTH_ID, email: EMAIL }]] });
    expect(await fake.port.findAuthUserByEmail(EMAIL)).toMatchObject({
      id: AUTH_ID, provisioned: false, googleVerified: false, hasEmailIdentity: false,
    });
  });

  it('does not mark a Google identity verified when its email differs', async () => {
    const fake = fakeAdapter({ listPages: [[{
      id: AUTH_ID, email: EMAIL, app_metadata: { gymloop_provisioned: 'true' },
      identities: [{ provider: 'google', identity_data: { email: 'other@example.com' } }],
    }]] });
    expect(await fake.port.findAuthUserByEmail(EMAIL)).toMatchObject({
      provisioned: false, googleVerified: false, hasEmailIdentity: false,
    });
  });

  it('treats an exactly full final directory page as exhausted, not an error', async () => {
    const full = Array.from({ length: PROVISION_IDENTITY_LIMITS.authListUsersPerPage }, (_, index) => ({
      id: `other-${index}`, email: `other${index}@example.com`,
    }));
    const pages = Array.from({ length: PROVISION_IDENTITY_LIMITS.authListUsersMaxPages }, () => full);
    const fake = fakeAdapter({ listPages: [...pages, []] });
    expect(await fake.port.findAuthUserByEmail(EMAIL)).toBeNull();
    expect(fake.calls.filter((call) => call.method === 'listUsers')).toHaveLength(PROVISION_IDENTITY_LIMITS.authListUsersMaxPages + 1);
  });

  it('fails closed if an additional page is present beyond the directory cap', async () => {
    const full = Array.from({ length: PROVISION_IDENTITY_LIMITS.authListUsersPerPage }, (_, index) => ({
      id: `other-${index}`, email: `other${index}@example.com`,
    }));
    const pages = Array.from({ length: PROVISION_IDENTITY_LIMITS.authListUsersMaxPages + 1 }, () => full);
    const fake = fakeAdapter({ listPages: pages });
    await assertGenericError(fake.port.findAuthUserByEmail(EMAIL));
  });

  it('throws generically rather than treating a listUsers API error as an absent Auth user', async () => {
    const fake = fakeAdapter({ adminErrors: { listUsers: { message: `private ${SECRET_MARKERS.join(' ')}` } } });
    await assertGenericError(fake.port.findAuthUserByEmail(EMAIL));
  });
});

describe('PROV-007 supabase-js adapter: create confirmed, provisioned Auth users', () => {
  it('creates with provisioned metadata, confirmed email and no password field', async () => {
    const fake = fakeAdapter();
    expect(await fake.port.createConfirmedAuthUser(EMAIL)).toEqual({ id: CREATED_AUTH_ID });
    expect(fake.calls).toEqual([{ method: 'createUser', args: [{
      email: EMAIL, email_confirm: true, app_metadata: { gymloop_provisioned: true },
    }] }]);
    expect(JSON.stringify(fake.calls)).not.toContain('password');
  });

  it.each(['createUser', 'deleteUser'] as const)('throws a secret-safe error on %s failure', async (method) => {
    const fake = fakeAdapter({ adminErrors: { [method]: { message: `private ${SECRET_MARKERS.join(' ')}` } } });
    const operation = method === 'createUser' ? fake.port.createConfirmedAuthUser(EMAIL) : fake.port.deleteAuthUser(AUTH_ID);
    await assertGenericError(operation);
  });

  it.each([
    'findGymByCode', 'findMember', 'findStaff', 'bindMember', 'bindStaff', 'unbindMember', 'unbindStaff',
  ] as const)('throws a secret-safe error on %s query failure', async (method) => {
    const fake = fakeAdapter({ replies: [{ data: null, error: { message: `private ${SECRET_MARKERS.join(' ')}` }, count: 0 }] });
    const operation = {
      findGymByCode: () => fake.port.findGymByCode(GYM_CODE),
      findMember: () => fake.port.findMember(TENANT_ID, MEMBER_ID),
      findStaff: () => fake.port.findStaff(TENANT_ID, STAFF_ID),
      bindMember: () => fake.port.bindMember(TENANT_ID, MEMBER_ID, AUTH_ID, EMAIL),
      bindStaff: () => fake.port.bindStaff(TENANT_ID, STAFF_ID, AUTH_ID, EMAIL),
      unbindMember: () => fake.port.unbindMember(TENANT_ID, MEMBER_ID, AUTH_ID),
      unbindStaff: () => fake.port.unbindStaff(TENANT_ID, STAFF_ID, AUTH_ID),
    }[method]();
    await assertGenericError(operation);
  });
});
