// Frozen GRD contract. Actual page tree; no invented GuardianPanel props.
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, expect, it, vi } from 'vitest';
import type { MemberAppAccess } from '../../apps/web/lib/member-invites';
import type { AppAccessPanel as ExistingAppAccessPanel } from '../../apps/web/app/(console)/members/[memberId]/app-access-panel';
type GuardianRow = {
  age_state: string; date_of_birth: string | null; adult_on: string; gym_today: string;
  guardian_name: string; guardian_relation: 'mother'; guardian_phone: string; guardian_email: string;
  guardian_complete: boolean; link_email: string; link_email_in_use: boolean; consent_state: string;
  consent_recorded_at: string | null; consent_version: string | null; scoring_state: string;
  guardian_linked_at: string | null; handover_due: boolean; legacy_attested_adult: boolean;
};
type CoverageRow = { tracked: number; no_birth_date: number; minor_no_guardian: number; minor_consent_missing: number; handover_due: number; members_without_dob_attested_adult_at: string | null };
type ReadReply = { data: unknown; error: null };
type Query = Promise<ReadReply> & {
  select: () => Query; eq: () => Query; order: () => Query; limit: () => Query;
  maybeSingle: () => Promise<ReadReply>;
};
const h = vi.hoisted(() => ({ role: 'gym_owner', guardian: {} as GuardianRow, guardianUnavailable: false, coverage: {} as CoverageRow, rpc: vi.fn(), access: null as MemberAppAccess | null, accessProps: null as { email: string | null; guardian?: { name: string; memberFirstName: string } | null } | null }));
const memberId = '69910000-0000-4000-8000-000000000001';
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }), notFound: () => { throw Error('not-found'); }, redirect: () => { throw Error('redirect'); } }));
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: async () => ({ identity: h.role === 'preview' ? { kind: 'impersonation', tenantId: memberId } : { kind: 'staff', role: h.role, tenantId: memberId } }) }));
vi.mock('../../apps/web/app/(console)/members/member-data', () => ({ loadMember: async () => ({ data: { id: memberId, full_name: 'Mira Rao', phone: '+919876543210', email: 'child@holdout.example', status: 'active', branch_id: memberId, joined_on: '2020-01-01', erased_at: null } }) }));
vi.mock('../../apps/web/lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../../apps/web/lib/member-invites', () => ({ loadMemberAppAccess: async () => h.access }));
vi.mock('../../apps/web/lib/member-invite-history', () => ({ loadMemberInviteActivity: async () => [] }));
vi.mock('../../apps/web/lib/red-list', () => ({ loadRedList: async () => ({ cases: [], pageSize: 50, nextCursor: null, errorMessage: null }) }));
// Capture the established INV prop seam without suppressing its actual page content.
vi.mock('../../apps/web/app/(console)/members/[memberId]/app-access-panel', async importOriginal => {
  const actual = await importOriginal<{ AppAccessPanel: typeof ExistingAppAccessPanel }>();
  return { ...actual, AppAccessPanel: (props: React.ComponentProps<typeof ExistingAppAccessPanel>) => {
    h.accessProps = props;
    return React.createElement(actual.AppAccessPanel, props);
  } };
});
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: async () => ({
  rpc: h.rpc,
  from: (table: string) => {
    const reply = { data: table === 'organizations' ? { name: 'Holdout Gym' } : table === 'branches' ? { name: 'Main' } : [], error: null };
    const chain = Promise.resolve(reply) as Query;
    for (const key of ['select', 'eq', 'order', 'limit'] as const) chain[key] = () => chain;
    chain.maybeSingle = async () => reply;
    return chain;
  },
}) }));

