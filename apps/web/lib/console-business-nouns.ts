import { loadBusinessNouns } from './business-type';
import { requireAudience } from './identity-session';

/** Console pages that need only vocabulary share the existing audience guard. */
export async function loadConsoleBusinessNouns() {
  const caller = await requireAudience('console');
  return loadBusinessNouns(caller.supabase, caller.identity.tenantId);
}
