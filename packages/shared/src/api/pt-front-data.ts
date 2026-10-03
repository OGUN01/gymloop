import type { Database } from '@gymloop/db';
import { INSTANT_FRACTIONAL_SECOND_DIGITS, MEMBER_PAGE_SIZE_DEFAULT, MINUTES_PER_HOUR, MS_PER_HOUR } from '../config/constants';
import { formatDateTime } from '../display/display';
import { ptApiError, ptPolicyRequestSchema } from './pt-front';

type Functions = Database['public']['Functions'];
type MemberRead = 'read_member_trainers' | 'read_member_programmes' | 'read_member_pt_packs' | 'read_member_pt_sessions' | 'read_member_pt_slots';
export type PtReadClient = {
  rpc<N extends MemberRead>(name: N, args?: Functions[N]['Args']): PromiseLike<{ data: Functions[N]['Returns'] | null; error: { code: string; details: string } | null }>;
};
export type PtHistoryCursor = { startsAt: string; sessionId: string };
export type PtMemberPolicy = { cancelWindowHours: number; lateCancelConsumes: boolean };
export type PtPolicyRead = { data: PtMemberPolicy | null; error: string | null };
export type PtPolicyReadClient = {
  rpc(name: 'read_member_pt_policy'): PromiseLike<{ data: unknown; error: unknown }>;
};
/** The current caller's policy is required; missing settings never imply defaults. */
export async function readMemberPtPolicy(client: PtPolicyReadClient): Promise<PtPolicyRead> {
  const failed: PtPolicyRead = { data: null, error: 'retryable' };
  try {
    const result = await client.rpc('read_member_pt_policy');
    if (result.error !== null || !Array.isArray(result.data)) return failed;
    if (result.data.length === 0) return { data: null, error: null };
    if (result.data.length !== 1) return failed;
    const row: unknown = result.data[0];
    if (row === null || typeof row !== 'object' || Array.isArray(row)
      || !Object.hasOwn(row, 'cancel_window_hours') || !Object.hasOwn(row, 'late_cancel_consumes_session')) return failed;
    const fields = row as Record<string, unknown>;
    const parsed = ptPolicyRequestSchema.pick({ cancelWindowHours: true, lateCancelConsumes: true }).safeParse({
      cancelWindowHours: fields.cancel_window_hours,
      lateCancelConsumes: fields.late_cancel_consumes_session,
    });
    return parsed.success ? { data: parsed.data, error: null } : failed;
  } catch { return failed; }
}
export type PtReadSection<T> = { data: T[] | null; error: string | null };
async function read<N extends MemberRead>(client: PtReadClient, name: N, args?: Functions[N]['Args']) {
  try { return await client.rpc(name, args); }
  catch { return { data: null, error: { code: '', details: '' } }; }
}
function section<R, T>(result: { data: R[] | null; error: { code: string; details: string } | null }, map: (row: R) => T): PtReadSection<T> {
  return result.error ? { data: null, error: ptApiError(result.error.code, result.error.details).code } : { data: (result.data ?? []).map(map), error: null };
}
const pack = (row: Functions['read_member_pt_packs']['Returns'][number]) => ({ orderId: row.order_id, programmeName: row.programme_name, trainerKey: row.trainer_key, trainerName: row.trainer_name, sessionsTotal: row.sessions_total, sessionsUsed: row.sessions_used, sessionsScheduled: row.sessions_scheduled, sessionsRemaining: row.sessions_remaining, startsOn: row.starts_on, expiresOn: row.expires_on, state: row.state, canBook: row.can_book, timezone: row.timezone });
const session = (row: Functions['read_member_pt_sessions']['Returns'][number]) => ({ sessionId: row.session_id, orderId: row.order_id, programmeName: row.programme_name, trainerKey: row.trainer_key, trainerName: row.trainer_name, startsAt: row.starts_at, endsAt: row.ends_at, timezone: row.timezone, status: row.status, consumed: row.consumed, cancelledAt: row.cancelled_at, cancelCutoff: row.cancel_cutoff, lateNow: row.late_now, consumesNow: row.consumes_now, canCancel: row.can_cancel });
const programme = (row: Functions['read_member_programmes']['Returns'][number]) => ({ programmeId: row.programme_id, trainerKey: row.trainer_key, trainerName: row.trainer_name, trainerQualification: row.trainer_qualification, name: row.name, description: row.description, pricePaise: row.price_paise, currency: row.currency, gstRateBp: row.gst_rate_bp, sessionCount: row.session_count, validityDays: row.validity_days, cancellationTerms: row.cancellation_terms });
export type PtPack = ReturnType<typeof pack>;
export type PtSession = Omit<ReturnType<typeof session>, 'cancelledAt' | 'cancelCutoff'> & { cancelledAt: string | null; cancelCutoff: string | null };
/** Recorded instants alone determine the confirmation; policy defaults never do. */
export function ptRecordedInterval(facts: Pick<PtSession, 'startsAt' | 'endsAt' | 'timezone'>): { startsAtLabel: string; endsAtLabel: string; durationLabel: string } | null {
  if ([facts.startsAt, facts.endsAt, facts.timezone].some(value => typeof value !== 'string' || !value.trim())) return null;
  const start = Date.parse(facts.startsAt);
  const end = Date.parse(facts.endsAt);
  if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) return null;
  const millisecondsPerMinute = MS_PER_HOUR / MINUTES_PER_HOUR;
  const millisecondsPerSecond = millisecondsPerMinute / MINUTES_PER_HOUR;
  const elapsed = end - start;
  if (!Number.isSafeInteger(elapsed)) return null;
  const minutes = Math.floor(elapsed / millisecondsPerMinute);
  const seconds = Math.floor(elapsed % millisecondsPerMinute / millisecondsPerSecond);
  const milliseconds = elapsed % millisecondsPerSecond;
  const durationLabel = [minutes ? `${minutes} minutes` : null, seconds ? `${seconds} seconds` : null, milliseconds ? `${milliseconds} milliseconds` : null].filter(Boolean).join(' ');
  try {
    const labels = [facts.startsAt, facts.endsAt].map(instant => {
      const date = new Date(instant);
      const label = formatDateTime(instant, facts.timezone);
      if (date.getUTCSeconds() === 0 && date.getUTCMilliseconds() === 0) return label;
      const clock = new Intl.DateTimeFormat('en-US', { hour: 'numeric', minute: '2-digit', second: '2-digit', fractionalSecondDigits: INSTANT_FRACTIONAL_SECOND_DIGITS, timeZone: facts.timezone }).format(date).toLowerCase();
      return `${label.split(',')[0]}, ${clock}`;
    });
    return { startsAtLabel: labels[0]!, endsAtLabel: labels[1]!, durationLabel };
  } catch { return null; }
}
export type PtProgramme = ReturnType<typeof programme>;
export type PtTrainer = { trainerKey: string; displayName: string; qualification: string | null; bio: string; specialities: string[]; imageUrl: string | null; branchName: string | null; isProfileListed: boolean };

