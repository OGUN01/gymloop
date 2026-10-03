import { mediaRefusalMessage } from '@gymloop/shared';
import { apiFail, noStore, type ApiFailStatus } from './api';
import { readRequestIdentity } from './identity-session';

/** MED refuses every wrong/incomplete caller before consuming JSON. */
export async function mediaCommand<T>(request: Request, audience: 'staff' | 'member', schema: { safeParse(value: unknown): { success: true; data: T } | { success: false } }) {
  const caller = await readRequestIdentity(request);
  if (!caller || caller.identity.kind !== audience || (caller.identity.kind === 'staff' && caller.identity.role === 'trainer')) return { failure: mediaFailure('not_permitted') };
  try {
    const parsed = schema.safeParse(await request.json());
    if (!parsed.success) return { failure: mediaFailure('invalid_request') };
    return { ...caller, input: parsed.data, token: request.headers.get('authorization')?.slice('Bearer '.length) };
  } catch { return { failure: mediaFailure('invalid_request') }; }
}
const REFUSALS: Record<string, ApiFailStatus> = { not_permitted: 'forbidden', invalid_request: 'bad_request', asset_not_found: 'not_found', upload_missing: 'conflict', upload_changed: 'conflict', upload_rejected: 'unprocessable', upload_rate_limited: 'too_many_requests', media_in_use: 'conflict', media_not_ready: 'conflict', media_failed: 'server_error', upload_failed: 'server_error', storage_unavailable: 'server_error' };
export function mediaFailure(code: string): Response {
  const known = Object.hasOwn(REFUSALS, code) ? code : 'storage_unavailable';
  return noStore(apiFail(REFUSALS[known]!, known, known === 'invalid_request' ? 'Choose a valid photo and try again.' : known === 'not_permitted' ? 'This account cannot perform this photo action.' : mediaRefusalMessage(known === 'upload_rate_limited' ? 'media_limit' : known)));
}
