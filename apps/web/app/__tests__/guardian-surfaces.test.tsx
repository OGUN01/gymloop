import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, isValidElement, type ReactElement, type ReactNode } from 'react';

// GRD-023/024: discover client component props from real page output, never invent a prop API.
type Row = Record<string, unknown>;
type Element = ReactElement<Row>;
const h = vi.hoisted(() => ({ role: 'gym_owner', preview: false, tables: {} as Record<string, Row[]>,
  guardian: null as Row | null, coverage: null as Row | null, attention: [] as Row[], access: null as Row | null, readError: false,
  calls: [] as string[], slots: [] as unknown[], cursor: 0, effects: [] as Array<() => unknown>,
  requests: [] as Array<{ url: string; init: RequestInit }>, response: { ok: true, data: {} } as Row,
  responseStatus: 200, online: true, refreshes: 0, pendingFetch: false,
  releaseFetch: null as (() => void) | null }));
vi.mock('react', async (original) => {
  const actual = await original<typeof import('react')>();
  const slot = (initial: unknown) => { const key = h.cursor++; if (!(key in h.slots)) h.slots[key] = typeof initial === 'function' ? (initial as () => unknown)() : initial; return key; };
  return { ...actual,
    useState: (initial: unknown) => { const key = slot(initial); return [h.slots[key], (next: unknown) => { h.slots[key] = typeof next === 'function' ? (next as (old: unknown) => unknown)(h.slots[key]) : next; }]; },
    useRef: (initial: unknown) => h.slots[slot({ current: initial })],
    useEffect: (effect: () => unknown, deps?: unknown[]) => { const key = h.cursor++; const old = h.slots[key] as unknown[] | undefined; if (!old || !deps || deps.some((v, i) => !Object.is(v, old[i]))) { h.slots[key] = deps; h.effects.push(effect); } },
    useMemo: (make: () => unknown) => make(), useCallback: (callback: unknown) => callback,
    useTransition: () => [false, (run: () => unknown) => run()], useId: () => 'guardian-visible',
  };
});
const MEMBER = '69000000-0000-4000-8000-000000000030';
const TENANT = '69000000-0000-4000-8000-000000000031';
const STAFF = '69000000-0000-4000-8000-000000000032';
const USER = '69000000-0000-4000-8000-000000000033';
const identity = () => h.preview ? { kind: 'impersonation', userId: USER, tenantId: TENANT, impersonationSessionId: MEMBER }
  : h.role === 'member' ? { kind: 'member', userId: USER, tenantId: TENANT, memberId: MEMBER }
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
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: client(), identity: identity() }), readIdentity: async () => ({ supabase: client(), identity: identity(), signedIn: true }) }));
vi.mock('../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../(console)/members/member-data', () => ({ loadMember: async () => ({ data: h.tables.members?.[0] ?? null, error: null }) }));
vi.mock('../preview-context', () => ({ usePreviewReadOnly: () => h.preview, MutationForm: (props: Row) => createElement('form', props) }));

