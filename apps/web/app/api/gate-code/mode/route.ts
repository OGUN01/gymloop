import { gateModeCommandSchema } from '@gymloop/shared';
import { apiFail, apiOk, PG_INSUFFICIENT_PRIVILEGE } from '../../../../lib/api';
import { gateAdminCommand } from '../gate-admin-command';

type ModeRpc = {
  rpc(name: 'set_checkin_gate_mode', args: { p_mode: 'printed_poster' | 'rotating_screen' }): Promise<{
    data: 'printed_poster' | 'rotating_screen' | null;
    error: { code: string } | null;
  }>;
};

/** POST /api/gate-code/mode — atomic, audited gym-wide gate switch. */
export async function POST(request: Request): Promise<Response> {
  const command = await gateAdminCommand(request, gateModeCommandSchema, 'invalid_mode',
    'Choose printed poster or rotating screen; no tenant or actor fields are accepted.');
  if ('failure' in command) return command.failure;
  const { session, input } = command;
  const { data, error } = await (session.supabase as unknown as ModeRpc)
    .rpc('set_checkin_gate_mode', { p_mode: input.mode });
  if (error?.code === PG_INSUFFICIENT_PRIVILEGE) return apiFail('forbidden', 'not_permitted', 'Only an active gym owner or manager can change gate mode.');
  if (error || data !== input.mode) return apiFail('server_error', 'mode_change_failed', 'Gate mode could not be confirmed. Reload the gate before retrying.');
  return apiOk({ mode: data });
}