/** Pure caller-bound orchestration: no singleton, private-table read or retained cache. */
export async function readMemberTraining(client: PtReadClient, signImage?: (assetId: string) => Promise<string | null>) {
  const [trainersRead, programmesRead, packsRead, upcomingRead, historyRead] = await Promise.all([
    read(client, 'read_member_trainers'), read(client, 'read_member_programmes'), read(client, 'read_member_pt_packs'),
    read(client, 'read_member_pt_sessions', { p_scope: 'upcoming', p_limit: MEMBER_PAGE_SIZE_DEFAULT }),
    read(client, 'read_member_pt_sessions', { p_scope: 'history', p_limit: MEMBER_PAGE_SIZE_DEFAULT }),
  ]);
  const trainerRows = trainersRead.error ? [] : trainersRead.data ?? [];
  const trainers = await Promise.all(trainerRows.map(async (row): Promise<PtTrainer> => {
    let imageUrl: string | null = null;
    if (row.is_profile_listed && row.image_asset_id && signImage) { try { imageUrl = await signImage(row.image_asset_id); } catch { imageUrl = null; } }
    return { trainerKey: row.trainer_key, displayName: row.display_name, qualification: row.qualification, bio: row.bio, specialities: row.specialities, imageUrl, branchName: row.branch_name, isProfileListed: row.is_profile_listed };
  }));
  return { trainers: { data: trainersRead.error ? null : trainers, error: trainersRead.error ? ptApiError(trainersRead.error.code, trainersRead.error.details).code : null }, programmes: section(programmesRead, programme), packs: section(packsRead, pack), upcoming: section(upcomingRead, (row): PtSession => session(row)), history: section(historyRead, (row): PtSession => session(row)) };
}
export type MemberTraining = Awaited<ReturnType<typeof readMemberTraining>>;
export async function readMemberPtHistory(client: PtReadClient, cursor?: PtHistoryCursor) {
  return section(await read(client, 'read_member_pt_sessions', { p_scope: 'history', p_limit: MEMBER_PAGE_SIZE_DEFAULT, ...(cursor ? { p_after_starts_at: cursor.startsAt, p_after_id: cursor.sessionId } : {}) }), (row): PtSession => session(row));
}
export async function readMemberPtSlots(client: PtReadClient, orderId: string, from: string, to: string) {
  return section(await read(client, 'read_member_pt_slots', { p_order_id: orderId, p_from: from, p_to: to }), (row) => ({ startsAt: row.starts_at, endsAt: row.ends_at, timezone: row.timezone }));
}
