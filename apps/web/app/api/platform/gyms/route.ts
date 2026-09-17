import { onboardGymRequestSchema } from '@gymloop/shared';
import { onboardGym, platformAdminRequest } from '../../../../lib/platform';

export async function POST(request: Request): Promise<Response> {
  const command = await platformAdminRequest(request, onboardGymRequestSchema, 'That gym onboarding request was not readable.');
  if ('failure' in command) return command.failure;
  return onboardGym(command.client, command.data, request);
}

