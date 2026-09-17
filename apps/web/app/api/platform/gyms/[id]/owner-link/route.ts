import { linkGymOwnerRequestSchema } from '@gymloop/shared';
import { linkGymOwner, platformAdminRequest } from '../../../../../../lib/platform';

export async function POST(request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  const command = await platformAdminRequest(request, linkGymOwnerRequestSchema, 'That owner link request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' });
  if ('failure' in command) return command.failure;
  return linkGymOwner(command.client, command.id!, command.data, request);
}
