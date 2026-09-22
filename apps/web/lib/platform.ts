import { fleetMetricsSchema, platformRpcArgs, type OnboardGymRequest, type SetGymStatusRequest, type SetGymTierRequest, type LinkGymOwnerRequest, type DeactivateGymOwnerRequest } from '@gymloop/shared';
import { apiFail, apiOk, formFields, jsonBody, platformSession, seeOther, type PlatformSession } from './api';
import { UUID_PATTERN } from './keyset';

type RpcClient = PlatformSession['supabase'];
type RpcResult = { data: unknown; error: { code?: string; message?: string; details?: string } | null };
type RequestSchema<T> = {
  safeParse: (payload: unknown) => { success: true; data: T } | { success: false };
};
type RouteContext = { params?: Promise<{ id?: string }> };
export function commandSuccess(request: Request, data: unknown, path: string): Response {
  return (request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')
    ? apiOk(data) : seeOther(request, path);
}

async function platformBody(request: Request): Promise<{ payload: unknown } | { failure: Response }> {
  if ((request.headers.get('content-type') ?? '').toLowerCase().includes('application/json')) return jsonBody(request);
  const parsed = await formFields(request);
  if ('failure' in parsed) return parsed;
  const fields = parsed.fields;
  const payload: Record<string, unknown> = { ...fields };
  for (const key of ['requestKey', 'tenantId', 'ownerStaffId', 'expectedUserId']) {
    if (payload[key] === '') payload[key] = null;
  }
  for (const key of ['expectedTier', 'tier', 'reason', 'ownerEmail']) {
    if (payload[key] === '') payload[key] = null;
  }
  for (const key of ['requestKey', 'tenantId', 'ownerStaffId', 'expectedUserId']) {
    if (typeof payload[key] === 'string' && payload[key] === null) delete payload[key];
  }
  return { payload };
}

/** Authenticate, optionally resolve a gym id, and validate one platform command body. */
export async function platformAdminRequest<T>(
  request: Request,
  schema: RequestSchema<T>,
  invalidBodyMessage: string,
  options?: { context?: RouteContext | undefined; invalidIdMessage?: string },
): Promise<{ client: RpcClient; data: T; id?: string } | { failure: Response }> {
  const caller = await platformSession({ requireAdmin: true });
  if ('failure' in caller) return caller;
  let id: string | undefined;
  if (options?.invalidIdMessage !== undefined) {
    id = (await options.context?.params)?.id;
    if (!(typeof id === 'string' && UUID_PATTERN.test(id))) {
      return { failure: apiFail('bad_request', 'invalid_request', options.invalidIdMessage) };
    }
  }
  const body = await platformBody(request);
  if ('failure' in body) return body;
  const parsed = schema.safeParse(body.payload);
  if (!parsed.success) return { failure: apiFail('bad_request', 'invalid_request', invalidBodyMessage) };
  return { client: caller.session.supabase, data: parsed.data, ...(id === undefined ? {} : { id }) };
}

export function platformError(error: RpcResult['error']): Response {
  const code = error?.code;
  const detail = error?.details ?? error?.message ?? '';
  if (code === '42501') return apiFail('forbidden', 'not_permitted', 'Platform administrator access is required.');
  if (code === 'P0002') return apiFail('not_found', 'not_found', 'That gym is not available.');
  if (code === 'GL049') return apiFail('forbidden', 'platform_commercial_write_required', 'This change must use the platform command.');
  if (code === 'GL050') return apiFail('unprocessable', 'invalid_organization_transition', 'That gym status change is not allowed.');
  if (code === 'GL051') {
    let missing: string[] = [];
    try {
      const parsed = JSON.parse(detail) as { missingSettings?: unknown };
      if (Array.isArray(parsed.missingSettings)) missing = parsed.missingSettings.filter((value): value is string => typeof value === 'string');
    } catch { /* database detail is not JSON; retain safe generic response */ }
    const suffix = missing.length ? ` Missing: ${missing.join(', ')}.` : '';
    return apiFail(
      'conflict',
      'organization_not_ready',
      `Complete the required gym settings before activation.${suffix}`,
      { missingSettings: missing },
    );
  }
  if (code === 'GL068') return apiFail('conflict', 'idempotency_conflict', 'This request key was already used for different facts.');
  if (code === '40001' || code === '40P01') return apiFail('conflict', 'stale_platform_state', 'The gym changed. Refresh and try again.');
  if (code === '23505' && detail.includes('preview')) return apiFail('conflict', 'preview_already_open', 'A preview is already open for this gym.');
  if (code === '22023') return apiFail('unprocessable', detail.includes('owner_account') ? 'owner_account_unavailable' : 'invalid_platform_input', 'Check the platform request and try again.');
  return apiFail('server_error', 'operation_failed', 'The platform operation could not be completed.');
}

async function rpc(client: RpcClient, name: string, args: Record<string, unknown>, request: Request, path: string): Promise<Response> {
  const result = await client.rpc(name as never, args as never) as unknown as RpcResult;
  if (result.error) return platformError(result.error);
  if (result.data === null || result.data === undefined) return platformError({ code: 'XX000' });
  return commandSuccess(request, result.data, path);
}

export const onboardGym = (client: RpcClient, request: OnboardGymRequest, httpRequest: Request) => rpc(client, 'onboard_gym', platformRpcArgs(request), httpRequest, '/platform');
export const setGymStatus = (client: RpcClient, tenantId: string, request: SetGymStatusRequest, httpRequest: Request) => rpc(client, 'set_gym_status', { p_tenant_id: tenantId, p_expected_status: request.expectedStatus, p_status: request.status, p_reason: request.reason, p_request_key: request.requestKey }, httpRequest, `/platform/${tenantId}`);
export const setGymTier = (client: RpcClient, tenantId: string, request: SetGymTierRequest, httpRequest: Request) => rpc(client, 'set_gym_tier', { p_tenant_id: tenantId, p_expected_tier: request.expectedTier, p_tier: request.tier, p_request_key: request.requestKey }, httpRequest, `/platform/${tenantId}`);
export const linkGymOwner = (client: RpcClient, tenantId: string, request: LinkGymOwnerRequest, httpRequest: Request) => rpc(client, 'link_gym_owner', { p_tenant_id: tenantId, p_owner_staff_id: request.ownerStaffId, p_expected_user_id: request.expectedUserId, p_owner_email: request.ownerEmail, p_request_key: request.requestKey }, httpRequest, `/platform/${tenantId}`);
export const deactivateGymOwner = (client: RpcClient, tenantId: string, request: DeactivateGymOwnerRequest, httpRequest: Request) => rpc(client, 'deactivate_gym_owner', { p_tenant_id: tenantId, p_owner_staff_id: request.ownerStaffId, p_expected_user_id: request.expectedUserId, p_request_key: request.requestKey }, httpRequest, `/platform/${tenantId}`);
export const fleetMetrics = async (client: RpcClient) => {
  const result = await client.rpc('fleet_metrics' as never, {} as never) as unknown as RpcResult;
  if (result.error) return { error: platformError(result.error) } as const;
  const parsed = fleetMetricsSchema.safeParse(result.data);
  return parsed.success ? { data: parsed.data } as const : { error: platformError({ code: 'XX000' }) } as const;
};
