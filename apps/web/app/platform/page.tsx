import { requireAudience } from '../../lib/identity-session';
import { gymTimeLabel } from '../../lib/payments';

export default async function PlatformPage() {
  const { supabase, identity } = await requireAudience('platform');
  const { data: gyms, error } = await supabase.from('organizations')
    .select('id,name,gym_code,status,tier,timezone,trial_ends_at').order('name').order('id');
  return (
    <main className="mx-auto max-w-6xl px-6 py-8">
      <h1 className="text-2xl font-semibold">Gyms</h1>
      <p className="mt-2 text-neutral-600">{identity.role === 'platform_support' ? 'Support access · read only' : 'Your platform’s gym directory'}</p>
      {error ? <p role="alert" className="mt-6">We couldn’t load the gyms. Please try again.</p> :
        !gyms?.length ? <p className="mt-6 text-neutral-600">No gyms yet.</p> :
        <div className="mt-6 overflow-x-auto"><table className="w-full text-left text-sm">
          <thead><tr className="border-b border-neutral-200">
            {['Gym', 'Code', 'Status', 'Tier', 'Trial ends (gym time)'].map((label) => <th key={label} scope="col" className="px-3 py-3 font-medium">{label}</th>)}
          </tr></thead>
          <tbody>{gyms.map((gym) => <tr key={gym.id} className="border-b border-neutral-100">
            <td className="px-3 py-4 font-medium">{gym.name}</td>
            <td className="px-3 py-4">{gym.gym_code}</td>
            <td className="px-3 py-4">{gym.status}</td>
            <td className="px-3 py-4">{gym.tier ?? 'Not assigned'}</td>
            <td className="px-3 py-4">{gym.trial_ends_at ? gymTimeLabel(gym.trial_ends_at, gym.timezone) : 'Not set'}</td>
          </tr>)}</tbody>
        </table></div>}
    </main>
  );
}
