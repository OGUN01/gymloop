// Frozen GRD contract. Actual page tree; no invented GuardianPanel props.
import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, expect, it, vi } from 'vitest';
import type { MemberAppAccess } from '../../apps/web/lib/member-invites';
import type { AppAccessPanel as ExistingAppAccessPanel } from '../../apps/web/app/(console)/members/[memberId]/app-access-panel';
import type { GymloopIdentity, StaffRole } from '../../packages/shared/src/api/identity';
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
const h = vi.hoisted(() => {
  const rpc = vi.fn();
  const supabase = {
    rpc,
    from: (table: string) => {
      const reply = { data: table === 'organizations' ? { name: 'Holdout Gym' } : table === 'branches' ? { name: 'Main' } : [], error: null };
      const chain = Promise.resolve(reply) as Query;
      for (const key of ['select', 'eq', 'order', 'limit'] as const) chain[key] = () => chain;
      chain.maybeSingle = async () => reply;
      return chain;
    },
  };
  return { role: 'gym_owner' as StaffRole | 'preview', guardian: {} as GuardianRow, guardianUnavailable: false, guardianError: false, coverage: {} as CoverageRow, rpc, supabase, access: null as MemberAppAccess | null, accessProps: null as { email: string | null; guardian?: { name: string; memberFirstName: string } | null } | null };
});
const memberId = '69910000-0000-4000-8000-000000000001';
vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }), notFound: () => { throw Error('not-found'); }, redirect: () => { throw Error('redirect'); } }));
vi.mock('../../apps/web/lib/identity-session', () => ({ requireAudience: async () => ({
  identity: (h.role === 'preview'
    ? { kind: 'impersonation', userId: memberId, tenantId: memberId, impersonationSessionId: memberId }
    : { kind: 'staff', role: h.role, userId: memberId, tenantId: memberId, staffId: memberId }) satisfies GymloopIdentity,
  supabase: h.supabase,
}) }));
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
vi.mock('../../apps/web/lib/guardian', async importOriginal => {
  const actual = await importOriginal<Record<string, unknown>>();
  return { ...actual, loadMemberGuardian: async () => h.guardianUnavailable || h.guardianError ? null : ({
    ageState: h.guardian.age_state, dateOfBirth: h.guardian.date_of_birth, adultOn: h.guardian.adult_on, gymToday: h.guardian.gym_today,
    guardianName: h.guardian.guardian_name, guardianRelation: h.guardian.guardian_relation, guardianPhone: h.guardian.guardian_phone,
    guardianEmail: h.guardian.guardian_email, guardianComplete: h.guardian.guardian_complete, linkEmail: h.guardian.link_email,
    linkEmailInUse: h.guardian.link_email_in_use, consentState: h.guardian.consent_state, consentRecordedAt: h.guardian.consent_recorded_at,
    consentVersion: h.guardian.consent_version, scoringState: h.guardian.scoring_state, guardianLinkedAt: h.guardian.guardian_linked_at,
    handoverDue: h.guardian.handover_due, legacyAttestedAdult: h.guardian.legacy_attested_adult,
  }) };
});
vi.mock('../../apps/web/lib/supabase/server', () => ({ createServerSupabase: async () => h.supabase }));

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
  h.role = 'gym_owner'; h.accessProps = null; h.access = null; h.guardianUnavailable = false; h.guardianError = false;
  h.guardian = { age_state: 'minor', date_of_birth: '2012-01-01', adult_on: '2030-01-01', gym_today: '2026-10-02', guardian_name: 'Alia Rao', guardian_relation: 'mother', guardian_phone: '+919999999999', guardian_email: 'guardian@holdout.example', guardian_complete: true, link_email: 'guardian@holdout.example', link_email_in_use: false, consent_state: 'none', consent_recorded_at: null, consent_version: null, scoring_state: 'off_no_consent', guardian_linked_at: null, handover_due: false, legacy_attested_adult: false };
  h.coverage = { tracked: 0, no_birth_date: 0, minor_no_guardian: 0, minor_consent_missing: 0, handover_due: 0, members_without_dob_attested_adult_at: null };
  h.rpc.mockReset(); h.rpc.mockImplementation((name: string) => {
    const row = name === 'read_member_guardian' ? h.guardianUnavailable ? null : h.guardian : h.coverage;
    const single = async () => ({ data: row, error: h.guardianError ? { code: '42501', message: 'Private guardian read failed' } : null });
    return Object.assign(Promise.resolve({ data: row === null ? null : [row], error: h.guardianError ? { code: '42501', message: 'Private guardian read failed' } : null }), { single, maybeSingle: single });
  });
});



