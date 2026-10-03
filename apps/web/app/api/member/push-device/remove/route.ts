import { unregisterMemberPushDeviceRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../../lib/comms';

/**
 * `POST /api/member/push-device/remove` — the member unregisters one
 * installation (sign-out, NTF-004). Removing an installation the caller does
 * not own is inert and indistinguishable from removing an absent one; the
 * send-time authorization remains the security boundary when the app is
 * offline and cannot reach this route.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.'));
  if (caller.identity.kind !== 'member') return noStore(apiFail('forbidden', 'not_permitted', 'Only your own member account can remove a device.'));

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That device removal was not valid JSON.'));
  }
  const body = unregisterMemberPushDeviceRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'That device removal is missing the installation identifier.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'unregister_member_push_device', args: { p_installation_id: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('unregister_member_push_device', { p_installation_id: body.data.installationId });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : (data as { disabled: boolean } | null);
  if (row === null || typeof row !== 'object') return noStore(apiFail('server_error', 'operation_failed', 'The device could not be removed. Try again.'));
  return noStore(commsOk('ok', row));
}