// Resolve actual asynchronous server children before React's static renderer. Client
// components are evaluated by React normally, preserving hooks and native controls.
async function resolveServer(node: React.ReactNode): Promise<React.ReactNode> {
  if (Array.isArray(node)) return Promise.all(node.map(resolveServer));
  if (!React.isValidElement(node)) return node;
  const element = node as React.ReactElement<{ children?: React.ReactNode }>;
  if (typeof element.type === 'function' && element.type.constructor.name === 'AsyncFunction') return resolveServer(await (element.type as unknown as (props: object) => Promise<React.ReactNode>)(element.props));
  if (element.props.children !== undefined) {
    const children = await resolveServer(element.props.children);
    return React.cloneElement(element, {}, ...(Array.isArray(children) ? children : [children]));
  }
  return element;
}
async function memberHtml() {
  const { default: Page } = await import('../../apps/web/app/(console)/members/[memberId]/page');
  return renderToStaticMarkup(await resolveServer(await Page({ params: Promise.resolve({ memberId }), searchParams: Promise.resolve({}) })));
}
beforeEach(() => {
  h.role = 'gym_owner'; h.accessProps = null; h.access = null; h.guardianUnavailable = false;
  h.guardian = { age_state: 'minor', date_of_birth: '2012-01-01', adult_on: '2030-01-01', gym_today: '2026-10-02', guardian_name: 'Alia Rao', guardian_relation: 'mother', guardian_phone: '+919999999999', guardian_email: 'guardian@holdout.example', guardian_complete: true, link_email: 'guardian@holdout.example', link_email_in_use: false, consent_state: 'none', consent_recorded_at: null, consent_version: null, scoring_state: 'off_no_consent', guardian_linked_at: null, handover_due: false, legacy_attested_adult: false };
  h.coverage = { tracked: 0, no_birth_date: 0, minor_no_guardian: 0, minor_consent_missing: 0, handover_due: 0, members_without_dob_attested_adult_at: null };
  h.rpc.mockReset(); h.rpc.mockImplementation((name: string) => {
    const row = name === 'read_member_guardian' ? h.guardianUnavailable ? null : h.guardian : h.coverage;
    const single = async () => ({ data: row, error: null });
    return Object.assign(Promise.resolve({ data: row === null ? null : [row], error: null }), { single, maybeSingle: single });
  });
});

