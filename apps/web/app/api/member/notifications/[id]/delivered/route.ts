import { apiFail, memberSession } from '../../../../../../lib/api';
import { commsOk, commsRpcFailure, notificationResult, resolveNotificationId } from '../../../../../../lib/comms';

/**
 * `POST /api/member/notifications/[id]/delivered` — the member's explicit
 * "I opened this" action (contract §5). This is the only route that may call
 * `acknowledge_notification`; no other identity has a delivered action at all,
 * so a staff or preview caller is refused with the same `not_signed_in` a
 * caller who is not a member gets everywhere else.
 *
 * The request carries no body facts — the notification id in the path is the
 * whole command, and it must be verified before any RPC runs.
 */
export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<Response> {
  const caller = await memberSession(request);
  if ('failure' in caller) return caller.failure;

  const id = await resolveNotificationId(context);
  if (typeof id !== 'string') return id;

  const writer = caller.session.supabase as unknown as {
    rpc(name: 'acknowledge_notification', args: { p_notification_id: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('acknowledge_notification', { p_notification_id: id });
  if (error) return commsRpcFailure(error);

  const result = notificationResult(data);
  if (result === null) return apiFail('server_error', 'operation_failed', 'That message could not be marked delivered.');
  return commsOk('ok', result);
}
