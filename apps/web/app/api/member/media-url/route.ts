import { memberMediaUrlRequestSchema } from '@gymloop/shared';
import { apiOk, noStore } from '../../../../lib/api';
import { memberMediaUrl } from '../../../../lib/media';
import { mediaCommand, mediaFailure } from '../../../../lib/media-http';

export async function POST(request: Request): Promise<Response> {
  const command = await mediaCommand(request, 'member', memberMediaUrlRequestSchema);
  if ('failure' in command) return command.failure;
  try {
    const imageUrl = await memberMediaUrl(command.supabase, command.input.assetId, command.token);
    return imageUrl === null ? mediaFailure('asset_not_found') : noStore(apiOk({ imageUrl }));
  } catch { return mediaFailure('storage_unavailable'); }
}
