import { noStore } from '../../../../lib/api';
import { commsOk, memberPushSession, pushRpc } from '../../../../lib/push-http';

/**
 * `POST /api/member/push-settings` — the member's own push settings projection
 * ({preferences, devices, pushConfigured}) from `read_member_push_settings()`.
 * A POST read seam keeps the mobile `ApiClient` (command-shaped, POST-only)
 * able to load the settings without granting it an ad-hoc query channel; the
 * web hydration path reads the same RPC through the browser session instead.
 * No body facts are accepted here — the read carries the session and nothing
 * else. `pushConfigured` is the honest provider state from the
 * pre-configuration amendment: while no push configuration revision is active
 * it is false and every surface says so — it never pretends delivery is
 * available.
 */
export async function POST(request: Request): Promise<Response> {
  const head = await memberPushSession(request, { signedOut: 'Sign in as a member first.', wrongAudience: 'Only your own member account can read your notification settings.' });
  if ('failure' in head) return head.failure;
  const result = await pushRpc<{ preferences?: unknown[]; devices?: unknown[]; pushConfigured?: unknown }>(head.session, 'read_member_push_settings', {});
  if ('failure' in result) return result.failure;
  return noStore(commsOk('ok', {
    preferences: Array.isArray(result.row.preferences) ? result.row.preferences : [],
    devices: Array.isArray(result.row.devices) ? result.row.devices : [],
    // The provider-configuration truth rides with the settings row once SQL
    // publishes it; until then the only honest value is unconfigured.
    pushConfigured: typeof result.row.pushConfigured === 'boolean' ? result.row.pushConfigured : false,
  }));
}
