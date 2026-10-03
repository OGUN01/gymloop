import { trainerProfileRequestSchema, ptCommandAnswer } from '@gymloop/shared';
import { ptCommand, ptNullableRpc } from '../../../lib/pt-http';

export async function POST(request: Request): Promise<Response> {
  return ptCommand(request, {
    roles: ['gym_owner', 'gym_manager'],
    schema: trainerProfileRequestSchema,
    execute: (client, input) => ptNullableRpc(client, 'set_trainer_profile', { p_staff_id: input.staffId, p_bio: input.bio, p_specialities: input.specialities, p_photo_asset_id: input.photoAssetId, p_is_listed: input.isListed }),
    answer: (data) => ptCommandAnswer('profile', data),
  });
}
