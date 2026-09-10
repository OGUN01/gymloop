'use server';

import { offsetInstantFromGymWallTime } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { loadMemberSearch } from '../../../lib/members';
import { ADDON_OFFER_COLUMNS, type AddonOffer } from './display';

/** Read-only search action preserves client draft state while reusing roster pagination. */
export async function searchAddonMembers(q: string, cursor?: string) {
  await requireAudience('console');
  const search = await loadMemberSearch(Promise.resolve({ q, ...(cursor ? { cursor } : {}) }));
  return { members: search.members, nextCursor: search.nextCursor, failed: search.errorMessage !== null };
}

/** Interpret wall-clock fields in the verified gym's zone, never the browser's. */
export async function convertAddonSlot(startsAt: string, endsAt: string) {
  const { supabase, identity } = await requireAudience('console');
  const gym = await supabase.from('organizations').select('timezone').eq('id', identity.tenantId).maybeSingle();
  if (gym.error || !gym.data?.timezone) return null;
  const start = offsetInstantFromGymWallTime(startsAt, gym.data.timezone);
  const end = offsetInstantFromGymWallTime(endsAt, gym.data.timezone);
  return start && end ? { startsAt: start, endsAt: end } : null;
}

/** Refresh changed disclosure without discarding the member or sale draft. */
export async function refreshAddonOffer(productId: string) {
  const { supabase } = await requireAudience('console');
  const result = await supabase.from('addon_products').select(ADDON_OFFER_COLUMNS).eq('id', productId).maybeSingle();
  return result.error ? null : result.data as unknown as AddonOffer | null;
}
