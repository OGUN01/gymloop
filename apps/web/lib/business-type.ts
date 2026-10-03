import { businessNouns, DEFAULT_BUSINESS_TYPE, isBusinessType, type BusinessType, type BusinessNouns } from '@gymloop/shared';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
import { cache } from 'react';

type BusinessOrganizationRead = {
  data: Pick<Database['public']['Tables']['organizations']['Row'], 'name' | 'gym_code' | 'timezone' | 'business_type'> | null;
  error: { message: string } | null;
};
// React owns the lifetime: separate client objects in one render share one
// snapshot, while the next request gets a new map and a fresh RLS read.
const requestOrganizations = cache(() => new Map<string, Promise<BusinessOrganizationRead>>());

export function loadBusinessOrganization(supabase: SupabaseClient<Database>, tenantId: string): Promise<BusinessOrganizationRead> {
  const snapshots = requestOrganizations();
  const existing = snapshots.get(tenantId);
  if (existing) return existing;
  const snapshot = (async (): Promise<BusinessOrganizationRead> => {
    try {
      return await supabase.from('organizations').select('name,gym_code,timezone,business_type').eq('id', tenantId).maybeSingle();
    } catch { return { data: null, error: { message: 'Business details could not be loaded.' } }; }
  })();
  snapshots.set(tenantId, snapshot);
  return snapshot;
}

export async function loadBusinessType(supabase: SupabaseClient<Database>, tenantId: string): Promise<BusinessType> {
  const { data, error } = await loadBusinessOrganization(supabase, tenantId);
  return !error && isBusinessType(data?.business_type) ? data.business_type : DEFAULT_BUSINESS_TYPE;
}
export async function loadBusinessNouns(supabase: SupabaseClient<Database>, tenantId: string): Promise<BusinessNouns> {
  return businessNouns(await loadBusinessType(supabase, tenantId));
}
