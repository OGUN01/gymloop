import { setGymStatusRequestSchema } from '@gymloop/shared';
import { platformAdminRequest, setGymStatus } from '../../../../../../lib/platform';

export async function POST(request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  const command = await platformAdminRequest(request, setGymStatusRequestSchema, 'That status request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' });
  if ('failure' in command) return command.failure;
  return setGymStatus(command.client, command.id!, command.data, request);
}





