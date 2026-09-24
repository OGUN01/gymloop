import { Fragment } from 'react';
import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { fleetMetrics } from '../../../lib/platform';
import { humanize } from '@gymloop/shared';
import { Alert } from '../../(console)/alert';
import { StatusWord } from '../../status-word';

/** Why a provider is not ready, in words an operator can act on (the contract's codes stay out of the UI). */
const PROVIDER_REASONS: Record<string, string> = {
  provider_unconfigured: 'Not set up yet',
  outside_v1: 'Not offered yet',
};

export default async function PlatformGymPage({ params }: { params: Promise<{ id: string }> }) {
  const { supabase } = await requireAudience('platform');
  const { id } = await params;
  if (!UUID_PATTERN.test(id)) return <main className="cl-page"><Alert>That gym is not available.</Alert></main>;
  const result = await fleetMetrics(supabase);
  if ('error' in result) return <main className="cl-page"><Alert>We couldn’t load this gym’s details. Please try again.</Alert></main>;
  const gym = result.data.gyms.find((row) => row.tenantId === id);
  if (!gym) return <main className="cl-page"><Alert>That gym is not available.</Alert></main>;
  return <main className="cl-page">
    <a href="/platform" className="cl-back">← All gyms</a>
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">{gym.gymCode}</p>
        <h1 className="cl-title">{gym.name}</h1>
        <p className="cl-lede">{gym.tier === null ? 'Unassigned' : humanize(gym.tier)} · {gym.timezone}</p>
      </div>
      <div className="cl-actions"><StatusWord status={gym.status} /></div>
    </div>
    <section className="cl-section" aria-labelledby="readiness-heading">
      <div className="cl-section-head"><h2 id="readiness-heading" className="cl-section-title">Readiness</h2></div>
      <dl className="cl-dl">
        <dt>Settings</dt><dd>{gym.settingsComplete ? 'Activation ready' : `Readiness incomplete: ${gym.missingSettings.map(humanize).join(', ') || 'unknown'}`}</dd>
        <dt>Owner</dt><dd>{gym.ownerAccessPending ? 'Owner access pending' : 'Owner access linked'}</dd>
        {Object.entries(gym.providerReadiness).map(([provider, readiness]) =>
          <Fragment key={provider}><dt>{humanize(provider)}</dt><dd>{readiness.ready ? 'Ready' : PROVIDER_REASONS[readiness.reason] ?? humanize(readiness.reason)}</dd></Fragment>)}
      </dl>
    </section>
  </main>;
}
