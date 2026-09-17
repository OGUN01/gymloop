import { walletAdjustRequestSchema } from '@gymloop/shared';
import { apiFail, jsonBody, platformSession } from '../../../../lib/api';
import { commsOk, commsRpcFailure, walletAdjustmentResult } from '../../../../lib/comms';

/**
 * `POST /api/messaging-wallet/adjust` — a super-admin credit movement
 * (contract §7). Platform admin only: no gym, staff, member or preview
 * identity may reach this route, so it uses `platformSession` rather than
 * `staffSession` — the wallet has no gym-side identity at all.
 *
 * `deltaCredits` travels as the exact string the caller submitted, all the
 * way to the RPC argument and back out in the response: it is never routed
 * through `Number()`, so a value beyond `Number.MAX_SAFE_INTEGER` survives
 * byte-for-byte (§1). A zero delta is forwarded rather than pre-refused —
 * the database's own CHECK constraint owns that refusal (`23514`).
 */
export async function POST(request: Request): Promise<Response> {
  const caller = await platformSession({ requireAdmin: true });
  if ('failure' in caller) return caller.failure;

  const body = await jsonBody(request);
  if ('failure' in body) return body.failure;

  const parsed = walletAdjustRequestSchema.safeParse(body.payload);
  if (!parsed.success) {
    return apiFail('bad_request', 'invalid_request', 'Check the tenant, delta credits, reason and request key, then try again.');
  }
  const { tenantId, deltaCredits, reason, requestKey } = parsed.data;

  const writer = caller.session.supabase as unknown as {
    rpc(name: 'adjust_messaging_wallet', args: {
      p_tenant_id: string; p_delta_credits: string; p_reason: string; p_request_key: string;
    }): Promise<{ data: unknown; error: { code: string; message: string } | null }>;
  };
  const { data, error } = await writer.rpc('adjust_messaging_wallet', {
    p_tenant_id: tenantId, p_delta_credits: deltaCredits, p_reason: reason, p_request_key: requestKey,
  });
  if (error) return commsRpcFailure(error);

  const result = walletAdjustmentResult(data);
  if (result === null) return apiFail('server_error', 'operation_failed', 'The wallet adjustment could not be confirmed. Nothing was written.');
  return commsOk('created', result);
}
