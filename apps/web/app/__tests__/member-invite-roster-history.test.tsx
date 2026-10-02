import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

/** Implementation-blind INV v1.2 / INV-025..026, derived from INV-Q9/Q11.
 * Real roster/detail pages and read adapters run against a caller-session query boundary.
 * Fixtures deliberately cross UTC's date boundary, mix closed invite states, and include
 * unrelated audit records. No implementation, migration or holdout was read to author this.
 */
type Row = Record<string, unknown>;
const { state } = vi.hoisted(() => ({ state: {
  role: 'gym_owner', preview: false,
  tables: {} as Record<string, Row[]>, errors: {} as Record<string, boolean>,
  history: [] as Row[], historyError: false,
  calls: [] as Array<{ table: string; method: string; args: unknown[] }>,
} }));
const MEMBER = 'a8200000-0000-4000-8000-000000000001';
const TENANT = 'a8200000-0000-4000-8000-000000000002';
const STAFF = 'a8200000-0000-4000-8000-000000000003';
const ACTOR = 'a8200000-0000-4000-8000-000000000004';
const INVITE = 'a8200000-0000-4000-8000-000000000005';
const OLD_INVITE = 'a8200000-0000-4000-8000-000000000006';
const SENT = '2026-10-02T20:00:00.000Z'; // 3 Oct, 1:30 am IST
const EXPIRES = '2026-10-04T20:00:00.000Z'; // 5 Oct, 1:30 am IST
const TOKEN = 'Z'.repeat(43);
const HASH = 'f'.repeat(64);

function identity() {
  return state.preview
    ? { kind: 'impersonation', userId: ACTOR, tenantId: TENANT, impersonationSessionId: 'preview' }
    : { kind: 'staff', userId: ACTOR, tenantId: TENANT, staffId: STAFF, role: state.role };
}
function client() {
  return {
    auth: {
      getUser: async () => ({ data: { user: { id: ACTOR, email: 'viewer@example.com' } }, error: null }),
      getClaims: async () => ({ data: { claims: { sub: ACTOR, tenant_id: TENANT, staff_id: STAFF, app_role: state.role } }, error: null }),
    },
    from: (table: string) => {
      const filters: Array<(row: Row) => boolean> = [];
      const query: Record<string, unknown> = {};
      const result = () => ({ data: state.errors[table] ? null : (state.tables[table] ?? []).filter((row) => filters.every((filter) => filter(row))), error: state.errors[table] ? { message: 'private backend detail', code: 'XX000' } : null });
      for (const method of ['select', 'eq', 'neq', 'in', 'is', 'order', 'limit', 'range', 'ilike', 'or', 'gte', 'gt', 'lte', 'lt', 'not']) {
        query[method] = (...args: unknown[]) => {
          state.calls.push({ table, method, args });
          const [key, value] = args;
          if (method === 'eq') filters.push((row) => row[String(key)] === value);
          if (method === 'is') filters.push((row) => row[String(key)] === value);
          if (method === 'in') filters.push((row) => (value as unknown[]).includes(row[String(key)]));
          if (method === 'ilike') filters.push((row) => String(row[String(key)] ?? '').includes(String(value).replaceAll('%', '')));
          return query;
        };
      }
      query.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result()).then(resolve);
      query.maybeSingle = async () => { const answer = result(); return { ...answer, data: answer.data?.[0] ?? null }; };
      query.single = query.maybeSingle;
      return query;
    },
    rpc: async (name: string, args: unknown) => {
      state.calls.push({ table: name, method: 'rpc', args: [args] });
      if (name === 'read_member_app_access') return { data: [{ state: 'invite_pending', invite_id: INVITE, issued_at: SENT, expires_at: EXPIRES, linked_at: null }], error: null };
      if (name === 'read_member_invite_history') return {
        data: state.historyError ? null : state.history,
        error: state.historyError ? { code: 'XX000', message: 'private backend detail' } : null,
      };
      throw new Error(`Unexpected command in a read-only page: ${name}`);
    },
  };
}
vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); }, notFound: () => { throw new Error('NOT_FOUND'); },
  useRouter: () => ({ refresh: vi.fn() }), usePathname: () => '/members', useSearchParams: () => new URLSearchParams(),
}));
vi.mock('next/link', () => ({ default: ({ href, children, ...props }: { href: string; children?: ReactNode }) => createElement('a', { href, ...props }, children) }));
vi.mock('next/headers', () => ({ cookies: async () => ({ get: () => undefined, getAll: () => [] }), headers: async () => new Headers() }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({ supabase: client(), identity: identity() }),
  readIdentity: async () => ({ supabase: client(), identity: identity(), signedIn: true }),
}));
vi.mock('../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../(console)/members/member-data', () => ({ loadMember: async () => ({ data: state.tables.members?.[0] ?? null, error: null }) }));
vi.mock('../(console)/preview-context', () => ({
  usePreviewReadOnly: () => state.preview,
  MutationForm: (props: Record<string, unknown>) => createElement('form', props),
}));

