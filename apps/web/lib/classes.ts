import { readMemberClasses, readClassTimetable, readClassRoster, type ClassReadClient, type ClassReadWindow } from '@gymloop/shared';
import type { SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@gymloop/db';
export function loadMemberClassSchedule(client: SupabaseClient<Database>, window: ClassReadWindow) { return readMemberClasses(client as unknown as ClassReadClient, window); }
export function loadClassTimetable(client: SupabaseClient<Database>, window: ClassReadWindow & { branchId: string | null }) { return readClassTimetable(client as unknown as ClassReadClient, window); }
export function loadClassRoster(client: SupabaseClient<Database>, sessionId: string) { return readClassRoster(client as unknown as ClassReadClient, sessionId); }
export async function loadServices(client: SupabaseClient<Database>) { try { const result = await client.from('services').select('id,name,description,default_duration_minutes,default_capacity,is_active,sort_order').order('sort_order').order('name').order('id'); return result.error ? null : result.data; } catch { return null; } }
export async function loadClassRules(client: SupabaseClient<Database>) { try { const result = await client.from('class_rules').select('id,service_id,branch_id,weekday,start_time,duration_minutes,capacity,trainer_staff_id,valid_from,valid_until,is_active').order('weekday').order('start_time').order('id'); return result.error ? null : result.data; } catch { return null; } }
export async function loadClassSettings(client: SupabaseClient<Database>) { try { const result = await client.from('organization_settings').select('class_cancel_window_hours,class_allow_cross_branch').maybeSingle(); return result.error ? null : result.data; } catch { return null; } }
export async function loadClassVisibility(client: SupabaseClient<Database>): Promise<boolean | null> {
  try {
    const result = await client.from('organization_settings').select('member_classes_enabled').maybeSingle();
    return !result.error && typeof result.data?.member_classes_enabled === 'boolean' ? result.data.member_classes_enabled : null;
  } catch { return null; }
}
