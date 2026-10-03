import Link from 'next/link';
import { notFound } from 'next/navigation';
import { Constants } from '@gymloop/db';
import { MS_PER_DAY, PT_BOOKING_LIMITS, ptBookRequestSchema, ptBookingStatusLabel, ptCopy, toLocalDate, offsetInstantFromGymWallTime } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessNouns, loadBusinessOrganization } from '../../../lib/business-type';
import { loadPtBookings, loadTrainerChoices } from '../../../lib/training-console';
import { trainerDayView } from './trainer-day';
import { isUuid } from '../../../lib/keyset';
import { gymTimeLabel } from '../../../lib/time';
import { StatusWord } from '../../status-word';
import { ConsoleTrainingConnectionNotice } from './control-state';
import { Field, inputClass } from '../field';
import { consoleCaller, TrainingNavigation, ReadFailure } from './presentation';
import { BookingRowActions } from './booking-actions';

export default async function Page({ searchParams }: { searchParams: Promise<{ from?: string; to?: string; trainerStaffId?: string; status?: string; afterStartsAt?: string; afterId?: string; date?: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  const caller = consoleCaller(identity);
  const params = await searchParams;
  if (caller.viewer.role === 'trainer') return trainerDayView(supabase, caller, identity.tenantId, params.date);
  const status = Constants.public.Enums.booking_status.find(value => value === params.status);
  if ((params.from !== undefined && !ptBookRequestSchema.shape.startsAt.safeParse(params.from).success) || (params.to !== undefined && !ptBookRequestSchema.shape.startsAt.safeParse(params.to).success) || (params.from && params.to && (Date.parse(params.to) <= Date.parse(params.from) || Date.parse(params.to) - Date.parse(params.from) > PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY)) || (params.trainerStaffId && !isUuid(params.trainerStaffId)) || (params.status && !status) || ((params.afterStartsAt !== undefined) !== (params.afterId !== undefined)) || (params.afterId !== undefined && (!isUuid(params.afterId) || !ptBookRequestSchema.shape.startsAt.safeParse(params.afterStartsAt).success))) notFound();
  const [nouns, trainers, organization] = await Promise.all([loadBusinessNouns(supabase, identity.tenantId), loadTrainerChoices(supabase, caller), params.from ? Promise.resolve(null) : loadBusinessOrganization(supabase, identity.tenantId)]);
  const timezone = trainers.data?.find(trainer => trainer.staffId === (params.trainerStaffId || caller.viewer.staffId))?.timezone ?? organization?.data?.timezone;
  let from = params.from;
  let to = params.to;
  if (!from && timezone) {
    try {
      const day = toLocalDate(new Date(), timezone);
      const tomorrow = new Date(Date.parse(`${day}T00:00:00Z`) + MS_PER_DAY).toISOString().split('T')[0];
      from = offsetInstantFromGymWallTime(`${day}T00:00`, timezone) ?? undefined;
      to ??= offsetInstantFromGymWallTime(`${tomorrow}T00:00`, timezone) ?? undefined;
    } catch { /* A failed zone never supplies a guessed booking range. */ }
  }
  if (from && !to) to = new Date(Date.parse(from) + MS_PER_DAY).toISOString();
  if (!from || !to) return <main className="cl-page"><h1 className="cl-title">Bookings</h1><TrainingNavigation viewer={caller.viewer} /><ReadFailure href="/training" /></main>;
  if (Date.parse(to) <= Date.parse(from) || Date.parse(to) - Date.parse(from) > PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY) notFound();
  const bookings = await loadPtBookings(supabase, caller, { p_from: from, p_to: to, ...(params.trainerStaffId ? { p_trainer_staff_id: params.trainerStaffId } : {}), ...(status ? { p_status: status } : {}), ...(params.afterId && params.afterStartsAt ? { p_after_id: params.afterId, p_after_starts_at: params.afterStartsAt } : {}) });
  const last = bookings.data?.at(-1);
  const next = new URLSearchParams({ from, to, ...(params.trainerStaffId ? { trainerStaffId: params.trainerStaffId } : {}), ...(params.status ? { status: params.status } : {}), ...(last ? { afterId: last.session_id, afterStartsAt: last.starts_at } : {}) });
  return <main className="cl-page classes-workspace"><ConsoleTrainingConnectionNotice /><header><p className="cl-eyebrow">Training</p><h1 className="cl-title">Bookings</h1><TrainingNavigation viewer={caller.viewer} />{caller.viewer.readOnly ? <p>Read-only support preview.</p> : null}</header>
    <form className="class-editor"><Field label="From (ISO instant, inclusive)"><input className={inputClass} name="from" defaultValue={from} required /></Field><Field label="To (ISO instant, exclusive)"><input className={inputClass} name="to" defaultValue={to} required /></Field><Field label={nouns.trainer}><select className={inputClass} name="trainerStaffId" defaultValue={params.trainerStaffId ?? ''}><option value="">All trainers</option>{trainers.data?.map(trainer => <option key={trainer.staffId} value={trainer.staffId}>{trainer.displayName}</option>)}</select></Field><Field label="Status"><select className={inputClass} name="status" defaultValue={params.status ?? ''}><option value="">All statuses</option>{Constants.public.Enums.booking_status.map(value => <option key={value} value={value}>{ptBookingStatusLabel(value, false, nouns.place)}</option>)}</select></Field><button className="cl-btn">Show bookings</button></form>
    {trainers.error ? <ReadFailure href="/training" /> : null}{bookings.error || bookings.data === null ? <ReadFailure href={`/training?${new URLSearchParams({ from, to })}`} /> : bookings.data.length === 0 ? <p className="cl-empty">No {nouns.sessions} in this range.</p> : <ul className="class-ledger">{bookings.data.map(booking => <li className="class-entry" key={booking.session_id}><div><p className="cl-eyebrow">{gymTimeLabel(booking.starts_at, booking.timezone)}</p><h2 className="cl-section-title">{booking.member_name} · {booking.member_code}</h2><p>{booking.trainer_name}</p><StatusWord status={booking.status} label={ptBookingStatusLabel(booking.status, booking.consumed, nouns.place)} />{booking.status === 'booked' && Date.parse(booking.ends_at) < Date.now() ? <p>{ptCopy(nouns).waiting}</p> : null}{booking.status === 'no_show' ? <p>Uses 0 {nouns.sessions}.</p> : null}<p>{booking.sessions_used} of {booking.sessions_total} used · {booking.sessions_remaining} remaining</p></div><BookingRowActions booking={booking} viewer={caller.viewer} nouns={nouns} /></li>)}</ul>}{last ? <Link className="cl-btn" href={`/training?${next}`}>More bookings</Link> : null}</main>;
}