const text = (html: string) => html.replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ');
async function roster(params: Record<string, string> = {}) {
  // Registered roster consumer in docs/registry.md (loadMemberSearch).
  const { default: Page } = await import('../(console)/console/page');
  return renderToStaticMarkup(await Page({ searchParams: Promise.resolve(params) }));
}
async function detail() {
  const { default: Page } = await import('../(console)/members/[memberId]/page');
  return renderToStaticMarkup(await Page({ params: Promise.resolve({ memberId: MEMBER }), searchParams: Promise.resolve({}) }));
}
function member(id = MEMBER, full_name = 'Asha Rao', user_id: string | null = null) {
  return { id, tenant_id: TENANT, full_name, phone: '+919876543210', email: 'asha@example.com', status: 'active', branch_id: null, user_id, erased_at: null, joined_on: '2026-09-01', member_code: 'M1' };
}
function invite(status = 'pending', id = INVITE, member_id = MEMBER) {
  return { id, tenant_id: TENANT, member_id, status, issued_at: SENT, expires_at: EXPIRES, issued_by_staff_id: STAFF, token_hash: HASH };
}
function audit(action: string, record_id: string, after: Row, occurred_at = SENT) {
  return { id: `${action}:${record_id}`, tenant_id: TENANT, actor_user_id: ACTOR, actor_role: 'gym_owner', action, record_type: 'member_invite', record_id, before: null, after, occurred_at, reason: null };
}
beforeEach(() => {
  state.role = 'gym_owner'; state.preview = false; state.errors = {}; state.calls = [];
  state.history = []; state.historyError = false;
  state.tables = {
    members: [member()], member_invites: [invite()], audit_log: [],
    staff: [{ id: STAFF, tenant_id: TENANT, user_id: ACTOR, full_name: 'Meera Desk', role: 'gym_owner', is_active: true }],
    organizations: [{ id: TENANT, name: 'Iron Box Fitness', timezone: 'Asia/Kolkata' }], branches: [],
  };
});

