import Link from 'next/link';
import { humanize, toLocalDate, isoDaySchema, formatDateTime } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessOrganization, loadBusinessNouns } from '../../../lib/business-type';
import { loadClassTimetable } from '../../../lib/classes';
import { ClassConnectionNotice } from '../../member/classes/class-actions';
import { StatusWord } from '../../status-word';
import '../../styles/classes.css';
export default async function ClassesPage({ searchParams }: { searchParams: Promise<{ day?: string; branch?: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  const params = await searchParams;
  const [gym, nouns, branches] = await Promise.all([loadBusinessOrganization(supabase, identity.tenantId), loadBusinessNouns(supabase, identity.tenantId), supabase.from('branches').select('id,name,timezone').order('name')]);
  const selected = branches.data?.find((row) => row.id === params.branch) ?? branches.data?.[0];
  let timezone = 'UTC'; for (const zone of [selected?.timezone, gym.data?.timezone]) { if (zone) { try { new Intl.DateTimeFormat('en', { timeZone: zone }); timezone = zone; break; } catch { /* SQL fallback. */ } } }
  const day = isoDaySchema.safeParse(params.day).success ? params.day! : toLocalDate(new Date(), timezone);
  const rows = await loadClassTimetable(supabase, { branchId: selected?.id ?? null, from: day, to: day });
  const admin = identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  return <main className="cl-page classes-workspace"><ClassConnectionNotice /><header><p className="cl-eyebrow">Front desk</p><h1 className="cl-title">{humanize(nouns.classes)}</h1><p>{day} · {timezone}</p>{admin ? <div className="cl-actions"><Link className="cl-btn" href="/classes/services">Services</Link><Link className="cl-btn" href="/classes/schedule">Schedule and settings</Link></div> : null}</header>
    <form className="class-editor"><label>Day<input className="cl-input" type="date" name="day" defaultValue={day} /></label><label>Branch<select className="cl-input" name="branch" defaultValue={selected?.id}>{branches.data?.map((row) => <option key={row.id} value={row.id}>{row.name}</option>)}</select></label><button className="cl-btn">Show timetable</button></form>
    {rows === null ? <div className="cl-alert" role="alert"><p>The timetable could not be loaded.</p><Link className="cl-btn" href="/classes">Try again</Link></div> : rows.length === 0 ? <p className="cl-empty">No {nouns.classes} scheduled today.</p> : <ul className="class-ledger">{rows.map((row) => <li key={row.sessionId} className="class-entry"><div><p className="cl-eyebrow">{formatDateTime(row.startsAt, row.timezone)}</p><h2 className="cl-section-title">{row.serviceName}</h2><p>{row.trainerName ?? `${humanize(nouns.trainer)} not assigned`} · {row.spotsLeft} spots left / {row.capacity}</p><StatusWord status={row.sessionStatus} label={row.sessionStatus === 'cancelled' ? 'Cancelled' : Date.parse(row.endsAt) < Date.now() ? 'Ended' : Date.parse(row.startsAt) <= Date.now() ? 'In progress' : 'Scheduled'} />{row.onHoliday ? <p>Holiday; existing commitments remain.</p> : null}{row.trainerOverlaps ? <p>{humanize(nouns.trainer)} has an overlapping session. Review the timetable.</p> : null}{row.trainerStaffId && !row.trainerIsActive ? <p>{humanize(nouns.trainer)} is inactive; bookings remain.</p> : null}</div><Link className="cl-btn" href={`/classes/${row.sessionId}`}>Open roster</Link></li>)}</ul>}
  </main>;
}
