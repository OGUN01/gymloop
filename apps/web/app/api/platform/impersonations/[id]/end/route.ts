import { apiFail, platformSession } from '../../../../../../lib/api';
import { commandSuccess, platformError } from '../../../../../../lib/platform';
import { UUID_PATTERN } from '../../../../../../lib/keyset';

export async function POST(_request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  const caller = await platformSession({ requireAdmin: true });
  if ('failure' in caller) return caller.failure;
  const id = (await context?.params)?.id;
  if (!(typeof id === 'string' && UUID_PATTERN.test(id))) return apiFail('bad_request', 'invalid_request', 'That preview id was not readable.');
  const { data, error } = await caller.session.supabase.rpc('end_expired_gym_preview' as never, { p_session_id: id } as never) as never;
  if (error) return platformError(error);
  if (!data) return platformError({ code: 'XX000' });
  return commandSuccess(_request, data, '/platform');
}