describe('INV-025 member roster invite state and queue', () => {
  it('INV-025 failed roster read announces failure without claiming the gym has no members', async () => {
    state.errors.members = true;
    const html = await roster();
    expect(text(html)).toMatch(/could(n.?t| not)|unable|failed|try again/i);
    expect(html).toMatch(/role="alert"|aria-live=/);
    expect(text(html)).not.toMatch(/no members yet|no members|add (your|the) first member/i);
    expect(html).not.toContain('private backend detail');
  });
  it.each(['pending', 'redeemed', 'revoked', 'superseded'])('shows latest %s invite inline with dot plus word and absolute sent/expiry IST', async (status) => {
    state.tables.member_invites = [invite(status)];
    const html = await roster();
    const row = [...html.matchAll(/<(tr|a)\b[^>]*>([\s\S]*?)<\/\1>/g)].find((match) => match[2]?.includes('Asha Rao'))?.[2] ?? '';
    expect(row).not.toBe('');
    expect(text(row)).toMatch(new RegExp(status, 'i'));
    expect(row).toMatch(/class="[^"]*(?:dot|status-indicator)[^"]*"|aria-hidden="true"[^>]*>\s*[●•]/);
    expect(text(row)).toMatch(/3 Oct 2026,?\s+1:30\s*am\s*IST/i);
    expect(text(row)).toMatch(/5 Oct 2026,?\s+1:30\s*am\s*IST/i);
    expect(html).not.toContain(HASH);
  });
  it('distinguishes an expired pending invite without claiming it is active', async () => {
    state.tables.member_invites = [{ ...invite(), issued_at: '2026-09-01T20:00:00Z', expires_at: '2026-09-03T20:00:00Z' }];
    expect(text(await roster())).toMatch(/expired/i);
  });
  it('offers Not joined yet on the list and applies it before pagination while retaining phone search', async () => {
    const html = await roster();
    expect(text(html)).toContain('Not joined yet');
    // Discover the UI's own parameter rather than inventing a public query contract.
    const filter = [...html.matchAll(/<a\b[^>]*href="([^"]*)"[^>]*>([\s\S]*?)<\/a>/g)].find((match) => text(match[2] ?? '').includes('Not joined yet'));
    const option = [...html.matchAll(/<select\b[^>]*name="([^"]*)"[^>]*>([\s\S]*?)<\/select>/g)].map((match) => ({ name: match[1] ?? '', option: [...(match[2] ?? '').matchAll(/<option\b[^>]*value="([^"]*)"[^>]*>([\s\S]*?)<\/option>/g)].find((item) => text(item[2] ?? '').includes('Not joined yet')) })).find((item) => item.option);
    expect(Boolean(filter || option), 'queue must be operable from the member list').toBe(true);
    const params = filter ? Object.fromEntries(new URL((filter[1] ?? '').replaceAll('&amp;', '&'), 'https://app.example').searchParams) : { [option?.name ?? '']: option?.option?.[1] ?? '' };
    state.tables.members = [member(), member('a8200000-0000-4000-8000-000000000007', 'Linked Member', ACTOR)];
    state.calls = [];
    const queued = await roster({ ...params, q: '9876' });
    expect(queued).toContain('Asha Rao'); expect(queued).not.toContain('Linked Member');
    expect(state.calls.some((call) => call.table === 'members' && ['is', 'eq', 'or'].includes(call.method) && JSON.stringify(call.args).includes('user_id'))).toBe(true);
    expect(state.calls.some((call) => call.table === 'members' && call.method === 'ilike' && call.args.includes('%9876%'))).toBe(true);
  });
  it('does not turn an invite read failure into Pending or Linked', async () => {
    state.errors.member_invites = true;
    const html = await roster();
    expect(text(html)).toMatch(/could(n.?t| not)|unable|unavailable|try again/i);
    expect(text(html)).not.toMatch(/Invite pending|Linked/i);
    expect(html).not.toContain('private backend detail');
  });
  it('trainer receives no invite metadata', async () => {
    state.role = 'trainer';
    const html = await roster();
    expect(text(html)).not.toContain('Not joined yet'); expect(text(html)).not.toContain('IST');
    expect(state.calls.filter((call) => call.table === 'member_invites')).toEqual([]);
  });
});

