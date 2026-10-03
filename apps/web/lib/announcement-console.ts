import { notFound } from 'next/navigation';
import { requireAudience } from './identity-session';
import { FRONT_OFFICE_ROLES } from './leads';
import { loadBusinessNouns } from './business-type';
import { canPublishAnnouncements } from './announcements';
import { DEFAULT_TIMEZONE } from '@gymloop/shared';
export async function announcementConsole() {
  const caller = await requireAudience('console');
  if (caller.identity.kind === 'staff' && !FRONT_OFFICE_ROLES.includes(caller.identity.role as typeof FRONT_OFFICE_ROLES[number])) notFound();
  const [nouns, gym] = await Promise.all([loadBusinessNouns(caller.supabase, caller.identity.tenantId), caller.supabase.from('organizations').select('timezone').eq('id', caller.identity.tenantId).maybeSingle()]);
  return { ...caller, nouns, timezone: gym.data?.timezone ?? DEFAULT_TIMEZONE, preview: caller.identity.kind === 'impersonation', canPublish: canPublishAnnouncements(caller.identity) };
}