function accessSection(html: string) {
  return (html.match(/<section[^>]*aria-labelledby="member-app-access-heading"[\s\S]*?<\/section>/)?.[0] ?? '')
    .replaceAll('&#x27;', "'").replaceAll('&#39;', "'").replace(/<[^>]*>/g, ' ');
}
function linked() {
  h.access = { state: 'linked', inviteId: memberId, issuedAt: '2026-01-01T00:00:00Z', expiresAt: null, linkedAt: '2026-01-01T00:00:00Z' };
}
it.each(['minor', 'adult', 'unknown'])('linked %s without authoritative marker has neutral actual panel copy and no guardian prop', async age => {
  h.guardian.age_state = age; h.guardian.guardian_linked_at = null; linked();
  const copy = accessSection(await memberHtml());
  expect(h.accessProps?.guardian ?? null).toBeNull();
  expect(copy).toMatch(/(?:app|membership)[^.]*connected|connected[^.]*(?:app|membership)/i);
  expect(copy).not.toMatch(/(?:own|guardian)[^.]*Google account|Google account[^.]*(?:member|guardian)|guardian[^.]*(?:account|sign.in)/i);
});
it.each(['minor', 'adult', 'unknown'])('retained authoritative marker preserves guardian provenance for linked %s', async age => {
  h.guardian.age_state = age; h.guardian.guardian_linked_at = '2026-01-01T00:00:00Z';
  h.guardian.handover_due = age === 'adult'; linked();
  const copy = accessSection(await memberHtml());
  expect(h.accessProps?.guardian).toEqual({ name: 'Alia Rao', memberFirstName: 'Mira' });
  expect(copy).toMatch(/guardian[^.]*(?:account|sign.in)|(?:account|sign.in)[^.]*guardian/i);
  expect(copy).not.toMatch(/(?:member|Mira)[^.]*own Google account|signs? in[^.]*own Google account/i);
});
it.each(['missing', 'error'] as const)('failed %s guardian read cannot invent linked provenance', async failure => {
  h.guardianUnavailable = failure === 'missing'; h.guardianError = failure === 'error'; linked();
  const copy = accessSection(await memberHtml());
  expect(h.accessProps?.guardian ?? null).toBeNull(); expect(h.accessProps?.email ?? null).toBeNull();
  expect(copy).not.toMatch(/guardian[^.]*(?:Google|account|sign.in)|own Google account/i);
});
it.each(['minor', 'adult', 'unknown'])('prospective %s routes and explains current eligible account independently of old marker', async age => {
  h.guardian.age_state = age; h.guardian.guardian_linked_at = null;
  h.guardian.link_email = age === 'minor' ? 'guardian@holdout.example' : 'child@holdout.example';
  h.access = { state: 'not_invited', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null };
  const copy = accessSection(await memberHtml());
  expect(h.accessProps?.email).toBe(h.guardian.link_email);
  expect(h.accessProps?.guardian ?? null).toEqual(age === 'minor' ? { name: 'Alia Rao', memberFirstName: 'Mira' } : null);
  if (age === 'minor') { expect(copy).toMatch(/guardian/i); expect(copy).not.toContain('child@holdout.example'); }
  else expect(copy).not.toMatch(/invite[^.]*guardian|guardian[^.]*Google account/i);
});
it.each(['missing', 'error'] as const)('prospective failed %s guardian read keeps invite recipient closed without child fallback', async failure => {
  h.guardianUnavailable = failure === 'missing'; h.guardianError = failure === 'error';
  h.access = { state: 'not_invited', inviteId: null, issuedAt: null, expiresAt: null, linkedAt: null };
  const html = await memberHtml(); const copy = accessSection(html);
  expect(h.accessProps?.email ?? null).toBeNull(); expect(h.accessProps?.guardian ?? null).toBeNull();
  expect(copy).not.toContain('child@holdout.example'); expect(html).not.toMatch(/mailto:child|wa\.me\/919876543210/);
});
it('actual panel neutral linked copy also holds when called directly without guardian metadata', async () => {
  const module = await import('../../apps/web/app/(console)/members/[memberId]/app-access-panel'); linked();
  const html = renderToStaticMarkup(React.createElement(module.AppAccessPanel, { memberId, memberName: 'Mira Rao', gymName: 'Held Gym', email: 'child@holdout.example', phone: '+919876543210', role: 'gym_owner', access: h.access, guardian: null }));
  const copy = accessSection(html); expect(copy).toMatch(/connected/i);
  expect(copy).not.toMatch(/own Google account|guardian[^.]*(?:account|sign.in)/i);
});
it('prospective known minor share retains guardian explanation and existing share route', async () => {
  const module = await import('../../apps/web/app/(console)/members/[memberId]/app-access-panel');
  h.access = { state: 'invite_pending', inviteId: memberId, issuedAt: '2026-10-01T12:00:00Z', expiresAt: '2026-10-03T12:00:00Z', linkedAt: null };
  const html = renderToStaticMarkup(React.createElement(module.AppAccessPanel, { memberId, memberName: 'Mira Rao', gymName: 'Held Gym', email: 'guardian@holdout.example', phone: '+919999999999', role: 'gym_owner', access: h.access, guardian: { name: 'Alia Rao', memberFirstName: 'Mira' }, initialIssued: { link: 'https://gymloop.test/invite/held', expiresAt: '2026-10-03T12:00:00Z', replacedPrevious: false } }));
  const copy = accessSection(html); expect(copy).toMatch(/guardian/i); expect(html).toMatch(/wa\.me\/919999999999/);
  expect(html).not.toMatch(/wa\.me\/919876543210|mailto:child/);
});

