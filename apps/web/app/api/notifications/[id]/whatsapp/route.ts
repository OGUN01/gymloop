import { apiFail, staffSession } from '../../../../../lib/api';
import { commsOk, commsRpcFailure, isCommunicationOptedOut, resolveNotificationId, whatsappOpenResult } from '../../../../../lib/comms';
import { FRONT_OFFICE_ROLES } from '../../../../../lib/leads';

/**
 * `POST /api/notifications/[id]/whatsapp` — front office opens the WhatsApp
 * deep link for an already-sent in-app message (contract §5). There is
 * deliberately no `GET`: the URL is the narrow command's return value, never
 * something a browser can fetch idly, because a `GET` that could mint a send
 * action would defeat the "explicit open" rule this cluster is built around.
 *
 * A refused current consent/eligibility/renewal decision creates no child and
 * exposes no URL — `open_notification_whatsapp` answers a plain refusal shape
 * for that case rather than an error, so it is checked before the ordinary
 * result validator.
 */
export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<Response> {
  void request;
  const caller = await staffSession(FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;

  const id = await resolveNotificationId(context);
  if (typeof id !== 'string') return id;

  const writer = caller.session.supabase as unknown as {
    rpc(name: 'open_notification_whatsapp', args: { p_notification_id: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('open_notification_whatsapp', { p_notification_id: id });
  if (error) return commsRpcFailure(error);

  if (isCommunicationOptedOut(data)) {
    return apiFail('forbidden', 'communication_opted_out', 'This member cannot be messaged right now. No link was created.');
  }

  const result = whatsappOpenResult(data);
  if (result === null) return apiFail('server_error', 'operation_failed', 'The WhatsApp link could not be created.');
  return commsOk('ok', result);
}
