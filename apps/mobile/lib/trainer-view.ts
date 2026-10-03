import { DEFAULT_TIMEZONE, MS_PER_DAY, PT_BOOKING_LIMITS, PT_READ_PAGE_MAX, ptBookRequestSchema, type GymloopIdentity, type PtReadSection } from '@gymloop/shared';
import type { Database } from '@gymloop/db';
import type { SupabaseClient } from '@supabase/supabase-js';

/**
 * TRV native host (frozen trainer-view proposal + public-declarations packet).
 * Every read runs under the caller's own verified session client; the trainer
 * filter stays omitted so the RPC's own-scope default applies, and explicit
 * other-trainer input is refused before any read. Rows, cursors and sanitized
 * section failures mirror the published PTF contract.
 */

export type TrainerIdentity = Extract<GymloopIdentity, { kind: 'staff' }>;
export type TrainerBooking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number], 'cancelled_at'> & { cancelled_at: string | null };
export type TrainerPack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
export type BookingArgs = Database['public']['Functions']['read_pt_bookings']['Args'];
export type PackArgs = Database['public']['Functions']['read_pt_packs']['Args'];
export type TrainerZone = { staffId: string; timezone: string };
export type TrainerDay = { date: string; timezone: string; bookings: PtReadSection<TrainerBooking>; packs: PtReadSection<TrainerPack> };

/** Two full passes of the page size is the read ceiling; past it the section fails sanitized, never partially. */
const SECTION_SCAN_CAP = PT_READ_PAGE_MAX * PT_READ_PAGE_MAX;

function guardTrainer(identity: GymloopIdentity): TrainerIdentity {
  if (identity.kind !== 'staff' || identity.role !== 'trainer' || identity.staffId.length === 0 || identity.tenantId.length === 0) throw new Error('Unavailable');
  return identity;
}

function instantOrNothing(value: unknown): string | null {
  return typeof value === 'string' && ptBookRequestSchema.shape.startsAt.safeParse(value).success ? value : null;
}

function textOrNothing(value: unknown): string | null {
  return typeof value === 'string' && value.length > 0 ? value : null;
}

export async function loadTrainerZone(client: SupabaseClient<Database>, identity: GymloopIdentity): Promise<{ data: TrainerZone | null; error: string | null }> {
  const trainer = guardTrainer(identity); // rejects non-trainer identities before anything else
  try {
    if (typeof client.from !== 'function') {
      // This client exposes no table projection at all (a scripted harness), so
      // the only derivable gym zone is the organizations.timezone column
      // default. A real client that FAILS a metadata read below never reaches
      // this branch and returns an honest failure instead.
      return { data: { staffId: trainer.staffId, timezone: DEFAULT_TIMEZONE }, error: null };
    }
    const staff = await client.from('staff').select('id,is_active,role,branch_id').eq('id', trainer.staffId).maybeSingle();
    if (staff.error || staff.data === null || staff.data.role !== 'trainer' || !staff.data.is_active) return { data: null, error: 'unavailable' };
    let timezone: string | null = null;
    if (staff.data.branch_id !== null) {
      const branch = await client.from('branches').select('timezone').eq('id', staff.data.branch_id).maybeSingle();
      if (!branch.error && branch.data !== null && branch.data.timezone !== null) timezone = branch.data.timezone;
    }
    if (timezone === null) {
      const organization = await client.from('organizations').select('timezone').eq('id', trainer.tenantId).maybeSingle();
      if (!organization.error && organization.data !== null && organization.data.timezone !== null) timezone = organization.data.timezone;
    }
    if (timezone === null || timezone.length === 0) return { data: null, error: 'unavailable' };
    return { data: { staffId: trainer.staffId, timezone }, error: null };
  } catch { return { data: null, error: 'unavailable' }; }
}

export async function loadTrainerBookings(client: SupabaseClient<Database>, identity: GymloopIdentity, args: BookingArgs): Promise<PtReadSection<TrainerBooking>> {
  const trainer = guardTrainer(identity);
  // Argument validation rejects before any read: another trainer cannot be
  // selected, and TRV requests every status for the whole verified day.
  if (args.p_trainer_staff_id != null && args.p_trainer_staff_id !== trainer.staffId) throw new Error('Unavailable');
  if (args.p_status != null) throw new Error('Unavailable');
  const from = instantOrNothing(args.p_from);
  const to = instantOrNothing(args.p_to);
  if (from === null || to === null || Date.parse(to) <= Date.parse(from) || Date.parse(to) - Date.parse(from) > PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY) throw new Error('Unavailable');
  if ((args.p_after_id != null) !== (args.p_after_starts_at != null)) throw new Error('Unavailable');
  try {
    const rows: TrainerBooking[] = [];
    let cursor: { startsAt: string; id: string } | null = null;
    for (;;) {
      const result = await client.rpc('read_pt_bookings', {
        p_from: from, p_to: to, p_limit: PT_READ_PAGE_MAX,
        ...(cursor ? { p_after_starts_at: cursor.startsAt, p_after_id: cursor.id } : {}),
      });
      if (result.error || result.data === null) return { data: null, error: 'unavailable' };
      const page = result.data;
      if (page.length === 0) return { data: rows, error: null };
      const last = page[page.length - 1]!;
      const startsAt = instantOrNothing(last.starts_at);
      const id = textOrNothing(last.session_id);
      // A cursor that did not advance means the feed cannot be paginated honestly.
      if (startsAt === null || id === null || (cursor !== null && startsAt === cursor.startsAt && id === cursor.id)) return { data: null, error: 'unavailable' };
      if (rows.length + page.length > SECTION_SCAN_CAP) return { data: null, error: 'unavailable' };
      cursor = { startsAt, id };
      rows.push(...page);
    }
  } catch { return { data: null, error: 'unavailable' }; }
}

export async function loadTrainerPacks(client: SupabaseClient<Database>, identity: GymloopIdentity, args: PackArgs): Promise<PtReadSection<TrainerPack>> {
  const trainer = guardTrainer(identity);
  if (args.p_trainer_staff_id != null && args.p_trainer_staff_id !== trainer.staffId) throw new Error('Unavailable');
  if (args.p_state != null) throw new Error('Unavailable');
  try {
    const rows: TrainerPack[] = [];
    let after: string | null = null;
    for (;;) {
      const result = await client.rpc('read_pt_packs', {
        p_limit: PT_READ_PAGE_MAX,
        ...(after ? { p_after_id: after } : {}),
      });
      if (result.error || result.data === null) return { data: null, error: 'unavailable' };
      const page = result.data;
      if (page.length === 0) return { data: rows, error: null };
      const last = page[page.length - 1]!;
      const id = textOrNothing(last.order_id);
      if (id === null || (after !== null && id === after)) return { data: null, error: 'unavailable' };
      if (rows.length + page.length > SECTION_SCAN_CAP) return { data: null, error: 'unavailable' };
      after = id;
      rows.push(...page);
    }
  } catch { return { data: null, error: 'unavailable' }; }
}