it('linked neutral account keeps ordinary owner unlink control', async () => {
  h.guardian.age_state = 'adult'; h.guardian.guardian_linked_at = null; linked();
  const html = await memberHtml(); const section = html.match(/<section[^>]*aria-labelledby="member-app-access-heading"[\s\S]*?<\/section>/)?.[0] ?? '';
  const unlink = section.match(/<button\b[^>]*>[\s\S]*?Unlink account[\s\S]*?<\/button>/)?.[0] ?? '';
  expect(unlink).not.toBe(''); expect(unlink).not.toMatch(/\sdisabled(?:\s|=|>)/);
});
it('preview linked account preserves disabled unlink regardless of guardian copy', async () => {
  const module = await import('../../apps/web/app/(console)/members/[memberId]/app-access-panel'); linked();
  const html = renderToStaticMarkup(React.createElement(module.AppAccessPanel, { memberId, memberName: 'Mira Rao', gymName: 'Held Gym', email: 'child@holdout.example', phone: '+919876543210', role: 'gym_owner', access: h.access, guardian: null, readOnly: true }));
  const controls = html.match(/<button\b[^>]*>[\s\S]*?<\/button>/g) ?? [];
  for (const control of controls.filter(button => /Unlink account/.test(button))) expect(control).toMatch(/\sdisabled(?:\s|=|>)/);
});
