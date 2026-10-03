import { acknowledgeMemberPushRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../../../lib/api';
import { commsOk, commsRpcFailure, notificationResult } from '../../../../../../lib/comms';

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
  context: { params: Promise<{ notificationId: string }> },
): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.'));
  if (caller.identity.kind !== 'member') return noStore(apiFail('forbidden', 'not_permitted', 'Only your own member account can report a push event.'));

  const { notificationId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(notificationId)) {
    return noStore(apiFail('bad_request', 'invalid_request', 'That message reference is not a valid id.'));
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That push event was not valid JSON.'));
  }
  const body = acknowledgeMemberPushRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'That push event is not a receipt the app can report.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'acknowledge_member_push', args: { p_notification_id: string; p_device_id: string; p_token_revision: number; p_event: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('acknowledge_member_push', {
    p_notification_id: notificationId,
    p_device_id: body.data.deviceId,
    p_token_revision: body.data.tokenRevision,
    p_event: body.data.event,
  });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : data;
  const result = notificationResult(row);
  if (result === null) return noStore(apiFail('server_error', 'operation_failed', 'That push event could not be recorded. Try again.'));
  return noStore(commsOk('ok', result));
}
