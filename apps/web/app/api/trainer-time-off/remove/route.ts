import { trainerTimeOffRemoveRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager', 'trainer'],
    schema: trainerTimeOffRemoveRequestSchema,
    execute: (client, input) => client.rpc('remove_trainer_time_off', { p_time_off_id: input.timeOffId }),
    answer: (data) => ptCommandAnswer('removeTimeOff', data),
  });
}
