import type { PushCampaignSummary } from '@gymloop/shared';

/**
 * Reads the reviewed push campaigns for the Messages console (NTF-011/016)
 * through `public.read_push_campaigns` with the frozen keyset envelope
 * `{campaigns, nextBefore, nextBeforeId}`. Anything but a well-formed page is
 * reported as "not available" — before the push migration is applied (the
 * pre-configuration amendment state) the console shows the truthful
 * unconfigured copy instead of pretending a campaign list exists.
 */
type ReadResult = { data: unknown; error: { code: string; message: string } | null };

type RpcCaller = {
  rpc(name: 'read_push_campaigns', args?: { p_before?: string | null; p_before_id?: string | null }):
    Promise<ReadResult>;
};

/** A count that is a safe integer, or a canonical decimal string of one. */
const numeric = (value: unknown): number | null => {
  if (typeof value === 'number' && Number.isSafeInteger(value)) return value;
  if (typeof value === 'string' && /^(?:0|[1-9][0-9]*)$/.test(value)) return Number(value);
  return null;
};

/** Validates one campaign row's review facts; an unknown shape drops the row, never invents one. */
function campaignRow(row: unknown): PushCampaignSummary | null {
  if (row === null || typeof row !== 'object') return null;
  const value = row as Record<string, unknown>;
  if (typeof value.campaignId !== 'string' || typeof value.announcementId !== 'string') return null;
  if (numeric(value.versionNo) === null) return null;
  // read_push_campaigns returns flat count columns, not a nested counts object.
  const counts = {
    accepted: numeric(value.acceptedCount),
    received: numeric(value.receivedCount),
    opened: numeric(value.openedCount),
    failed: numeric(value.failedCount),
    uncertain: numeric(value.uncertainCount),
  };
  return {
    campaignId: value.campaignId,
    announcementId: value.announcementId,
    versionNo: numeric(value.versionNo) as number,
    reviewedAt: typeof value.reviewedAt === 'string' ? value.reviewedAt : null,
    cancelledAt: typeof value.cancelledAt === 'string' ? value.cancelledAt : null,
    eligibleCount: numeric(value.eligibleCount),
    counts: (counts.accepted === null && counts.received === null && counts.opened === null && counts.failed === null && counts.uncertain === null) ? null : counts,
  };
}

export type PushCampaignsRead =
  | { ok: true; page: { campaigns: PushCampaignSummary[]; nextBefore: string | null; nextBeforeId: string | null } }
  | { ok: false };

function parsePushCampaignPage(data: unknown): { campaigns: PushCampaignSummary[]; nextBefore: string | null; nextBeforeId: string | null } | null {
  if (data === null || typeof data !== 'object') return null;
  const value = data as Record<string, unknown>;
  if (!Array.isArray(value.campaigns)) return null;
  const campaigns = value.campaigns.map(campaignRow);
  if (campaigns.some((row) => row === null)) return null;
  const nextBefore = typeof value.nextBefore === 'string' ? value.nextBefore : null;
  const nextBeforeId = typeof value.nextBeforeId === 'string' ? value.nextBeforeId : null;
  // The page cursor is two facts that only ever appear together.
  if ((nextBefore === null) !== (nextBeforeId === null)) return null;
  return { campaigns: campaigns as PushCampaignSummary[], nextBefore, nextBeforeId };
}

export async function loadPushCampaigns(db: RpcCaller, before?: { at: string; id: string } | null): Promise<PushCampaignsRead> {
  let result: ReadResult;
  try {
    result = await db.rpc('read_push_campaigns', before === undefined || before === null
      ? undefined
      : { p_before: before.at, p_before_id: before.id });
  } catch {
    return { ok: false };
  }
  if (result.error) return { ok: false };
  const page = parsePushCampaignPage(result.data);
  return page === null ? { ok: false } : { ok: true, page };
}
