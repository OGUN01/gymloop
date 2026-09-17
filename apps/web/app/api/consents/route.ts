import { Constants } from '@gymloop/db';
import { recordConsentRequestSchema } from '@gymloop/shared';
import { apiFail, staffJson } from '../../../lib/api';
import { commsOk, commsRpcFailure, consentResult } from '../../../lib/comms';
import { FRONT_OFFICE_ROLES } from '../../../lib/leads';

/**
 * `POST /api/consents` — record a consent decision (contract §3, §8).
 *
 * Front office only, the same audience `app.is_front_office()` requires at
 * the database: an unpermitted role, a member and a support preview identity
 * are all refused before the body is parsed — `staffJson`'s prologue, the
 * same one `apps/web/app/api/leads/route.ts` uses. `purpose` is shape-checked
 * by the shared schema and then checked against the generated `consent_purpose`
 * catalogue here, because `packages/shared` cannot import `@gymloop/db`
 * (AGENTS.md rule 11).
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await staffJson(request, FRONT_OFFICE_ROLES, { completeWrongAudience: 'forbidden' });
  if ('failure' in caller) return caller.failure;

  const parsed = recordConsentRequestSchema.safeParse(caller.payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'Check the member, purpose, version and source, then try again.');
  }
  const { memberId, purpose, granted, version, source, requestKey } = parsed.data;
  if (!(Constants.public.Enums.consent_purpose as readonly string[]).includes(purpose)) {
    return apiFail('bad_request', 'invalid_request', 'That consent purpose is not recognized.');
  }

  const writer = caller.supabase as unknown as {
    rpc(name: 'record_consent', args: {
      p_member_id: string; p_purpose: string; p_granted: boolean;
      p_version: string; p_source: string; p_request_key: string;
    }): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('record_consent', {
    p_member_id: memberId, p_purpose: purpose, p_granted: granted,
    p_version: version, p_source: source, p_request_key: requestKey,
  });
  if (error) return commsRpcFailure(error);

  const result = consentResult(data);
  if (result === null) return apiFail('server_error', 'operation_failed', 'The consent could not be recorded. Nothing was written.');
  return commsOk('created', result);
}
