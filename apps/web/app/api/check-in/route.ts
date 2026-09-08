import { checkInRequestSchema } from '@gymloop/shared';
import {
  apiFail,
  apiOk,
  staffSession,
  PG_INSUFFICIENT_PRIVILEGE,
  PG_UNIQUE_VIOLATION,
  type ApiFailStatus,
} from '../../../lib/api';
import { hashGateCode } from '../../../lib/gate-code';

/**
 * POST /api/check-in — record a visit (ATT-001 to ATT-006).
 *
 * **This handler does not make exactly-once true and must not be read as if it
 * did.** `attendance` grants `insert` to `authenticated` and
 * `attendance_tenant_write` admits any front-office session, so a screen could
 * insert a row through `supabase-js` without ever coming here — that is the
 * architecture working as designed, reads and writes both going through RLS. A
 * rule enforced by a caller is therefore a rule that has a way round it. Every
 * rule below is enforced by the `attendance_enforce_check_in` trigger, which
 * every writer meets; this handler's job is to turn one HTTP request into one
 * insert, and to turn what the database refuses into something a person at a
 * front desk can act on.
 *
 * The one thing it does decide is which row to propose: it resolves a gate code
 * to a `qr_sessions` id (the code itself is never stored, so nothing downstream
 * can do that lookup), and it reads the tenant from the verified JWT claim so
 * that no request body ever names a gym.
 */

/**
 * The five refusals `app.enforce_check_in()` raises, by SQLSTATE.
 *
 * Mapped by code and never by matching the message text: the message carries a
 * uuid and a timestamp for whoever reads the Postgres log, and the message here
 * is the one that has to be legible across a room.
 */
const REFUSALS: Record<string, { status: ApiFailStatus; message: string }> = {
  GL010: { status: 'unprocessable', message: 'That gate code belongs to another gym.' },
  GL011: { status: 'unprocessable', message: 'That gate code has expired. Show a new one.' },
  GL012: { status: 'unprocessable', message: 'That gate code has been revoked.' },
  GL013: {
    status: 'unprocessable',
    message: 'No active membership. Renew before checking in.',
  },
  GL014: { status: 'conflict', message: 'Already checked in a moment ago.' },
};

const RECORDED_COLUMNS = 'id, checked_in_at, source';

export async function POST(request: Request): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId } = caller.session;

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return apiFail('bad_request', 'malformed_body', 'The request body was not JSON.');
  }

  const parsed = checkInRequestSchema.safeParse(payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'That check-in was not readable.');
  }
  const { memberId, token, reason, clientEventId } = parsed.data;

  // No `.eq('tenant_id', …)`: the policy on `members` does the filtering, so a
  // member id from another gym simply is not there. Adding the predicate would
  // return the right row even with the policy broken, hiding the defect the
  // pgTAP suite exists to find.
  const { data: member } = await supabase
    .from('members')
    .select('id, full_name, branch_id')
    .eq('id', memberId)
    .maybeSingle();

  if (!member) {
    return apiFail('not_found', 'member_unknown', 'No member of this gym has that id.');
  }

  let qrSessionId: string | null = null;
  let branchId = member.branch_id;

  if (token === undefined) {
    // No gate code means the desk is recording this visit for someone, which is
    // the case ATT-005/006 requires a reason for. The schema already rejects a
    // blank one and the check constraint rejects a whitespace one; this is the
    // "neither a code nor a reason" case, which is neither kind of check-in.
    if (reason === undefined) {
      return apiFail(
        'bad_request',
        'reason_required',
        'Scan the gate code, or give a reason for checking this member in at the desk.',
      );
    }
  } else {
    // Only the hash is stored, so the code can be matched but never read back.
    const { data: gate } = await supabase
      .from('qr_sessions')
      .select('id, branch_id')
      .eq('token_hash', hashGateCode(token))
      .maybeSingle();

    if (!gate) {
      return apiFail('unprocessable', 'gate_code_unknown', 'That gate code is not in use here.');
    }
    // Expiry and revocation are the trigger's to judge, against the instant of
    // the scan rather than the instant of the lookup. Re-testing them here would
    // put the same rule in two places, and the copy in the weaker place.
    qrSessionId = gate.id;
    branchId = gate.branch_id;
  }

  const { data: recorded, error } = await supabase
    .from('attendance')
    .insert({
      tenant_id: tenantId,
      branch_id: branchId,
      member_id: memberId,
      source: qrSessionId === null ? 'front_desk' : 'qr',
      qr_session_id: qrSessionId,
      // A scan carries no reason and so must carry no acting staff member either
      // (`attendance_assisted_pair_chk`). The staff member on an assisted row is
      // stamped from the JWT by the trigger, not sent from here.
      assist_reason: qrSessionId === null ? (reason ?? null) : null,
      client_event_id: clientEventId ?? null,
    })
    .select(RECORDED_COLUMNS)
    .single();

  if (error === null) {
    return apiOk({ memberName: member.full_name, replay: false, ...recorded });
  }

  // The same attempt arriving twice — a retry or a replay, not a second visit.
  // Reporting it as an error would make a correctly-retrying client look broken,
  // so the answer is the row that already exists.
  if (error.code === PG_UNIQUE_VIOLATION && clientEventId !== undefined) {
    const { data: already } = await supabase
      .from('attendance')
      .select(RECORDED_COLUMNS)
      .eq('client_event_id', clientEventId)
      .maybeSingle();

    if (already) {
      return apiOk({ memberName: member.full_name, replay: true, ...already });
    }
  }

  if (error.code === PG_INSUFFICIENT_PRIVILEGE) {
    return apiFail('forbidden', 'not_permitted', 'Your role may not record attendance.');
  }

  const refusal = REFUSALS[error.code];
  if (refusal) {
    return apiFail(refusal.status, error.code, refusal.message);
  }

  return apiFail('server_error', 'check_in_failed', 'That check-in could not be recorded.');
}
