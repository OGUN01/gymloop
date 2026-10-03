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

vi.mock('../../lib/guardian', () => ({ loadMemberGuardian: async () => h.guardian ? Object.fromEntries(Object.entries(h.guardian).map(([key, value]) => [key.replace(/_([a-z])/g, (_match, letter: string) => letter.toUpperCase()), value])) : null }));
vi.mock('../../lib/member-invites', () => ({ loadMemberAppAccess: async () => h.access ? Object.fromEntries(Object.entries(h.access).map(([key, value]) => [key.replace(/_([a-z])/g, (_match, letter: string) => letter.toUpperCase()), value])) : null }));
vi.mock('../../lib/member-invite-history', () => ({ loadMemberInviteActivity: async () => [] }));
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


// GRD-013 owner-approved linked-account-copy boundary; implementation-blind author.
describe('GRD-013 linked account provenance on actual detail and panel', () => {
  it.each(['minor', 'adult', 'unknown'])('no marker and %s age has neutral connected copy', async (age) => {
    h.guardian = guardianRow({ age_state: age, date_of_birth: age === 'unknown' ? null : age === 'adult' ? '2000-01-01' : '2012-01-01', guardian_linked_at: null });
    h.access = { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-01-01T00:00:00Z' };
    const panel = accessPanel(await detail());
    expect(panel.props.guardian == null).toBe(true);
    const copy = visible(panel);
    expect(copy).toMatch(/connected|linked/i);
    expect(copy).not.toMatch(/guardian|(?:own|their|member.s) Google account/i);
  });
  it.each(['minor', 'adult', 'unknown'])('retained marker and %s age keeps guardian provenance', async (age) => {
    h.guardian = guardianRow({ age_state: age, date_of_birth: age === 'unknown' ? null : age === 'adult' ? '2000-01-01' : '2012-01-01', guardian_linked_at: '2026-01-01T00:00:00Z', handover_due: age === 'adult' });
    h.access = { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-01-01T00:00:00Z' };
    const panel = accessPanel(await detail());
    expect(panel.props.guardian).toEqual({ name: 'Mira Rao', memberFirstName: 'Asha' });
    const copy = visible(panel);
    expect(copy).toMatch(/guardian.*Google|Google.*guardian/i);
    expect(copy).not.toMatch(/their own Google account|member.s Google account/i);
  });
  it.each(['minor', 'adult', 'unknown'])('prospective %s uses current eligible email', async (age) => {
    h.guardian = guardianRow({ age_state: age, link_email: age === 'minor' ? 'mira@example.com' : 'child@example.com', guardian_linked_at: '2026-01-01T00:00:00Z' });
    const panel = accessPanel(await detail());
    expect(panel.props.email).toBe(age === 'minor' ? 'mira@example.com' : 'child@example.com');
    expect(panel.props.guardian ?? null).toEqual(age === 'minor' ? { name: 'Mira Rao', memberFirstName: 'Asha' } : null);
    const copy = visible(panel);
    expect(copy).toContain(age === 'minor' ? 'mira@example.com' : 'child@example.com');
    if (age === 'minor') expect(copy).toMatch(/guardian.*Google|Google.*guardian/i);
    else expect(copy).not.toMatch(/guardian.*Google|Google.*guardian/i);
  });
  it.each(['linked', 'not_invited', 'invite_pending'])('missing authoritative guardian read with %s access fails closed', async (state) => {
    h.guardian = null;
    h.access = { state, invite_id: null, issued_at: null, expires_at: null, linked_at: state === 'linked' ? '2026-01-01T00:00:00Z' : null };
    const panel = accessPanel(await detail());
    expect(panel.props.guardian == null).toBe(true);
    expect(panel.props.email).not.toBe('child@example.com');
    const html = renderToStaticMarkup(panel); const copy = visible(panel);
    expect(copy).toMatch(/unavailable|could not|couldn't|retry|try again/i);
    expect(copy).not.toMatch(/guardian.*Google|Google.*guardian|their own Google account/i);
    expect(html).not.toContain('mailto:child@example.com');
    expect(html).not.toContain('wa.me/918888888888');
  });
  it('actual linked panel with no guardian prop makes no Google ownership assertion', async () => {
    const { AppAccessPanel } = await import('../(console)/members/[memberId]/app-access-panel');
    const panel = createElement(AppAccessPanel, { memberId: MEMBER, memberName: 'Asha Rao', gymName: 'River Studio', email: 'child@example.com', phone: '+918888888888', role: 'gym_owner', guardian: null, access: { state: 'linked', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: '2026-01-01T00:00:00Z' } });
    const copy = visible(panel);
    expect(copy).toMatch(/connected|linked/i);
    expect(copy).not.toMatch(/guardian|(?:own|their|member.s) Google account/i);
  });
  it('owner retains unlink control for a linked member', async () => {
    h.access = { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-01-01T00:00:00Z' };
    expect(visible(accessPanel(await detail()))).toMatch(/unlink/i);
  });
  it('support preview cannot operate unlink', async () => {
    h.preview = true;
    h.access = { state: 'linked', invite_id: null, issued_at: null, expires_at: null, linked_at: '2026-01-01T00:00:00Z' };
    const panel = accessPanel(await detail());
    expect(panel.props.readOnly).toBe(true);
    const buttons = renderToStaticMarkup(panel).match(/<button\b[^>]*>[\s\S]*?<\/button>/gi) ?? [];
    for (const button of buttons.filter((item) => /unlink/i.test(item))) expect(button).toMatch(/disabled/);
  });
  it('trainer receives no app-access surface', async () => {
    h.role = 'trainer';
    expect(descendants(await detail()).some((el) => typeof el.type === 'function' && el.type.name === 'AppAccessPanel')).toBe(false);
  });
});