describe('INV-026 persisted member invite history', () => {
  beforeEach(() => {
    state.tables.member_invites = [invite('superseded', OLD_INVITE), invite('revoked')];
    state.tables.audit_log = [
      audit('member_invite.superseded', OLD_INVITE, { status: 'superseded', replaced_by: INVITE }),
      audit('member_invite.issued', INVITE, { member_id: MEMBER, expires_at: EXPIRES, superseded_invite_id: OLD_INVITE }),
      audit('member_invite.revoked', INVITE, { status: 'revoked' }),
    ];
    state.history = [
      { event_id: 'a8200000-0000-4000-8000-000000000013', occurred_at: SENT, action: 'member_invite.revoked', actor_name: 'Meera Desk' },
      { event_id: 'a8200000-0000-4000-8000-000000000012', occurred_at: SENT, action: 'member_invite.issued', actor_name: 'Meera Desk' },
      { event_id: 'a8200000-0000-4000-8000-000000000011', occurred_at: SENT, action: 'member_invite.superseded', actor_name: 'Meera Desk' },
    ];
  });
  it.each(['gym_owner', 'gym_manager', 'front_desk'])('%s reads this member through the safe projection, never broad audit rows', async (role) => {
    state.role = role;
    const html = await detail();
    expect(text(html)).toContain('Meera Desk');
    expect(state.calls.filter((call) => call.table === 'read_member_invite_history')).toEqual([
      { table: 'read_member_invite_history', method: 'rpc', args: [{ p_member_id: MEMBER }] },
    ]);
    expect(state.calls.filter((call) => call.table === 'audit_log')).toEqual([]);
  });
  it('shows persisted resend and revoke events with actor, readable action, absolute IST', async () => {
    const html = await detail(); const visible = text(html);
    expect(visible).toMatch(/recent.*history|recent.*activity/i);
    expect(visible).toContain('Meera Desk');
    expect(visible).toMatch(/superseded|replaced/i); expect(visible).toMatch(/issued|sent/i); expect(visible).toMatch(/revoked/i);
    expect(visible).toMatch(/3 Oct 2026,?\s+1:30\s*am\s*IST/i);
    expect(html).not.toContain(HASH); expect(html).not.toContain(TOKEN);
    expect(visible).not.toContain('member_invite.');
  });
  it('has an honest actor fallback when the actor name cannot be resolved', async () => {
    state.tables.staff = [];
    state.history = state.history.map((row) => ({ ...row, actor_name: null }));
    const visible = text(await detail());
    expect(visible).toContain('Name unavailable');
    expect(visible).not.toMatch(/by you|viewer@example.com/i);
  });
  it('empty persisted history is explicit and never inferred from current invite state', async () => {
    state.tables.audit_log = [];
    state.history = [];
    const visible = text(await detail());
    expect(visible).toMatch(/no (invite )?(history|activity)|no .*invite.*yet/i);
    expect(visible).not.toMatch(/Meera Desk.*revoked/i);
  });
  it('history failure is explicit and exposes no backend detail or fabricated events', async () => {
    state.errors.audit_log = true;
    state.historyError = true;
    const html = await detail();
    expect(text(html)).toMatch(/history|activity/i); expect(text(html)).toMatch(/could(n.?t| not)|unable|try again/i);
    expect(html).not.toContain('private backend detail'); expect(html).not.toContain('Meera Desk');
  });
  it('never prints refusal-attempt identity data or raw audit JSON', async () => {
    state.tables.audit_log?.push(audit('member_invite.redeem_refused', INVITE, { outcome: 'email_mismatch', email: 'outsider@example.com', token: TOKEN, token_hash: HASH }));
    const html = await detail();
    for (const secret of ['outsider@example.com', TOKEN, HASH, 'email_mismatch', 'replaced_by', 'superseded_invite_id']) expect(html).not.toContain(secret);
  });
  it('excludes another member\'s invite audit activity', async () => {
    const foreignMember = 'a8200000-0000-4000-8000-000000000008';
    const foreignInvite = 'a8200000-0000-4000-8000-000000000009';
    state.tables.member_invites?.push(invite('pending', foreignInvite, foreignMember));
    state.tables.audit_log?.push(audit('member_invite.issued', foreignInvite, { member_id: foreignMember }, '2026-08-01T20:00:00Z'));
    const html = await detail();
    expect(text(html)).not.toMatch(/2 Aug 2026/i);
    expect(state.calls.filter((call) => call.table === 'read_member_invite_history')).toEqual([
      { table: 'read_member_invite_history', method: 'rpc', args: [{ p_member_id: MEMBER }] },
    ]);
    expect(state.calls.filter((call) => call.table === 'audit_log')).toEqual([]);
  });
  it.each(['trainer', 'preview'])('%s gets no invite history or underlying history read', async (role) => {
    state.role = role === 'preview' ? 'gym_owner' : role; state.preview = role === 'preview';
    const visible = text(await detail());
    expect(visible).not.toContain('Meera Desk'); expect(visible).not.toMatch(/invite history|app access history/i);
    expect(state.calls.filter((call) => call.table === 'audit_log')).toEqual([]);
    expect(state.calls.filter((call) => call.table === 'read_member_invite_history')).toEqual([]);
  });
  it('records the separate safe history bound in shared constants', async () => {
    const shared = await import('@gymloop/shared') as unknown as { MEMBER_INVITE_HISTORY_LIMIT?: number };
    expect(shared.MEMBER_INVITE_HISTORY_LIMIT).toBe(50);
  });
});
