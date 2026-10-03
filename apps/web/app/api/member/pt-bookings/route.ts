import { ptBookRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    schema: ptBookRequestSchema,
    execute: (client, input) => client.rpc('book_pt_session', { p_order_id: input.orderId, p_session_id: input.sessionId, p_starts_at: input.startsAt }),
    answer: (data) => ptCommandAnswer('book', data),
  });
}
