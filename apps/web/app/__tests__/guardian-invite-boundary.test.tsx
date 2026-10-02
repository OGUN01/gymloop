import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import type { GymloopIdentity, StaffRole } from '@gymloop/shared';
import type { Database } from '@gymloop/db';
import type { SupabaseClient } from '@supabase/supabase-js';

// GRD-023/024: discover client component props from real page output, never invent a prop API.
type Row = Record<string, unknown>;
type Element = ReactElement<Row>;
const h = vi.hoisted(() => ({ role: 'gym_owner' as StaffRole, preview: false, tables: {} as Record<string, Row[]>,
  guardian: null as Row | null, coverage: null as Row | null, attention: [] as Row[], access: null as Row | null, readError: false,
  calls: [] as string[], slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>,
  requests: [] as Array<{ url: string; init: RequestInit }>, response: { ok: true, data: {} } as Row,
  responseStatus: 200, online: true, refreshes: 0, pendingFetch: false,
  releaseFetch: null as (() => void) | null }));
const MEMBER = '69000000-0000-4000-8000-000000000030';
const TENANT = '69000000-0000-4000-8000-000000000031';
const STAFF = '69000000-0000-4000-8000-000000000032';
const USER = '69000000-0000-4000-8000-000000000033';
const identity = (): GymloopIdentity => h.preview ? { kind: 'impersonation', userId: USER, tenantId: TENANT, impersonationSessionId: MEMBER }

  : { kind: 'staff', userId: USER, tenantId: TENANT, staffId: STAFF, role: h.role };
