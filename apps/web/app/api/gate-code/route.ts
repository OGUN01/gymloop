import { GATE_CODE_TTL_MS } from '@gymloop/shared';
import { apiFail, apiOk, staffSession, PG_INSUFFICIENT_PRIVILEGE } from '../../../lib/api';
import { hashGateCode, newGateCode } from '../../../lib/gate-code';

/**
 * POST /api/gate-code — issue the rotating code the gate displays (ATT-003).
 *
 * Not in the brief for this slice, and here anyway, because without it the QR
 * half of check-in has nothing to scan: `qr_sessions` stores only a hash, so a
 * code cannot be conjured with a SQL insert or a seed row, and the only place
 * that can mint one is the only place that knows the hash function. A screen
 * that can scan but has nothing to scan is a screen nobody can test.
 *
 * It is deliberately small: no rotation schedule, no revoke endpoint, no
 * per-gym lifetime. Issuing supersedes nothing — a previously issued code stays
 * valid until it expires — because "which codes are live" is a question the
 * gate-management screen a later phase builds should answer, and inventing the
 * answer here would put policy in an endpoint.
 *
 * The code is returned **once**, in this response, and never again: it exists
 * nowhere else, which is exactly ATT-003's point.
 */
export async function POST(): Promise<Response> {
  const caller = await staffSession();
  if ('failure' in caller) return caller.failure;
  const { supabase, tenantId, staffId } = caller.session;

  // RLS scopes this to the caller's own gym; v1 shows one branch per gym, so the
  // default branch is the gate. `is_default` descending puts `true` first.
  const { data: branch } = await supabase
    .from('branches')
    .select('id')
    .order('is_default', { ascending: false })
    .order('created_at')
    .limit(1)
    .maybeSingle();

  if (!branch) {
    return apiFail('unprocessable', 'no_branch', 'This gym has no branch to issue a code for.');
  }

  const code = newGateCode();
  // One value, used for the row and for the response. Computing it twice would
  // tell the screen a different expiry from the one the trigger later judges
  // the scan against.
  const expiresAt = new Date(Date.now() + GATE_CODE_TTL_MS).toISOString();

  const { error } = await supabase.from('qr_sessions').insert({
    tenant_id: tenantId,
    branch_id: branch.id,
    token_hash: hashGateCode(code),
    expires_at: expiresAt,
    created_by_staff_id: staffId,
  });

  if (error) {
    // `qr_sessions_tenant_write` is `is_front_office()`, so a trainer's session
    // arrives here as 42501 rather than as a bad request.
    return error.code === PG_INSUFFICIENT_PRIVILEGE
      ? apiFail('forbidden', 'not_permitted', 'Your role may not issue a gate code.')
      : apiFail('server_error', 'gate_code_failed', 'That gate code could not be issued.');
  }

  return apiOk({ code, expiresAt });
}
