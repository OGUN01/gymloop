import { staffWhatsappConsentRequestSchema } from '@gymloop/shared';
import { apiFail, jsonBody } from '../../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../../lib/comms';
import { whatsappDispatchResult, whatsappStaffCaller } from '../../../../../lib/whatsapp';

/**
 * `POST /api/notifications/[id]/whatsapp-dispatch` — the front
 * office queues a notification's WhatsApp send (WSP-001). The body carries
 * exactly the replay key; recipient, cost, sender, template and channel are
 * all derived by trusted server code and never accepted from a request, so a
 * client cannot smuggle a recipient or a price through this route. The path
 * reference and replay key reuse the canonical UUID wire schema; trusted SQL
 * still performs current tenant, recipient and dispatch eligibility checks.
 */
/** The body carries exactly the replay key and nothing else. */
function parseDispatchBody(payload: unknown): string | null {
  if (typeof payload !== 'object' || payload === null || Array.isArray(payload)) return null;
  const record = payload as Record<string, unknown>;
  const keys = Object.keys(record).sort();
  if (keys.length !== 1 || keys[0] !== 'requestKey') return null;
  const parsed = staffWhatsappConsentRequestSchema.shape.requestKey.safeParse(record.requestKey);
  return parsed.success ? parsed.data : null;
}

export async function POST(
  request: Request,
  context: { params: Promise<{ id: string }> },
): Promise<Response> {
  const caller = await whatsappStaffCaller(request);
  if ('failure' in caller) return caller.failure;

  const { id: notificationId } = await context.params;
  if (!staffWhatsappConsentRequestSchema.shape.memberId.safeParse(notificationId).success) {
    return apiFail('bad_request', 'invalid_request', 'That message reference is not a valid id.');
  }

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;
  const requestKey = parseDispatchBody(body.payload);
  if (requestKey === null) {
    return apiFail('bad_request', 'invalid_request', 'Send the request key only — recipients and costs are decided by the gym, not the client.');
  }

  const dispatcher = caller.session.supabase as unknown as {
    rpc(name: 'request_whatsapp_dispatch', args: { p_notification_id: string; p_request_key: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await dispatcher.rpc('request_whatsapp_dispatch', {
    p_notification_id: notificationId,
    p_request_key: requestKey,
  });
  if (error) return commsRpcFailure(error, 'paise');

  const result = whatsappDispatchResult(data);
  if (result === null) return apiFail('server_error', 'operation_failed', 'The WhatsApp send could not be queued.');
  return commsOk('ok', result);
}
