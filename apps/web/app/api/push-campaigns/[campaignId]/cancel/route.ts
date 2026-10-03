import { cancelAnnouncementPushRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../../lib/comms';

/**
 * `POST /api/push-campaigns/[id]/cancel` — an owner or manager cancels a
 * reviewed push campaign before its attempts are reserved (NTF-011). This
 * prevents all not-yet-reserved requests; a provider-accepted send can never
 * be recalled, and the result says `cancelled`, never "recalled".
 */
const REVIEW_ROLES = new Set(['gym_owner', 'gym_manager']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function POST(
  request: Request,
  context: { params: Promise<{ campaignId: string }> },
): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in first, then cancel the campaign.'));
  if (caller.identity.kind !== 'staff' || !REVIEW_ROLES.has(caller.identity.role)) {
    return noStore(apiFail('forbidden', 'not_permitted', 'Only the owner or a manager can cancel a push campaign.'));
  }

  const { campaignId } = await context.params;
  if (!UUID.test(campaignId)) return noStore(apiFail('not_found', 'request_unavailable', 'That campaign could not be found.'));

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That cancellation was not valid JSON.'));
  }
  const body = cancelAnnouncementPushRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'A campaign cancel carries no fields.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'cancel_announcement_push', args: { p_campaign_id: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('cancel_announcement_push', { p_campaign_id: campaignId });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : (data as { cancelled: boolean } | null);
  if (row === null || typeof row !== 'object') return noStore(apiFail('server_error', 'operation_failed', 'The campaign could not be cancelled. Try again.'));
  return noStore(commsOk('ok', row));
}
