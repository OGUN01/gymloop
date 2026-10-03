import { registerMemberPushDeviceRequestSchema } from '@gymloop/shared';
import { pushMemberCommandRoute } from '../../../../lib/push-http';

/**
 * `POST /api/member/push-device` — the member registers or rotates the FCM
 * token of one Android installation (NTF-003/004). Only the member's own
 * identity may call it; the RPC derives tenant/member from claims, never from
 * the body. A same installation/token replay is inert server-side, so a retry
 * after a lost response is safe.
 */
export async function POST(request: Request): Promise<Response> {
  return pushMemberCommandRoute(request, {
    signedOut: 'Sign in as a member first.',
    wrongAudience: 'Only your own member account can register a device.',
    jsonError: 'That device registration was not valid JSON.',
    invalidMessage: 'That device registration is missing a required fact or carries an unknown field.',
    schema: registerMemberPushDeviceRequestSchema,
    rpc: 'register_member_push_device',
    args: (data) => {
      const d = data as { installationId: string; pushToken: string; platform: string };
      return { p_installation_id: d.installationId, p_push_token: d.pushToken, p_platform: d.platform };
    },
  });
}
