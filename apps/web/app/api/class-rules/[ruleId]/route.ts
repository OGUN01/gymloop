import { classRuleUpdateRequestSchema, parseClassRuleUpdateResult, classIdentifierSchema } from '@gymloop/shared';
import { classCommand, classRpc } from '../../../../lib/class-http';
export async function PUT(request: Request, context: { params: Promise<{ ruleId: string }> }): Promise<Response> {
  const { ruleId } = await context.params;
  return classCommand(request, { schema: classRuleUpdateRequestSchema, roles: ['gym_owner', 'gym_manager'], errors: { '42501': ['not_found', 'rule_not_found'] },
    execute: (client, input) => classIdentifierSchema.safeParse(ruleId).success ? classRpc(client, 'update_class_rule', { p_rule_id: ruleId, p_duration_minutes: input.durationMinutes, p_capacity: input.capacity, p_trainer_staff_id: input.trainerStaffId, p_valid_until: input.validUntil, p_is_active: input.isActive }) : Promise.resolve({ data: null, error: { code: '22023' } }),
    answer: (data) => parseClassRuleUpdateResult(data, ruleId),
  });
}
