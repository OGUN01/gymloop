import { memberWhatsappConsentRequestSchema } from '@gymloop/shared';
import { Constants } from '@gymloop/db';

import { apiFail, jsonBody, memberSession } from '../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../lib/comms';
import { whatsappConsentWriteResult } from '../../../../lib/whatsapp';

/**
 * `POST /api/member/whatsapp-consent` — the member's own channel-consent
 * command (WSP-002). The body carries exactly the three fields the future
 * `set_member_whatsapp_consent` signature names; the route never accepts a
 * member or staff id, a channel field, or any version of a generic consent
 * shape. Purpose membership in the generated `consent_purpose` vocabulary is
 * the same route-layer check `api/consents` performs.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await memberSession(request);
  if ('failure' in caller) return caller.failure;

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;

  const parsed = memberWhatsappConsentRequestSchema.safeParse(body.payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'Check the purpose, grant choice and notice version, then try again.');
  }
  const { purpose, granted, noticeVersion } = parsed.data;
  if (!(Constants.public.Enums.consent_purpose as readonly string[]).includes(purpose)) {
    return apiFail('bad_request', 'invalid_request', 'That consent purpose is not recognized.');
  }

  // `set_member_whatsapp_consent` does not exist before the WSP migration; the
  // narrow local cast matches the pattern `member-imports.ts` and the delivered
  // route use for not-yet-generated RPCs.
  const writer = caller.session.supabase as unknown as {
    rpc(name: 'set_member_whatsapp_consent', args: {
      p_purpose: string; p_granted: boolean; p_notice_version: string;
    }): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('set_member_whatsapp_consent', {
    p_purpose: purpose,
    p_granted: granted,
    p_notice_version: noticeVersion,
  });
  if (error) return commsRpcFailure(error, 'paise');

  const result = whatsappConsentWriteResult(data);
  if (result === null || result.purpose !== purpose || result.granted !== granted) return apiFail('server_error', 'operation_failed', 'The WhatsApp consent result could not be confirmed. Refresh your settings before trying again.');
  return commsOk('created', result);
}
