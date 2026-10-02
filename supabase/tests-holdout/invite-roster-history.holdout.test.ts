// Independent contract-derived INV-025/026/027/028 suite. No implementation or other tests consulted.
import { createRequire } from 'node:module';
import { beforeEach, afterEach, describe, expect, it, vi } from 'vitest';

const webRequire = createRequire(new URL('../../apps/web/package.json', import.meta.url));
const React = webRequire('react');
const { renderToStaticMarkup } = webRequire('react-dom/server');
const h = vi.hoisted(() => ({ client: null as any, identity: null as any, cookies: [] as any[] }));
vi.mock('../../apps/web/lib/supabase/server.ts', () => ({ createServerSupabase: async () => h.client }));
vi.mock('../../apps/web/lib/identity-session.ts', () => ({
  readIdentity: async () => h.identity,
  requireAudience: async () => ({ ...h.identity, identity: h.identity, supabase: h.client }),
}));
vi.mock('next/navigation', () => ({
  redirect: (url: string) => { throw new Error(`redirect:${url}`); },
  notFound: () => { throw new Error('not-found'); },
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
  usePathname: () => '/console',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('next/headers', () => ({ cookies: async () => ({
  set: (...args: any[]) => h.cookies.push(args), get: () => undefined, getAll: () => [],
}) }));

const fixture = {
  tenant: '17777777-7777-4777-8777-777777777777',
  otherTenant: '28888888-8888-4888-8888-888888888888',
  viewer: '39999999-9999-4999-8999-999999999999',
  staff: '41111111-1111-4111-8111-111111111111',
  author: '52222222-2222-4222-8222-222222222222',
  target: '63333333-3333-4333-8333-333333333333',
  peer: '74444444-4444-4444-8444-444444444444',
  invite: '85555555-5555-4555-8555-555555555555',
  oldInvite: '96666666-6666-4666-8666-666666666666',
  otherInvite: 'a7777777-7777-4777-8777-777777777777',
  issued: '2026-09-29T19:45:00.000Z',
  expiry: '2026-10-01T19:45:00.000Z',
  now: '2026-10-02T03:00:00.000Z',
  token: 'IndependentInviteTokenNeverRender01234567890',
  hash: 'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
};
let rows: Record<string, any[]>;
let failures: Set<string>;
let reads: string[];
let rpcState: string;

function member(id: string, full_name: string, extra: Record<string, any> = {}) {
  return { id, tenant_id: fixture.tenant, full_name, phone: '+919876543210', email: 'member@holdout.example',
    status: 'active', user_id: null, erased_at: null, joined_on: '2026-09-01', member_code: 'HOLD',
    created_at: fixture.issued, updated_at: fixture.issued, ...extra };
}
function invite(id: string, member_id: string, status: string, extra: Record<string, any> = {}) {
  return { id, member_id, tenant_id: fixture.tenant, status, token_hash: fixture.hash,
    issued_by_staff_id: fixture.staff, issued_at: fixture.issued, expires_at: fixture.expiry,
    closed_at: status === 'pending' ? null : fixture.expiry, closed_by_staff_id: fixture.staff,
    redeemed_user_id: null, ...extra };
}
function event(id: string, action: string, record_id: string, extra: Record<string, any> = {}) {
  return { id, tenant_id: fixture.tenant, actor_user_id: fixture.author, actor_role: 'gym_manager',
    action, record_type: 'member_invite', record_id, before: null,
    after: { member_id: fixture.target, token: fixture.token, token_hash: fixture.hash, diagnostic: 'PRIVATE_AUDIT_JSON' },
    reason: null, occurred_at: fixture.issued, ...extra };
}

// The fake executes supplied query predicates. It models tenant RLS independently of page code;
// same-tenant wrong-target history still requires a genuine target-bound query/projection.
function query(table: string) {
  reads.push(table);
  if (table === 'audit_log') throw new Error('INV-028 forbids a broad web audit_log read');
  let data = [...(rows[table] ?? [])].filter(row => row.tenant_id == null || row.tenant_id === fixture.tenant);
  let one = false;
  const q: any = {
    select: () => q,
    eq: (key: string, value: any) => { data = data.filter(row => row[key] === value); return q; },
    neq: (key: string, value: any) => { data = data.filter(row => row[key] !== value); return q; },
    is: (key: string, value: any) => { data = data.filter(row => row[key] === value); return q; },
    in: (key: string, values: any[]) => { data = data.filter(row => values.includes(row[key])); return q; },
    ilike: (key: string, value: string) => { data = data.filter(row => String(row[key] ?? '').toLowerCase().includes(value.replaceAll('%', '').toLowerCase())); return q; },
    order: (key: string, options: any = {}) => { data.sort((a, b) => String(a[key]).localeCompare(String(b[key])) * (options.ascending === false ? -1 : 1)); return q; },
    limit: (n: number) => { data = data.slice(0, n); return q; },
    range: (a: number, b: number) => { data = data.slice(a, b + 1); return q; },
    gt: (key: string, value: any) => { data = data.filter(row => row[key] > value); return q; },
    gte: (key: string, value: any) => { data = data.filter(row => row[key] >= value); return q; },
    lt: (key: string, value: any) => { data = data.filter(row => row[key] < value); return q; },
    lte: (key: string, value: any) => { data = data.filter(row => row[key] <= value); return q; },
    not: (key: string, op: string, value: any) => { if (op === 'is') data = data.filter(row => row[key] !== value); return q; },
    or: () => q,
    single: () => { one = true; return q; }, maybeSingle: () => { one = true; return q; },
    then: (resolve: any, reject: any) => Promise.resolve(failures.has(table)
      ? { data: null, error: { message: 'PRIVATE_QUERY_FAILURE' }, count: null }
      : { data: one ? data[0] ?? null : data, error: null, count: data.length }).then(resolve, reject),
  };
  return q;
}
function client() {
  return {
    from: query,
    rpc: vi.fn(async (name: string, args: Record<string, unknown>) => {
      reads.push(name);
      if (failures.has(name)) return { data: null, error: { message: 'PRIVATE_RPC_FAILURE' } };
      if (name === 'read_member_app_access') return { data: [{ state: rpcState, invite_id: fixture.invite,
        issued_at: fixture.issued, expires_at: fixture.expiry, linked_at: null }], error: null };
      if (name === 'read_member_invite_history') {
        // Emulate only the frozen projection contract, never an implementation helper.
        expect(args).toEqual({ p_member_id: fixture.target });
        const allowed = ['member_invite.issued', 'member_invite.superseded', 'member_invite.revoked',
          'member_invite.redeemed', 'member.linked', 'member.unlinked'];
        const projected = rows.audit_log.filter(row => {
          if (row.tenant_id !== fixture.tenant || !allowed.includes(row.action)) return false;
          if (row.record_type === 'member') return row.record_id === args.p_member_id;
          return row.record_type === 'member_invite' && rows.member_invites.some(inv =>
            inv.id === row.record_id && inv.tenant_id === fixture.tenant && inv.member_id === args.p_member_id);
        }).map(row => {
          const recordedStaff = rows.staff.find(staff => staff.tenant_id === fixture.tenant && staff.user_id === row.actor_user_id);
          const recordedMember = rows.members.find(member => member.tenant_id === fixture.tenant && member.id === args.p_member_id && member.user_id === row.actor_user_id);
          return { event_id: row.id, occurred_at: row.occurred_at, action: row.action,
            actor_name: recordedStaff?.full_name ?? (row.actor_role === 'member' ? recordedMember?.full_name : null) ?? null };
        }).sort((a, b) => b.occurred_at.localeCompare(a.occurred_at) || b.event_id.localeCompare(a.event_id)).slice(0, 50);
        return { data: projected, error: null };
      }
      return { data: [], error: null };
    }),
    auth: {
      getUser: async () => ({ data: { user: { id: fixture.viewer, email: 'viewer@holdout.example' } }, error: null }),
      getClaims: async () => ({ data: { claims: { sub: fixture.viewer, tenant_id: fixture.tenant,
        staff_id: fixture.staff, app_role: h.identity.role, impersonation_session_id: h.identity.impersonationId ?? null } }, error: null }),
      signInWithOAuth: vi.fn(async () => ({ data: { url: 'https://accounts.google.com/holdout' }, error: null })),
      signOut: vi.fn(async () => ({ error: null })),
    },
  };
}
async function roster(params: Record<string, string> = {}) {
  const { default: Page } = await import('../../apps/web/app/(console)/console/page');
  return renderToStaticMarkup(await Page({ searchParams: Promise.resolve(params) }));
}
async function detail() {
  const { default: Page } = await import('../../apps/web/app/(console)/members/[memberId]/page');
  return renderToStaticMarkup(await Page({ params: Promise.resolve({ memberId: fixture.target }), searchParams: Promise.resolve({}) }));
}
function plain(markup: string) { return markup.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' '); }
function assertPrivate(markup: string) {
  for (const secret of [fixture.hash, fixture.token, 'PRIVATE_AUDIT_JSON', 'PRIVATE_QUERY_FAILURE', 'PRIVATE_RPC_FAILURE', 'REFUSAL_IDENTITY']) {
    expect(markup).not.toContain(secret);
  }
}
function rowFor(markup: string, name: string) {
  const matches = markup.match(/<tr\b[^>]*>[\s\S]*?<\/tr>/g) ?? [];
  const row = matches.find((candidate: string) => candidate.includes(name));
  expect(row, `member ${name} must have an inline roster row`).toBeTruthy();
  return row!;
}
function filterParams(markup: string) {
  const link = (markup.match(/<a\b[^>]*>[\s\S]*?<\/a>/g) ?? []).find(x => /Not joined yet/i.test(plain(x)));
  if (link) {
    const href = link.match(/href="([^"]+)"/)?.[1]?.replaceAll('&amp;', '&');
    expect(href).toBeTruthy();
    return Object.fromEntries(new URL(href!, 'https://holdout.example').searchParams);
  }
  const select = (markup.match(/<select\b[^>]*>[\s\S]*?<\/select>/g) ?? []).find(x => /Not joined yet/i.test(plain(x)));
  if (select) {
    const name = select.match(/name="([^"]+)"/)?.[1];
    const option = (select.match(/<option\b[^>]*>[\s\S]*?<\/option>/g) ?? []).find(x => /Not joined yet/i.test(plain(x)));
    expect(name).toBeTruthy();
    expect(option).toBeTruthy();
    const value = option!.match(/value="([^"]*)"/)?.[1];
    expect(value).toBeTruthy();
    return { [name!]: value! };
  }
  const control = (markup.match(/<label\b[^>]*>[\s\S]*?<\/label>/g) ?? []).find(x => /Not joined yet/i.test(plain(x)));
  expect(control, 'Not joined yet must be a usable filter, not explanatory text').toBeTruthy();
  const name = control!.match(/name="([^"]+)"/)?.[1];
  const value = control!.match(/value="([^"]+)"/)?.[1] ?? 'on';
  expect(name).toBeTruthy();
  return { [name!]: value };
}

beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(new Date(fixture.now));
  failures = new Set(); reads = []; rpcState = 'invite_expired'; h.cookies = [];
  h.identity = { kind: 'staff', role: 'gym_manager', userId: fixture.viewer, tenantId: fixture.tenant, staffId: fixture.staff };
  rows = {
    members: [member(fixture.target, 'Holdout Mira'), member(fixture.peer, 'Holdout Peer')],
    organizations: [{ id: fixture.tenant, name: 'Holdout Gym', status: 'active', timezone: 'Asia/Kolkata' }],
    organization_settings: [{ tenant_id: fixture.tenant, timezone: 'Asia/Kolkata' }],
    member_invites: [invite(fixture.invite, fixture.target, 'pending')],
    staff: [ { id: fixture.staff, tenant_id: fixture.tenant, user_id: fixture.viewer, full_name: 'VIEWER_NOT_AUTHOR', role: 'gym_manager', is_active: true },
      { id: fixture.author, tenant_id: fixture.tenant, user_id: fixture.author, full_name: 'Persisted Nila', role: 'gym_manager', is_active: false } ],
    audit_log: [], attendance: [], memberships: [], payments: [], branches: [],
  };
  h.client = client();
});
afterEach(() => vi.useRealTimers());

describe('INV-025 actual member roster boundary', () => {
  it('derives expired pending from server time and gives raw enum plus sent/expiry explicitly in IST', async () => {
    const html = await roster(); const row = rowFor(html, 'Holdout Mira');
    expect(plain(row)).toMatch(/expired/i);
    expect(plain(row)).toMatch(/pending/i);
    expect(plain(row)).toMatch(/sent|issued/i); expect(plain(row)).toMatch(/expir/i);
    expect(plain(row).match(/IST/g)?.length ?? 0).toBeGreaterThanOrEqual(2);
    expect(row).toMatch(/aria-hidden="true"|status-dot|data-status|●|•/);
    assertPrivate(html);
  });
  it.each(['revoked', 'redeemed', 'superseded'])('keeps latest %s invite truth on the member row', async status => {
    rows.member_invites = [invite(fixture.oldInvite, fixture.target, 'pending', { issued_at: '2026-09-28T00:00:00Z' }),
      invite(fixture.invite, fixture.target, status)];
    const row = rowFor(await roster(), 'Holdout Mira');
    expect(plain(row)).toMatch(new RegExp(status, 'i'));
    expect(plain(row)).toMatch(/IST/);
  });
  it('Not joined yet includes unavailable/null bindings but excludes every non-null binding', async () => {
    rows.members = [member(fixture.target, 'Never invited'), member(fixture.peer, 'Cancelled null', { status: 'cancelled' }),
      member('b8888888-8888-4888-8888-888888888888', 'Linked active', { user_id: fixture.author }),
      member('c9999999-9999-4999-8999-999999999999', 'Blocked bound', { status: 'blocked', user_id: fixture.viewer })];
    rows.member_invites = [];
    const params = filterParams(await roster());
    const html = await roster(params);
    expect(html).toContain('Never invited'); expect(html).toContain('Cancelled null');
    expect(html).not.toContain('Linked active'); expect(html).not.toContain('Blocked bound');
  });
  it('reports failed invite reads rather than a successful state or empty invite history', async () => {
    failures.add('member_invites'); failures.add('read_member_app_access');
    const html = await roster();
    expect(plain(html)).toMatch(/could not|couldn.t|unable|unavailable|error|try again/i);
    expect(plain(rowFor(html, 'Holdout Mira'))).not.toMatch(/invite pending|linked|not invited/i);
    assertPrivate(html);
  });
  it.each(['trainer', 'preview'])('does not fetch or render invite metadata for %s', async audience => {
    if (audience === 'trainer') h.identity.role = 'trainer';
    else h.identity = { kind: 'impersonation', role: 'super_admin', userId: fixture.viewer,
      tenantId: fixture.tenant, impersonationId: fixture.invite, impersonationSessionId: fixture.invite };
    const html = await roster();
    expect(reads).not.toContain('member_invites'); expect(reads).not.toContain('audit_log');
    expect(reads).not.toContain('read_member_app_access');
    expect(plain(html)).not.toMatch(/invite pending|invite expired|Not joined yet/);
    assertPrivate(html);
  });
});

