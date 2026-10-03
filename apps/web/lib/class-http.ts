import { classRefusalMessage } from '@gymloop/shared';
import { apiFail, apiOk, memberSession, staffSession, noStore, type StaffSession, type ApiFailStatus } from './api';
import type { StaffRole } from './identity';

type Command<T> = {
  schema: { safeParse(value: unknown): { success: true; data: T } | { success: false } };
  roles?: readonly StaffRole[];
  booking?: boolean;
  errors: Readonly<Record<string, readonly [ApiFailStatus, string]>>;
  execute(client: StaffSession['supabase'], input: T, tenantId: string): PromiseLike<{ data: unknown; error: { code?: string } | null }>;
  answer(data: unknown, input: T): unknown | null;
};
/** CLS routes use the established verified identity seam before parsing bodies. */
export async function classCommand<T>(request: Request, command: Command<T>): Promise<Response> {
  const failed = () => noStore(apiFail('server_error', command.booking ? 'booking_failed' : 'class_failed', classRefusalMessage('booking_failed')));
  const invalid = () => noStore(apiFail('bad_request', 'invalid_request', 'Check the class details and try again.'));
  const caller = command.roles ? await staffSession(command.roles, { completeWrongAudience: 'forbidden' }, request) : await memberSession(request);
  if ('failure' in caller) return noStore(caller.failure);
  let input: T;
  try { const parsed = command.schema.safeParse(await request.json()); if (!parsed.success) return invalid(); input = parsed.data; } catch { return invalid(); }
  try {
    const result = await command.execute(caller.session.supabase, input, caller.session.tenantId);
    if (result.error) {
      const key = result.error.code ?? '';
      const refusal = Object.hasOwn(command.errors, key) ? command.errors[key] : undefined;
      return refusal ? noStore(apiFail(refusal[0], refusal[1], classRefusalMessage(refusal[1]))) : failed();
    }
    const answer = command.answer(result.data, input);
    return answer === null ? failed() : noStore(apiOk(answer));
  } catch { return failed(); }
}
/** SQL metadata does not encode nullable arguments; caller client remains unchanged. */
export function classRpc(client: StaffSession['supabase'], name: string, args: Record<string, unknown>) {
  const rpc = client.rpc as unknown as (name: string, args: Record<string, unknown>) => PromiseLike<{ data: unknown; error: { code?: string } | null }>;
  return rpc.call(client, name, args);
}
