import { staffWhatsappConsentRequestSchema } from '@gymloop/shared';
import { Constants } from '@gymloop/db';

import { apiFail, jsonBody } from '../../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../../lib/comms';
import { whatsappConsentWriteResult, whatsappStaffCaller } from '../../../../../lib/whatsapp';

/**
 * `POST /api/members/[memberId]/whatsapp-consent` — the front office's
 * verified actual-recipient recording (WSP-002). The body's six fields match
 * the future `record_whatsapp_consent` signature exactly; a default-on bulk
 * consent shape cannot even parse. The path member id and the body member id
 * must agree — a mismatch is a bad request, never a lookup of a third id.
 */
export async function POST(
  request: Request,
  context: { params: Promise<{ memberId: string }> },
): Promise<Response> {
  const caller = await whatsappStaffCaller(request);
  if ('failure' in caller) return caller.failure;

  const { memberId } = await context.params;
  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;

  const parsed = staffWhatsappConsentRequestSchema.safeParse(body.payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'Check the member, purpose, grant choice, notice version, evidence source and request key, then try again.');
  }
  const request_ = parsed.data;
  if (request_.memberId !== memberId) {
    return apiFail('bad_request', 'invalid_request', 'The member in the path and the body must match.');
  }
  if (!(Constants.public.Enums.consent_purpose as readonly string[]).includes(request_.purpose)) {
    return apiFail('bad_request', 'invalid_request', 'That consent purpose is not recognized.');
  }

  const writer = caller.session.supabase as unknown as {
    rpc(name: 'record_whatsapp_consent', args: {
      p_member_id: string; p_purpose: string; p_granted: boolean;
      p_notice_version: string; p_source: string; p_request_key: string;
    }): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('record_whatsapp_consent', {
    p_member_id: request_.memberId,
    p_purpose: request_.purpose,
    p_granted: request_.granted,
    p_notice_version: request_.noticeVersion,
    p_source: request_.source,
    p_request_key: request_.requestKey,
  });
  if (error) return commsRpcFailure(error, 'paise');

  const result = whatsappConsentWriteResult(data);
  if (result === null || result.purpose !== request_.purpose || result.granted !== request_.granted) return apiFail('server_error', 'operation_failed', 'The WhatsApp consent result could not be confirmed. Refresh the member settings before trying again.');
  return commsOk('created', result);
}
