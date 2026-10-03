import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement, type ReactNode } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import type { GymloopIdentity } from '@gymloop/shared';
import type { Database } from '@gymloop/db';
import type { SupabaseClient } from '@supabase/supabase-js';

// LDC-001…011 visible regression + gap pins. The repo's visible harness is
// static-render only (no DOM environment), so click-driven requirements — the
// per-row pending lock (LDC-002), same-key retry after a lost response
// (LDC-006) and the uncertain-result copy (LDC-011) — are covered by the
// independent holdout author and real acceptance, not here. Behavior comes
// from the frozen contract, never from component bodies.
type Row = Record<string, unknown>;
const h = vi.hoisted(() => ({
  rows: [] as Row[],
  errorMessage: null as string | null,
  online: true,
}));
const LEAD = '69000000-0000-4000-8000-000000000101';
const MEMBER = '69000000-0000-4000-8000-000000000102';
const BRANCH = '69000000-0000-4000-8000-000000000103';
const TENANT = '69000000-0000-4000-8000-000000000104';
const STAFF = '69000000-0000-4000-8000-000000000105';
const USER = '69000000-0000-4000-8000-000000000106';
const REVISION = '7f000000-0000-4000-8000-000000000007';

const row = (over: Row = {}): Row => ({
  id: LEAD,
  revision: REVISION,
  fullName: 'Asha Rao',
  phone: '+918888888888',
  source: 'walk_in',
  stage: 'trial_done',
  assignedToStaffId: STAFF,
  assignedToName: 'Desk Kaur',
  branchId: BRANCH,
  branchName: 'Main',
  trialAt: '2026-10-02T10:00+05:30',
  convertedMemberId: null,
  lostReason: null,
  updatedAt: '2026-10-02T12:00:00Z',
  ...over,
});

const screen = (): Row => ({
  rows: h.rows,
  stageCounts: { new: '0', contacted: '0', trial_scheduled: '0', trial_done: '1', converted: '0', lost: '0' },
  pageResultCount: String(h.rows.length),
  totalMatchingCount: String(h.rows.length),
  asOf: '2026-10-02T12:30:00Z',
  nextCursor: null,
  pageSize: 50,
  timezone: 'Asia/Kolkata',
  staffChoices: [],
  branchChoices: [{ id: BRANCH, name: 'Main' }],
  editableText: {},
  errorMessage: h.errorMessage,
});

vi.mock('next/navigation', () => ({
  redirect: (path: string) => { throw new Error(`REDIRECT:${path}`); },
  notFound: () => { throw new Error('NOT_FOUND'); },
  useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }),
  usePathname: () => '/leads',
  useSearchParams: () => new URLSearchParams(),
}));
vi.mock('next/link', () => ({ default: (props: Row) => createElement('a', props) }));
vi.mock('../../lib/leads', async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  return { ...actual, loadLeads: async () => screen() };
});
vi.mock('../../lib/supabase/server', () => ({
  createServerSupabase: async () => ({}) as unknown as SupabaseClient<Database>,
}));
vi.mock('../../lib/identity-session', () => ({
  requireAudience: async () => ({
    supabase: {} as unknown as SupabaseClient<Database>,
    identity: {
      kind: 'staff', userId: USER, tenantId: TENANT, staffId: STAFF, role: 'front_desk',
    } as GymloopIdentity,
  }),
  readIdentity: async () => ({
    supabase: {} as unknown as SupabaseClient<Database>,
    identity: {
      kind: 'staff', userId: USER, tenantId: TENANT, staffId: STAFF, role: 'front_desk',
    } as GymloopIdentity,
    signedIn: true,
  }),
}));

function visible(node: ReactNode): string {
  return renderToStaticMarkup(node).replace(/<[^>]*>/g, ' ').replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"');
}
/** A row action labelled exactly "Convert to member" (LDC-002's frozen label) —
 * its own text node, not prose containing the words. Anchored so prose like
 * "Convert or mark lost" never matches. */
function convertActions(html: string): number {
  return (html.match(/>\s*Convert to member\s*</g) ?? []).length;
}
async function leadsPage() {
  const mod = await import('../(console)/leads/page');
  return mod.default({ searchParams: Promise.resolve(new URLSearchParams()) } as never);
}

beforeEach(() => {
  h.rows = []; h.errorMessage = null; h.online = true;
  vi.stubGlobal('navigator', { get onLine() { return h.online; } });
  vi.stubGlobal('window', { location: { origin: 'https://app.example' }, addEventListener: vi.fn(), removeEventListener: vi.fn() });
});
afterEach(() => vi.unstubAllGlobals());

