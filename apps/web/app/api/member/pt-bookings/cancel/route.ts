import { ptCancelRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    schema: ptCancelRequestSchema,
    execute: (client, input) => client.rpc('cancel_pt_booking', { p_session_id: input.sessionId }),
    answer: (data) => ptCommandAnswer('cancel', data),
  });
}
