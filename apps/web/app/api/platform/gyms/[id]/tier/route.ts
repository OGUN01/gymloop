import { setGymTierRequestSchema } from '@gymloop/shared';
import { platformAdminRequest, setGymTier } from '../../../../../../lib/platform';

export async function POST(request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  const command = await platformAdminRequest(request, setGymTierRequestSchema, 'That tier request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' });
  if ('failure' in command) return command.failure;
  return setGymTier(command.client, command.id!, command.data, request);
}
