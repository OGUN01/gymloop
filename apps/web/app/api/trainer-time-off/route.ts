import { trainerTimeOffRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand, ptNullableRpc } from '../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager', 'trainer'],
    schema: trainerTimeOffRequestSchema,
    execute: (client, input) => ptNullableRpc(client, 'add_trainer_time_off', { p_staff_id: input.staffId, p_starts_on: input.startsOn, p_ends_on: input.endsOn, p_reason: input.reason ?? null }),
    answer: (data) => ptCommandAnswer('timeOff', data),
  });
}
