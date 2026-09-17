import { startGymPreviewRequestSchema } from '@gymloop/shared';
import { expireSupabaseAuthCookies } from '../../../../lib/api';
import { commandSuccess, platformAdminRequest, platformError } from '../../../../lib/platform';
import { readIdentity } from '../../../../lib/identity-session';
import { identityHome } from '../../../../lib/identity';
import { seeOther } from '../../../../lib/api';

export async function POST(request: Request): Promise<Response> {
  const command = await platformAdminRequest(request, startGymPreviewRequestSchema, 'That preview request was not readable.');
  if ('failure' in command) return command.failure;
  const { tenantId, reason, requestKey } = command.data;
  const { data, error } = await command.client.rpc('start_gym_preview' as never, { p_tenant_id: tenantId, p_reason: reason, p_request_key: requestKey } as never) as never;
  if (error) return platformError(error);
  if (!data) return platformError({ code: 'XX000' });
  let refreshFailed: boolean;
  try {
    refreshFailed = Boolean((await command.client.auth.refreshSession()).error);
  } catch {
    refreshFailed = true;
  }
  if (refreshFailed) {
    try { await command.client.auth.signOut({ scope: 'local' }); } catch { /* cookie expiry below */ }
    return expireSupabaseAuthCookies(request, seeOther(request, '/sign-in'));
  }
  if ((request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) return commandSuccess(request, data, '/console');
  const refreshed = await readIdentity(command.client);
  return seeOther(request, identityHome(refreshed.identity));
}
