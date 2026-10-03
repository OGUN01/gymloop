import { classSessionUpdateRequestSchema, parseClassSessionUpdateResult, classIdentifierSchema } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function PUT(request: Request, context: { params: Promise<{ sessionId: string }> }): Promise<Response> {
  const { sessionId } = await context.params;
  return classCommand(request, { schema: classSessionUpdateRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'session_not_found'], GL111: ['conflict', 'session_not_open'], GL112: ['conflict', 'session_has_bookings'], '22023': ['bad_request', 'invalid_request'] },
    execute: (client, input) => classIdentifierSchema.safeParse(sessionId).success ? classRpc(client, 'update_class_session', { p_session_id: sessionId, p_session_date: input.sessionDate, p_start_time: input.startTime, p_duration_minutes: input.durationMinutes, p_capacity: input.capacity, p_trainer_staff_id: input.trainerStaffId ?? null }) : Promise.resolve({ data: null, error: { code: '22023' } }),
    answer: (data) => parseClassSessionUpdateResult(data, sessionId),
  });
}
