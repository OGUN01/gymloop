import { PT_HTTP_STATUS, ptApiError, ptRefusalMessage } from '@gymloop/shared';
import { apiFail, apiOk, memberSession, noStore, staffSession, type StaffSession, type ApiFailStatus } from './api';
import type { StaffRole } from './identity';
import type { Database } from '@gymloop/db';

type Parser<T> = { safeParse(value: unknown): { success: true; data: T } | { success: false } };
type PtCommand<T> = {
  roles?: readonly StaffRole[];
  schema: Parser<T>;
  execute(client: StaffSession['supabase'], input: T): PromiseLike<{ data: unknown; error: { code: string; details: string } | null }>;
  answer(data: unknown): unknown | null;
};
const statuses: Readonly<Record<number, ApiFailStatus>> = { [PT_HTTP_STATUS.invalid]: 'bad_request', [PT_HTTP_STATUS.missing]: 'not_found', [PT_HTTP_STATUS.conflict]: 'conflict', [PT_HTTP_STATUS.limited]: 'too_many_requests', [PT_HTTP_STATUS.failed]: 'server_error' };
type NullablePtRpc = 'set_trainer_profile' | 'add_trainer_time_off' | 'reassign_pt_packs';
type NullableKeys = 'p_photo_asset_id' | 'p_reason' | 'p_order_ids';
type NullableArgs<N extends NullablePtRpc> = { [K in keyof Database['public']['Functions'][N]['Args']]: K extends NullableKeys ? Database['public']['Functions'][N]['Args'][K] | null : Database['public']['Functions'][N]['Args'][K] };
/** Generated RPC argument metadata omits SQL nullability; these three documented nullable arguments preserve SQL NULL. */
export function ptNullableRpc<N extends NullablePtRpc>(client: StaffSession['supabase'], name: N, args: NullableArgs<N>) {
  const rpc = client.rpc as unknown as (name: N, args: NullableArgs<N>) => PromiseLike<{ data: Database['public']['Functions'][N]['Returns'] | null; error: { code: string; details: string } | null }>;
  return rpc.call(client, name, args);
}
function failure(sqlstate: string, detail: string | null = null): Response {
  const mapped = ptApiError(sqlstate, detail);
  return noStore(apiFail(statuses[mapped.status] ?? 'server_error', mapped.code, ptRefusalMessage(mapped.code)));
}
/** Caller-scoped PTF commands share authorization, strict parsing and sanitized failures. */
export async function ptCommand<T>(request: Request, spec: PtCommand<T>): Promise<Response> {
  const caller = spec.roles ? await staffSession(spec.roles, { completeWrongAudience: 'forbidden' }, request) : await memberSession(request);
  if ('failure' in caller) return noStore(caller.failure);
  let input: T;
  try {
    const parsed = spec.schema.safeParse(await request.json());
    if (!parsed.success) return failure('22023');
    input = parsed.data;
  } catch { return failure('22023'); }
  try {
    const { data, error } = await spec.execute(caller.session.supabase, input);
    if (error) return failure(error.code, error.details);
    const answer = spec.answer(data);
    return answer === null ? failure('') : noStore(apiOk(answer));
  } catch { return failure(''); }
}
