import {
  DEFAULT_TIMEZONE,
  GYM_PRESETS,
  ORGANIZATION_STATUSES,
  PLAN_TIERS,
  PLAN_TIER_PRICES_PAISE,
  UI_TOKENS,
  formatDay,
  formatMoney,
  humanize,
} from '@gymloop/shared';
import { ChevronDown, ChevronRight, Plus } from 'lucide-react';
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
/** Time zones offered when adding a gym: human labels, IANA ids stored (the database accepts any `pg_timezone_names` entry). */
const TIMEZONE_CHOICES = [
  { id: 'Asia/Kolkata', label: 'India (IST)' },
  { id: 'Asia/Kathmandu', label: 'Nepal (NPT)' },
  { id: 'Asia/Colombo', label: 'Sri Lanka (SLST)' },
  { id: 'Asia/Dhaka', label: 'Bangladesh (BST)' },
  { id: 'Asia/Dubai', label: 'United Arab Emirates (GST)' },
] as const;
/** A gym with no tier yet, said as a state rather than as missing data. */
const NO_TIER = 'No plan yet';
/** A column label shown only where the ledger stacks into cards (under 40rem). */
const Cell = ({ label }: { label: string }) => <span className="platform-cell-label">{label}</span>;
/** Non-breaking space: keeps "Pro ₹4,999 a month" and each "·" with its plan when the plans line wraps. */
const NBSP = '\u00a0';
/** A 16px Lucide glyph at the kit's stroke. */
const iconProps = { 'aria-hidden': true, size: UI_TOKENS.icons.controlSize, strokeWidth: UI_TOKENS.icons.strokeWidth } as const;

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
        <p className="cl-eyebrow">{isAdmin ? 'Platform' : 'Platform · support access, read only'}</p>
        <h1 className="cl-title">Gyms</h1>
        <p className="cl-lede platform-plans">
          Plans: {PLAN_TIERS.map((tier) => `${humanize(tier)}${NBSP}${tierPrice(tier)}`).join(`${NBSP}· `)}{NBSP}a{NBSP}month
        </p>
      </div>
      {/* The header only jumps to the form below; "Create gym" is the clay commit, so this is the outline anchor. */}
      {isAdmin ? <div className="cl-actions"><a href="#onboard" className="cl-btn"><Plus {...iconProps} />Add gym</a></div> : null}
    </div>

    <div className="cl-metrics platform-kpis">
      <div className="cl-metric"><span className="cl-eyebrow">Gyms</span><span className="cl-metric-value tabular-nums">{gyms.length}</span><small>In every status</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Needs setup</span><span className="cl-metric-value tabular-nums">{exceptions.settingsIncomplete.length}</span><small>Not ready to go live</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Owner pending</span><span className="cl-metric-value tabular-nums">{exceptions.ownerAccessPending.length}</span><small>Owner can’t sign in yet</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Trial expired</span><span className="cl-metric-value tabular-nums">{exceptions.trialExpired.length}</span><small>Past the trial end date</small></div>
    </div>

    {!gyms.length ? <div className="cl-empty"><strong>No gyms yet.</strong><p>{isAdmin ? 'Onboard the first gym below.' : 'Gyms appear here once a platform admin onboards them.'}</p></div> : <>
      <section className="cl-section platform-zone" aria-labelledby="fleet-heading">
        <div className="platform-zone-head">
          <h2 id="fleet-heading" className="cl-section-title">Fleet</h2>
          <p className="cl-muted">Every gym on the platform. Open one for its readiness and failed sends.</p>
        </div>
        <div className="cl-ledger-wrap">
          <table className="cl-ledger platform-ledger">
            <thead><tr>
              <th scope="col">Gym</th><th scope="col">Status</th><th scope="col" className="platform-col-wide">Tier</th><th scope="col" className="platform-col-mid">Trial ends</th>
              <th scope="col" className="cl-num">Members</th><th scope="col" className="cl-num platform-col-mid">Open cases</th><th scope="col" className="cl-num">Failed sends</th>
              <th scope="col" className="platform-col-readiness">Readiness</th><th scope="col"><span className="sr-only">Open</span></th>
            </tr></thead>
            <tbody>
              {gyms.map((gym) => <tr key={gym.tenantId}>
                <td className="platform-cell-gym"><span className="cl-row-title">{gym.name}</span><span className="cl-row-meta">{gym.gymCode}</span></td>
                <td className="platform-cell-status"><StatusWord status={gym.status} /></td>
                <td className="platform-cell-fact platform-cell-plan platform-col-wide"><Cell label="Tier" /><span>{gym.tier === null ? NO_TIER : humanize(gym.tier)}</span></td>
                <td className="platform-cell-fact platform-cell-plan platform-col-mid"><Cell label="Trial ends" /><span>{gym.trialEndsAt === null ? 'No trial' : dayOf(gym.trialEndsAt, zoneOf(gym))}</span></td>
                <td className="cl-num platform-cell-fact platform-cell-count"><Cell label="Members" /><span>{gym.activeMembers ?? 'Unavailable'}</span></td>
                <td className="cl-num platform-cell-fact platform-cell-count platform-col-mid"><Cell label="Open cases" /><span>{gym.openCases}</span></td>
                <td className="cl-num platform-cell-fact platform-cell-count"><Cell label="Failed sends" /><span>{gym.failedNotifications}</span></td>
                <td className="platform-cell-readiness platform-col-readiness">{gym.settingsComplete ? <StatusWord status="ready" label="Activation ready" /> : <StatusWord status="pending" label={`Readiness incomplete: ${gym.missingSettings.map(humanize).join(', ') || 'unknown'}`} />}</td>
                <td className="platform-cell-open"><a href={`/platform/${gym.tenantId}`} className="platform-open-link" aria-label={`Open ${gym.name}`}>Open<ChevronRight {...iconProps} /></a></td>
              </tr>)}
            </tbody>
          </table>
        </div>
      </section>

      {isAdmin ? <section className="cl-section platform-zone" aria-labelledby="manage-heading">
        <div className="platform-zone-head">
          <h2 id="manage-heading" className="cl-section-title">Manage gyms</h2>
          <p className="cl-muted">Status, tier, support preview and owner sign-in for each gym. Open one to change it.</p>
        </div>
        {gyms.map((gym) => {
          const gymOwners = owners.filter((owner) => owner.tenant_id === gym.tenantId);
          return <details key={gym.tenantId} id={`manage-${gym.tenantId}`} className="cl-disclosure platform-manage" open={manage === gym.tenantId}>
            <summary>
              <span className="platform-manage-title"><span className="platform-manage-name">{gym.name}</span><StatusWord status={gym.status} /></span>
              <span className="platform-manage-toggle" aria-hidden="true">Manage<ChevronDown {...iconProps} /></span>
            </summary>
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
                <label className="cl-field platform-control-wide"><span>Tier</span><select name="tier" defaultValue={gym.tier ?? ''} className="cl-input"><option value="">{NO_TIER}</option>{PLAN_TIERS.map((tier) => <option key={tier} value={tier}>{humanize(tier)} · {tierPrice(tier)}/month</option>)}</select></label>
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

    {isAdmin ? <section className="cl-section platform-zone platform-onboard" aria-labelledby="onboard-heading" id="onboard">
      <div className="platform-zone-head">
        <h2 id="onboard-heading" className="cl-section-title">Add a gym</h2>
        <p className="cl-muted">Creates the gym, its first branch and its owner, and starts the trial.</p>
      </div>
      <form action="/api/platform/gyms" method="post" className="cl-form">
        <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
        <input type="hidden" name="currency" value="INR" />
        <div className="cl-form-row">
          <label className="cl-field"><span>Gym name</span><input name="name" required className="cl-input" /></label>
          <label className="cl-field"><span>Time zone</span><select name="timezone" required defaultValue="Asia/Kolkata" className="cl-input">{TIMEZONE_CHOICES.map((zone) => <option key={zone.id} value={zone.id}>{zone.label}</option>)}</select></label>
          <label className="cl-field"><span>Preset</span><select name="preset" required className="cl-input">{GYM_PRESETS.map((preset) => <option key={preset} value={preset}>{humanize(preset)}</option>)}</select></label>
        </div>
        <div className="cl-form-row">
          <label className="cl-field"><span>Default branch</span><input name="branchName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner name</span><input name="ownerName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner email</span><input name="ownerEmail" type="email" className="cl-input" /></label>
        </div>
        <button type="submit" className="cl-btn cl-btn--primary">Create gym</button>
      </form>
    </section> : null}
  </main>;
}
