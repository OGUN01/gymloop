import { setMemberPushPreferenceRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../lib/comms';

/**
 * `POST /api/member/push-preference` — one member's own push category switch
 * (NTF-002). This never touches purpose consent: a preference only lowers the
 * member's device delivery, and withdrawing consent remains the separate
 * written action in the consents flow.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.'));
  if (caller.identity.kind !== 'member') return noStore(apiFail('forbidden', 'not_permitted', 'Only your own member account can change notification settings.'));

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That preference change was not valid JSON.'));
  }
  const body = setMemberPushPreferenceRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'That preference change names an unknown category or carries an unknown field.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'set_member_push_preference', args: { p_category: string; p_enabled: boolean }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('set_member_push_preference', {
    p_category: body.data.category,
    p_enabled: body.data.enabled,
  });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : (data as { category: string; enabled: boolean } | null);
  if (row === null || typeof row !== 'object') return noStore(apiFail('server_error', 'operation_failed', 'The preference could not be saved. Try again.'));
  return noStore(commsOk('ok', row));
}