describe('LDC page regressions (LDC-001/008/011)', () => {
  it('LDC-001/002: exactly the trial_done row offers the Convert action', async () => {
    h.rows = [
      row(),
      row({ id: '69000000-0000-4000-8000-000000000201', fullName: 'Vikram Das', stage: 'new', trialAt: null }),
      row({ id: '69000000-0000-4000-8000-000000000202', fullName: 'Meera Nair', stage: 'trial_scheduled' }),
      row({ id: '69000000-0000-4000-8000-000000000203', fullName: 'Sam José', stage: 'contacted' }),
    ];
    const convertButtons = convertActions(renderToStaticMarkup(await leadsPage()));
    expect(convertButtons).toBe(1);
    const copy = visible(await leadsPage());
    expect(copy).toMatch(/Asha Rao/);
  });

  it('LDC-008: a lost lead shows its loss reason and offers no Convert button', async () => {
    h.rows = [row({ stage: 'lost', lostReason: 'Moved cities', trialAt: null })];
    const html = renderToStaticMarkup(await leadsPage());
    expect(visible(html)).toMatch(/Moved cities/);
    expect(convertActions(html)).toBe(0);
  });

  it('LDC-008/011: a converted lead offers Open member for its converted member', async () => {
    h.rows = [row({ stage: 'converted', convertedMemberId: MEMBER, lostReason: null })];
    const html = renderToStaticMarkup(await leadsPage());
    expect(html).toContain('Open member');
    expect(html).toContain(MEMBER);
    expect(convertActions(html)).toBe(0);
  });

  it('LDC-001: a loader-reported error renders no Convert affordance', async () => {
    h.errorMessage = 'Leads could not be loaded.';
    const html = renderToStaticMarkup(await leadsPage());
    expect(html).toMatch(/could not be loaded/i);
    expect(convertActions(html)).toBe(0);
  });

  it('LDC-011 GAP: while offline the workspace tells the desk conversion needs a connection', async () => {
    h.rows = [row()];
    h.online = false;
    const copy = visible(await leadsPage());
    expect(copy).toContain("You're offline. Connect to convert this lead.");
  });
});

describe('LDC refusal/result mapping regressions (LDC-004/005/006/007/011)', () => {
  // GL061's DETAIL is the database contract: a JSON object of exactly the four
  // disclosed facts (phase6_leads.sql). The mapping must carry them and
  // nothing more; an unparseable DETAIL still answers link_required without
  // inventing facts.
  const DETAIL = JSON.stringify({ fullName: 'Asha Rao', memberId: MEMBER, phone: '+918888888888', status: 'active' });

  it('LDC-004: an eligible duplicate answers 409 link_required with exactly the four member facts', async () => {
    const { convertLeadFailure } = await import('../../app/api/leads/lead-input');
    const response = convertLeadFailure({ code: 'GL061', message: 'An eligible member with this phone already exists', details: DETAIL });
    expect(response.status).toBe(409);
    const body = (await response.json()) as Row;
    const error = body.error as Row;
    expect(error.code).toBe('link_required');
    expect(error.member).toEqual({ memberId: MEMBER, fullName: 'Asha Rao', phone: '+918888888888', status: 'active' });
    expect(Object.keys(error).filter((key) => key !== 'code' && key !== 'message')).toEqual(['member']);
  });

  it('LDC-004: an unparseable GL061 DETAIL still answers link_required with no member facts', async () => {
    const { convertLeadFailure } = await import('../../app/api/leads/lead-input');
    const response = convertLeadFailure({ code: 'GL061', message: 'An eligible member with this phone already exists', details: 'not-json' });
    expect(response.status).toBe(409);
    const error = ((await response.json()) as Row).error as Row;
    expect(error.code).toBe('link_required');
    expect(error.member).toBeUndefined();
  });

  it('LDC-005: an unavailable same-phone member discloses no profile facts', async () => {
    const { memberUnavailableFailure } = await import('../../app/api/leads/lead-input');
    const response = memberUnavailableFailure();
    expect(response.status).toBe(409);
    const error = ((await response.json()) as Row).error as Row;
    expect(error.code).toBe('member_unavailable');
    expect(error.member).toBeUndefined();
  });

  it('LDC-007: a stale lead answers 409 stale_lead carrying the current revision', async () => {
    const { staleLeadFailure } = await import('../../app/api/leads/lead-input');
    const response = staleLeadFailure('9f000000-0000-4000-8000-000000000009');
    expect(response.status).toBe(409);
    const error = ((await response.json()) as Row).error as Row;
    expect(error.code).toBe('stale_lead');
    expect(error.currentRevision).toBe('9f000000-0000-4000-8000-000000000009');
  });

  it('LDC-006: a reused key with changed facts answers 409 idempotency_conflict', async () => {
    const { convertLeadFailure } = await import('../../app/api/leads/lead-input');
    const response = convertLeadFailure({ code: 'GL062', message: 'Request key reused with different facts' });
    expect(response.status).toBe(409);
    const error = ((await response.json()) as Row).error as Row;
    expect(error.code).toBe('idempotency_conflict');
  });

  it('LDC-011: an unknown SQLSTATE is a 500, never a guessed success', async () => {
    const { convertLeadFailure } = await import('../../app/api/leads/lead-input');
    const response = convertLeadFailure({ code: 'ZZ999', message: 'unexpected' });
    expect(response.status).toBe(500);
  });

  it('LDC-011: only a complete catalogue result is accepted as success', async () => {
    const { convertLeadResult } = await import('../../app/api/leads/lead-input');
    expect(convertLeadResult({ leadId: LEAD, memberId: MEMBER, outcome: 'created_member', revision: REVISION, replayed: false })).toMatchObject({ outcome: 'created_member', replayed: false });
    expect(convertLeadResult({ leadId: LEAD, memberId: MEMBER, outcome: 'linked_existing', revision: REVISION, replayed: true })).toMatchObject({ outcome: 'linked_existing', replayed: true });
    expect(convertLeadResult({ leadId: LEAD, memberId: MEMBER, outcome: 'forged_outcome', revision: REVISION, replayed: false })).toBeNull();
    expect(convertLeadResult({ leadId: LEAD, outcome: 'created_member', revision: REVISION, replayed: false })).toBeNull();
    expect(convertLeadResult({ leadId: 'not-a-uuid', memberId: MEMBER, outcome: 'created_member', revision: REVISION, replayed: false })).toBeNull();
  });
});
