'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { CLASS_LIMITS, DAYS_PER_WEEK, classDayStrip, classAvailabilityLabel, formatDateTime, formatDay, humanize, type MemberClassSession, type BusinessNouns } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { ClassActions, ClassConnectionNotice } from './class-actions';

export function MemberClassesView({ sessions, today, nouns, cancelWindowHours = null, scopeKey, refreshSessions }: { sessions: MemberClassSession[] | null; today: string; nouns: BusinessNouns; cancelWindowHours?: number | null; scopeKey?: string; refreshSessions?: () => Promise<MemberClassSession[] | null> }) {
  const [day, setDay] = useState(today);
  const [week, setWeek] = useState(0);
  const router = useRouter();
  const days = classDayStrip(today, CLASS_LIMITS.horizonDays);
  const shown = sessions?.filter((row) => row.sessionDate === day) ?? [];
  const bookings = sessions?.filter((row) => row.myBookingStatus === 'booked' && Date.parse(row.startsAt) > Date.now()) ?? [];
  function entry(row: MemberClassSession) {
    const status = classAvailabilityLabel(row.availability, row.spotsLeft);
    const ended = Date.parse(row.endsAt) <= Date.now();
    const pastWord = row.myBookingStatus === 'attended' ? 'Attended' : row.myBookingStatus === 'no_show' ? 'Missed' : 'Ended';
    return <li key={row.sessionId} className="class-entry"><div><p className="cl-eyebrow">{formatDateTime(row.startsAt, row.timezone)} – {formatDateTime(row.endsAt, row.timezone)}</p><h2 className="cl-section-title">{row.serviceName}</h2><p>{row.trainerName ? `${humanize(nouns.trainer)}: ${row.trainerName}` : `${humanize(nouns.trainer)} not assigned`} · {row.branchName}</p><p className="cl-muted">{row.timezone}</p>{row.serviceDescription ? <p>{row.serviceDescription}</p> : null}<StatusWord status={ended ? row.myBookingStatus ?? 'closed' : status.tone === 'ok' ? 'active' : status.tone === 'warn' ? 'pending' : status.tone === 'risk' ? 'cancelled' : 'closed'} label={ended ? pastWord : status.word} />{!ended && row.myBookingStatus && row.myBookingStatus !== 'booked' ? <StatusWord status={row.myBookingStatus} label={row.myBookingStatus === 'no_show' ? 'Missed' : humanize(row.myBookingStatus)} /> : null}</div><ClassActions session={row} cancelWindowHours={cancelWindowHours} {...(scopeKey === undefined ? {} : { scopeKey })} {...(refreshSessions === undefined ? {} : { refreshSession: async () => { const current = (await refreshSessions())?.filter((item) => item.sessionId === row.sessionId); return current?.length === 1 ? current[0]! : null; } })} /></li>;
  }
  return <section className="classes-workspace"><ClassConnectionNotice /><div className="class-days" aria-label="Choose a day">{days.slice(week * DAYS_PER_WEEK, (week + 1) * DAYS_PER_WEEK).map((date) => <button key={date} type="button" className="cl-btn cl-btn--quiet" aria-pressed={date === day} onClick={() => setDay(date)}>{date === today ? 'Today' : formatDay(date)}</button>)}</div><div className="cl-actions"><button type="button" className="cl-btn cl-btn--quiet" disabled={week === 0} onClick={() => { setWeek(week - 1); setDay(days[(week - 1) * DAYS_PER_WEEK]!); }}>Previous week</button><button type="button" className="cl-btn cl-btn--quiet" disabled={(week + 1) * DAYS_PER_WEEK >= days.length} onClick={() => { setWeek(week + 1); setDay(days[(week + 1) * DAYS_PER_WEEK]!); }}>Next week</button></div>
    {sessions === null ? <div className="cl-alert" role="alert"><p>Your {nouns.classes} could not be loaded.</p><button className="cl-btn" onClick={() => router.refresh()}>Try again</button></div> : sessions.length === 0 ? <div className="cl-empty"><p>No {nouns.classes} are scheduled yet. Ask the front desk when the timetable goes up.</p><button className="cl-btn" onClick={() => router.refresh()}>Refresh timetable</button></div> : <><h2 className="cl-section-title">{day === today ? `Today's ${nouns.classes}` : `${humanize(nouns.classes)} on ${formatDay(day)}`}</h2>{shown.length === 0 ? <p className="cl-empty">Nothing is scheduled on this day.</p> : <ul className="class-ledger">{shown.map(entry)}</ul>}<h2 className="cl-section-title">Your bookings</h2>{bookings.length ? <ul className="class-ledger">{bookings.map(entry)}</ul> : <p className="cl-empty">You have no upcoming bookings.</p>}</>}
  </section>;
}
