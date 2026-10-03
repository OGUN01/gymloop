import { classRulesRequestSchema, parseClassRulesResult } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../lib/class-http';
export async function POST(request: Request): Promise<Response> {
  return classCommand(request, { schema: classRulesRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'reference_not_found'], GL110: ['conflict', 'service_inactive'], GL114: ['conflict', 'limit_reached'], '23505': ['conflict', 'rule_exists'], '22023': ['bad_request', 'invalid_request'] },
    execute: (client, input) => classRpc(client, 'create_class_rules', { p_service_id: input.serviceId, p_branch_id: input.branchId, p_weekdays: input.weekdays, p_start_time: input.startTime, p_duration_minutes: input.durationMinutes, p_capacity: input.capacity, p_trainer_staff_id: input.trainerStaffId ?? null, p_valid_from: input.validFrom ?? null, p_valid_until: input.validUntil ?? null }),
    answer: (data, input) => parseClassRulesResult(data, input),
  });
}
