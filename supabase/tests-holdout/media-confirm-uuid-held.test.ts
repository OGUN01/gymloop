// Independent MED-007 web transport regression; actual route and request schema.
import { afterEach, expect, it, vi } from 'vitest';
import { mediaConfirmRequestSchema } from '../../packages/shared/src/index';

const h = vi.hoisted(() => ({ read: vi.fn(), invoke: vi.fn(), getSession: vi.fn() }));
vi.mock('../../apps/web/lib/identity-session', () => ({ readIdentity: h.read, readRequestIdentity: h.read }));
vi.mock('server-only', () => ({}));

afterEach(() => vi.unstubAllGlobals());

it('accepted uppercase UUID confirms when trusted Edge returns the same canonical UUID', async () => {
  const assetId = 'ABCDEF00-ABCD-4000-8000-ABCDEF000003';
  const canonicalAssetId = assetId.toLowerCase();
  const accessToken = 'held-verified-owner-token';
  const edgeReply = { ok: true, data: { assetId: canonicalAssetId, confirmed: true } };
  expect(mediaConfirmRequestSchema.safeParse({ assetId }).success).toBe(true);
  h.invoke.mockResolvedValue({ data: edgeReply, error: null });
  h.getSession.mockResolvedValue({ data: { session: { access_token: accessToken } }, error: null });
  h.read.mockResolvedValue({
    identity: { kind: 'staff', userId: '72940000-0000-4000-8000-000000000001', tenantId: '72940000-0000-4000-8000-000000000002', staffId: '72940000-0000-4000-8000-000000000003', role: 'gym_owner' },
    accessToken,
    supabase: { auth: { getSession: h.getSession }, functions: { invoke: h.invoke } },
  });
  const { POST } = await import('../../apps/web/app/api/media/confirm/route');
  const request = new Request('https://held.example/api/media/confirm', {
    method: 'POST', headers: { authorization: `Bearer ${accessToken}`, 'content-type': 'application/json' }, body: JSON.stringify({ assetId }),
  });
  const response = await POST(request);
  expect(h.read).toHaveBeenCalledWith(request);
  expect(h.invoke).toHaveBeenCalledOnce();
  const [functionName, forwarded] = h.invoke.mock.calls[0]! as [string, { body: { operation: string; assetId: string }; headers: HeadersInit }];
  expect(functionName).toBe('media');
  expect(forwarded.body).toEqual({ operation: 'confirm', assetId: expect.any(String) });
  expect(forwarded.body.assetId.toLowerCase()).toBe(canonicalAssetId);
  expect(new Headers(forwarded.headers).get('authorization')).toBe(`Bearer ${accessToken}`);
  expect(response.headers.get('cache-control')).toBe('no-store');
  expect(response.status).toBe(200);
  const body = await response.json() as { ok: boolean; data: { assetId: string; confirmed: boolean } };
  expect(body).toEqual({ ok: true, data: { assetId: expect.any(String), confirmed: true } });
  expect(body.data.assetId.toLowerCase()).toBe(canonicalAssetId);
});