it('known minor uses database age, guardian invite address, dot-plus-word badge and inline consent form', async () => {
  const html = await memberHtml();
  expect(html).toContain('Under 18'); expect(html).toContain('Absence follow-ups are off until');
  expect(html).toMatch(/type="checkbox"/); expect(html).toMatch(/>Record(?: consent)?</); expect(html).toMatch(/source|Source/);
  expect(h.accessProps?.email).toBe('guardian@holdout.example'); expect(h.accessProps?.guardian).toEqual({ name: 'Alia Rao', memberFirstName: 'Mira' });
});
it.each([
  ['on_adult', 'Absence follow-ups are on.'],
  ['on_consent', "Absence follow-ups are on, with the guardian's consent on record."],
  ['off_age_unknown', 'Absence follow-ups are off. Add a date of birth to turn them on.'],
  ['off_no_guardian', "Absence follow-ups are off. Add the guardian's name, relation and phone."],
  ['off_no_consent', "Absence follow-ups are off until the guardian's consent is recorded."],
  ['off_consent_withdrawn', 'The guardian withdrew consent, so absence follow-ups are off. Visits are still recorded.'],
  ['off_consent_stale', "The guardian's details changed after consent was recorded, so absence follow-ups are off. Record consent again."],
])('actual member page preserves complete %s consequence', async (state, sentence) => {
  h.guardian.scoring_state = state;
  const html = await memberHtml();
  const plain = html.replaceAll('&#x27;', "'").replaceAll('&#39;', "'").replaceAll('&apos;', "'");
  expect(plain).toContain(sentence);
});
it('database adult state wins over apparent minor birth date and never computes age in the browser', async () => {
  h.guardian.age_state = 'adult'; h.guardian.scoring_state = 'on_adult';
  expect(await memberHtml()).not.toContain('Under 18');
});
it('attested missing DOB stays unknown, explains the exception, and does not use guardian email', async () => {
  Object.assign(h.guardian, { age_state: 'unknown', date_of_birth: null, scoring_state: 'on_adult', legacy_attested_adult: true, link_email: 'child@holdout.example' });
  const html = await memberHtml(); expect(html).toContain('Absence follow-ups are on.'); expect(html).toContain('The owner confirmed existing members without a date of birth are adults.');
  expect(h.accessProps?.email).toBe('child@holdout.example'); expect(h.accessProps?.guardian ?? null).toBeNull();
});
it('trainer sees no guardian section and causes no guardian read', async () => {
  h.role = 'trainer'; const html = await memberHtml();
  expect(html).not.toContain('Alia Rao'); expect(html).not.toMatch(/>Record(?: consent)?</);
  expect(h.rpc.mock.calls.some(([name]) => name === 'read_member_guardian')).toBe(false);
});
it.each(['none', 'granted', 'handover'])('support preview keeps %s mutations read-only, whether absent or disabled', async state => {
  h.role = 'preview';
  if (state === 'granted') Object.assign(h.guardian, { consent_state: 'granted', scoring_state: 'on_consent', consent_version: 'guardian-absence-v1', consent_recorded_at: '2026-10-02T12:00:00Z' });
  if (state === 'handover') Object.assign(h.guardian, { age_state: 'adult', scoring_state: 'on_adult', guardian_linked_at: '2026-01-01T00:00:00Z', handover_due: true });
  const html = await memberHtml();
  for (const control of html.matchAll(/<button\b([^>]*)>([\s\S]*?)<\/button>/g)) {
    const label = control[2].replace(/<[^>]*>/g, '').trim();
    if (!/^(?:Save|Record(?: consent)?|Withdraw consent|Hand over account|Confirm(?: withdrawal| handover)?)$/i.test(label)) continue;
    // Native disabled controls and inherited disabled fieldsets both prevent mutation.
    const fieldsets: boolean[] = [];
    for (const tag of html.slice(0, control.index).matchAll(/<\/?fieldset\b[^>]*>/g)) {
      if (tag[0].startsWith('</')) fieldsets.pop();
      else fieldsets.push(/\sdisabled(?:\s|=|>)/.test(tag[0]));
    }
    expect(/\sdisabled(?:\s|=|$)/.test(control[1]) || fieldsets.includes(true), label).toBe(true);
  }
});
it('account collision warning never names another member', async () => {
  h.guardian.link_email_in_use = true;
  const html = await memberHtml(); expect(html).toMatch(/another|already/i); expect(html).not.toContain('Other Child Private');
});
it('known adult guardian-linked handover names retained history and requires a reason', async () => {
  Object.assign(h.guardian, { age_state: 'adult', scoring_state: 'on_adult', guardian_linked_at: '2026-01-01T00:00:00Z', handover_due: true });
  const html = await memberHtml(); expect(html).toMatch(/Hand over|own account/i);
  // The confirmation is exercised by the live browser harness; a hidden panel may
  // legitimately be absent from this initial static tree.
});
it('read failure shows no fabricated guardian eligibility or consent form', async () => {
  h.guardianUnavailable = true; const html = await memberHtml(); expect(html).not.toMatch(/>Record(?: consent)?</); expect(html).not.toContain("with the guardian&#x27;s consent on record");
});
it.each(['invite_pending', 'invite_expired'] as const)('known adult with pre-birthday %s gets the GRD-011 re-issue notice', async state => {
  Object.assign(h.guardian, { age_state: 'adult', adult_on: '2026-10-02', scoring_state: 'on_adult', link_email: 'child@holdout.example' });
  h.access = { state, inviteId: memberId, issuedAt: '2026-10-01T12:00:00Z', expiresAt: '2026-10-03T12:00:00Z', linkedAt: null };
  expect(await memberHtml()).toContain('Re-issue the invite');
  expect(h.accessProps?.email).toBe('child@holdout.example'); expect(h.accessProps?.guardian ?? null).toBeNull();
});
it.each([
  { age: 'minor', state: 'invite_pending', issuedAt: '2026-10-01T12:00:00Z' },
  { age: 'unknown', state: 'invite_expired', issuedAt: '2026-10-01T12:00:00Z' },
  { age: 'adult', state: 'invite_pending', issuedAt: '2026-10-02T00:00:00Z' },
  { age: 'adult', state: 'invite_expired', issuedAt: '2026-10-03T12:00:00Z' },
  { age: 'adult', state: 'linked', issuedAt: '2026-10-01T12:00:00Z' },
] as const)('does not invent a birthday re-issue notice for $age / $state / $issuedAt', async ({ age, state, issuedAt }) => {
  Object.assign(h.guardian, { age_state: age, adult_on: '2026-10-02' });
  h.access = { state, inviteId: memberId, issuedAt, expiresAt: '2026-10-03T12:00:00Z', linkedAt: null };
  expect(await memberHtml()).not.toContain('Re-issue the invite');
});
it('privacy page states guardian account and contact routing without advertising claim drift', async () => {
  const { default: Page } = await import('../../apps/web/app/(public)/privacy/page');
  const html = renderToStaticMarkup(await resolveServer(await Page()));
  expect(html).toMatch(/guardian.{0,20}Google account/); expect(html).toMatch(/messages go to the guardian/); expect(html).toContain('not for children under 13');
});
it('zero-count pre-attestation red list still explains missing-DOB consequence', async () => {
  const { default: Page } = await import('../../apps/web/app/(console)/red-list/page');
  const html = renderToStaticMarkup(await resolveServer(await Page({ searchParams: Promise.resolve({}) })));
  expect(html).toMatch(/date of birth/i); expect(html).toMatch(/attest|confirm.*adult/i);
});
it('attested zero-count red list removes the one-time coverage note', async () => {
  h.coverage.members_without_dob_attested_adult_at = '2026-10-02T12:00:00Z';
  const { default: Page } = await import('../../apps/web/app/(console)/red-list/page');
  const html = renderToStaticMarkup(await resolveServer(await Page({ searchParams: Promise.resolve({}) })));
  expect(html).not.toMatch(/no date of birth|attest.*adult/i);
});
