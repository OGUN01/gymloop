import { DEFAULT_TIMEZONE, formatDateTime } from '@gymloop/shared';
import { loadPushCampaigns } from '../../../lib/push-campaigns';
import { PushCampaignReviewForm } from './push-review-form';

/**
 * The push-campaign review/status section of the Messages console
 * (NTF-011/016, pre-configuration amendment). Facts only: a reviewed campaign
 * is "Accepted by push service" — never a receipt; an attempt with an unknown
 * outcome is "Delivery unknown" and is never silently resent. While the push
 * provider is unconfigured the campaign reader answers `ok: false` and the
 * section shows the honest unconfigured line instead of listing campaigns
 * that cannot exist yet.
 */
const COPY_ACCEPTED = 'Accepted by push service';
const COPY_UNKNOWN = 'Delivery unknown';

/** One campaign's status line. Zero known acceptances after every attempt resolved failed is a refusal; anything unresolved is unknown. */
function statusLine(campaign: { counts: { accepted: number | null; failed: number | null; uncertain: number | null } | null; cancelledAt: string | null }): string {
  if (campaign.cancelledAt !== null) return 'Cancelled — queued requests will not go out.';
  const counts = campaign.counts;
  if (counts === null || (counts.accepted === null && counts.failed === null && counts.uncertain === null)) return COPY_UNKNOWN;
  if (counts.failed !== null && counts.accepted === null && counts.uncertain === null && counts.failed > 0) {
    return 'Not sent — every attempt was refused by the push service.';
  }
  if (counts.accepted !== null && counts.uncertain === null) {
    return `${COPY_ACCEPTED} (${counts.accepted} ${counts.accepted === 1 ? 'device' : 'devices'}).`;
  }
  return COPY_UNKNOWN;
}

export function PushCampaignsSection({ campaigns, loaded, review, role }: {
  campaigns: Awaited<ReturnType<typeof loadPushCampaigns>>;
  loaded: boolean;
  review: { announcementId: string; versionNo: number; title: string; kind: string } | null;
  role: 'owner-manager' | 'desk-preview';
}) {
  const ready = loaded && campaigns.ok;
  const page = ready ? campaigns.page : null;
  return <section id="push-campaigns" aria-labelledby="push-campaigns-heading" className="comms-section comms-anchor">
    <div className="comms-section-head"><h2 id="push-campaigns-heading" className="cl-section-title">Push campaigns</h2></div>
    {!loaded
      ? <p className="comms-push-note"><a className="comms-section-link" href="?push=1#push-campaigns">Load push campaign status</a> — the count-only campaign list loads on demand, alongside the message log snapshot.</p>
      : null}
    {!ready ? <p className="comms-push-unconfigured">Push isn&#39;t configured. Updates remain in the app.</p> : null}
    <p className="comms-push-note">
      &quot;Accepted by push service&quot; means the delivery service took a request — only the receipt inside each
      member&#39;s app shows that a message arrived. An attempt whose outcome was never learned stays
      &quot;Delivery unknown&quot; and is never silently resent.
    </p>
    {review !== null && role === 'owner-manager'
      ? <div className="comms-subsection">
        <div className="comms-subsection-head"><h3 className="comms-subsection-title">Review a push campaign</h3></div>
        <PushCampaignReviewForm
          announcementId={review.announcementId}
          versionNo={review.versionNo}
          title={review.title}
          kind={review.kind}
          quietHoursNote="No promotion-category request is dispatched between 9 pm and 8 am Asia/Kolkata; it is deferred to after 8 am. The deferral never changes the announcement's scheduled time."
        />
      </div>
      : null}
    {page !== null && page.campaigns.length > 0
      ? <div className="cl-ledger-wrap"><table className="cl-ledger comms-push-campaigns"><thead><tr>
        <th scope="col">Announcement</th><th scope="col">Version</th><th scope="col">Reviewed</th><th scope="col">Status</th>
      </tr></thead><tbody>
        {page.campaigns.map((campaign) => <tr key={campaign.campaignId}>
          <td className="comms-log-member">{campaign.announcementId}</td>
          <td className="comms-log-fact tabular-nums">v{campaign.versionNo}</td>
          <td className="comms-log-fact">{campaign.reviewedAt !== null ? <time dateTime={campaign.reviewedAt}>{formatDateTime(campaign.reviewedAt, DEFAULT_TIMEZONE)}</time> : '—'}</td>
          <td className="comms-log-status">{statusLine(campaign)}</td>
        </tr>)}
      </tbody></table></div>
      : page !== null ? <div className="cl-empty"><strong>No push campaigns reviewed yet.</strong><p>Review a campaign from its announcement page; it appears here with its delivery status.</p></div> : null}
  </section>;
}
