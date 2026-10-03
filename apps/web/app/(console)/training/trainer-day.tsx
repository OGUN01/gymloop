import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import {
  MS_PER_DAY, PT_BOOKING_LIMITS, PT_READ_PAGE_MAX, isoDaySchema, offsetInstantFromGymWallTime,
  ptBookRequestSchema, ptBookingStatusLabel, ptPackStateLabel, toLocalDate,
} from '@gymloop/shared';
import { loadPtBookings, loadPtPacks, loadTrainerChoices, type StaffBooking, type StaffPack, type TrainerChoice, type VerifiedConsoleViewer } from '../../../lib/training-console';
import { loadBusinessNouns } from '../../../lib/business-type';
import type { BusinessNouns } from '@gymloop/shared';
import { gymTimeLabel } from '../../../lib/time';
import { StatusWord } from '../../status-word';
import { TrainingNavigation } from './presentation';
import { TrainerOfflineNotice } from './trainer-offline-notice';

/**
 * TRV — the trainer's own-client day (frozen trainer-view proposal). Reads
 * compose the published PTF single-page adapters `loadPtBookings`/`loadPtPacks`
 * under the original trainer's client (the adapters inject the trainer's own
 * staffId per PTF-022; TRV passes no selectable trainer/status/state filter)
 * and exhaust every keyset page until a successful empty page before the day
 * renders. The trainer branch of the Training host renders this view; other
 * staff keep the existing PTF page untouched.
 */

type Section<T> = { rows: T[]; failed: boolean };

/** Two full passes of the page size is the read ceiling; past it the section is a sanitized failure, never a partial day. */
const SECTION_SCAN_CAP = PT_READ_PAGE_MAX * PT_READ_PAGE_MAX;

function instantOrNothing(value: unknown): string | null {
  return typeof value === 'string' && ptBookRequestSchema.shape.startsAt.safeParse(value).success ? value : null;
}

function textOrNothing(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

async function readCompleteBookings(client: SupabaseClient<Database>, caller: VerifiedConsoleViewer, from: string, to: string): Promise<Section<StaffBooking>> {
  const rows: StaffBooking[] = [];
  let cursor: StaffBooking | undefined;
  for (;;) {
    const page = await loadPtBookings(client, caller, {
      p_from: from, p_to: to,
      ...(cursor ? { p_after_starts_at: cursor.starts_at, p_after_id: cursor.session_id } : {}),
    });
    if (page.error || page.data === null) return { rows: [], failed: true };
    if (page.data.length === 0) return { rows, failed: false };
    const last = page.data[page.data.length - 1]!;
    const startsAt = instantOrNothing(last.starts_at);
    const id = textOrNothing(last.session_id);
    // A cursor that did not advance means the feed cannot be paginated honestly.
    if (!startsAt || !id || (cursor !== undefined && startsAt === cursor.starts_at && id === cursor.session_id)) return { rows: [], failed: true };
    if (rows.length + page.data.length > SECTION_SCAN_CAP) return { rows: [], failed: true };
    cursor = last;
    rows.push(...page.data);
  }
}

async function readCompletePacks(client: SupabaseClient<Database>, caller: VerifiedConsoleViewer): Promise<Section<StaffPack>> {
  const rows: StaffPack[] = [];
  let after: string | undefined;
  for (;;) {
    const page = await loadPtPacks(client, caller, { ...(after ? { p_after_id: after } : {}) });
    if (page.error || page.data === null) return { rows: [], failed: true };
    if (page.data.length === 0) return { rows, failed: false };
    const last = page.data[page.data.length - 1]!;
    const id = textOrNothing(last.order_id);
    if (!id || (after !== undefined && id === after)) return { rows: [], failed: true };
    if (rows.length + page.data.length > SECTION_SCAN_CAP) return { rows: [], failed: true };
    after = id;
    rows.push(...page.data);
  }
}

function dayShift(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * MS_PER_DAY).toISOString().split('T')[0]!;
}

function DayControls({ date }: { date: string }) {
  return <nav className="cl-actions" aria-label="Day selection">
    <Link className="cl-btn" href={`/training?date=${dayShift(date, -1)}`}>Previous day</Link>
    <Link className="cl-btn" href="/training">Today</Link>
    <Link className="cl-btn" href={`/training?date=${dayShift(date, 1)}`}>Next day</Link>
  </nav>;
}

function FailureDay() {
  return <div className="cl-alert" role="alert"><p>Couldn&apos;t load your sessions.</p><Link className="cl-btn" href="/training">Refresh</Link></div>;
}

const PACK_UNAVAILABLE_COPY = "Pack details aren't available. Refresh to try again.";

