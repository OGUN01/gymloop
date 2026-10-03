import { businessTypeCommandSchema, isBusinessType } from '@gymloop/shared';
import { apiFail, apiOk } from '../../../lib/api';
import { gateAdminCommand } from '../gate-code/gate-admin-command';

async function changeBusinessType(request: Request): Promise<Response> {
  const command = await gateAdminCommand(request, businessTypeCommandSchema, 'invalid_request', 'Choose one of the listed business types.', ['gym_owner']);
  if ('failure' in command) return command.failure;
  const { data, error } = await command.session.supabase.rpc('set_business_type', { p_business_type: command.input.businessType });
  const errors = { '42501': () => apiFail('forbidden', 'not_permitted', 'Only the owner can change the business type.') };
  if (error && Object.hasOwn(errors, error.code)) return errors[error.code as keyof typeof errors]();
  const row = data?.[0];
  if (error || !row || typeof row.changed !== 'boolean' || !isBusinessType(row.business_type) || !isBusinessType(row.previous_business_type)) return apiFail('server_error', 'business_type_failed', 'The business type could not be changed. Reload and try again.');
  return apiOk({ businessType: row.business_type, previousBusinessType: row.previous_business_type, changed: row.changed });
}

export async function POST(request: Request): Promise<Response> {
  const response = await changeBusinessType(request).catch(() => apiFail('server_error', 'business_type_failed', 'The business type could not be changed. Reload and try again.'));
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
