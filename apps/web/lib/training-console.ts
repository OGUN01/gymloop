import type { SupabaseClient } from '@supabase/supabase-js';
import { Constants, type Database } from '@gymloop/db';
import { MS_PER_DAY, PT_BOOKING_LIMITS, PT_READ_PAGE_MAX, ptCancelRequestSchema, ptBookRequestSchema, trainerTimeOffRequestSchema, ptPolicyRequestSchema, ptRefusalMessage, offsetInstantFromGymWallTime, type GymloopIdentity, type PtReadSection } from '@gymloop/shared';
import { mediaDisplayUrl } from './media';

type CallerClient = SupabaseClient<Database>;
type ConsoleIdentity = Extract<GymloopIdentity, { kind: 'staff' | 'impersonation' }>;
export type ConsoleViewer = { role: Extract<GymloopIdentity, { kind: 'staff' }>['role'] | null; staffId: string | null; readOnly: boolean; scopeKey: string };
export type VerifiedConsoleViewer = { identity: ConsoleIdentity; viewer: ConsoleViewer };
export type TrainerChoice = { staffId: string; displayName: string; isActive: boolean; qualification: string | null; timezone: string; branchName: string | null };
export type StaffBooking = Omit<Database['public']['Functions']['read_pt_bookings']['Returns'][number], 'cancelled_at'> & { cancelled_at: string | null };
export type StaffPack = Database['public']['Functions']['read_pt_packs']['Returns'][number];
export type TrainerProfile = Pick<Database['public']['Tables']['trainer_profiles']['Row'], 'bio' | 'specialities' | 'photo_asset_id' | 'is_listed'>;
export type TimeOff = Pick<Database['public']['Tables']['trainer_time_off']['Row'], 'id' | 'starts_on' | 'ends_on' | 'reason' | 'removed_at'>;
export type PtPolicy = { cancelWindowHours: number; lateCancelConsumes: boolean; sessionMinutes: number };
export type ReadValue<T> = { data: T | null; error: string | null };
type BookingArgs = Database['public']['Functions']['read_pt_bookings']['Args'];
type PackArgs = Database['public']['Functions']['read_pt_packs']['Args'];
function failedRead(): { data: null; error: string } { return { data: null, error: ptRefusalMessage('pt_failed') }; }
function guardConsoleCaller(caller: VerifiedConsoleViewer, management = false, mutation = false): void {
  const { identity: i, viewer: v } = caller;
  if (!i.userId || !i.tenantId || !v.scopeKey) throw new Error('Unavailable');
  if (i.kind === 'impersonation') {
    if (mutation || !i.impersonationSessionId || v.role !== null || v.staffId !== null || !v.readOnly) throw new Error('Unavailable');
    return;
  }
  if (i.kind !== 'staff' || !i.staffId || v.role !== i.role || v.staffId !== i.staffId || v.readOnly || !['gym_owner', 'gym_manager', 'front_desk', 'trainer'].includes(i.role) || (management && i.role !== 'gym_owner' && i.role !== 'gym_manager')) throw new Error('Unavailable');
}
function guardTrainerTarget(caller: VerifiedConsoleViewer, id: string): void {
  guardConsoleCaller(caller);
  if (!ptCancelRequestSchema.shape.sessionId.safeParse(id).success || (caller.identity.kind === 'staff' && caller.identity.role === 'trainer' && caller.identity.staffId !== id)) throw new Error('Unavailable');
}
function clampPtPageLimit(value?: number | null): number {
  if (value != null && !Number.isInteger(value)) throw new Error('Unavailable');
  return Math.min(PT_READ_PAGE_MAX, Math.max(1, value ?? PT_READ_PAGE_MAX));
}
function guardPackArgs(caller: VerifiedConsoleViewer, args: PackArgs): PackArgs {
  guardConsoleCaller(caller);
  if (args.p_trainer_staff_id != null) guardTrainerTarget(caller, args.p_trainer_staff_id);
  if (args.p_after_id != null && !ptCancelRequestSchema.shape.sessionId.safeParse(args.p_after_id).success) throw new Error('Unavailable');
  if (args.p_state != null && !Constants.public.Enums.pt_pack_state.includes(args.p_state)) throw new Error('Unavailable');
  return { ...args, p_limit: clampPtPageLimit(args.p_limit), ...(caller.identity.kind === 'staff' && caller.identity.role === 'trainer' ? { p_trainer_staff_id: caller.identity.staffId } : {}) };
}
function guardBookingArgs(caller: VerifiedConsoleViewer, args: BookingArgs): BookingArgs {
  guardPackArgs(caller, args.p_trainer_staff_id ? { p_trainer_staff_id: args.p_trainer_staff_id } : {});
  if (!ptBookRequestSchema.shape.startsAt.safeParse(args.p_from).success || !ptBookRequestSchema.shape.startsAt.safeParse(args.p_to).success || Date.parse(args.p_to) <= Date.parse(args.p_from) || Date.parse(args.p_to) - Date.parse(args.p_from) > PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY) throw new Error('Unavailable');
  if ((args.p_after_id != null) !== (args.p_after_starts_at != null) || (args.p_after_id != null && (!ptCancelRequestSchema.shape.sessionId.safeParse(args.p_after_id).success || !ptBookRequestSchema.shape.startsAt.safeParse(args.p_after_starts_at).success))) throw new Error('Unavailable');
  if (args.p_status != null && !Constants.public.Enums.booking_status.includes(args.p_status)) throw new Error('Unavailable');
  return { ...args, p_limit: clampPtPageLimit(args.p_limit), ...(caller.identity.kind === 'staff' && caller.identity.role === 'trainer' ? { p_trainer_staff_id: caller.identity.staffId } : {}) };
}
export async function loadPtBookings(client: CallerClient, caller: VerifiedConsoleViewer, args: BookingArgs): Promise<PtReadSection<StaffBooking>> {
  try { const result = await client.rpc('read_pt_bookings', guardBookingArgs(caller, args)); return result.error || result.data === null ? failedRead() : { data: result.data, error: null }; } catch { return failedRead(); }
}
export async function loadPtPacks(client: CallerClient, caller: VerifiedConsoleViewer, args: PackArgs): Promise<PtReadSection<StaffPack>> {
  try { const result = await client.rpc('read_pt_packs', guardPackArgs(caller, args)); return result.error || result.data === null ? failedRead() : { data: result.data, error: null }; } catch { return failedRead(); }
}
export async function loadTrainerChoices(client: CallerClient, caller: VerifiedConsoleViewer): Promise<PtReadSection<TrainerChoice>> {
  try {
    guardConsoleCaller(caller);
    let query = client.from('staff').select('id,full_name,is_active,qualification,branch_id').eq('role', 'trainer');
    if (caller.identity.kind === 'staff' && caller.identity.role === 'trainer') query = query.eq('id', caller.identity.staffId);
    const staff = await query;
    if (staff.error || staff.data === null) return failedRead();
    const [branches, organization] = await Promise.all([client.from('branches').select('id,name,timezone'), client.from('organizations').select('timezone').eq('id', caller.identity.tenantId).maybeSingle()]);
    if (branches.error || branches.data === null || organization.error || !organization.data?.timezone) return failedRead();
    const organizationTimezone = organization.data.timezone;
    return { data: staff.data.map(row => { const branch = branches.data.find(b => b.id === row.branch_id); return { staffId: row.id, displayName: row.full_name, isActive: row.is_active, qualification: row.qualification, branchName: branch?.name ?? null, timezone: branch?.timezone ?? organizationTimezone }; }), error: null };
  } catch { return failedRead(); }
}
export async function loadTrainerDetail(client: CallerClient, caller: VerifiedConsoleViewer, staffId: string) {
  guardTrainerTarget(caller, staffId);
  const choices = await loadTrainerChoices(client, caller);
  const trainer = choices.data?.find(t => t.staffId === staffId);
  if (!trainer) return { trainer: failedRead(), profile: failedRead(), windows: failedRead(), timeOff: failedRead(), imageUrl: failedRead() };
  const [profile, windows, timeOff] = await Promise.all([
    Promise.resolve(client.from('trainer_profiles').select('bio,specialities,photo_asset_id,is_listed').eq('staff_id', staffId).maybeSingle()).then(r => r.error ? failedRead() : { data: r.data ? { bio: r.data.bio, specialities: r.data.specialities, photo_asset_id: r.data.photo_asset_id, is_listed: r.data.is_listed } satisfies TrainerProfile : null, error: null }).catch(failedRead),
    Promise.resolve(client.from('trainer_availability').select('weekday,start_minute,end_minute').eq('staff_id', staffId)).then(r => r.error || r.data === null ? failedRead() : { data: r.data.map(w => ({ weekday: w.weekday, startMinute: w.start_minute, endMinute: w.end_minute })), error: null }).catch(failedRead),
    Promise.resolve(client.from('trainer_time_off').select('id,starts_on,ends_on,reason,removed_at').eq('staff_id', staffId)).then(r => r.error || r.data === null ? failedRead() : { data: r.data.map(row => ({ id: row.id, starts_on: row.starts_on, ends_on: row.ends_on, reason: row.reason, removed_at: row.removed_at } satisfies TimeOff)), error: null }).catch(failedRead),
  ]);
  let imageUrl: ReadValue<string> = { data: null, error: null };
  if (profile.error) imageUrl = failedRead();
  else if (profile.data?.photo_asset_id) { try { imageUrl = { data: await mediaDisplayUrl(client, profile.data.photo_asset_id), error: null }; } catch { imageUrl = failedRead(); } }
  return { trainer: { data: trainer, error: null }, profile, windows, timeOff, imageUrl };
}
export async function loadPtPolicy(client: CallerClient, caller: VerifiedConsoleViewer): Promise<ReadValue<PtPolicy>> {
  try { guardConsoleCaller(caller, true); const r = await client.from('organization_settings').select('pt_cancel_window_hours,pt_late_cancel_consumes_session,pt_session_minutes').eq('tenant_id', caller.identity.tenantId).maybeSingle(); if (r.error || !r.data) return failedRead(); const parsed = ptPolicyRequestSchema.safeParse({ cancelWindowHours: r.data.pt_cancel_window_hours, lateCancelConsumes: r.data.pt_late_cancel_consumes_session, sessionMinutes: r.data.pt_session_minutes }); return parsed.success ? { data: parsed.data, error: null } : failedRead(); } catch { return failedRead(); }
}
async function readCompletePacks(client: CallerClient, caller: VerifiedConsoleViewer, staffId: string): Promise<StaffPack[]> {
  const rows: StaffPack[] = []; let after: string | undefined;
  for (;;) { const page = await loadPtPacks(client, caller, { p_trainer_staff_id: staffId, ...(after ? { p_after_id: after } : {}) }); if (!page.data) throw new Error('Unavailable'); if (!page.data.length) return rows; for (const row of page.data) { if (!ptCancelRequestSchema.shape.sessionId.safeParse(row.order_id).success || row.trainer_staff_id !== staffId || (after && row.order_id <= after)) throw new Error('Unavailable'); after = row.order_id; rows.push(row); } }
}
async function readActiveOrderIds(client: CallerClient, caller: VerifiedConsoleViewer, staffId: string): Promise<Set<string>> {
  const ids = new Set<string>(); let after: string | undefined;
  for (;;) { let query = client.from('addon_orders').select('id,status,trainer_staff_id').eq('tenant_id', caller.identity.tenantId).eq('trainer_staff_id', staffId).eq('status', 'active').order('id'); if (after) query = query.gt('id', after); const page = await query.limit(PT_READ_PAGE_MAX); if (page.error || page.data === null) throw new Error('Unavailable'); if (!page.data.length) return ids; for (const row of page.data) { if (!ptCancelRequestSchema.shape.sessionId.safeParse(row.id).success || row.status !== 'active' || row.trainer_staff_id !== staffId || (after && row.id <= after)) throw new Error('Unavailable'); after = row.id; ids.add(row.id); } }
}
export async function loadReassignmentCandidates(client: CallerClient, caller: VerifiedConsoleViewer, fromStaffId: string): Promise<ReadValue<{ packs: StaffPack[]; scheduledCount: number; overLimit: boolean }>> {
  try { guardConsoleCaller(caller, true, true); guardTrainerTarget(caller, fromStaffId); const rows = await readCompletePacks(client, caller, fromStaffId); const ids = await readActiveOrderIds(client, caller, fromStaffId); const packs = rows.filter(p => ids.has(p.order_id)); return { data: { packs, scheduledCount: packs.reduce((sum, p) => sum + p.sessions_scheduled, 0), overLimit: packs.length > PT_BOOKING_LIMITS.reassignBatchMax }, error: null }; } catch { return failedRead(); }
}
async function readCompleteBookings(client: CallerClient, caller: VerifiedConsoleViewer, args: BookingArgs): Promise<StaffBooking[]> {
  const rows: StaffBooking[] = []; let cursor: StaffBooking | undefined;
  for (;;) { const page = await loadPtBookings(client, caller, { ...args, ...(cursor ? { p_after_starts_at: cursor.starts_at, p_after_id: cursor.session_id } : {}) }); if (!page.data) throw new Error('Unavailable'); if (!page.data.length) return rows; for (const row of page.data) { if (!ptCancelRequestSchema.shape.sessionId.safeParse(row.session_id).success || !ptBookRequestSchema.shape.startsAt.safeParse(row.starts_at).success || (cursor && (Date.parse(row.starts_at) < Date.parse(cursor.starts_at) || (Date.parse(row.starts_at) === Date.parse(cursor.starts_at) && row.session_id <= cursor.session_id)))) throw new Error('Unavailable'); cursor = row; rows.push(row); } }
}
export async function loadTimeOffBookings(client: CallerClient, caller: VerifiedConsoleViewer, staffId: string, startsOn: string, endsOn: string, timezone: string): Promise<PtReadSection<StaffBooking>> {
  try { guardTrainerTarget(caller, staffId); if (!trainerTimeOffRequestSchema.safeParse({ staffId, startsOn, endsOn }).success) return failedRead(); const nextDay = new Date(Date.parse(`${endsOn}T00:00:00Z`) + MS_PER_DAY).toISOString().split('T')[0]; const from = offsetInstantFromGymWallTime(`${startsOn}T00:00`, timezone); const to = offsetInstantFromGymWallTime(`${nextDay}T00:00`, timezone); if (!from || !to) return failedRead(); const rows: StaffBooking[] = []; let start = Date.parse(from); const end = Date.parse(to); while (start < end) { const stop = Math.min(end, start + PT_BOOKING_LIMITS.bookingRangeDaysMax * MS_PER_DAY); rows.push(...await readCompleteBookings(client, caller, { p_from: new Date(start).toISOString(), p_to: new Date(stop).toISOString(), p_trainer_staff_id: staffId, p_status: 'booked' })); start = stop; } return { data: rows, error: null }; } catch { return failedRead(); }
}
