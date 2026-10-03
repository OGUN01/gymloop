import { ownTrainerProfileRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand } from '../../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['trainer'],
    schema: ownTrainerProfileRequestSchema,
    execute: (client, input) => client.rpc('set_own_trainer_profile', { p_bio: input.bio, p_specialities: input.specialities }),
    answer: (data) => ptCommandAnswer('profile', data),
  });
}
