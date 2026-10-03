import { registerMemberPushDeviceRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../lib/comms';

/**
 * `POST /api/member/push-device` — the member registers or rotates the FCM
 * token of one Android installation (NTF-003/004). Only the member's own
 * identity may call it; the RPC derives tenant/member from claims, never from
 * the body. A same installation/token replay is inert server-side, so a retry
 * after a lost response is safe.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.'));
  if (caller.identity.kind !== 'member') return noStore(apiFail('forbidden', 'not_permitted', 'Only your own member account can register a device.'));

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That device registration was not valid JSON.'));
  }
  const body = registerMemberPushDeviceRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'That device registration is missing a required fact or carries an unknown field.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'register_member_push_device', args: { p_installation_id: string; p_push_token: string; p_platform: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('register_member_push_device', {
    p_installation_id: body.data.installationId,
    p_push_token: body.data.pushToken,
    p_platform: body.data.platform,
  });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : (data as { deviceId: string; tokenRevision: number; active: boolean } | null);
  if (row === null || typeof row !== 'object') return noStore(apiFail('server_error', 'operation_failed', 'The device could not be registered. Try again.'));
  return noStore(commsOk('ok', row));
}
