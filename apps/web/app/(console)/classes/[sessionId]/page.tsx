import Link from 'next/link';
import { notFound } from 'next/navigation';
import { classIdentifierSchema, formatDateTime } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { loadClassTimetable, loadClassRoster } from '../../../../lib/classes';
import { loadMemberSearch } from '../../../../lib/members';
import { SessionEditor } from '../class-forms';
import { loadServices } from '../../../../lib/classes';
import { RosterActions } from './roster-actions';
import '../../../styles/classes.css';
export default async function ClassRosterPage({ params, searchParams }: { params: Promise<{ sessionId: string }>; searchParams: Promise<{ q?: string; cursor?: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  const { sessionId } = await params;
  if (!classIdentifierSchema.safeParse(sessionId).success) notFound();
  const source = await supabase.from('class_sessions').select('session_date,branch_id').eq('id', sessionId).maybeSingle();
  if (source.error) throw new Error('The session could not be loaded.');
  if (!source.data) notFound();
  const [sessions, roster, nouns, search] = await Promise.all([loadClassTimetable(supabase, { branchId: source.data.branch_id, from: source.data.session_date, to: source.data.session_date }), loadClassRoster(supabase, sessionId), loadBusinessNouns(supabase, identity.tenantId), loadMemberSearch(searchParams)]);
  if (sessions === null || roster === null) throw new Error('The roster could not be loaded.');
  const session = sessions.find((row) => row.sessionId === sessionId); if (!session) notFound();
  const admin = identity.kind === 'staff' && ['gym_owner', 'gym_manager'].includes(identity.role);
  const adminData = admin ? await Promise.all([loadServices(supabase), supabase.from('branches').select('id,name,timezone'), supabase.from('staff').select('id,full_name,branch_id').eq('is_active', true).in('role', ['gym_owner', 'gym_manager', 'trainer'])]) : null;
  return <main className="cl-page classes-workspace"><Link className="cl-back" href="/classes">Back to {nouns.classes}</Link><header><h1 className="cl-title">{session.serviceName}</h1><p>{formatDateTime(session.startsAt, session.timezone)} · {session.timezone}</p><p>{session.bookedCount} booked / {session.capacity} · {session.spotsLeft} spots left</p></header>{search.errorMessage ? <p className="cl-alert" role="alert">{search.errorMessage}</p> : null}<RosterActions session={session} bookings={roster} members={search.phone ? search.members : []} role={identity.kind === 'staff' ? identity.role : 'preview'} staffId={identity.kind === 'staff' ? identity.staffId : null} nouns={nouns} />{search.nextCursor ? <Link className="cl-btn" href={`?${new URLSearchParams({ q: search.phone, cursor: search.nextCursor })}`}>More search results</Link> : null}{adminData && adminData[0] && !adminData[1].error && !adminData[2].error ? <SessionEditor session={session} bookingsToCancel={roster.filter((row) => row.status === 'booked').length} services={adminData[0]} branches={adminData[1].data ?? []} trainers={adminData[2].data ?? []} nouns={nouns} /> : admin ? <p role="alert">Session editing details could not be loaded. Refresh to try again.</p> : null}</main>;
}
