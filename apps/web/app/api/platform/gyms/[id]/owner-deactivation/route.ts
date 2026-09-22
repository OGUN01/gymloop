import { deactivateGymOwnerRequestSchema } from '@gymloop/shared';
import { deactivateGymOwner, platformAdminRequest } from '../../../../../../lib/platform';

export async function POST(request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  const command = await platformAdminRequest(request, deactivateGymOwnerRequestSchema, 'That owner deactivation request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' });
  if ('failure' in command) return command.failure;
  return deactivateGymOwner(command.client, command.id!, command.data, request);
}
