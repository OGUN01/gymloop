import { ptPolicyRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager'],
    schema: ptPolicyRequestSchema,
    execute: (client, input) => client.rpc('set_pt_policy', { p_cancel_window_hours: input.cancelWindowHours, p_late_cancel_consumes: input.lateCancelConsumes, p_session_minutes: input.sessionMinutes }),
    answer: (data) => ptCommandAnswer('policy', data),
  });
}
