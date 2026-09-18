import { checkInRequestSchema } from '@gymloop/shared';
import { apiFail, apiOk, PG_INSUFFICIENT_PRIVILEGE, PG_UNIQUE_VIOLATION, type ApiFailStatus } from '../../../lib/api';
import { readIdentity, readRequestIdentity } from '../../../lib/identity-session';
import { hashGateCode } from '../../../lib/gate-code';

const REFUSALS: Record<string, { status: ApiFailStatus; message: string }> = {
  GL010: { status: 'unprocessable', message: 'That gate code belongs to another gym.' }, GL011: { status: 'unprocessable', message: 'That gate code has expired. Show a new one.' }, GL012: { status: 'unprocessable', message: 'That gate code has been revoked.' }, GL013: { status: 'unprocessable', message: 'No active membership. Renew before checking in.' }, GL014: { status: 'conflict', message: 'Already checked in a moment ago.' }, GL017: { status: 'unprocessable', message: 'That offline check-in time is not valid for this gate session.' },
};
const RECORDED_COLUMNS = 'id, checked_in_at, source';

/** POST /api/check-in — staff assistance and verified member QR replay. */
export async function POST(request: Request): Promise<Response> {
  let caller: Awaited<ReturnType<typeof readIdentity>> | Awaited<ReturnType<typeof readRequestIdentity>>;
  if (request.headers.get('authorization') !== null) caller = await readRequestIdentity(request);
  else {
    try { caller = await readIdentity(); }
    catch { caller = null; }
  }
  if (caller === null || caller.identity.kind === 'unlinked') return apiFail('unauthorized', 'not_signed_in', 'Sign in with one valid user session first.');
  if (caller.identity.kind !== 'staff' && caller.identity.kind !== 'member') return apiFail('forbidden', 'not_permitted', 'This account cannot record attendance.');
  const { supabase, identity } = caller;
  let payload: unknown;
  try { payload = await request.json(); } catch { return apiFail('bad_request', 'malformed_body', 'The request body was not JSON.'); }
  const parsed = checkInRequestSchema.safeParse(payload);
  if (!parsed.success) return apiFail('bad_request', 'invalid_request', 'That check-in was not readable.');
  const { token, reason, clientEventId, offlineRecordedAt } = parsed.data;
  const memberId = identity.kind === 'member' ? identity.memberId : parsed.data.memberId;
  if (memberId === undefined) return apiFail('bad_request', 'invalid_request', 'Choose a member before recording an assisted check-in.');
  if (identity.kind === 'member' && (token === undefined || reason !== undefined)) return apiFail('bad_request', 'member_gate_required', 'Member check-in requires a scanned gate code.');
  if (identity.kind === 'staff' && offlineRecordedAt !== undefined) return apiFail('bad_request', 'invalid_request', 'Only member device replay may carry an offline capture time.');
  const { data: member } = await supabase.from('members').select('id, full_name, branch_id').eq('id', memberId).maybeSingle();
  if (!member) return apiFail('not_found', 'member_unknown', 'No member of this gym has that id.');
  let qrSessionId: string | null = null;
  let branchId = member.branch_id;
  if (token === undefined) {
    if (reason === undefined) return apiFail('bad_request', 'reason_required', 'Scan the gate code, or give a reason for checking this member in at the desk.');
  } else {
    const { data: gate } = await supabase.from('qr_sessions').select('id, branch_id').eq('token_hash', hashGateCode(token)).maybeSingle();
    if (!gate) return apiFail('unprocessable', 'gate_code_unknown', 'That gate code is not in use here.');
    qrSessionId = gate.id; branchId = gate.branch_id;
  }
  const attendance = { tenant_id: identity.tenantId, branch_id: branchId, member_id: memberId, source: qrSessionId === null ? 'front_desk' as const : 'qr' as const, qr_session_id: qrSessionId, assist_reason: qrSessionId === null ? (reason ?? null) : null, client_event_id: clientEventId ?? null };
  const offlineAttendance = offlineRecordedAt === undefined ? attendance : { ...attendance, checked_in_at: offlineRecordedAt, offline_recorded_at: offlineRecordedAt };
  const { data: recorded, error } = await supabase.from('attendance').insert(offlineAttendance).select(RECORDED_COLUMNS).single();
  if (error === null) return apiOk({ memberName: member.full_name, replay: false, ...recorded });
  if (error.code === PG_UNIQUE_VIOLATION && clientEventId !== undefined) {
    const { data: already } = await supabase.from('attendance').select(RECORDED_COLUMNS).eq('client_event_id', clientEventId).eq('member_id', memberId).maybeSingle();
    if (already) return apiOk({ memberName: member.full_name, replay: true, ...already });
    return apiFail('conflict', 'client_event_id_reused', 'That check-in id has already been used for a different member.');
  }
  if (error.code === PG_INSUFFICIENT_PRIVILEGE) return apiFail('forbidden', 'not_permitted', 'Your role may not record attendance.');
  const refusal = Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  if (refusal) return apiFail(refusal.status, error.code, refusal.message);
  return apiFail('server_error', 'check_in_failed', 'That check-in could not be recorded.');
}
