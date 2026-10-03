import type { GymloopIdentity, StaffRole } from '../../lib/identity';
import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';

// RPE frozen contract (CSV-first delivery): the owner Exports screen shows the
// three CSV datasets with their meaning, basis, zone, branch semantics, limits
// and warnings before any Download. RPE-010…012 (invoice PDF) are deferred and
// intentionally absent here.
const state = vi.hoisted(() => ({
  kind: 'staff' as 'staff' | 'member' | 'unlinked',
  role: 'gym_owner' as StaffRole,
  signedIn: true,
}));
const identity = (): { signedIn: boolean; authenticatedUser: boolean; identity: GymloopIdentity } => {
  if (!state.signedIn) return { signedIn: false, authenticatedUser: false, identity: { kind: 'unlinked' } as GymloopIdentity };
  if (state.kind === 'member') {
    return { signedIn: true, authenticatedUser: true, identity: { kind: 'member', userId: '86000000-0000-4000-8000-000000000901', tenantId: '86000000-0000-4000-8000-000000000001', memberId: '86000000-0000-4000-8000-000000000101' } as GymloopIdentity };
  }
  return { signedIn: true, authenticatedUser: true, identity: { kind: 'staff', userId: '86000000-0000-4000-8000-000000000901', tenantId: '86000000-0000-4000-8000-000000000001', staffId: '86000000-0000-4000-8000-000000000021', role: state.role } as GymloopIdentity };
};

vi.mock('next/navigation', () => ({
  usePathname: () => '/console/exports',
  useRouter: () => ({ push: vi.fn(), replace: vi.fn(), refresh: vi.fn() }),
}));
vi.mock('../../lib/identity-session', () => ({
  readIdentity: async () => identity(),
  readRequestIdentity: async () => identity(),
}));

const renderPage = async () => {
  const { default: ExportsPage } = await import('../(console)/exports/page');
  return renderToStaticMarkup(<ExportsPage />);
};

beforeEach(() => {
  state.kind = 'staff';
  state.role = 'gym_owner';
  state.signedIn = true;
});

describe('RPE-013 the owner Exports screen discloses everything before Download', () => {
  it('shows the three dataset cards with their exact frozen labels and date bases', async () => {
    const html = await renderPage();
    expect(html).toContain('Payment records by creation date');
    expect(html).toContain('Recorded attendance events');
    expect(html).toMatch(/join/i);
    expect(html).toContain('created_at');
    expect(html).toContain('checked_in_at');
    expect(html).toContain('joined_on');
  });

  it('states the honest truths: payment records are not net revenue and members are a joining cohort, not a roster', async () => {
    const html = await renderPage();
    expect(html).toMatch(/not net revenue|not a net revenue/i);
    expect(html).toMatch(/not .*(roster|membership list)|joining cohort/i);
  });

  it('names the zone, branch semantics and current-branch labelling before Download', async () => {
    const html = await renderPage();
    expect(html).toMatch(/Asia\/Kolkata|gym timezone|zone/i);
    expect(html).toMatch(/branch/i);
    expect(html).toMatch(/current member branch|current branch/i);
  });

  it('names the limits (366 days, 5,000 rows, 8 MiB, 15 seconds) before Download', async () => {
    const html = await renderPage();
    expect(html).toContain('366');
    expect(html).toMatch(/5[,.]?000/);
    expect(html).toMatch(/8\s?MiB/);
    expect(html).toContain('15');
  });

  it('warns about member contact data and the spreadsheet-protection caveat', async () => {
    const html = await renderPage();
    expect(html).toMatch(/contact|phone|email/i);
    expect(html).toMatch(/spreadsheet/i);
    expect(html).toMatch(/re-sav|re Sav|saving again|reopen/i);
  });
});

describe('RPE-013 role gating and state copy', () => {
  it('the owner sees the Download controls', async () => {
    const html = await renderPage();
    expect(html).toMatch(/Download/i);
  });

  it.each([
    ['gym_manager' as StaffRole],
    ['front_desk' as StaffRole],
    ['trainer' as StaffRole],
  ])('%s sees no Downloads', async (role) => {
    state.role = role;
    const html = await renderPage();
    expect(html).not.toMatch(/Download/i);
  });

  it('a member or signed-out visitor never reaches the exports screen', async () => {
    state.kind = 'member';
    const memberHtml = await renderPage();
    expect(memberHtml).not.toMatch(/Download/i);
    state.kind = 'staff';
    state.signedIn = false;
    const anonHtml = await renderPage();
    expect(anonHtml).not.toMatch(/Download/i);
  });

  it('every CSV-applicable outcome state has its own label and a specific next action', async () => {
    const { REPORT_EXPORT_STATES } = await import('../../lib/report-exports');
    const required = ['generating', 'empty', 'ready', 'permission', 'invalid_range', 'too_large', 'unavailable', 'integrity', 'audit', 'timeout', 'server_error'] as const;
    for (const key of required) {
      const entry = (REPORT_EXPORT_STATES as Record<string, { label?: string; action?: string }>)[key];
      expect(entry, `state ${key} exists`).toBeDefined();
      expect(entry.label?.length ?? 0).toBeGreaterThan(0);
      expect(entry.action?.length ?? 0).toBeGreaterThan(0);
    }
    expect(String((REPORT_EXPORT_STATES as Record<string, { hint?: string }>).too_large?.hint ?? '')).toMatch(/narrow/i);
    const labels = required.map((key) => String((REPORT_EXPORT_STATES as Record<string, { label?: string }>)[key]?.label));
    expect(new Set(labels).size).toBe(required.length);
  });
});