function PackFacts({ pack }: { pack: StaffPack }) {
  const expired = pack.state === 'expired';
  return <div>
    <p>{pack.programme_name}</p>
    <p>{`${pack.sessions_used} of ${pack.sessions_total} used · ${pack.sessions_scheduled} scheduled · ${pack.sessions_remaining} ${expired ? 'unused · expired' : 'left to book'}`}</p>
    <p>Valid {pack.starts_on} – {pack.expires_on}</p>
    <StatusWord status={pack.state} label={ptPackStateLabel(pack.state)} />
  </div>;
}

export async function trainerDayView(supabase: SupabaseClient<Database>, caller: VerifiedConsoleViewer, tenantId: string, dateParam: string | undefined) {
  const nouns: BusinessNouns = await loadBusinessNouns(supabase, tenantId);
  // Zone comes only from the published own-trainer choices projection; a
  // missing or failed zone is an unavailable outcome, never a device fallback.
  const choices: unknown = await loadTrainerChoices(supabase, caller);
  const choiceRows: TrainerChoice[] = (Array.isArray(choices) ? choices : (choices as { data?: TrainerChoice[] | null }).data) ?? [];
  const timezone = textOrNothing(choiceRows.find(choice => choice?.staffId === caller.viewer.staffId)?.timezone);
  if (dateParam !== undefined && !isoDaySchema.safeParse(dateParam).success) notFound();
  const date = dateParam !== undefined
    ? dateParam
    : timezone !== null ? String(toLocalDate(new Date(), timezone)) : null;
  const header = <header><p className="cl-eyebrow">Training</p><h1 className="cl-title">My clients today</h1><TrainingNavigation viewer={caller.viewer} />{caller.viewer.readOnly ? <p>Read-only support preview.</p> : null}</header>;
  const offlineBanner = <TrainerOfflineNotice refreshHref={date !== null ? `/training?date=${date}` : '/training'} />;
  if (timezone === null || date === null) {
    return <main className="cl-page classes-workspace">{header}{offlineBanner}{date !== null ? <p><time dateTime={date}>{date}</time></p> : null}<FailureDay /></main>;
  }
  const from = offsetInstantFromGymWallTime(`${date}T00:00`, timezone);
  const to = offsetInstantFromGymWallTime(`${dayShift(date, 1)}T00:00`, timezone);
  if (from === null || to === null || Date.parse(to) <= Date.parse(from) || Date.parse(to) - Date.parse(from) > PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY) {
    return <main className="cl-page classes-workspace">{header}{offlineBanner}<p><time dateTime={date}>{date}</time> · {timezone}</p><FailureDay /></main>;
  }
  const [bookings, packs] = await Promise.all([readCompleteBookings(supabase, caller, from, to), readCompletePacks(supabase, caller)]);
  const packUnavailableIds = new Set<string>();
  const packsByOrder = new Map<string, StaffPack>();
  if (!packs.failed) {
    for (const pack of packs.rows) {
      if (packsByOrder.has(pack.order_id)) packUnavailableIds.add(pack.order_id);
      else packsByOrder.set(pack.order_id, pack);
    }
  }
  const fromMs = Date.parse(from);
  const toMs = Date.parse(to);
  const dayRows = bookings.failed ? [] : bookings.rows.filter(booking => {
    const startsMs = Date.parse(booking.starts_at);
    return Number.isFinite(startsMs) && startsMs >= fromMs && startsMs < toMs;
  });
  dayRows.sort((one, two) => {
    const byStart = Date.parse(one.starts_at) - Date.parse(two.starts_at);
    if (byStart !== 0) return byStart;
    return one.session_id < two.session_id ? -1 : one.session_id > two.session_id ? 1 : 0;
  });
  return <main className="cl-page classes-workspace">{header}{offlineBanner}
    <p><time dateTime={date}>{date}</time> · {timezone}</p>
    <DayControls date={date} />
    {bookings.failed ? <FailureDay /> : dayRows.length === 0
      ? <p className="cl-empty">No clients scheduled for this date.</p>
      : <ul className="class-ledger">{dayRows.map(booking => {
        const pack = !packs.failed && !packUnavailableIds.has(booking.order_id) ? packsByOrder.get(booking.order_id) ?? null : null;
        return <li className="class-entry" key={booking.session_id}><div>
          <p className="cl-eyebrow">{gymTimeLabel(booking.starts_at, timezone)}</p>
          <h2 className="cl-section-title">{booking.member_name} · {booking.member_code}</h2>
          <StatusWord status={booking.status} label={ptBookingStatusLabel(booking.status, booking.consumed, nouns.place)} />
          {pack === null ? <p>{PACK_UNAVAILABLE_COPY}</p> : <PackFacts pack={pack} />}
        </div></li>;
      })}</ul>}
  </main>;
}
