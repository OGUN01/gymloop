import { setGymBusinessTypeRequestSchema } from '@gymloop/shared';
import { platformAdminRequest, platformError, setGymBusinessType } from '../../../../../../lib/platform';

export async function POST(request: Request, context?: { params?: Promise<{ id?: string }> }): Promise<Response> {
  let response: Response;
  try {
    const command = await platformAdminRequest(request, setGymBusinessTypeRequestSchema, 'That business type request was not readable.', { context, invalidIdMessage: 'That gym id was not readable.' });
    response = 'failure' in command ? command.failure : await setGymBusinessType(command.client, command.id!, command.data, request);
  } catch { response = platformError(null); }
  response.headers.set('Cache-Control', 'no-store');
  return response;
}
