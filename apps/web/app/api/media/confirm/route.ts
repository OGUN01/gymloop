import { mediaConfirmRequestSchema } from '@gymloop/shared';
import { apiOk, noStore } from '../../../../lib/api';
import { invokeMedia } from '../../../../lib/media';
import { mediaCommand, mediaFailure } from '../../../../lib/media-http';

export async function POST(request: Request): Promise<Response> {
  const command = await mediaCommand(request, 'staff', mediaConfirmRequestSchema);
  if ('failure' in command) return command.failure;
  const assetId = command.input.assetId.toLowerCase();
  try {
    const answer = await invokeMedia(command.supabase, 'confirm', assetId, command.token) as { ok?: unknown; data?: { assetId?: unknown; confirmed?: unknown }; error?: { code?: unknown } };
    if (answer?.ok === true && typeof answer.data?.assetId === 'string' && answer.data.assetId.toLowerCase() === assetId && answer.data.confirmed === true) return noStore(apiOk({ assetId, confirmed: true }));
    return mediaFailure(answer?.ok === false && typeof answer.error?.code === 'string' ? answer.error.code : 'storage_unavailable');
  } catch { return mediaFailure('storage_unavailable'); }
}
