import {
  DEFAULT_TIMEZONE,
  GYM_PRESETS,
  ORGANIZATION_STATUSES,
  PLAN_TIERS,
  PLAN_TIER_PRICES_PAISE,
  rupeesFromPaise,
} from '@gymloop/shared';
import { Fragment } from 'react';
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

const label = (value: string) => value.replaceAll('_', ' ');
/** A vocabulary value as people say it: "pending_approval" → "Pending approval". */
const say = (value: string) => `${value.charAt(0).toUpperCase()}${label(value.slice(1))}`;
/** A camelCase provider key as words: "whatsappBusiness" → "Whatsapp business". */
const sayProvider = (key: string) => say(key.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`));
const DATE = new Intl.DateTimeFormat('en-IN', { day: 'numeric', month: 'short', year: 'numeric', timeZone: DEFAULT_TIMEZONE });
const when = (iso: string) => <time dateTime={iso}>{DATE.format(new Date(iso))}</time>;

export default async function PlatformPage() {
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

  return <main className="cl-page">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">{isAdmin ? 'Your platform’s gym directory' : 'Support access · read only'}</p>
        <h1 className="cl-title">Gyms</h1>
        <p className="cl-lede">
          {PLAN_TIERS.map((tier) => `${say(tier)} ₹${rupeesFromPaise(String(PLAN_TIER_PRICES_PAISE[tier]))}`).join(' · ')} per month
        </p>
      </div>
      {isAdmin ? <div className="cl-actions"><a href="#onboard" className="cl-btn cl-btn--accent">Add gym</a></div> : null}
    </div>

    <div className="cl-metrics">
      <div className="cl-metric"><span className="cl-eyebrow">Gyms</span><span className="cl-metric-value tabular-nums">{gyms.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Settings incomplete</span><span className="cl-metric-value tabular-nums">{exceptions.settingsIncomplete.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Owner access pending</span><span className="cl-metric-value tabular-nums">{exceptions.ownerAccessPending.length}</span></div>
      <div className="cl-metric"><span className="cl-eyebrow">Trial expired</span><span className="cl-metric-value tabular-nums">{exceptions.trialExpired.length}</span></div>
    </div>

    {!gyms.length ? <div className="cl-empty"><strong>No gyms yet.</strong><p>{isAdmin ? 'Onboard the first gym below.' : 'Gyms appear here once a platform admin onboards them.'}</p></div> : <>
      <section className="cl-section" aria-labelledby="fleet-heading">
        <div className="cl-section-head"><h2 id="fleet-heading" className="cl-section-title">Fleet</h2></div>
        <div className="cl-ledger-wrap">
          <table className="cl-ledger cl-ledger-stack">
            <thead><tr>
              <th scope="col">Gym</th><th scope="col">Status</th><th scope="col">Tier</th><th scope="col">Trial ends</th>
              <th scope="col" className="cl-num">Active members</th><th scope="col" className="cl-num">Open cases</th><th scope="col" className="cl-num">Failed notifications</th>
              <th scope="col">Readiness</th>
            </tr></thead>
            <tbody>
              {gyms.map((gym) => <tr key={gym.tenantId}>
                <td><a href={`/platform/${gym.tenantId}`} className="cl-row-title">{gym.name}</a> <span className="cl-row-meta">{gym.gymCode}</span></td>
                <td><StatusWord status={gym.status} /></td>
                <td>{gym.tier === null ? 'Unassigned' : say(gym.tier)}</td>
                <td>{gym.trialEndsAt === null ? 'Not set' : when(gym.trialEndsAt)}</td>
                <td className="cl-num">{gym.activeMembers ?? 'Unavailable'}</td>
                <td className="cl-num">{gym.openCases}</td>
                <td className="cl-num">{gym.failedNotifications}</td>
                <td>{gym.settingsComplete ? <StatusWord status="active" label="Activation ready" /> : <span className="cl-status" data-tone="warn">{`Readiness incomplete: ${gym.missingSettings.join(', ') || 'unknown'}`}</span>}</td>
              </tr>)}
            </tbody>
          </table>
        </div>
      </section>

      <section className="cl-section" aria-labelledby="gym-detail-heading">
        <div className="cl-section-head"><h2 id="gym-detail-heading" className="cl-section-title">{isAdmin ? 'Providers and controls' : 'Providers'}</h2></div>
        {gyms.map((gym) => {
          const gymOwners = owners.filter((owner) => owner.tenant_id === gym.tenantId);
          return <article key={gym.tenantId} className="cl-section" aria-label={gym.name}>
            <h3 className="cl-eyebrow">{gym.name} · {gym.gymCode}</h3>
            <dl className="cl-dl">{Object.entries(gym.providerReadiness).map(([provider, readiness]) =>
              <Fragment key={provider}><dt>{sayProvider(provider)}</dt><dd>{readiness.ready ? 'Ready' : say(readiness.reason)}</dd></Fragment>)}</dl>
            {gym.components.failedNotifications.length ? <details className="cl-disclosure"><summary>Failed notification evidence</summary><ul className="cl-rows">{gym.components.failedNotifications.map((failure) =>
              <li key={failure.notificationId}><span><span className="cl-row-title">{say(failure.channel)}</span><span className="cl-row-meta">{failure.failedReason ?? 'reason unavailable'}</span></span><span className="cl-muted">{failure.failedAt === null ? 'time unavailable' : when(failure.failedAt)}</span></li>)}</ul></details> : null}

            {isAdmin ? <div className="mt-4 grid gap-8 md:grid-cols-2">
              <form action={`/api/platform/gyms/${gym.tenantId}/status`} method="post" className="cl-form">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="expectedStatus" value={gym.status} />
                <div className="cl-form-row">
                  <label className="cl-field"><span>Status</span><select name="status" defaultValue={gym.status} className="cl-input">{ORGANIZATION_STATUSES.map((status) => <option key={status} value={status}>{say(status)}</option>)}</select></label>
                  <label className="cl-field"><span>Reason</span><input name="reason" className="cl-input" /></label>
                </div>
                <button type="submit" className="cl-btn self-start justify-self-start">Save status</button>
              </form>
              <form action={`/api/platform/gyms/${gym.tenantId}/tier`} method="post" className="cl-form">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="expectedTier" value={gym.tier ?? ''} />
                <label className="cl-field"><span>Tier</span><select name="tier" defaultValue={gym.tier ?? ''} className="cl-input"><option value="">Unassigned</option>{PLAN_TIERS.map((tier) => <option key={tier} value={tier}>{say(tier)} · ₹{rupeesFromPaise(String(PLAN_TIER_PRICES_PAISE[tier]))}/month</option>)}</select></label>
                <button type="submit" className="cl-btn self-start justify-self-start">Save tier</button>
              </form>
              <form action="/api/platform/impersonations" method="post" className="cl-form">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="tenantId" value={gym.tenantId} />
                <label className="cl-field"><span>Preview reason</span><input name="reason" required defaultValue="Support review" className="cl-input" /></label>
                <button type="submit" className="cl-btn self-start justify-self-start">Start preview</button>
              </form>
              {ownerLoadFailed ? <Alert>Owner-link details are temporarily unavailable.</Alert> : gymOwners.length ? gymOwners.map((owner) =>
                <form key={owner.id} action={`/api/platform/gyms/${gym.tenantId}/owner-link`} method="post" className="cl-form">
                  <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                  <input type="hidden" name="ownerStaffId" value={owner.id} />
                  <input type="hidden" name="expectedUserId" value={owner.user_id ?? ''} />
                  <p>Link owner profile: <strong>{owner.full_name}</strong></p>
                  <label className="cl-field"><span>Exact Auth email</span><input name="ownerEmail" type="email" required defaultValue={owner.email ?? ''} className="cl-input" /><small>Sign in again after this gym is activated.</small></label>
                  <button type="submit" className="cl-btn self-start justify-self-start">Link owner</button>
                </form>) : <p className="cl-muted">No active owner profile is available to link.</p>}
            </div> : null}
          </article>;
        })}
      </section>
    </>}

    {isAdmin ? <section className="cl-section" aria-labelledby="onboard-heading" id="onboard">
      <div className="cl-section-head"><h2 id="onboard-heading" className="cl-section-title">Onboard a gym</h2></div>
      <form action="/api/platform/gyms" method="post" className="cl-form">
        <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
        <input type="hidden" name="currency" value="INR" />
        <div className="cl-form-row">
          <label className="cl-field"><span>Gym name</span><input name="name" required className="cl-input" /></label>
          <label className="cl-field"><span>Timezone</span><input name="timezone" required defaultValue="Asia/Kolkata" className="cl-input" /></label>
          <label className="cl-field"><span>Preset</span><select name="preset" required className="cl-input">{GYM_PRESETS.map((preset) => <option key={preset} value={preset}>{say(preset)}</option>)}</select></label>
        </div>
        <div className="cl-form-row">
          <label className="cl-field"><span>Default branch</span><input name="branchName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner name</span><input name="ownerName" required className="cl-input" /></label>
          <label className="cl-field"><span>Owner email</span><input name="ownerEmail" type="email" className="cl-input" /></label>
        </div>
        <button type="submit" className="cl-btn cl-btn--primary self-start justify-self-start">Onboard</button>
      </form>
    </section> : null}
  </main>;
}
