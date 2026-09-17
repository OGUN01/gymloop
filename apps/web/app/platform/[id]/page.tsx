import { requireAudience } from '../../../lib/identity-session';
import { UUID_PATTERN } from '../../../lib/keyset';

export default async function PlatformGymPage({ params }: { params: Promise<{ id: string }> }) {
  const { supabase } = await requireAudience('platform');
  const { id } = await params;
  if (!UUID_PATTERN.test(id)) return <main className="p-8"><p role="alert">That gym is not available.</p></main>;
  const [{ data: gym, error: gymError }, { data: readiness, error: readinessError }] = await Promise.all([
    supabase.from('organizations').select('id,name,gym_code,status,tier,timezone,currency,trial_ends_at,activated_at').eq('id', id).maybeSingle(),
    supabase.rpc('gym_readiness' as never, { p_tenant_id: id } as never),
  ]);
  if (gymError || readinessError) return <main className="p-8"><p role="alert">We couldn’t load this gym’s details. Please try again.</p></main>;
  if (!gym) return <main className="p-8"><p role="alert">That gym is not available.</p></main>;
  return <main className="mx-auto max-w-4xl px-6 py-8"><h1 className="text-2xl font-semibold">{gym.name}</h1><p className="mt-1 text-neutral-500">{gym.gym_code} · {gym.status} · {gym.tier ?? 'Unassigned'}</p><section className="mt-8 rounded border p-5"><h2 className="font-semibold">Readiness</h2><pre className="mt-3 overflow-auto text-sm">{JSON.stringify(readiness ?? null)}</pre></section></main>;
}
