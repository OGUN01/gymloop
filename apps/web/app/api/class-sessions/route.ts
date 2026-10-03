import { classSessionRequestSchema, parseClassSessionResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classSessionRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'reference_not_found'], GL110: ['conflict', 'service_inactive'], '23505': ['conflict', 'session_exists'], '22023': ['bad_request', 'invalid_request'] },
    execute: (client, input) => classRpc(client, 'create_class_session', { p_service_id: input.serviceId, p_branch_id: input.branchId, p_session_date: input.sessionDate, p_start_time: input.startTime, p_duration_minutes: input.durationMinutes, p_capacity: input.capacity, p_trainer_staff_id: input.trainerStaffId ?? null }),
    answer: (data) => parseClassSessionResult(data),
  });
}
