import { setMemberPushPreferenceRequestSchema } from '@gymloop/shared';
import { pushMemberCommandRoute } from '../../../../lib/push-http';

/**
 * `POST /api/member/push-preference` — one member's own push category switch
 * (NTF-002). This never touches purpose consent: a preference only lowers the
 * member's device delivery, and withdrawing consent remains the separate
 * written action in the consents flow.
 */
export async function POST(request: Request): Promise<Response> {
  return pushMemberCommandRoute(request, {
    signedOut: 'Sign in as a member first.',
    wrongAudience: 'Only your own member account can change notification settings.',
    jsonError: 'That preference change was not valid JSON.',
    invalidMessage: 'That preference change names an unknown category or carries an unknown field.',
    schema: setMemberPushPreferenceRequestSchema,
    rpc: 'set_member_push_preference',
    args: (data) => {
      const d = data as { category: string; enabled: boolean };
      return { p_category: d.category, p_enabled: d.enabled };
    },
  });
}
