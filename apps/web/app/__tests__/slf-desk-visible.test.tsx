import { beforeEach, describe, expect, it, vi } from 'vitest';
import { createElement } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';

// SLF staff desk queue, visible suite (red until built).
// FROZEN CONTRACT: openspec/changes/member-self-service/proposal.md
// (SLF-006…010) + docs/design/v2/slf-bar.md criterion 5.
// Planned interface this suite pins (implementation must satisfy it):
//   named export FreezeRequestQueue from ../(console)/freeze-requests/queue with
//     nouns: { place: string; member: string }
//     viewerRole: 'gym_owner' | 'gym_manager' | 'front_desk'
//     viewerStaffId: string
//     approverRole: string (current configured pause_approver_role)
//     requests: Array<{ id: string; memberName: string; memberCode: string;
//       status: 'requested' | 'desk_submitted' | 'approved' | 'rejected' |
//       'expired'; startsOn: string; endsOn: string; reason: string;
//       decisionReason: string | null; adoptedByStaffId: string | null }>
//     stale: boolean (default false; a revision conflict closed the row's confirmation)
vi.mock('next-themes', () => ({ useTheme: () => ({ theme: 'light', setTheme: vi.fn() }) }));
vi.mock('next/link', () => ({ default: (props: Record<string, unknown>) => ({ type: 'a', props }) }));

const nouns = { place: 'gym', member: 'member' } as const;
const staff = '81200000-0000-4000-8000-0000000000a1';
const other = '81200000-0000-4000-8000-0000000000a2';
const row = (over: Partial<Record<string, unknown>> = {}) => ({
  id: '81100000-0000-4000-8000-000000000001',
  memberName: 'Fixture Member',
  memberCode: 'IRN-0042',
  status: 'requested',
  startsOn: '2026-10-10',
  endsOn: '2026-10-17',
  reason: 'Family trip out of station',
  decisionReason: null,
  adoptedByStaffId: null,
  ...over,
});
let queue: (props: unknown) => unknown;
beforeEach(async () => {
  vi.resetModules();
  ({ FreezeRequestQueue: queue } = (await import('../(console)/freeze-requests/queue')) as never);
});
const html = (props: Record<string, unknown>) =>
  renderToStaticMarkup(createElement(queue as never, { nouns, viewerRole: 'front_desk', viewerStaffId: staff, approverRole: 'gym_manager', requests: [], ...props } as never));

describe('SLF desk queue (red until built)', () => {
  it('bar 5 shows the original member request and reason, and Adopt request / Approve freeze as two distinct actions', () => {
    const page = html({ requests: [row(), row({ id: '81100000-0000-4000-8000-000000000002', status: 'desk_submitted', adoptedByStaffId: other })] });
    expect(page).toContain('Fixture Member');
    expect(page).toContain('IRN-0042');
    expect(page).toContain('Family trip out of station');
    expect(page).toMatch(/Adopt request/);
    expect(page).toMatch(/Approve freeze/);
  });

  it('bar 5: an adopting staff member cannot approve their own adopted request', () => {
    const page = html({ viewerStaffId: staff, requests: [row({ status: 'desk_submitted', adoptedByStaffId: staff })] });
    expect(page).not.toMatch(/<button[^>]*>[^<]*Approve freeze/i);
    expect(page).toMatch(/cannot approve|another staff|different (staff|person)/i);
  });

  it('bar 5 keeps the configured-role boundary readable, naming the current approver role', () => {
    const page = html({ approverRole: 'gym_manager', requests: [row({ status: 'desk_submitted', adoptedByStaffId: other })] });
    expect(page).toContain('gym_manager');
  });

  it('bar 5: a solo owner with no second staff member gets a truthful no-approvable path, never an enabled Approve', () => {
    const page = html({ viewerRole: 'gym_owner', viewerStaffId: staff, approverRole: 'gym_owner', requests: [row({ status: 'desk_submitted', adoptedByStaffId: staff })] });
    expect(page).not.toMatch(/<button[^>]*>[^<]*Approve freeze/i);
    expect(page).toMatch(/no (other )?staff|second (staff|person|approver)|cannot be approved/i);
  });

  it('bar 5 labels the rejection reason as shown to the member', () => {
    const page = html({ requests: [row({ status: 'rejected', decisionReason: 'Dates overlap a peak month' })] });
    expect(page).toContain('Dates overlap a peak month');
    expect(page).toMatch(/shown to the member/i);
  });

  it('bar 5: a stale detail closes its confirmation and offers refresh instead of a decision', () => {
    const page = html({ requests: [row({ status: 'desk_submitted', adoptedByStaffId: other })], stale: true } as Record<string, unknown>);
    expect(page).toMatch(/refresh/i);
    expect(page).not.toMatch(/<button[^>]*>[^<]*Approve freeze/i);
  });

  it('SLF-018 desk states are distinct: awaiting adoption, awaiting approval, approved, rejected, expired', () => {
    const page = html({
      requests: [
        row({ id: '81100000-0000-4000-8000-000000000002', status: 'requested' }),
        row({ id: '81100000-0000-4000-8000-000000000003', status: 'desk_submitted', adoptedByStaffId: other }),
        row({ id: '81100000-0000-4000-8000-000000000004', status: 'approved', adoptedByStaffId: other }),
        row({ id: '81100000-0000-4000-8000-000000000005', status: 'rejected', decisionReason: 'Peak month', adoptedByStaffId: other }),
        row({ id: '81100000-0000-4000-8000-000000000006', status: 'expired' }),
      ],
    });
    expect(page).toMatch(/Awaiting (desk )?adoption/i);
    expect(page).toMatch(/Awaiting approval/i);
    expect(page).toMatch(/Approved/i);
    expect(page).toMatch(/Rejected/i);
    expect(page).toMatch(/Expired/i);
  });
});
