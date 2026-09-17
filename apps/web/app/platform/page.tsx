import {
  GYM_PRESETS,
  ORGANIZATION_STATUSES,
  PLAN_TIERS,
  PLAN_TIER_PRICES_PAISE,
  rupeesFromPaise,
} from '@gymloop/shared';
import { requireAudience } from '../../lib/identity-session';
import { fleetMetrics } from '../../lib/platform';

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

export default async function PlatformPage() {
  const { supabase, identity } = await requireAudience('platform');
  const result = await fleetMetrics(supabase);
  if ('error' in result) {
    return <main className="p-8"><p role="alert">We couldn’t load the gym fleet. Please try again.</p></main>;
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

  const { gyms } = result.data;
  const isAdmin = identity.role === 'super_admin';

  return <main className="mx-auto max-w-6xl px-6 py-8">
    <h1 className="text-2xl font-semibold">Gyms</h1>
    <p className="mt-2 text-neutral-600">{isAdmin ? 'Your platform’s gym directory' : 'Support access · read only'}</p>
    <p className="mt-2 text-sm text-neutral-500">
      {PLAN_TIERS.map((tier) => `${label(tier)} ₹${rupeesFromPaise(String(PLAN_TIER_PRICES_PAISE[tier]))}`).join(' · ')} per month
    </p>

    {isAdmin ? <form action="/api/platform/gyms" method="post" className="mt-4 grid gap-2 rounded border p-4">
      <h2 className="font-semibold">Onboard a gym</h2>
      <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
      <input type="hidden" name="currency" value="INR" />
      <label>Gym name <input name="name" required /></label>
      <label>Timezone <input name="timezone" required defaultValue="Asia/Kolkata" /></label>
      <label>Preset <select name="preset" required>{GYM_PRESETS.map((preset) => <option key={preset} value={preset}>{label(preset)}</option>)}</select></label>
      <label>Default branch <input name="branchName" required /></label>
      <label>Owner name <input name="ownerName" required /></label>
      <label>Owner email <input name="ownerEmail" type="email" /></label>
      <button type="submit">Onboard</button>
    </form> : null}

    {!gyms.length ? <p className="mt-6">No gyms yet.</p> : <div className="mt-6 grid gap-5">
      {gyms.map((gym) => {
        const gymOwners = owners.filter((owner) => owner.tenant_id === gym.tenantId);
        return <article key={gym.tenantId} className="rounded border p-5">
          <h2 className="text-lg font-semibold"><a className="underline" href={`/platform/${gym.tenantId}`}>{gym.name}</a></h2>
          <p className="text-sm text-neutral-500">{gym.gymCode} · {gym.status} · {gym.tier ?? 'unassigned'} · trial ends {gym.trialEndsAt ?? 'not set'}</p>
          <p className="mt-3">Active members: {gym.activeMembers ?? 'unavailable'} · Open cases: {gym.openCases} · Failed notifications: {gym.failedNotifications}</p>
          <p>{gym.settingsComplete ? 'Activation ready' : `Readiness incomplete: ${gym.missingSettings.join(', ') || 'unknown'}`}</p>
          <ul className="mt-2 text-sm">{Object.entries(gym.providerReadiness).map(([provider, readiness]) =>
            <li key={provider}>{label(provider)}: {readiness.ready ? 'ready' : readiness.reason}</li>)}</ul>
          {gym.components.failedNotifications.length ? <details className="mt-2"><summary>Failed notification evidence</summary><ul>{gym.components.failedNotifications.map((failure) =>
            <li key={failure.notificationId}>{failure.channel} · {failure.failedAt ?? 'time unavailable'} · {failure.failedReason ?? 'reason unavailable'}</li>)}</ul></details> : null}

          {isAdmin ? <div className="mt-4 grid gap-3 border-t pt-4">
            <form action={`/api/platform/gyms/${gym.tenantId}/status`} method="post">
              <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
              <input type="hidden" name="expectedStatus" value={gym.status} />
              <label>Status <select name="status" defaultValue={gym.status}>{ORGANIZATION_STATUSES.map((status) => <option key={status} value={status}>{label(status)}</option>)}</select></label>
              <label>Reason <input name="reason" /></label>
              <button type="submit">Save status</button>
            </form>
            <form action={`/api/platform/gyms/${gym.tenantId}/tier`} method="post">
              <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
              <input type="hidden" name="expectedTier" value={gym.tier ?? ''} />
              <label>Tier <select name="tier" defaultValue={gym.tier ?? ''}><option value="">Unassigned</option>{PLAN_TIERS.map((tier) => <option key={tier} value={tier}>{label(tier)} · ₹{rupeesFromPaise(String(PLAN_TIER_PRICES_PAISE[tier]))}/month</option>)}</select></label>
              <button type="submit">Save tier</button>
            </form>
            <form action="/api/platform/impersonations" method="post">
              <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
              <input type="hidden" name="tenantId" value={gym.tenantId} />
              <label>Preview reason <input name="reason" required defaultValue="Support review" /></label>
              <button type="submit">Start preview</button>
            </form>
            {ownerLoadFailed ? <p role="alert">Owner-link details are temporarily unavailable.</p> : gymOwners.length ? gymOwners.map((owner) =>
              <form key={owner.id} action={`/api/platform/gyms/${gym.tenantId}/owner-link`} method="post">
                <input type="hidden" name="requestKey" value={crypto.randomUUID()} />
                <input type="hidden" name="ownerStaffId" value={owner.id} />
                <input type="hidden" name="expectedUserId" value={owner.user_id ?? ''} />
                <p>Link owner profile: {owner.full_name}</p>
                <label>Exact Auth email <input name="ownerEmail" type="email" required defaultValue={owner.email ?? ''} /></label>
                <button type="submit">Link owner</button>
                <p className="text-xs">Sign in again after this gym is activated.</p>
              </form>) : <p>No active owner profile is available to link.</p>}
          </div> : null}
        </article>;
      })}
    </div>}
  </main>;
}
