import { ptGymCancelRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager', 'front_desk'],
    schema: ptGymCancelRequestSchema,
    execute: (client, input) => client.rpc('cancel_pt_session_as_gym', { p_session_id: input.sessionId, p_reason: input.reason }),
    answer: (data) => ptCommandAnswer('gymCancel', data),
  });
}
