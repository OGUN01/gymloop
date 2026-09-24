import { ChevronDown } from 'lucide-react';
import { groupByMonth, UI_TOKENS } from '@gymloop/shared';
import { loadMemberPortal } from '../../../lib/member-portal';
import { MemberWeekRhythm, memberShortDate } from '../member-ui';

export default async function MemberActivityPage() {
  const portal = await loadMemberPortal();
  if (portal.errorMessage) return <main className="member-route member-portal"><h1 className="member-title">Activity</h1><p className="cl-alert" role="alert">{portal.errorMessage}</p></main>;
  const timeZone = portal.gym.timezone;
  const time = new Intl.DateTimeFormat('en-IN', { hour: 'numeric', minute: '2-digit', timeZone });
  const months = groupByMonth(portal.visits, (visit) => visit.checked_in_at, timeZone);
  const { current, unit, rule } = portal.streak;
  const remaining = Math.max(portal.weeklyGoal - portal.weekVisits, 0);
  // The rule as memberStreak counts it: whole weeks that reach the goal, or visited days in a row.
  // Rest days, gym holidays and approved pauses never break either (STK-002).
  const streakNote = rule === 'weekly_goal'
    ? current === 0
      ? `Reach ${portal.weeklyGoal} ${portal.weeklyGoal === 1 ? 'visit' : 'visits'} in a week to start a streak.`
      : remaining === 0 ? 'This week counts. Keep the run going next week.' : `${remaining} more ${remaining === 1 ? 'visit' : 'visits'} this week keeps it going.`
    : `${current === 0 ? 'Visit on consecutive days to build a streak.' : 'Each consecutive day you visit adds a day.'} Rest days, holidays and approved pauses never break it.`;
  const renderMonth = (month: (typeof months)[number]) => <section key={month.key} className="member-activity-month" aria-labelledby={`month-${month.key}`}>
    <h3 id={`month-${month.key}`} className="cl-eyebrow member-eyebrow">{month.label}</h3>
    <ul className="cl-rows">{month.items.map((visit) => {
      const at = new Date(visit.checked_in_at);
      return <li key={visit.id}>
        <span><strong className="cl-row-title member-visit-time">{at.toLocaleDateString('en-GB', { weekday: 'short', timeZone })}, {memberShortDate(at.toLocaleDateString('en-CA', { timeZone }))} <span className="member-visit-sep">·</span> {time.formatToParts(at).map((part) => part.type === 'dayPeriod' ? <span key={part.type} className="member-visit-meridiem">{part.value}</span> : part.value)}</strong><small className="cl-row-meta">{visit.source === 'qr' ? 'Gym QR' : 'Desk assisted'}</small></span>
        <span className="cl-status" data-tone="ok">Confirmed</span>
      </li>;
    })}</ul>
  </section>;
  const [latest, ...older] = months;
  return <main className="member-route member-portal member-activity">
    <header><p className="cl-eyebrow">Your progress</p><h1 className="member-title">Activity</h1></header>
    <section className="member-week member-week--activity" aria-label="This week">
      <p className="member-activity-figure"><span className="cl-display member-activity-count">{portal.weekVisits}</span> <span className="cl-display">{portal.weekVisits === 1 ? 'visit' : 'visits'} this week</span></p>
      <MemberWeekRhythm visits={portal.visits} timezone={timeZone} weekStart={portal.weekStart} />
    </section>
    <section className="member-streak" aria-label="Streak">
      {current > 0
        ? <p className="cl-display member-streak-line">Streak: {current} {current === 1 ? unit : `${unit}s`}</p>
        : <p className="cl-display member-streak-line member-streak-line--empty">No streak yet</p>}
      <p className="member-streak-note">{streakNote}</p>
    </section>
    <section aria-labelledby="visits-heading">
      <h2 id="visits-heading" className="sr-only">Visits</h2>
      {latest === undefined
        ? <div className="cl-empty"><strong>No confirmed visits yet</strong><p>Your visits appear here once the gym confirms a check-in.</p></div>
        : <>
          {renderMonth(latest)}
          {older.length > 0 ? <details className="member-activity-older">
            <summary>Show older visits<ChevronDown aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></summary>
            {older.map(renderMonth)}
          </details> : null}
        </>}
    </section>
  </main>;
}
