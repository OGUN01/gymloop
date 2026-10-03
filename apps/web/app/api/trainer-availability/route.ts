import { trainerAvailabilityRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager', 'trainer'],
    schema: trainerAvailabilityRequestSchema,
    execute: (client, input) => client.rpc('set_trainer_availability', { p_staff_id: input.staffId, p_windows: input.windows }),
    answer: (data) => ptCommandAnswer('availability', data),
  });
}
