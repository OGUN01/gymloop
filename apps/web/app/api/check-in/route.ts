import { checkInRequestSchema } from '@gymloop/shared';
import { apiFail, apiOk, PG_INSUFFICIENT_PRIVILEGE, PG_UNIQUE_VIOLATION, type ApiFailStatus } from '../../../lib/api';
import { readIdentity, readRequestIdentity } from '../../../lib/identity-session';
import { hashGateCode } from '../../../lib/gate-code';
import { createOperationalLogger } from '../../../lib/observability';

const REFUSALS: Record<string, { status: ApiFailStatus; message: string }> = {
  GL010: { status: 'unprocessable', message: 'That gate code belongs to another gym.' }, GL011: { status: 'unprocessable', message: 'That gate code has expired. Show a new one.' }, GL012: { status: 'unprocessable', message: 'That gate code has been revoked.' }, GL013: { status: 'unprocessable', message: 'No active membership. Renew before checking in.' }, GL014: { status: 'conflict', message: 'Already checked in a moment ago.' }, GL017: { status: 'unprocessable', message: 'That offline check-in time is not valid for this gate session.' }, GL018: { status: 'conflict', message: 'That check-in id has already been used for a different member.' },
  GL070: { status: 'conflict', message: 'The gym changed gate mode. Scan the currently displayed code or poster.' },
  GL071: { status: 'unprocessable', message: 'That poster belongs to another branch. Use the poster at this member’s branch.' },
  GL072: { status: 'unprocessable', message: 'The gym is closed for poster check-in. Try again during opening hours.' },
  GL073: { status: 'conflict', message: 'This member already checked in today. No second check-in was recorded.' },
};
const RECORDED_COLUMNS = 'id, checked_in_at, source';
const SAFE_DATABASE_ERROR_CODE = /^(?:[A-Z0-9]{5}|PGRST[0-9]{3})$/;
type MemberCheckInRecord = { id: string; checked_in_at: string; source: string; replay: boolean };
type MemberCheckInRpc = {
  rpc(name: 'member_mobile_check_in', args: { p_token_hash: string; p_client_event_id: string | null; p_offline_recorded_at: string | null }): {
    single(): Promise<{ data: MemberCheckInRecord | null; error: { code: string } | null }>;
  };
};
type StaffFrontDeskRecord = { id: string; checked_in_at: string; source: string; member_name: string };
type StaffFrontDeskRpc = {
  rpc(name: 'record_staff_front_desk_check_in', args: {
    p_member_id: string; p_reason: string; p_client_event_id: string | null;
  }): {
    maybeSingle(): Promise<{ data: StaffFrontDeskRecord | null; error: { code: string } | null; status: number }>;
  };
};
type StaffReplayRecord = {
  id: string; checked_in_at: string; source: string; member: { full_name: string } | null;
};

function staffCheckInOk(
  record: { id: string; checked_in_at: string; source: string },
  memberName: string,
  replay: boolean,
): Response {
  return apiOk({ memberName, id: record.id, checked_in_at: record.checked_in_at,
    source: record.source, replay });
}

function checkInFailure(error: { code: string } | null, tenantId: string): Response {
  if (error?.code === PG_INSUFFICIENT_PRIVILEGE) {
    return apiFail('forbidden', 'not_permitted', 'Your role may not record attendance.');
  }
  const refusal = error && Object.hasOwn(REFUSALS, error.code) ? REFUSALS[error.code] : undefined;
  if (refusal) return apiFail(refusal.status, error?.code ?? 'check_in_failed', refusal.message);
  createOperationalLogger({ write: (event) => console.error(event) }).error('check_in.database_error', {
    tenantId,
    context: { code: typeof error?.code === 'string' && SAFE_DATABASE_ERROR_CODE.test(error.code)
      ? error.code : 'unclassified' },
  });
  return apiFail('server_error', 'check_in_failed', 'That check-in could not be recorded.');
}

/** POST /api/check-in â€” staff assistance and verified member QR replay. */
export async function POST(request: Request): Promise<Response> {
  let caller: Awaited<ReturnType<typeof readIdentity>> | Awaited<ReturnType<typeof readRequestIdentity>>;
  if (request.headers.get('authorization') !== null) caller = await readRequestIdentity(request);
  else {
    try { caller = await readIdentity(); }
    catch { caller = null; }
  }
  if (caller === null || caller.identity.kind === 'unlinked') return apiFail('unauthorized', 'not_signed_in', 'Sign in with one valid user session first.');
  if (caller.identity.kind === 'member' && caller.authenticatedUser === false) return apiFail('unauthorized', 'not_signed_in', 'Sign in with one valid user session first.');
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
  if (identity.kind === 'staff' && token === undefined) {
    if (reason === undefined) return apiFail('bad_request', 'reason_required', 'Scan the gate code, or give a reason for checking this member in at the desk.');
    const command = { p_member_id: memberId, p_reason: reason, p_client_event_id: clientEventId ?? null };
    let result = await (supabase as unknown as StaffFrontDeskRpc)
      .rpc('record_staff_front_desk_check_in', command).maybeSingle();
    // Status zero can hide a committed write if its response was lost. The
    // unchanged event ID and same-member replay guard make one retry safe.
    if (clientEventId !== undefined && (result.error?.code === 'PGRST003' ||
        (result.status === 0 && result.error?.code === ''))) {
      result = await (supabase as unknown as StaffFrontDeskRpc)
        .rpc('record_staff_front_desk_check_in', command).maybeSingle();
    }
    const { data: recorded, error } = result;
    if (error === null && recorded !== null) return staffCheckInOk(recorded, recorded.member_name, false);
    if (error === null) return apiFail('not_found', 'member_unknown', 'No member of this gym has that id.');
    if (error.code === PG_UNIQUE_VIOLATION && clientEventId !== undefined) {
      const { data: already } = await supabase.from('attendance')
        .select('id, checked_in_at, source, member:members(full_name)')
        .eq('client_event_id', clientEventId).eq('member_id', memberId).maybeSingle();
      const replay = already as StaffReplayRecord | null;
      if (replay?.member) return staffCheckInOk(replay, replay.member.full_name, true);
      return apiFail('conflict', 'client_event_id_reused', 'That check-in id has already been used for a different member.');
    }
    return checkInFailure(error, identity.tenantId);
  }
  const { data: member } = await supabase.from('members').select('id, full_name, branch_id').eq('id', memberId).maybeSingle();
  if (!member) return apiFail('not_found', 'member_unknown', 'No member of this gym has that id.');
  if (identity.kind === 'member') {
    const { data: recorded, error } = await (supabase as unknown as MemberCheckInRpc)
      .rpc('member_mobile_check_in', {
        p_token_hash: hashGateCode(token as string),
        p_client_event_id: clientEventId ?? null,
        p_offline_recorded_at: offlineRecordedAt ?? null,
      }).single();
    if (error === null && recorded !== null) return apiOk({ memberName: member.full_name, ...recorded });
    return checkInFailure(error, identity.tenantId);
  }
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
  return checkInFailure(error, identity.tenantId);
}
