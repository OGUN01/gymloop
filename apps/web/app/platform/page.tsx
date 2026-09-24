import {
  DEFAULT_TIMEZONE,
  GYM_PRESETS,
  ORGANIZATION_STATUSES,
  PLAN_TIERS,
  PLAN_TIER_PRICES_PAISE,
  formatDay,
  formatMoney,
  humanize,
} from '@gymloop/shared';
import { requireAudience } from '../../lib/identity-session';
import { fleetMetrics } from '../../lib/platform';
import { Alert } from '../(console)/alert';
import { StatusWord } from '../status-word';

type OwnerRow = {
  id: string;
  tenant_id: string;
  user_id: string | null;
  full_name: string;
  email: string | null;
  role: string;
  is_active: boolean;
};

/** The gym's own timezone, unless the loader flagged it as invalid. */
const zoneOf = (gym: { timezone: string; metricsError: unknown }) => gym.metricsError === null ? gym.timezone : DEFAULT_TIMEZONE;
/** An instant as that gym's calendar day, "5 Oct 2026". */
const dayOf = (instant: string, timeZone: string) => <time dateTime={instant}>{formatDay(new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone }).format(new Date(instant)))}</time>;
const tierPrice = (tier: (typeof PLAN_TIERS)[number]) => formatMoney(PLAN_TIER_PRICES_PAISE[tier]);
/** A column label shown only where the ledger stacks into cards (under 40rem). */
const Cell = ({ label }: { label: string }) => <span className="platform-cell-label">{label}</span>;

