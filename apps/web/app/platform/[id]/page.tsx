import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';
import { fleetMetrics } from '../../../lib/platform';

export default async function PlatformGymPage({ params }: { params: Promise<{ id: string }> }) {
  const { supabase } = await requireAudience('platform');
  const { id } = await params;
  if (!UUID_PATTERN.test(id)) return <main className="p-8"><p role="alert">That gym is not available.</p></main>;
  const result = await fleetMetrics(supabase);
  if ('error' in result) return <main className="p-8"><p role="alert">We couldn’t load this gym’s details. Please try again.</p></main>;
  const gym = result.data.gyms.find((row) => row.tenantId === id);
  if (!gym) return <main className="p-8"><p role="alert">That gym is not available.</p></main>;
  return <main className="mx-auto max-w-4xl px-6 py-8">
    <h1 className="text-2xl font-semibold">{gym.name}</h1>
    <p className="mt-1 text-neutral-500">{gym.gymCode} · {gym.status} · {gym.tier ?? 'Unassigned'} · {gym.timezone}</p>
    <section className="mt-8 rounded border p-5">
      <h2 className="font-semibold">Readiness</h2>
      <p>{gym.settingsComplete ? 'Activation ready' : `Readiness incomplete: ${gym.missingSettings.join(', ') || 'unknown'}`}</p>
      <p>{gym.ownerAccessPending ? 'Owner access pending' : 'Owner access linked'}</p>
      <ul>{Object.entries(gym.providerReadiness).map(([provider, readiness]) =>
        <li key={provider}>{provider}: {readiness.ready ? 'ready' : readiness.reason}</li>)}</ul>
    </section>
  </main>;
}