describe('INV-026 persisted member history at actual detail boundary', () => {
  it('INV-028 exposes the separately named history bound of 50', async () => {
    const shared = await import('@gymloop/shared');
    expect((shared as any).MEMBER_INVITE_HISTORY_LIMIT).toBe(50);
  });
  it('shows issue, supersede and revoke, attributed to persisted actor, with IST and no audit metadata', async () => {
    rows.member_invites.push(invite(fixture.oldInvite, fixture.target, 'superseded'));
    rows.audit_log = [event('d1111111-1111-4111-8111-111111111111', 'member_invite.issued', fixture.invite),
      event('d2222222-2222-4222-8222-222222222222', 'member_invite.superseded', fixture.oldInvite),
      event('d3333333-3333-4333-8333-333333333333', 'member_invite.revoked', fixture.invite)];
    const html = await detail(); const text = plain(html);
    expect(h.client.rpc).toHaveBeenCalledWith('read_member_invite_history', { p_member_id: fixture.target });
    expect(reads).not.toContain('audit_log');
    expect(text).toMatch(/invite.*history|invite.*activity|app access.*history/i);
    expect(text).toContain('Persisted Nila'); expect(text).not.toContain('VIEWER_NOT_AUTHOR');
    expect(text).toMatch(/issued|sent/i); expect(text).toMatch(/superseded|replaced/i); expect(text).toMatch(/revoked/i);
    expect(text.match(/IST/g)?.length ?? 0).toBeGreaterThanOrEqual(3);
    assertPrivate(html);
  });
  it('does not accept same-tenant wrong-target, foreign-tenant or refusal-attempt events', async () => {
    rows.member_invites.push(invite(fixture.otherInvite, fixture.peer, 'pending'));
    rows.audit_log = [event('e1111111-1111-4111-8111-111111111111', 'member_invite.issued', fixture.otherInvite,
      { after: { member_id: fixture.peer }, occurred_at: '2026-08-16T00:00:00Z' }),
      event('e2222222-2222-4222-8222-222222222222', 'member_invite.revoked', fixture.invite,
        { tenant_id: fixture.otherTenant, occurred_at: '2026-08-17T00:00:00Z' }),
      event('e3333333-3333-4333-8333-333333333333', 'member_invite.redeem_refused', fixture.invite,
        { after: { outcome: 'email_mismatch', identity: 'REFUSAL_IDENTITY' }, occurred_at: '2026-08-18T00:00:00Z' })];
    const html = await detail();
    expect(plain(html)).toMatch(/no .*history|no .*activity|no .*events|no .*invites|no .*record/i);
    expect(plain(html)).not.toMatch(/superseded|revoked|redeem refused|email_mismatch/);
    assertPrivate(html);
  });
  it('uses honest fallback for an unresolved historical actor, never the viewer', async () => {
    rows.staff = rows.staff.filter(row => row.user_id !== fixture.author);
    rows.audit_log = [event('f1111111-1111-4111-8111-111111111111', 'member_invite.issued', fixture.invite)];
    const text = plain(await detail());
    expect(text).toContain('Name unavailable');
    expect(text).not.toContain('VIEWER_NOT_AUTHOR');
  });
  it('distinguishes failed audit read from empty history and never invents an event', async () => {
    failures.add('read_member_invite_history');
    const html = await detail();
    expect(plain(html)).toMatch(/history.*(?:unavailable|could|unable|error)|(?:could|unable).*history|activity.*(?:unavailable|error)/i);
    expect(plain(html)).not.toMatch(/no invite history|no invite activity/i);
    assertPrivate(html);
  });
  it('unknown raw access state cannot render as linked or a successful invite', async () => {
    rpcState = 'accidentally_successful';
    const html = await detail();
    expect(plain(html)).not.toContain('accidentally_successful');
    expect(plain(html)).toMatch(/unavailable|could not|couldn.t|unable|error/i);
    assertPrivate(html);
  });
  it.each(['trainer', 'preview'])('excludes history for %s', async audience => {
    if (audience === 'trainer') h.identity.role = 'trainer';
    else h.identity = { kind: 'impersonation', role: 'super_admin', userId: fixture.viewer,
      tenantId: fixture.tenant, impersonationId: fixture.invite, impersonationSessionId: fixture.invite };
    rows.audit_log = [event('f2222222-2222-4222-8222-222222222222', 'member_invite.issued', fixture.invite)];
    const html = await detail();
    expect(reads).not.toContain('audit_log'); expect(html).not.toContain('Persisted Nila');
    expect(reads).not.toContain('read_member_invite_history');
    assertPrivate(html);
  });
  it('front desk gets the same recent persisted projection without broad audit access', async () => {
    h.identity.role = 'front_desk';
    rows.audit_log = [event('f3333333-3333-4333-8333-333333333333', 'member_invite.revoked', fixture.invite)];
    const html = await detail();
    expect(h.client.rpc).toHaveBeenCalledWith('read_member_invite_history', { p_member_id: fixture.target });
    expect(reads).not.toContain('audit_log');
    expect(plain(html)).toMatch(/recent.*history/i);
    expect(plain(html)).toContain('Persisted Nila');
    expect(plain(html)).toMatch(/revoked/i);
    assertPrivate(html);
  });
  it('shows member-attributed link truth from the projection rather than attributing it to staff', async () => {
    rows.members[0].user_id = fixture.author;
    rows.staff = rows.staff.filter(row => row.user_id !== fixture.author);
    rows.audit_log = [event('f4444444-4444-4444-8444-444444444444', 'member.linked', fixture.target,
      { record_type: 'member', actor_role: 'member' })];
    const html = await detail();
    expect(plain(html)).toMatch(/linked/i);
    expect(plain(html).match(/Holdout Mira/g)?.length ?? 0).toBeGreaterThanOrEqual(2);
    expect(plain(html)).not.toContain('VIEWER_NOT_AUTHOR');
    assertPrivate(html);
  });
  it('renders the complete latest-50 projection in server order and labels it recent', async () => {
    rows.audit_log = Array.from({ length: 51 }, (_, index) => event(
      `a${String(index).padStart(7, '0')}-1111-4111-8111-111111111111`,
      'member_invite.issued', fixture.invite, { actor_user_id: `actor-${index}` }));
    rows.staff.push(...Array.from({ length: 51 }, (_, index) => ({ tenant_id: fixture.tenant,
      id: `staff-${index}`, user_id: `actor-${index}`, full_name: `HistoryActor_${String(index).padStart(2, '0')}` })));
    const html = await detail(); const text = plain(html);
    expect(text).toMatch(/recent.*history/i);
    expect(text).not.toContain('HistoryActor_00');
    expect(text.match(/HistoryActor_\d\d/g)).toHaveLength(50);
    expect(text.indexOf('HistoryActor_50')).toBeLessThan(text.indexOf('HistoryActor_01'));
    expect(reads).not.toContain('audit_log'); assertPrivate(html);
  });
});