const preAttestation = 'Members without a date of birth have absence follow-ups off. The owner can confirm once that existing members without a date of birth are adults. Members added afterwards still need a date of birth.';
const legacy = 'The owner confirmed existing members without a date of birth are adults. Absence follow-ups are on.';
const collision = 'Another member of this gym with the same address is already linked. A Google account links to one member only, so this invite will be refused if the guardian uses the same account. Enter a different address if this child should use another account.';
const guardianRow = (over: Row = {}) => ({ age_state: 'minor', date_of_birth: '2012-01-01', adult_on: '2030-01-01', gym_today: '2026-10-02', guardian_name: 'Mira Rao', guardian_relation: 'mother', guardian_phone: '+919999999999', guardian_email: 'mira@example.com', guardian_complete: true, link_email: 'mira@example.com', link_email_in_use: false, consent_state: 'none', consent_recorded_at: null, consent_version: null, scoring_state: 'off_no_consent', guardian_linked_at: null, handover_due: false, legacy_attested_adult: false, ...over });
const coverageRow = (over: Row = {}) => ({ tracked: 0, no_birth_date: 0, minor_no_guardian: 0, minor_consent_missing: 0, handover_due: 0, members_without_dob_attested_adult_at: null, ...over });
async function detail() { return (await import('../(console)/members/[memberId]/page')).default({ params: Promise.resolve({ memberId: MEMBER }), searchParams: Promise.resolve({}) }); }
async function redList() { return (await import('../(console)/red-list/page')).default({ searchParams: Promise.resolve({}) }); }
function descendants(node: ReactNode): Element[] {
  if (Array.isArray(node)) return node.flatMap(descendants); if (!isValidElement<Row>(node)) return [];
  return [node, ...descendants(node.props.children as ReactNode)];
}
function component(node: ReactNode, name: string): Element {
  const found = descendants(node).find((el) => typeof el.type === 'function' && el.type.name === name);
  expect(found, `Real page mounts ${name}`).toBeDefined(); return found!;
}
async function mounted(node: ReactNode, name: string): Promise<Element | null> {
  if (Array.isArray(node)) {
    for (const child of node) { const found = await mounted(child, name); if (found) return found; }
    return null;
  }
  if (!isValidElement<Row>(node)) return null;
  if (typeof node.type === 'function') {
    if (node.type.name === name) return node;
    return mounted(await (node.type as (props: Row) => ReactNode | Promise<ReactNode>)(node.props), name);
  }
  return mounted(node.props.children as ReactNode, name);
}
function text(node: ReactNode): string {
  if (Array.isArray(node)) return node.map(text).join(' '); if (typeof node === 'string' || typeof node === 'number') return String(node);
  return isValidElement<Row>(node) ? text(node.props.children as ReactNode) : '';
}
async function expand(node: ReactNode): Promise<ReactNode> {
  if (Array.isArray(node)) return Promise.all(node.map(expand)); if (!isValidElement<Row>(node)) return node;
  if (typeof node.type === 'function') return expand(await (node.type as (props: Row) => ReactNode | Promise<ReactNode>)(node.props));
  return createElement(node.type, { ...node.props, children: await expand(node.props.children as ReactNode) });
}
async function render(node: ReactNode) { h.cursor = 0; return descendants(await expand(node)); }
async function flush() { for (const effect of h.effects.splice(0)) await effect(); }
async function event(el: Element, name: string, value?: string, checked?: boolean) {
  const fn = el.props[name] as ((e: unknown) => unknown) | undefined; expect(fn).toBeTypeOf('function');
  await fn!({ preventDefault: () => undefined, target: { value, checked }, currentTarget: { value, checked } }); await flush();
}
function startEvent(el: Element, name: string): Promise<unknown> {
  const fn = el.props[name] as ((e: unknown) => unknown) | undefined;
  expect(fn).toBeTypeOf('function');
  return Promise.resolve(fn!({ preventDefault: () => undefined, target: {}, currentTarget: {} }));
}
function submitting(nodes: Element[], action: Element): { el: Element; event: string } {
  if (action.props.onClick) return { el: action, event: 'onClick' };
  const form = nodes.find((el) => el.type === 'form' && descendants(el).includes(action));
  expect(form, 'The action is operable through its enclosing form').toBeDefined();
  return { el: form!, event: 'onSubmit' };
}
const button = (nodes: Element[], label: RegExp) => nodes.find((el) => el.type === 'button' && label.test(text(el)));
beforeEach(() => {
  h.role = 'gym_owner'; h.preview = false; h.readError = false; h.calls = []; h.slots = []; h.cursor = 0; h.effects = [];
  h.requests = []; h.responseStatus = 200; h.response = { ok: true, data: {} }; h.online = true; h.refreshes = 0;
  h.pendingFetch = false; h.releaseFetch = null;
  h.guardian = guardianRow(); h.coverage = coverageRow(); h.attention = [];
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

describe('GRD actual member page', () => {
  it.each([
    ['off_age_unknown', 'unknown', 'Absence follow-ups are off. Add a date of birth to turn them on.'],
    ['off_no_guardian', 'minor', "Absence follow-ups are off. Add the guardian's name, relation and phone."],
    ['off_consent_withdrawn', 'minor', 'The guardian withdrew consent, so absence follow-ups are off. Visits are still recorded.'],
    ['off_consent_stale', 'minor', "The guardian's details changed after consent was recorded, so absence follow-ups are off. Record consent again."],
    ['on_adult', 'adult', 'Absence follow-ups are on.'],
    ['on_consent', 'minor', "Absence follow-ups are on, with the guardian's consent on record."],
  ])('renders the database consequence for %s', async (scoring_state, age_state, sentence) => {
    h.guardian = guardianRow({ scoring_state, age_state });
    const panel = component(await detail(), 'GuardianPanel'); const nodes = await render(panel);
    expect(nodes.map(text).join(' ')).toContain(sentence);
    expect(nodes.map(text).join(' ')).not.toMatch(/GL08[345]|SQLSTATE/);
  });
  it('mounts inline unchecked consent and records through three required interactions', async () => {
    const panel = component(await detail(), 'GuardianPanel'); await render(panel); await flush(); let nodes = await render(panel);
    expect(nodes.map(text).join(' ')).toContain('Age and guardian');
    expect(nodes.map(text).join(' ')).toContain("Absence follow-ups are off until the guardian's consent is recorded.");
    const checkbox = nodes.find((el) => el.type === 'input' && el.props.type === 'checkbox'); expect(checkbox).toBeDefined();
    expect(Boolean(checkbox!.props.checked ?? checkbox!.props.defaultChecked)).toBe(false);
    expect(nodes.map(text).join(' ')).toContain('I have collected this consent from the parent or guardian');
    const source = nodes.find((el) => ['input', 'textarea', 'select'].includes(String(el.type)) && /source/i.test(String(el.props.name ?? el.props.id ?? el.props['aria-label'] ?? '')));
    expect(source, 'Source is available inline before disclosure clicks').toBeDefined();
    const record = button(nodes, /^Record$/i); expect(record).toBeDefined();
    await event(checkbox!, 'onChange', undefined, true); await render(panel);
    await event(source!, 'onChange', 'Paper form'); nodes = await render(panel);
    const final = button(nodes, /^Record$/i)!;
    if (final.props.onClick) await event(final, 'onClick'); else await event(nodes.find((el) => el.type === 'form' && descendants(el).includes(final))!, 'onSubmit');
    expect(h.requests).toHaveLength(1); expect(h.requests[0]?.url).toBe('/api/member-guardian/consent');
    expect(JSON.parse(String(h.requests[0]?.init.body))).toEqual({ memberId: MEMBER, granted: true, source: 'Paper form' });
  });
  it('keeps age unknown for legacy adults and explains the owner decision', async () => {
    h.guardian = guardianRow({ age_state: 'unknown', date_of_birth: null, adult_on: null, scoring_state: 'on_adult', legacy_attested_adult: true });
    const nodes = await render(component(await detail(), 'GuardianPanel')); const visible = nodes.map(text).join(' ');
    expect(visible).toContain(legacy); expect(visible).toContain('Absence follow-ups are on.'); expect(visible).not.toMatch(/known adult/i);
  });
  it('adult retained guardian does not replace the normal invite recipient or claim Google linking is guardian-owned', async () => {
    h.guardian = guardianRow({ age_state: 'adult', scoring_state: 'on_adult', link_email: 'child@example.com' });
    const page = await detail(); const access = component(page, 'AppAccessPanel');
    expect(access.props.email).toBe('child@example.com'); expect(access.props.guardian == null).toBe(true);
    expect((await render(access)).map(text).join(' ')).not.toContain("This invite links the guardian's Google account.");
  });
  it('warns about D1 without naming another child or substituting the child email', async () => {
    h.guardian = guardianRow({ link_email_in_use: true }); const page = await detail();
    expect((await render(component(page, 'GuardianPanel'))).map(text).join(' ')).toContain(collision);
    const access = component(page, 'AppAccessPanel'); expect(access.props.email).toBe('mira@example.com');
    expect(access.props.guardian).toEqual({ name: 'Mira Rao', memberFirstName: 'Asha' });
    expect((await render(access)).map(text).join(' ')).toContain("This invite links the guardian's Google account.");
  });
  it('front desk has no handover action while owner has consequence and required reason confirmation', async () => {
    h.guardian = guardianRow({ age_state: 'adult', scoring_state: 'on_adult', guardian_linked_at: '2026-01-01T00:00:00Z', handover_due: true });
    h.role = 'front_desk'; let nodes = await render(component(await detail(), 'GuardianPanel'));
    expect(button(nodes, /Hand over account/i)).toBeUndefined();
    h.role = 'gym_owner'; h.slots = []; const panel = component(await detail(), 'GuardianPanel'); nodes = await render(panel);
    expect(nodes.map(text).join(' ')).toContain('Turned 18'); await event(button(nodes, /Hand over account/i)!, 'onClick'); nodes = await render(panel);
    const visible = nodes.map(text).join(' '); expect(visible).toMatch(/guardian.*sign.in/i);
    for (const word of ['visits', 'payments', 'history']) expect(visible.toLowerCase()).toContain(word);
    expect(nodes.some((el) => ['input', 'textarea'].includes(String(el.type)) && Boolean(el.props.required))).toBe(true);
    expect(h.requests).toEqual([]);
  });
  it('withdrawal is confirmed before any request and completes within two interactions', async () => {
    h.guardian = guardianRow({ consent_state: 'granted', scoring_state: 'on_consent', consent_version: 'guardian-absence-v1', consent_recorded_at: '2026-10-01T00:00:00Z' });
    const panel = component(await detail(), 'GuardianPanel'); let nodes = await render(panel);
    await event(button(nodes, /Withdraw consent/i)!, 'onClick'); expect(h.requests).toEqual([]); nodes = await render(panel);
    const confirm = button(nodes, /confirm|withdraw/i); expect(confirm).toBeDefined(); await event(confirm!, 'onClick');
    expect(h.requests).toHaveLength(1); expect(JSON.parse(String(h.requests[0]?.init.body))).toMatchObject({ memberId: MEMBER, granted: false });
  });
  it('preview cannot record, save or hand over', async () => {
    h.preview = true; const nodes = await render(component(await detail(), 'GuardianPanel'));
    for (const el of nodes.filter((n) => n.type === 'button' && /save|record|withdraw|hand over/i.test(text(n)))) expect(Boolean(el.props.disabled)).toBe(true);
    expect(h.requests).toEqual([]);
  });
  it('requires both consent confirmation and source before sending', async () => {
    const panel = component(await detail(), 'GuardianPanel'); let nodes = await render(panel);
    const record = button(nodes, /^Record$/i)!;
    expect(record).toBeDefined();
    if (!record.props.disabled) {
      if (record.props.onClick) await event(record, 'onClick');
      else await event(nodes.find((el) => el.type === 'form' && descendants(el).includes(record))!, 'onSubmit');
    }
    expect(h.requests).toEqual([]);
    nodes = await render(panel);
    const check = nodes.find((el) => el.type === 'input' && el.props.type === 'checkbox')!;
    await event(check, 'onChange', undefined, true); nodes = await render(panel);
    const after = button(nodes, /^Record$/i)!;
    if (!after.props.disabled) {
      if (after.props.onClick) await event(after, 'onClick');
      else await event(nodes.find((el) => el.type === 'form' && descendants(el).includes(after))!, 'onSubmit');
    }
    expect(h.requests).toEqual([]);
  });
  it('trainer sees no guardian panel and performs no guardian read', async () => {
    h.role = 'trainer'; const page = await detail();
    expect(descendants(page).some((el) => typeof el.type === 'function' && el.type.name === 'GuardianPanel')).toBe(false);
    expect(h.calls).not.toContain('read_member_guardian');
  });
  it('a failed guardian read offers retry without claiming consent or exposing backend details', async () => {
    h.readError = true; const panel = component(await detail(), 'GuardianPanel'); const nodes = await render(panel); const visible = nodes.map(text).join(' ');
    expect(visible).toMatch(/could(n.?t| not)|unable|failed|try again/i); expect(button(nodes, /retry|try again/i)).toBeDefined();
    expect(visible).not.toContain('private mira@example.com'); expect(visible).not.toContain('Consent on record');
    const reads = h.calls.length; h.readError = false;
    await event(button(nodes, /retry|try again/i)!, 'onClick');
    expect(h.refreshes > 0 || h.calls.length > reads).toBe(true);
  });
  it('a pending or failed consent never announces eligibility before the authoritative refresh', async () => {
    const panel = component(await detail(), 'GuardianPanel'); let nodes = await render(panel);
    const checkbox = nodes.find((el) => el.type === 'input' && el.props.type === 'checkbox')!;
    const source = nodes.find((el) => ['input', 'textarea', 'select'].includes(String(el.type)) && /source/i.test(String(el.props.name ?? el.props.id ?? el.props['aria-label'] ?? '')))!;
    expect(source).toBeDefined(); await event(checkbox, 'onChange', undefined, true);
    await render(panel); await event(source, 'onChange', 'Paper form'); nodes = await render(panel);
    h.pendingFetch = true; h.responseStatus = 409;
    h.response = { ok: false, error: { code: 'guardian_required', message: "Add the guardian's name, relation and phone, then record consent." } };
    const action = submitting(nodes, button(nodes, /^Record$/i)!); const pending = startEvent(action.el, action.event);
    await Promise.resolve(); nodes = await render(panel);
    expect(h.requests).toHaveLength(1); expect(h.refreshes).toBe(0);
    expect(Boolean(button(nodes, /^Record$|recording|saving/i)?.props.disabled)).toBe(true);
    const during = nodes.map(text).join(' ');
    expect(during).toContain("Absence follow-ups are off until the guardian's consent is recorded.");
    expect(during).not.toContain("Absence follow-ups are on, with the guardian's consent on record.");
    expect(h.releaseFetch).toBeTypeOf('function'); h.releaseFetch!(); await pending; await flush();
    nodes = await render(panel); const failed = nodes.map(text).join(' ');
    expect(failed).toContain("Absence follow-ups are off until the guardian's consent is recorded.");
    expect(failed).toMatch(/guardian.*(?:name|details|phone)/i);
    expect(failed).not.toContain('GL083'); expect(h.refreshes).toBe(0);
    h.pendingFetch = false; h.responseStatus = 200;
    h.response = { ok: true, data: { consentId: MEMBER, recordedAt: '2026-10-02T12:00:00Z', changed: true } };
    const retry = submitting(nodes, button(nodes, /^Record$|retry|try again/i)!); await event(retry.el, retry.event);
    expect(h.requests).toHaveLength(2);
    h.guardian = guardianRow({ consent_state: 'granted', scoring_state: 'on_consent', consent_version: 'guardian-absence-v1' });
    h.slots = []; const refreshed = (await render(component(await detail(), 'GuardianPanel'))).map(text).join(' ');
    expect(refreshed).toContain("Absence follow-ups are on, with the guardian's consent on record.");
  });
  it('offline consent cannot save or enqueue a mutation', async () => {
    h.online = false; const panel = component(await detail(), 'GuardianPanel'); await render(panel); await flush(); const nodes = await render(panel);
    const record = button(nodes, /^Record$/i);
    expect(record, 'Offline still explains how consent is recorded').toBeDefined();
    if (!record!.props.disabled) {
      const action = submitting(nodes, record!); await event(action.el, action.event);
    }
    expect(h.requests).toEqual([]);
    expect(nodes.map(text).join(' ')).toMatch(/offline|connection|connect|online/i);
  });
});

describe('GRD-011/023 actual pre-birthday invite Re-issue note', () => {
  it.each(['invite_pending', 'invite_expired'])('tells a known adult to Re-issue a pre-birthday %s invite', async (state) => {
    h.guardian = guardianRow({ age_state: 'adult', date_of_birth: '2008-10-02', adult_on: '2026-10-02',
      gym_today: state === 'invite_pending' ? '2026-10-02' : '2026-10-04', scoring_state: 'on_adult', link_email: 'child@example.com' });
    h.access = { state, invite_id: MEMBER, issued_at: '2026-10-01T18:29:59Z', expires_at: '2026-10-03T18:29:59Z', linked_at: null };
    const nodes = await render(component(await detail(), 'GuardianPanel'));
    expect(nodes.map(text).join(' ')).toContain('Re-issue the invite');
    expect(h.requests).toEqual([]);
  });
  it.each([
    ['minor', 'invite_pending', '2026-10-01T12:00:00Z', '2026-10-01'],
    ['unknown', 'invite_pending', '2026-10-01T12:00:00Z', '2026-10-02'],
    ['adult', 'linked', '2026-10-01T12:00:00Z', '2026-10-02'],
    ['adult', 'not_invited', '2026-10-01T12:00:00Z', '2026-10-02'],
    ['adult', 'unavailable', '2026-10-01T12:00:00Z', '2026-10-02'],
    ['adult', 'invite_pending', null, '2026-10-02'],
    ['adult', 'invite_pending', '2026-10-01T18:30:00Z', '2026-10-02'],
    ['adult', 'invite_expired', '2026-10-01T18:30:00Z', '2026-10-04'],
    ['adult', 'invite_pending', '2026-10-02T12:00:00Z', '2026-10-02'],
    ['adult', 'invite_expired', '2026-10-02T12:00:00Z', '2026-10-05'],
  ])('does not suggest Re-issue outside the public condition %#', async (age_state, state, issued_at, gym_today) => {
    h.guardian = guardianRow({ age_state, date_of_birth: age_state === 'unknown' ? null : '2008-10-02',
      adult_on: age_state === 'unknown' ? null : '2026-10-02', gym_today,
      scoring_state: age_state === 'adult' ? 'on_adult' : age_state === 'unknown' ? 'off_age_unknown' : 'off_no_consent' });
    h.access = { state, invite_id: MEMBER, issued_at, expires_at: '2026-10-03T12:00:00Z', linked_at: state === 'linked' ? '2026-10-01T13:00:00Z' : null };
    const nodes = await render(component(await detail(), 'GuardianPanel'));
    expect(nodes.map(text).join(' ')).not.toContain('Re-issue the invite');
    expect(h.requests).toEqual([]);
  });
});

describe('GRD zero-count and post-attestation red-list disclosure', () => {
  it('shows the unconditional note at zero counts before attestation', async () => {
    const nodes = await render(await redList()); expect(nodes.map(text).join(' ')).toContain(preAttestation);
  });
  it('removes the unconditional note after attestation with zero off counts', async () => {
    h.coverage = coverageRow({ members_without_dob_attested_adult_at: '2026-10-02T00:00:00Z' });
    const nodes = await render(await redList()); expect(nodes.map(text).join(' ')).not.toContain(preAttestation);
  });
  it('keeps category links after attestation for members still excluded', async () => {
    h.coverage = coverageRow({ no_birth_date: 1, minor_no_guardian: 1, minor_consent_missing: 1, handover_due: 1, members_without_dob_attested_adult_at: '2026-10-02T00:00:00Z' });
    const nodes = await render(await redList());
    for (const reason of ['no_birth_date', 'minor_no_guardian', 'minor_consent_missing', 'handover_due']) expect(nodes.some((el) => el.props.href === `/members/attention?reason=${reason}`)).toBe(true);
  });
  it('failed coverage is silent and does not invent zero counts', async () => {
    h.readError = true; const nodes = await render(await redList()); const visible = nodes.map(text).join(' ');
    expect(visible).not.toContain(preAttestation); expect(visible).not.toContain('private mira@example.com');
    expect(visible).not.toMatch(/guardian.*(?:failed|error)/i);
  });
});

describe('GRD-024 real red-list legacy attestation banner', () => {
  async function banner(): Promise<Element> {
    const found = await mounted(await redList(), 'LegacyAdultAttestationBanner');
    expect(found, 'The real front-office page mounts the one-time banner').toBeDefined();
    expect(found).not.toBeNull(); h.slots = []; h.effects = [];
    return found!;
  }
  async function confirmation(panel: Element): Promise<Element[]> {
    await render(panel); await flush(); let nodes = await render(panel);
    if (!nodes.some((el) => el.type === 'input' && el.props.type === 'checkbox')) {
      await event(button(nodes, /Confirm existing members are adults/i)!, 'onClick');
      nodes = await render(panel);
    }
    return nodes;
  }
  function confirmButton(nodes: Element[]): Element {
    const found = nodes.filter((el) => el.type === 'button' && /confirm|try again|retry/i.test(text(el)) && !el.props.disabled).at(-1);
    expect(found, 'Confirmed owner can submit or retry the attestation').toBeDefined(); return found!;
  }
  async function checkedConfirmation(panel: Element): Promise<Element[]> {
    const nodes = await confirmation(panel);
    const checkbox = nodes.find((el) => el.type === 'input' && el.props.type === 'checkbox');
    expect(checkbox).toBeDefined();
    expect(Boolean(checkbox!.props.checked ?? checkbox!.props.defaultChecked)).toBe(false);
    expect(Boolean(checkbox!.props.required)).toBe(true);
    expect(h.requests).toEqual([]);
    await event(checkbox!, 'onChange', undefined, true);
    return render(panel);
  }
  it.each(['gym_owner', 'gym_manager', 'front_desk'])('zero counts still disclose the cutoff to %s', async (role) => {
    h.role = role; const panel = await banner(); const nodes = await render(panel);
    expect(nodes.map(text).join(' ')).toContain(preAttestation);
    if (role === 'gym_owner') expect(button(nodes, /Confirm existing members are adults/i)).toBeDefined();
    else expect(button(nodes, /Confirm existing members are adults/i)).toBeUndefined();
    expect(h.requests).toEqual([]);
  });
  it('owner must confirm an unchecked required checkbox before the empty-body command', async () => {
    const panel = await banner(); const nodes = await checkedConfirmation(panel);
    const action = submitting(nodes, confirmButton(nodes));
    h.response = { ok: true, data: { attestedAt: '2026-10-02T12:00:00Z', changed: true } };
    await event(action.el, action.event);
    expect(h.requests).toHaveLength(1);
    expect(h.requests[0]?.url).toBe('/api/member-guardian/legacy-attestation');
    expect(JSON.parse(String(h.requests[0]?.init.body))).toEqual({});
  });
  it('preview owner reads the banner but cannot submit an attestation', async () => {
    h.preview = true; const panel = await banner(); const nodes = await render(panel);
    expect(nodes.map(text).join(' ')).toContain(preAttestation);
    const actions = nodes.filter((el) => el.type === 'button' && /confirm/i.test(text(el)));
    for (const action of actions) expect(Boolean(action.props.disabled)).toBe(true);
    expect(h.requests).toEqual([]);
  });
  it('an attested gym removes the banner while still showing remaining off counts', async () => {
    h.coverage = coverageRow({ members_without_dob_attested_adult_at: '2026-10-02T12:00:00Z', no_birth_date: 1 });
    const nodes = await render(await redList()); const visible = nodes.map(text).join(' ');
    expect(visible).not.toContain(preAttestation);
    expect(button(nodes, /Confirm existing members are adults/i)).toBeUndefined();
    expect(visible).toContain('1 has no date of birth.');
  });
  it('pending and failed confirmation retain disclosure, suppress repeat submission, and allow retry', async () => {
    const panel = await banner(); let nodes = await checkedConfirmation(panel);
    h.pendingFetch = true; h.responseStatus = 500;
    h.response = { ok: false, error: { code: 'attestation_failed', message: 'Could not confirm. Try again.' } };
    const action = submitting(nodes, confirmButton(nodes)); const pending = startEvent(action.el, action.event);
    await Promise.resolve(); nodes = await render(panel);
    expect(h.requests).toHaveLength(1);
    expect(nodes.map(text).join(' ')).toContain(preAttestation);
    const duplicates = nodes.filter((el) => el.type === 'button' && /confirm|retry|try again/i.test(text(el)));
    for (const duplicate of duplicates) expect(Boolean(duplicate.props.disabled)).toBe(true);
    expect(h.refreshes).toBe(0);
    expect(h.releaseFetch).toBeTypeOf('function'); h.releaseFetch!(); await pending; await flush();
    nodes = await render(panel); const failed = nodes.map(text).join(' ');
    expect(failed).toContain(preAttestation); expect(failed).toMatch(/could(n.?t| not)|failed|try again/i);
    expect(failed).not.toMatch(/confirmed existing|absence follow-ups are on/i);
    h.pendingFetch = false; h.responseStatus = 200;
    h.response = { ok: true, data: { attestedAt: '2026-10-02T12:00:00Z', changed: true } };
    const retry = submitting(nodes, confirmButton(nodes)); await event(retry.el, retry.event);
    expect(h.requests).toHaveLength(2);
    for (const request of h.requests) expect(JSON.parse(String(request.init.body))).toEqual({});
    h.coverage = coverageRow({ members_without_dob_attested_adult_at: '2026-10-02T12:00:00Z', minor_consent_missing: 1 });
    const refreshed = (await render(await redList())).map(text).join(' ');
    expect(refreshed).not.toContain(preAttestation);
    expect(refreshed).toContain('1 is under 18 without current guardian consent.');
  });
  it('coverage read failure exposes no owner confirmation or guardian backend values', async () => {
    h.readError = true; const nodes = await render(await redList());
    expect(button(nodes, /Confirm existing members are adults/i)).toBeUndefined();
    expect(nodes.map(text).join(' ')).not.toContain('private mira@example.com');
  });
});

describe('GRD actual attention ledger', () => {
  async function attention(reason: string) {
    return (await import('../(console)/members/attention/page')).default({ searchParams: Promise.resolve({ reason }) });
  }
  it('renders the scoped reason members with their scoring sentence and member link', async () => {
    h.attention = [{ member_id: MEMBER, member_name: 'Asha Rao', member_phone: '+918888888888', scoring_state: 'off_no_consent' }];
    const nodes = await render(await attention('minor_consent_missing')); const visible = nodes.map(text).join(' ');
    expect(visible).toContain('Asha Rao');
    expect(visible).toContain("Absence follow-ups are off until the guardian's consent is recorded.");
    expect(nodes.some((el) => el.props.href === `/members/${MEMBER}`)).toBe(true);
  });
  it('states plainly that an empty attention ledger has no members', async () => {
    const nodes = await render(await attention('no_birth_date'));
    expect(nodes.map(text).join(' ')).toMatch(/no (?:members|students)|nobody|none|nothing/i);
  });
  it('trainer sees no attention identities and makes no attention RPC', async () => {
    h.role = 'trainer'; h.attention = [{ member_id: MEMBER, member_name: 'Private Child', member_phone: '+918888888888', scoring_state: 'off_no_consent' }];
    let output: ReactNode = null;
    try { output = await attention('minor_consent_missing'); } catch (error) { expect(String(error)).toMatch(/REDIRECT:|NOT_FOUND/); }
    expect(h.calls).not.toContain('list_guardian_attention'); expect((await render(output)).map(text).join(' ')).not.toContain('Private Child');
  });
});
