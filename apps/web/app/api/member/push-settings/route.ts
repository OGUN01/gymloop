import { readRequestIdentity } from '../../../../lib/identity-session';
import { apiFail, noStore } from '../../../../lib/api';
import { commsOk, commsRpcFailure } from '../../../../lib/comms';

/**
 * `POST /api/member/push-settings` — the member's own push settings projection
 * ({preferences, devices, pushConfigured}) from `read_member_push_settings()`.
 * A POST read seam keeps the mobile `ApiClient` (command-shaped, POST-only)
 * able to load the settings without granting it an ad-hoc query channel; the
 * web hydration path reads the same RPC through the browser session instead.
 * `pushConfigured` is the honest provider state from the pre-configuration
 * amendment: while no push configuration revision is active it is false and
 * every surface says so — it never pretends delivery is available.
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return noStore(apiFail('unauthorized', 'not_signed_in', 'Sign in as a member first.'));
  if (caller.identity.kind !== 'member') return noStore(apiFail('forbidden', 'not_permitted', 'Only your own member account can read your notification settings.'));

  // No body facts are accepted here; the settings cannot be filtered or
  // shaped by caller input. Body parsing is skipped entirely rather than
  // validated, so the read carries the session and nothing else.
  const reader = caller.supabase as unknown as {
    rpc(name: 'read_member_push_settings'):
      Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await reader.rpc('read_member_push_settings');
  if (error) return noStore(commsRpcFailure(error));
  const row = Array.isArray(data) ? (data[0] ?? null) : data;
  if (row === null || typeof row !== 'object') {
    return noStore(apiFail('server_error', 'operation_failed', 'Notification settings could not be read. Try again.'));
  }
  const settings = row as { preferences?: unknown; devices?: unknown };
  return noStore(commsOk('ok', {
    preferences: Array.isArray(settings.preferences) ? settings.preferences : [],
    devices: Array.isArray(settings.devices) ? settings.devices : [],
    // The provider-configuration truth rides with the settings row once SQL
    // publishes it; until then the only honest value is unconfigured.
    pushConfigured: typeof (row as { pushConfigured?: unknown }).pushConfigured === 'boolean'
      ? (row as { pushConfigured: boolean }).pushConfigured
      : false,
  }));
}
