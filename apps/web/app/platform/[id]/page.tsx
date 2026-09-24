import { DEFAULT_TIMEZONE, formatDateTime, formatDay, humanize } from '@gymloop/shared';
import { Fragment } from 'react';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { fleetMetrics } from '../../../lib/platform';
import { Alert } from '../../(console)/alert';
import { StatusWord } from '../../status-word';

/** Why a provider is not ready, as a dot and words an operator can act on (the contract's codes stay out of the UI). */
const PROVIDER_STATES: Record<string, { status: string; label: string }> = {
  provider_unconfigured: { status: 'pending', label: 'Not set up yet' },
  outside_v1: { status: 'unavailable', label: 'Not offered yet' },
};
/** Timezones as an operator says them; anything else shows its IANA name. */
const TIMEZONE_NAMES: Record<string, string> = { 'Asia/Kolkata': 'India (IST)' };

/**
 * One gym, read only: the same facts as its fleet row, then readiness,
 * messaging providers and failed-send evidence. The status, tier, preview and
 * owner-link controls live with the fleet (`/platform?manage=<id>`), so a
 * super admin reaches them from here in one step and support never sees them.
 */
export default async function PlatformGymPage({ params }: { params: Promise<{ id: string }> }) {
  const { supabase, identity } = await requireAudience('platform');
  const { id } = await params;
  if (!UUID_PATTERN.test(id)) return <main className="cl-page"><Alert>That gym is not available.</Alert></main>;
  const result = await fleetMetrics(supabase);
  if ('error' in result) return <main className="cl-page"><Alert>We couldn’t load this gym’s details. Please try again.</Alert></main>;
  const gym = result.data.gyms.find((row) => row.tenantId === id);
  if (!gym) return <main className="cl-page"><Alert>That gym is not available.</Alert></main>;

  const isAdmin = identity.role === 'super_admin';
  // Owner names are a super-admin read, exactly as on the fleet screen; support sees only whether access is linked.
  const staffRead = isAdmin
    ? await supabase.from('staff').select('tenant_id,full_name,email,role,is_active,user_id').order('tenant_id').order('id')
    : null;
  const ownerNames = (staffRead?.data ?? [])
    .filter((row) => row.tenant_id === gym.tenantId && row.role === 'gym_owner' && row.is_active)
    .map((row) => row.full_name);
  const zone = gym.metricsError === null ? gym.timezone : DEFAULT_TIMEZONE;
  const trialDay = gym.trialEndsAt === null ? null : formatDay(new Intl.DateTimeFormat('en-CA', { year: 'numeric', month: '2-digit', day: '2-digit', timeZone: zone }).format(new Date(gym.trialEndsAt)));

  return <main className="cl-page platform-gym">
    <a href="/platform" className="cl-back">← All gyms</a>
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Gym code · {gym.gymCode}</p>
        <h1 className="cl-title">{gym.name}</h1>
        <p className="cl-lede platform-gym-lede">
          <StatusWord status={gym.status} />
          <span>{gym.tier === null ? 'No tier' : `${humanize(gym.tier)} tier`}</span>
          <span>{TIMEZONE_NAMES[gym.timezone] ?? gym.timezone}</span>
        </p>
      </div>
      {isAdmin ? <div className="cl-actions"><a href={`/platform?manage=${gym.tenantId}#manage-${gym.tenantId}`} className="cl-btn cl-btn--primary">Manage gym</a></div> : null}
    </div>

    <div className="cl-metrics platform-kpis">
      <div className="cl-metric"><span className="cl-eyebrow">Active members</span><span className="cl-metric-value tabular-nums">{gym.activeMembers ?? '—'}</span><small>{gym.activeMembers === null ? 'Unavailable' : 'With a live membership'}</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Open cases</span><span className="cl-metric-value tabular-nums">{gym.openCases}</span><small>Members to bring back</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Failed sends</span><span className="cl-metric-value tabular-nums">{gym.failedNotifications}</span><small>Messages that did not go out</small></div>
      <div className="cl-metric"><span className="cl-eyebrow">Trial ends</span>{trialDay === null
        ? <><span className="cl-metric-value" aria-hidden="true">—</span><small>No trial</small></>
        : <><span className="cl-metric-value tabular-nums"><time dateTime={gym.trialEndsAt ?? ''}>{trialDay.split(' ').slice(0, -1).join(' ')}</time></span><small>{trialDay}</small></>}</div>
    </div>

    <div className="platform-gym-grid">
      <section className="cl-section" aria-labelledby="readiness-heading">
        <div className="cl-section-head"><h2 id="readiness-heading" className="cl-section-title">Readiness</h2></div>
        <dl className="cl-dl">
          <dt>Settings</dt>
          <dd>{gym.settingsComplete ? <StatusWord status="ready" label="Activation ready" /> : <StatusWord status="pending" label={`Readiness incomplete: ${gym.missingSettings.map(humanize).join(', ') || 'unknown'}`} />}</dd>
          <dt>Owner</dt>
          <dd className="platform-gym-owner">
            {gym.ownerAccessPending ? <StatusWord status="pending" label="Owner access pending" /> : <StatusWord status="ready" label="Owner access linked" />}
            {ownerNames.length > 0 ? <span className="cl-row-meta">{ownerNames.join(', ')}</span> : null}
          </dd>
        </dl>
      </section>

      <section className="cl-section" aria-labelledby="providers-heading">
        <div className="cl-section-head"><h2 id="providers-heading" className="cl-section-title">Messaging providers</h2></div>
        <dl className="cl-dl">
          {Object.entries(gym.providerReadiness).map(([provider, readiness]) => {
            const state = readiness.ready ? { status: 'ready', label: 'Ready' } : PROVIDER_STATES[readiness.reason] ?? { status: readiness.reason, label: humanize(readiness.reason) };
            return <Fragment key={provider}><dt>{humanize(provider)}</dt><dd><StatusWord status={state.status} label={state.label} /></dd></Fragment>;
          })}
        </dl>
      </section>
    </div>

    {gym.components.failedNotifications.length ? <section className="cl-section" aria-labelledby="failures-heading">
      <div className="cl-section-head"><h2 id="failures-heading" className="cl-section-title">Failed sends</h2></div>
      <ul className="cl-rows">{gym.components.failedNotifications.map((failure) =>
        <li key={failure.notificationId}>
          <span><span className="cl-row-title">{humanize(failure.channel)}</span><span className="cl-row-meta">{failure.failedReason === null ? 'Reason unavailable' : humanize(failure.failedReason)}</span></span>
          <span className="cl-muted tabular-nums">{failure.failedAt === null ? 'Time unavailable' : <time dateTime={failure.failedAt}>{formatDateTime(failure.failedAt, zone)}</time>}</span>
        </li>)}
      </ul>
    </section> : null}
  </main>;
}
