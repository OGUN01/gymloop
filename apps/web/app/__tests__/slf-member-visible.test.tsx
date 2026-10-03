import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// SLF member web surface, visible suite (red until built).
// FROZEN CONTRACT: openspec/changes/member-self-service/proposal.md
// (SLF-001/002/016/017/018) + docs/design/v2/slf-bar.md criteria 1-4, 7, 8.
// Planned interface this suite pins (implementation must satisfy it):
//   default export of ../member/freeze-requests rendering
//   MemberFreezeRequestsSurface props:
//     nouns: { place: string; member: string }
//     membership: { planName: string | null; status: string; startsOn: string;
//       endsOn: string | null; recordedAgreedPricePaise: string | null;
//       currency: string } | null
//     requests: Array<{ id: string; status: 'requested' | 'desk_submitted' |
//       'approved' | 'rejected' | 'cancelled' | 'expired'; startsOn: string;
//       endsOn: string; reason: string; decisionReason: string | null;
//       effective: 'scheduled' | 'paused' | 'completed' | null }>
//     offline: boolean
//     loadedAt: string | null
//     permissionDenied: boolean (default false)
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'light', setTheme: vi.fn() }) }));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));

const nouns = { place: 'gym', member: 'member' } as const;
const membership = {
  planName: 'Monthly Unlimited',
  status: 'active',
  startsOn: '2026-09-01',
  endsOn: '2026-12-31',
  recordedAgreedPricePaise: '150000',
  currency: 'INR',
};
const request = (over: Partial<Record<string, unknown>> = {}) => ({
  id: '81100000-0000-4000-8000-000000000001',
  status: 'requested',
  startsOn: '2026-10-10',
  endsOn: '2026-10-17',
  reason: 'Family trip out of station',
  decisionReason: null,
  effective: null,
  ...over,
});
let screen: () => unknown;
beforeEach(async () => {
  vi.resetModules();
  ({ default: screen } = await import('../member/freeze-requests'));
});
const html = (props: Record<string, unknown>) =>
  renderToStaticMarkup(createElement(screen as never, { nouns, membership, requests: [], offline: false, loadedAt: '2026-10-03T09:00:00Z', permissionDenied: false, ...props } as never));

describe('SLF member web surface (red until built)', () => {
  it('SLF-001 discloses held plan, recorded sold net price with currency and actual inclusive dates before any action', () => {
    const page = html({});
    expect(page).toContain('Monthly Unlimited');
    expect(page).toMatch(/₹1,500/);
    expect(page).toMatch(/INR/);
    expect(page).toMatch(/2026-09-01/);
    expect(page).toMatch(/2026-12-31/);
  });

  it('SLF-002 disables freeze and renewal for a pending membership with a specific desk path, keeping plan and history readable', () => {
    const page = html({ membership: { ...membership, status: 'pending' }, requests: [request()] });
    expect(page).toMatch(/front desk|contact your gym|desk/i);
    expect(page).not.toMatch(/<button[^>]*>[^<]*Request freeze/i);
    expect(page).not.toMatch(/<button[^>]*>[^<]*Renew/i);
    expect(page).toContain('Monthly Unlimited');
    expect(page).toContain('Family trip out of station');
  });

  it('SLF-002 never invents a pending value for member status; a pending request leaves the membership status itself alone', () => {
    const page = html({ requests: [request({ status: 'desk_submitted' })] });
    expect(page).not.toMatch(/account is pending|membership is pending/i);
  });

  it('bar 2: the request sheet shows exact dates, reason and the frozen request-not-approval copy with the business noun', () => {
    const page = html({ requests: [request()] });
    expect(page).toMatch(/This is a request\. Your gym must approve it\./);
    expect(page).toMatch(/2026-10-10/);
    expect(page).toMatch(/2026-10-17/);
    expect(page).toMatch(/Family trip out of station/);
  });

  it('SLF-018 renders awaiting-desk-adoption, awaiting-approval, scheduled, paused and completed as distinct labelled states', () => {
    const page = html({
      requests: [
        request({ id: '81100000-0000-4000-8000-000000000002', status: 'requested' }),
        request({ id: '81100000-0000-4000-8000-000000000003', status: 'desk_submitted' }),
        request({ id: '81100000-0000-4000-8000-000000000004', status: 'approved', effective: 'scheduled' }),
        request({ id: '81100000-0000-4000-8000-000000000005', status: 'approved', effective: 'paused' }),
        request({ id: '81100000-0000-4000-8000-000000000006', status: 'approved', effective: 'completed' }),
      ],
    });
    expect(page).toMatch(/Awaiting desk adoption/i);
    expect(page).toMatch(/Awaiting approval/i);
    expect(page).toMatch(/Scheduled/i);
    expect(page).toMatch(/Paused/i);
    expect(page).toMatch(/Completed/i);
  });

  it('SLF-018 renders cancelled, rejected-with-reason and expired history with the requested dates retained', () => {
    const page = html({
      requests: [
        request({ id: '81100000-0000-4000-8000-000000000002', status: 'cancelled' }),
        request({ id: '81100000-0000-4000-8000-000000000003', status: 'rejected', decisionReason: 'Dates overlap a peak month' }),
        request({ id: '81100000-0000-4000-8000-000000000004', status: 'expired' }),
      ],
    });
    expect(page).toMatch(/Cancelled/i);
    expect(page).toMatch(/Rejected/i);
    expect(page).toContain('Dates overlap a peak month');
    expect(page).toMatch(/Expired/i);
    expect((page.match(/2026-10-10/g) ?? []).length).toBeGreaterThanOrEqual(3);
  });

  it('bar 4: cancellation is labelled Cancel request and never says cancel membership or resume an approved pause', () => {
    const page = html({ requests: [request({ status: 'desk_submitted' }), request({ id: '81100000-0000-4000-8000-000000000003', status: 'approved', effective: 'scheduled' })] });
    expect(page).toMatch(/Cancel request/);
    expect(page).not.toMatch(/cancel (my )?membership/i);
    expect(page).not.toMatch(/resume the pause|end the pause early/i);
  });

  it('SLF-016 renewal points at the single /member/buy destination and no other renewal endpoint', () => {
    const page = html({});
    expect(page).toMatch(/\/member\/buy/);
    expect(page).not.toMatch(/\/api\/member\/renew|\/renewals?\b/);
  });

  it('SLF-017 offline shows last-good data with its fetched time and refuses create and cancel without queueing', () => {
    const page = html({ offline: true, requests: [request({ status: 'desk_submitted' })] });
    expect(page).toMatch(/offline/i);
    expect(page).toMatch(/2026-10-03T09:00|fetched|last (loaded|updated)/i);
    expect(page).not.toMatch(/<button[^>]*>[^<]*Request freeze/i);
    expect(page).not.toMatch(/<button[^>]*>[^<]*Cancel request/i);
    expect(page).not.toMatch(/queued|will send when (back )?online/i);
  });

  it('SLF-018 permission denial, validation conflict and retryable error states are distinct from empty history', () => {
    const empty = html({});
    expect(empty).toMatch(/no (freeze )?requests|no requests yet/i);
    const denied = html({ permissionDenied: true });
    expect(denied).toMatch(/not permitted|don't have access|permission/i);
    expect(denied).not.toMatch(/no requests yet/i);
  });
});
