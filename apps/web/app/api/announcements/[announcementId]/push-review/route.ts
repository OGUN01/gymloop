import { reviewAnnouncementPushRequestSchema } from '@gymloop/shared';
import { readRequestIdentity } from '../../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../../lib/comms';

/**
 * `POST /api/announcements/[id]/push-review` — an owner or manager reviews and
 * commits one push campaign for the announcement's current live version
 * (NTF-011). Front desk may preview only; trainers, members, platform support
 * and impersonation are refused before anything runs. Review is permission to
 * attempt, never evidence of receipt.
 */
const REVIEW_ROLES = new Set(['gym_owner', 'gym_manager']);

export async function POST(
  request: Request,
  context: { params: Promise<{ announcementId: string }> },
): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in first, then review the campaign.'));
  if (caller.identity.kind !== 'staff' || !REVIEW_ROLES.has(caller.identity.role)) {
    return noStore(apiFail('forbidden', 'not_permitted', 'Only the owner or a manager can review a push campaign.'));
  }

  const { announcementId } = await context.params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(announcementId)) {
    return noStore(apiFail('not_found', 'request_unavailable', 'That announcement could not be found.'));
  }

  let payload: unknown;
  try {
    payload = await request.json();
  } catch {
    return noStore(apiFail('bad_request', 'invalid_request', 'That review was not valid JSON.'));
  }
  const body = reviewAnnouncementPushRequestSchema.safeParse(payload);
  if (!body.success) return noStore(apiFail('bad_request', 'invalid_request', 'That review is missing the version or replay key, or carries an unknown field.'));

  const writer = caller.supabase as unknown as {
    rpc(name: 'review_announcement_push', args: { p_announcement_id: string; p_version_no: number; p_request_key: string }):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('review_announcement_push', {
    p_announcement_id: announcementId,
    p_version_no: body.data.versionNo,
    p_request_key: body.data.requestKey,
  });
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : (data as { campaignId: string; versionNo: number; eligibleCount: number; reviewedAt: string } | null);
  if (row === null || typeof row !== 'object') return noStore(apiFail('server_error', 'operation_failed', 'The campaign review could not be saved. Try again.'));
  return noStore(commsOk('ok', row));
}