export default async function PlatformPage(props?: { searchParams?: Promise<{ manage?: string }> }) {
  const manage = (await props?.searchParams)?.manage;
  const { supabase, identity } = await requireAudience('platform');
  const result = await fleetMetrics(supabase);
  if ('error' in result) {
    return <main className="cl-page"><Alert>We couldn’t load the gym fleet. Please try again.</Alert></main>;
  }

  let owners: OwnerRow[] = [];
  let ownerLoadFailed = false;
  if (identity.role === 'super_admin') {
    const ownerResult = await supabase.from('staff')
      .select('id,tenant_id,user_id,full_name,email,role,is_active')
      .order('tenant_id').order('id');
    ownerLoadFailed = ownerResult.error !== null;
    owners = (ownerResult.data ?? []).filter((row) =>
      row.role === 'gym_owner' && row.is_active && typeof row.id === 'string' && typeof row.tenant_id === 'string');
  }

  const { gyms, exceptions } = result.data;
  const isAdmin = identity.role === 'super_admin';

  return <main className="cl-page platform-fleet">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">{isAdmin ? 'Your platform’s gym directory' : 'Support access · read only'}</p>
        <h1 className="cl-title">Gyms</h1>
        <p className="cl-lede">
          {PLAN_TIERS.map((tier) => `${humanize(tier)} ${tierPrice(tier)}`).join(' · ')} per month
        </p>
      </div>
      {isAdmin ? <div className="cl-actions"><a href="#onboard" className="cl-btn cl-btn--primary">Add gym</a></div> : null}
    </div>

    <div className="cl-metrics platform-kpis">
      <div className="cl-metric"><span className="cl-eyebrow">Gyms</span><span className="cl-metric-value tabular-nums">{gyms.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Settings incomplete</span><span className="cl-metric-value tabular-nums">{exceptions.settingsIncomplete.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Owner access pending</span><span className="cl-metric-value tabular-nums">{exceptions.ownerAccessPending.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Trial expired</span><span className="cl-metric-value tabular-nums">{exceptions.trialExpired.length}</span></div>
    </div>

    {!gyms.length ? <div className="cl-empty"><strong>No gyms yet.</strong><p>{isAdmin ? 'Onboard the first gym below.' : 'Gyms appear here once a platform admin onboards them.'}</p></div> : <>
      <section className="cl-section" aria-labelledby="fleet-heading">
        <div className="cl-section-head"><h2 id="fleet-heading" className="cl-section-title">Fleet</h2></div>
        <div className="cl-ledger-wrap">
          <table className="cl-ledger platform-ledger">
            <thead><tr>
              <th scope="col">Gym</th><th scope="col">Status</th><th scope="col">Tier</th><th scope="col">Trial ends</th>
              <th scope="col" className="cl-num">Active members</th><th scope="col" className="cl-num">Open cases</th><th scope="col" className="cl-num">Failed sends</th>
              <th scope="col">Readiness</th><th scope="col"><span className="sr-only">Open</span></th>
            </tr></thead>
            <tbody>
              {gyms.map((gym) => <tr key={gym.tenantId}>
                <td className="platform-cell-gym"><span className="cl-row-title">{gym.name}</span><span className="cl-row-meta">{gym.gymCode}</span></td>
                <td className="platform-cell-status"><StatusWord status={gym.status} /></td>
                <td className="platform-cell-fact"><Cell label="Tier" /><span>{gym.tier === null ? 'Unassigned' : humanize(gym.tier)}</span></td>
                <td className="platform-cell-fact"><Cell label="Trial ends" /><span>{gym.trialEndsAt === null ? 'No trial' : dayOf(gym.trialEndsAt, zoneOf(gym))}</span></td>
                <td className="cl-num platform-cell-fact"><Cell label="Active members" /><span>{gym.activeMembers ?? 'Unavailable'}</span></td>
                <td className="cl-num platform-cell-fact"><Cell label="Open cases" /><span>{gym.openCases}</span></td>
                <td className="cl-num platform-cell-fact"><Cell label="Failed sends" /><span>{gym.failedNotifications}</span></td>
                <td className="platform-cell-readiness">{gym.settingsComplete ? <StatusWord status="ready" label="Activation ready" /> : <StatusWord status="pending" label={`Readiness incomplete: ${gym.missingSettings.map(humanize).join(', ') || 'unknown'}`} />}</td>
                <td className="platform-cell-open"><a href={`/platform/${gym.tenantId}`} className="cl-btn cl-btn--accent cl-btn--small" aria-label={`Open ${gym.name}`}>Open <span aria-hidden="true">›</span></a></td>
              </tr>)}
            </tbody>
          </table>
        </div>
      </section>

      {isAdmin ? <section className="cl-section" aria-labelledby="manage-heading">
        <div className="cl-section-head"><h2 id="manage-heading" className="cl-section-title">Manage gyms</h2></div>
        {gyms.map((gym) => {
          const gymOwners = owners.filter((owner) => owner.tenant_id === gym.tenantId);
          return <details key={gym.tenantId} id={`manage-${gym.tenantId}`} className="cl-disclosure platform-manage" open={manage === gym.tenantId}>
            <summary><span className="platform-manage-title"><span>{gym.name}</span><StatusWord status={gym.status} /></span></summary>
            <div className="platform-manage-body">
              <form action={`/api/platform/gyms/${gym.tenantId}/status`} method="post" className="platform-control">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="expectedStatus" value={gym.status} />
                <label className="cl-field"><span>Status</span><select name="status" defaultValue={gym.status} className="cl-input">{ORGANIZATION_STATUSES.map((status) => <option key={status} value={status}>{humanize(status)}</option>)}</select></label>
                <label className="cl-field"><span>Reason</span><input name="reason" className="cl-input" /></label>
                <button type="submit" className="cl-btn">Save status</button>
                <small className="platform-control-hint">A reason is required to suspend, close or reopen a suspended gym.</small>
              </form>
              <form action={`/api/platform/gyms/${gym.tenantId}/tier`} method="post" className="platform-control">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="expectedTier" value={gym.tier ?? ''} />
                <label className="cl-field platform-control-wide"><span>Tier</span><select name="tier" defaultValue={gym.tier ?? ''} className="cl-input"><option value="">Unassigned</option>{PLAN_TIERS.map((tier) => <option key={tier} value={tier}>{humanize(tier)} · {tierPrice(tier)}/month</option>)}</select></label>
                <button type="submit" className="cl-btn">Save tier</button>
              </form>
              <form action="/api/platform/impersonations" method="post" className="platform-control">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="tenantId" value={gym.tenantId} />
                <label className="cl-field platform-control-wide"><span>Preview reason</span><input name="reason" required defaultValue="Support review" className="cl-input" /></label>
                <button type="submit" className="cl-btn">Start preview</button>
              </form>
              {ownerLoadFailed ? <Alert>Owner-link details are temporarily unavailable.</Alert> : gymOwners.length ? gymOwners.map((owner) =>
                <form key={owner.id} action={`/api/platform/gyms/${gym.tenantId}/owner-link`} method="post" className="platform-control">
                  <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                  <input type="hidden" name="ownerStaffId" value={owner.id} />
                  <input type="hidden" name="expectedUserId" value={owner.user_id ?? ''} />
                  <label className="cl-field platform-control-wide"><span>Link owner profile: {owner.full_name}</span><input name="ownerEmail" type="email" required defaultValue={owner.email ?? ''} aria-label={`Exact Auth email for ${owner.full_name}`} className="cl-input" /></label>
                  <button type="submit" className="cl-btn">Link owner</button>
                  <small className="platform-control-hint">Use the exact sign-in email. The owner signs in again after this gym is activated.</small>
                </form>) : <p className="cl-muted">No active owner profile is available to link.</p>}
            </div>
          </details>;
        })}
      </section> : null}
    </>}

    {isAdmin ? <section className="cl-section platform-onboard" aria-labelledby="onboard-heading" id="onboard">
      <div className="cl-section-head"><h2 id="onboard-heading" className="cl-section-title">Onboard a gym</h2></div>
      <form action="/api/platform/gyms" method="post" className="cl-form">
        <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
        <input type="hidden" name="currency" value="INR" />
        <div className="cl-form-row">
          <label className="cl-field"><span>Gym name</span><input name="name" required className="cl-input" /></label>
          <label className="cl-field"><span>Timezone</span><input name="timezone" required defaultValue="Asia/Kolkata" className="cl-input" /></label>
          <label className="cl-field"><span>Preset</span><select name="preset" required className="cl-input">{GYM_PRESETS.map((preset) => <option key={preset} value={preset}>{humanize(preset)}</option>)}</select></label>
        </div>
        <div className="cl-form-row">
          <label className="cl-field"><span>Default branch</span><input name="branchName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner name</span><input name="ownerName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner email</span><input name="ownerEmail" type="email" className="cl-input" /></label>
        </div>
        <button type="submit" className="cl-btn cl-btn--accent">Onboard</button>
      </form>
    </section> : null}
  </main>;
}
