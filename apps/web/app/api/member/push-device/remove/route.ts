import { unregisterMemberPushDeviceRequestSchema } from '@gymloop/shared';
import { commsOk, memberPushSession, pushJsonBody, pushRpc } from '../../../../../lib/push-http';
import { apiFail, noStore } from '../../../../../lib/api';

/**
 * `POST /api/member/push-device/remove` — the member unregisters one
 * installation (sign-out, NTF-004). Removing an installation the caller does
 * not own is inert and indistinguishable from removing an absent one; the
 * send-time authorization remains the security boundary when the app is
 * offline and cannot reach this route.
 */
export async function POST(request: Request): Promise<Response> {
  const head = await memberPushSession(request, { signedOut: 'Sign in as a member first.', wrongAudience: 'Only your own member account can remove a device.' });
  if ('failure' in head) return head.failure;
  const body = await pushJsonBody(request, 'That device removal was not valid JSON.');
  if ('failure' in body) return body.failure;
  const parsed = unregisterMemberPushDeviceRequestSchema.safeParse(body.payload);
  if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', 'That device removal is missing the installation identifier.'));
  const result = await pushRpc<{ disabled: boolean }>(head.session, 'unregister_member_push_device', { p_installation_id: parsed.data.installationId });
  if ('failure' in result) return result.failure;
  return noStore(commsOk('ok', result.row));
}
