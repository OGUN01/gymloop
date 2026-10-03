import { classSessionCancelRequestSchema, parseClassSessionCancelResult, classIdentifierSchema } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../../lib/class-http';
export async function POST(request: Request, context: { params: Promise<{ sessionId: string }> }): Promise<Response> {
  const { sessionId } = await context.params;
  return classCommand(request, { schema: classSessionCancelRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'session_not_found'], GL111: ['conflict', 'session_not_open'] },
    execute: (client, input) => classIdentifierSchema.safeParse(sessionId).success ? classRpc(client, 'cancel_class_session', { p_session_id: sessionId, p_reason: input.reason }) : Promise.resolve({ data: null, error: { code: '22023' } }),
    answer: (data) => parseClassSessionCancelResult(data, sessionId),
  });
}
