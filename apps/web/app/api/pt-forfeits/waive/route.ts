import { ptWaiveRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager'],
    schema: ptWaiveRequestSchema,
    execute: (client, input) => client.rpc('waive_pt_forfeit', { p_session_id: input.sessionId, p_reason: input.reason }),
    answer: (data) => ptCommandAnswer('waive', data),
  });
}