function client() {
  return {
    auth: { getClaims: async () => ({ data: { claims: { sub: USER, tenant_id: TENANT, staff_id: STAFF, app_role: h.role } }, error: null }) },
    from: (table: string) => {
      const query: Row = {}; const result = () => ({ data: h.tables[table] ?? [], error: null });
      for (const method of ['select', 'eq', 'neq', 'in', 'is', 'order', 'limit', 'range', 'ilike', 'or', 'gte', 'gt', 'lte', 'lt', 'not']) query[method] = () => query;
      query.then = (resolve: (value: unknown) => unknown) => Promise.resolve(result()).then(resolve);
      query.maybeSingle = async () => ({ data: result().data[0] ?? null, error: null }); query.single = query.maybeSingle; return query;
    },
    rpc: async (name: string) => {
      h.calls.push(name);
      const data = name === 'read_member_guardian' ? h.guardian ? [h.guardian] : []
        : name === 'read_guardian_coverage' ? h.coverage ? [h.coverage] : []
        : name === 'list_guardian_attention' ? h.attention
        : name === 'read_member_app_access' ? h.access ? [h.access] : [] : [];
      return { data: h.readError && name.includes('guardian') ? null : data,
        error: h.readError && name.includes('guardian') ? { code: 'XX000', message: 'private mira@example.com' } : null };
    },
  };
}
vi.mock('next/navigation', () => ({ redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); }, notFound: () => { throw new Error('NOT_FOUND'); }, useRouter: () => ({ refresh: () => { h.refreshes += 1; }, push: vi.fn() }), usePathname: () => '/members', useSearchParams: () => new URLSearchParams() }));
vi.mock('next/link', () => ({ default: (props: Row) => createElement('a', props) }));
vi.mock('next/headers', () => ({ cookies: async () => ({ get: () => undefined, getAll: () => [] }), headers: async () => new Headers() }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => client() }));
const caller = (): { supabase: SupabaseClient<Database>; identity: GymloopIdentity } => ({ supabase: client() as unknown as SupabaseClient<Database>, identity: identity() });
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => caller(), readIdentity: async () => ({ ...caller(), signedIn: true }) }));
vi.mock('../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../(console)/members/member-data', () => ({ loadMember: async () => ({ data: h.tables.members?.[0] ?? null, error: null }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => h.preview, MutationForm: (props: Row) => createElement('form', props) }));

const guardianRow = (over: Row = {}) => ({ age_state: 'minor', date_of_birth: '2012-01-01', adult_on: '2030-01-01', gym_today: '2026-10-02', guardian_name: 'Mira Rao', guardian_relation: 'mother', guardian_phone: '+919999999999', guardian_email: 'mira@example.com', guardian_complete: true, link_email: 'mira@example.com', link_email_in_use: false, consent_state: 'none', consent_recorded_at: null, consent_version: null, scoring_state: 'off_no_consent', guardian_linked_at: null, handover_due: false, legacy_attested_adult: false, ...over });
async function detail() { return (await import('../(console)/members/[memberId]/page')).default({ params: Promise.resolve({ memberId: MEMBER }), searchParams: Promise.resolve({}) }); }
function descendants(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(descendants);
  if (!isValidElement<Row>(node)) return [];
  return [node, ...descendants(node.props.children as ReactNode)];
}
function accessPanel(node: ReactNode): Element {
  const found = descendants(node).find((el) => typeof el.type === 'function' && el.type.name === 'AppAccessPanel');
  expect(found, 'Real member page mounts existing app-access boundary').toBeDefined();
  return found!;
}
function visible(node: ReactNode): string { return renderToStaticMarkup(node).replace(/<[^>]*>/g, ' ').replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"'); }
beforeEach(() => {
  h.role = 'gym_owner'; h.preview = false; h.readError = false; h.calls = []; h.slots = []; h.cursor = 0; h.effects = [];
  h.requests = []; h.responseStatus = 200; h.response = { ok: true, data: {} }; h.online = true; h.refreshes = 0;
  h.pendingFetch = false; h.releaseFetch = null;
  h.guardian = guardianRow(); h.coverage = null; h.attention = [];
  h.access = { state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null };
  h.tables = { members: [{ id: MEMBER, tenant_id: TENANT, full_name: 'Asha Rao', phone: '+918888888888', email: 'child@example.com', status: 'active', branch_id: null, user_id: null, erased_at: null, joined_on: '2026-09-01', member_code: 'M1' }],
    organizations: [{ id: TENANT, name: 'River Studio', timezone: 'Asia/Kolkata', business_type: 'dance' }], organization_settings: [{ tenant_id: TENANT }], staff: [], branches: [] };
  vi.stubGlobal('navigator', { get onLine() { return h.online; }, clipboard: { writeText: vi.fn() } });
  vi.stubGlobal('window', { addEventListener: vi.fn(), removeEventListener: vi.fn(), location: { origin: 'https://app.example' } });
  vi.stubGlobal('fetch', async (url: string, init: RequestInit) => {
    h.requests.push({ url, init });
    if (h.pendingFetch) await new Promise<void>((resolve) => { h.releaseFetch = resolve; });
    return new Response(JSON.stringify(h.response), { status: h.responseStatus, headers: { 'content-type': 'application/json' } });
  });
});
afterEach(() => vi.unstubAllGlobals());


// GRD-014/017/023/025: missing guardian facts cannot authorize child-targeted access.
describe('GRD real React member-page invite boundary regressions', () => {
  it.each([['error', 'not_invited'], ['empty', 'not_invited'], ['error', 'invite_pending'], ['empty', 'invite_pending']])('guardian %s with successful %s app-access read fails safely', async (failure, state) => {
    h.access = { state, invite_id: state === 'invite_pending' ? MEMBER : null, issued_at: state === 'invite_pending' ? '2026-10-02T12:00:00Z' : null, expires_at: state === 'invite_pending' ? '2026-10-04T12:00:00Z' : null, linked_at: null };
    h.readError = failure === 'error'; h.guardian = null;
    h.tables.members![0]!.date_of_birth = '2012-01-01';
    const panel = accessPanel(await detail());
    const html = renderToStaticMarkup(panel); const copy = visible(panel);
    expect(h.calls).toContain('read_member_app_access');
    expect(h.calls).toContain('read_member_guardian');
    expect(copy).toMatch(/unavailable|could not|couldn't|retry|try again/i);
    expect(copy).not.toMatch(/add.*email.*profile|Google account.*child@example.com/i);
    expect(html).not.toContain('mailto:child@example.com');
    expect(html).not.toContain('wa.me/918888888888');
    const actions = html.match(/<button\b[^>]*>[\s\S]*?<\/button>/gi) ?? [];
    for (const action of actions) {
      if (/invite|send|share|copy link/i.test(action.replace(/<[^>]*>/g, ' '))) expect(action).toMatch(/disabled/);
    }
    expect(h.requests).toEqual([]);
  });
  it('complete minor record without email directs staff to the guardian panel email field', async () => {
    h.guardian = guardianRow({ guardian_email: null, link_email: null });
    const panel = accessPanel(await detail()); const copy = visible(panel);
    expect(panel.props.email).toBeNull();
    expect(copy).toMatch(/(?:guardian[^.!?]*email|email[^.!?]*guardian)/i);
    expect(copy).toMatch(/Age and guardian|guardian (?:panel|section|details)/i);
    expect(copy).not.toMatch(/add.*email.*profile/i);
    expect(h.requests).toEqual([]);
  });
  // GRD-011: birthdays change invite routing, never the identity already bound.
  it('known adult awaiting handover honestly names the existing guardian Google binding', async () => {
    h.guardian = guardianRow({ age_state: 'adult', scoring_state: 'on_adult', link_email: 'child@example.com', guardian_linked_at: '2026-01-01T00:00:00Z', handover_due: true });
    h.access = { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-01-01T00:00:00Z' };
    h.tables.members![0]!.user_id = USER;
    const copy = visible(accessPanel(await detail()));
    expect(copy).toMatch(/guardian.*Google|Google.*guardian/i);
    expect(copy).not.toMatch(/their own Google account|(?:linked|joined|signed in).*child@example.com/i);
  });
  it.each(['after handover', 'new adult'])('%s uses own address and ordinary invite copy', async (state) => {
    h.guardian = guardianRow({ age_state: 'adult', scoring_state: 'on_adult', link_email: 'child@example.com', guardian_linked_at: null, handover_due: false });
    if (state === 'new adult') h.guardian = guardianRow({ ...h.guardian, guardian_name: null, guardian_relation: null, guardian_phone: null, guardian_email: null, guardian_complete: false });
    const panel = accessPanel(await detail()); const copy = visible(panel);
    expect(panel.props.email).toBe('child@example.com');
    expect(copy).toContain('child@example.com');
    expect(copy).not.toMatch(/guardian.*Google|Google.*guardian/i);
  });
});
