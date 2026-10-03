import React from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { businessNouns, type MemberClassSession } from '@gymloop/shared';
import { MemberClassesView } from '../../app/member/classes/member-classes-view';

vi.mock('next/navigation', () => ({ useRouter: () => ({ refresh: vi.fn(), push: vi.fn() }) }));

const today = '2026-10-03';
const session: MemberClassSession = {
  sessionId: '74000000-0000-4000-8000-000000000001',
  serviceId: '74000000-0000-4000-8000-000000000002',
  branchId: '74000000-0000-4000-8000-000000000003',
  serviceName: 'Evening mobility', serviceDescription: 'Move comfortably',
  branchName: 'East studio', timezone: 'Asia/Kolkata', sessionDate: today,
  startsAt: '2026-10-03T18:00:00+05:30', endsAt: '2026-10-03T19:00:00+05:30',
  trainerName: 'Coach Kavya', capacity: 13, bookedCount: 9, spotsLeft: 4,
  sessionStatus: 'scheduled', myBookingId: null, myBookingStatus: null,
  availability: 'open', canCancel: false, cancelBy: null,
};
const nouns = businessNouns('gym');
function markup(sessions: MemberClassSession[] | null, cancelWindowHours?: number) {
  return renderToStaticMarkup(<MemberClassesView sessions={sessions} today={today} nouns={nouns} {...(cancelWindowHours === undefined ? {} : { cancelWindowHours })} />);
}
function text(html: string) { return html.replace(/<[^>]*>/g, ' ').replace(/\s+/g, ' ').replace(/&#x27;|&#39;/g, "'"); }

beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date('2026-10-03T10:00:00+05:30')); });
afterEach(() => { vi.useRealTimers(); });

describe('CLS-031/034/035 rendered web member facts', () => {
  it('opens on supplied local today and shows the actual class facts and counts', () => {
    const html = markup([session, { ...session, sessionId: '74000000-0000-4000-8000-000000000004', sessionDate: '2026-10-04', serviceName: 'Tomorrow private sentinel' }]);
    const visible = text(html);
    expect(visible, 'today class is visible').toContain('Evening mobility');
    expect(visible, 'trainer is visible').toContain('Coach Kavya');
    expect(visible, 'location is visible').toContain('East studio');
    expect(visible, 'capacity derives from facts').toContain('4 spots left');
    expect(visible, 'selection starts today').not.toContain('Tomorrow private sentinel');
    expect(visible, 'branch-local start time').toMatch(/18:00|6:00\s*[pP][mM]/);
  });
  it('does not render surplus member identifiers or silently invent a missing deadline', () => {
    const extra = Object.assign({}, session, { otherMemberName: 'Privacy sentinel person', memberPhone: 'Privacy sentinel phone', memberId: 'Privacy sentinel identifier' });
    const visible = text(markup([extra], 2));
    expect(visible, 'member name excluded').not.toContain('Privacy sentinel person');
    expect(visible, 'member phone excluded').not.toContain('Privacy sentinel phone');
    expect(visible, 'member identifier excluded').not.toContain('Privacy sentinel identifier');
    expect(visible, 'missing deadline cannot use two-hour client default').not.toMatch(/16:00|4:00\s*[pP][mM]/);
  });
  it('shows Full and the closed-window explanation from authoritative read facts', () => {
    const visible = text(markup([{ ...session, availability: 'full', spotsLeft: 0 }, { ...session, sessionId: '74000000-0000-4000-8000-000000000005', serviceName: 'Booked stretch', myBookingId: '74000000-0000-4000-8000-000000000006', myBookingStatus: 'booked', availability: 'booked', canCancel: false, cancelBy: '2026-10-03T16:00:00+05:30' }]));
    expect(visible, 'full state explicit').toContain('Full');
    expect(visible, 'booked ledger exists').toContain('Your bookings');
    expect(visible, 'window closure explains next action').toContain("It's too close to the start time to cancel online. Speak to the front desk if you can't make it.");
  });
  it('distinguishes empty successful reads from failed reads with a real retry', () => {
    expect(text(markup([])), 'empty horizon copy').toContain('No classes are scheduled yet. Ask the front desk when the timetable goes up.');
    expect(text(markup(null)), 'failure offers retry').toMatch(/Retry|Try again/);
    expect(text(markup(null)), 'failure is not empty success').not.toContain('No classes are scheduled yet.');
  });
  it.each([{ status: 'attended', word: 'Attended' }, { status: 'no_show', word: 'Missed' }] as const)('uses own past booking status $status', ({ status, word }) => {
    const visible = text(markup([{ ...session, startsAt: '2026-10-03T00:01:00+05:30', endsAt: '2026-10-03T00:31:00+05:30', myBookingStatus: status, myBookingId: '74000000-0000-4000-8000-000000000006', availability: 'closed' }]));
    expect(visible, 'own authoritative booking status').toContain(word);
  });
});
