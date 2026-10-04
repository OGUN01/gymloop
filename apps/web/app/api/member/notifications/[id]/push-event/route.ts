import { acknowledgeMemberPushRequestSchema } from '@gymloop/shared';
import { commsOk, memberPushSession, pushJsonBody, pushRpc } from '../../../../../../lib/push-http';
import { apiFail, noStore } from '../../../../../../lib/api';
import { notificationResult } from '../../../../../../lib/comms';

/**
 * `POST /api/member/notifications/[id]/push-event` — the authenticated app
 * reports a push receipt (`received`) or an OS open (`opened`) against one
 * accepted device attempt (NTF-009/010). The allowlist is exactly these two
 * events: nothing here can claim delivered, clicked or a provider receipt on
 * its own, and an inbox list load must never call it. An `opened` response may
 * lawfully traverse `sent→delivered→clicked` inside the one RPC transaction.
 */
export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<Response> {
  const head = await memberPushSession(request, { signedOut: 'Sign in as a member first.', wrongAudience: 'Only your own member account can report a push event.' });
  if ('failure' in head) return head.failure;

  const { id: notificationId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(notificationId)) {
    return noStore(apiFail('bad_request', 'invalid_request', 'That message reference is not a valid id.'));
  }

  const body = await pushJsonBody(request, 'That push event was not valid JSON.');
  if ('failure' in body) return body.failure;
  const parsed = acknowledgeMemberPushRequestSchema.safeParse(body.payload);
  if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', 'That push event is not a receipt the app can report.'));

  const result = await pushRpc<unknown>(head.session, 'acknowledge_member_push', {
    p_notification_id: notificationId,
    p_device_id: parsed.data.deviceId,
    p_token_revision: parsed.data.tokenRevision,
    p_event: parsed.data.event,
  });
  if ('failure' in result) return result.failure;
  const receipt = notificationResult(result.row);
  if (receipt === null) return noStore(apiFail('server_error', 'operation_failed', 'That push event could not be recorded. Try again.'));
  return noStore(commsOk('ok', receipt));
}