describe('INV-027 both actual OAuth starters', () => {
  it.each([
    ['startInviteGoogleSignIn', 'fitcruxx_invite'],
    ['startStaffInviteGoogleSignIn', 'fitcruxx_staff_invite'],
  ])('%s requests chooser and carries token only in its HttpOnly cookie', async (action, cookieName) => {
    const actions = await import('../../apps/web/lib/auth-actions');
    // A valid, independently chosen 43-character base64url value, unrelated to any invite fixture.
    const token = 'Z'.repeat(43);
    await expect((actions as any)[action](token)).rejects.toThrow('redirect:https://accounts.google.com/holdout');
    expect(h.client.auth.signInWithOAuth).toHaveBeenCalledOnce();
    const args = h.client.auth.signInWithOAuth.mock.calls[0][0];
    expect(args.provider).toBe('google');
    expect(args.options.queryParams).toEqual({ prompt: 'select_account' });
    expect(new URL(args.options.redirectTo).pathname).toBe('/auth/callback');
    expect(new URL(args.options.redirectTo).search).toBe('');
    expect(JSON.stringify(args)).not.toContain(token);
    const cookie = h.cookies.find(args => args[0] === cookieName);
    expect(cookie).toBeTruthy(); expect(cookie[1]).toBe(token); expect(cookie[2].httpOnly).toBe(true);
    expect(h.cookies.filter(args => args[0] !== cookieName)).toEqual([]);
  });
});
