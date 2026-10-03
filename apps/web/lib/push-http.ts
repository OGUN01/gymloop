import { apiFail, noStore } from './api';
import { commsOk, commsRpcFailure } from './comms';
import { readRequestIdentity } from './identity-session';

/**
 * The shared NTF member-route head (session → member audience → body → one
 * guarded RPC round-trip), extracted so every push route is a thin delegation
 * with identical fail-closed behavior: the caller is verified before the body
 * is ever read, the audience is the member's own account, and the RPC answer
 * is unwrapped exactly once with the mapped failure envelope.
 */
type Caller = NonNullable<Awaited<ReturnType<typeof readRequestIdentity>>>;
export type MemberPushSession = Caller & { identity: Extract<Caller['identity'], { kind: 'member' }> };

export async function memberPushSession(request: Request, refusal: { signedOut: string; wrongAudience: string }): Promise<{ session: MemberPushSession } | { failure: Response }> {
  const caller = await readRequestIdentity(request);
  if (caller === null) return { failure: noStore(apiFail('unauthorized', 'not_signed_in', refusal.signedOut)) };
  if (caller.identity.kind !== 'member') return { failure: noStore(apiFail('forbidden', 'not_permitted', refusal.wrongAudience)) };
  return { session: caller as MemberPushSession };
}

type MemberPushHead =
  | { session: MemberPushSession; payload: unknown }
  | { failure: Response };

/** The shared session+body preamble for the member push command routes. */
async function pushMemberHead(
  request: Request,
  refusal: { signedOut: string; wrongAudience: string; jsonError: string },
): Promise<MemberPushHead> {
  const head = await memberPushSession(request, { signedOut: refusal.signedOut, wrongAudience: refusal.wrongAudience });
  if ('failure' in head) return head;
  const body = await pushJsonBody(request, refusal.jsonError);
  if ('failure' in body) return body;
  return { session: head.session, payload: body.payload };
}

/** The minimal zod surface the command runner needs. */
type PushCommandSchema = {
  safeParse(payload: unknown): { success: true; data: unknown } | { success: false };
};

/**
 * The whole shared skeleton of a member push command route: session, body,
 * strict schema gate, the one RPC call and the no-store success envelope.
 * Each route supplies only its own strings, schema and argument mapping.
 */
export async function pushMemberCommandRoute(
  request: Request,
  command: {
    signedOut: string;
    wrongAudience: string;
    jsonError: string;
    invalidMessage: string;
    schema: PushCommandSchema;
    rpc: string;
    args: (data: unknown) => Record<string, unknown>;
  },
): Promise<Response> {
  const head = await pushMemberHead(request, command);
  if ('failure' in head) return head.failure;
  const parsed = command.schema.safeParse(head.payload);
  if (!parsed.success) return noStore(apiFail('bad_request', 'invalid_request', command.invalidMessage));
  const result = await pushRpc<Record<string, unknown>>(head.session, command.rpc, command.args(parsed.data));
  if ('failure' in result) return result.failure;
  return noStore(commsOk('ok', result.row));
}

export async function pushJsonBody(request: Request, invalidMessage: string): Promise<{ payload: unknown } | { failure: Response }> {
  try {
    return { payload: await request.json() };
  } catch {
    return { failure: noStore(apiFail('bad_request', 'invalid_request', invalidMessage)) };
  }
}

export async function pushRpc<T>(session: MemberPushSession, name: string, args: Record<string, unknown>): Promise<{ row: T } | { failure: Response }> {
  const writer = session.supabase as unknown as {
    rpc(name: string, args: Record<string, unknown>): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc(name, args);
  if (error) return { failure: noStore(commsRpcFailure(error)) };
  const row = Array.isArray(data) ? (data[0] ?? null) : data;
  if (row === null || typeof row !== 'object') return { failure: noStore(apiFail('server_error', 'operation_failed', 'That push action could not be completed. Try again.')) };
  return { row: row as T };
}

export { commsOk };
