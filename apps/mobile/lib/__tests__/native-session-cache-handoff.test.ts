import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AuthRetryableFetchError } from '@supabase/supabase-js';
import { resolveNativeMobileSession } from '../native-session';

const cache = vi.hoisted(() => ({ value: null as string | null, getFails: false, setFails: false }));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async () => { if (cache.getFails) throw new Error('SecureStore read unavailable'); return cache.value; },
  setItemAsync: async (_key: string, value: string) => { if (cache.setFails) throw new Error('SecureStore write unavailable'); cache.value = value; },
  deleteItemAsync: async () => { cache.value = null; },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));

const USER = '11111111-1111-4111-8111-111111111111';
const TENANT = '22222222-2222-4222-8222-222222222222';
const MEMBER = '33333333-3333-4333-8333-333333333333';
const claims = { role: 'authenticated', sub: USER, app_role: 'member', tenant_id: TENANT, member_id: MEMBER };
const member = { kind: 'member', userId: USER, tenantId: TENANT, memberId: MEMBER };
const session = { access_token: 'invalid-local-jwt', refresh_token: 'test-refresh', token_type: 'bearer', expires_in: 3600, user: { id: USER } };

function client(network = false) {
  return { auth: { getClaims: vi.fn(async (token: string) => {
    expect(token).toBe(session.access_token);
    return network
      ? { data: null, error: new AuthRetryableFetchError('network unavailable', 503) }
      : { data: { claims }, error: null };
  }) } } as unknown as Parameters<typeof resolveNativeMobileSession>[0];
}
function resolve(network = false) {
  return resolveNativeMobileSession(client(network), session as Parameters<typeof resolveNativeMobileSession>[1]);
}

beforeEach(() => { cache.value = null; cache.getFails = false; cache.setFails = false; });

describe('INV-022 / HARD-011 optional native identity cache cannot override fresh claims', () => {
  it.each(['read', 'write', 'both'] as const)('verified online member resolves ready when optional cache %s fails', async (failure) => {
    cache.getFails = failure !== 'write'; cache.setFails = failure !== 'read';
    await expect(resolve()).resolves.toMatchObject({ identity: member, queueScope: { userId: USER, tenantId: TENANT, memberId: MEMBER }, replay: 'ready' });
  });

  it.each([
    { ...member, userId: '44444444-4444-4444-8444-444444444444' },
    { ...member, tenantId: '55555555-5555-4555-8555-555555555555', memberId: '66666666-6666-4666-8666-666666666666' },
  ])('verified claims replace wrong or stale cached association %#', async (stale) => {
    cache.value = JSON.stringify(stale); cache.setFails = true;
    await expect(resolve()).resolves.toMatchObject({ identity: member, queueScope: { userId: USER, tenantId: TENANT, memberId: MEMBER }, replay: 'ready' });
  });

  it('offline cache read failure with invalid local claims fails closed without an unhandled rejection or member Home authority', async () => {
    cache.getFails = true;
    const result = await resolve(true);
    expect(result.identity.kind).not.toBe('member');
    expect(result.queueScope).toBeNull();
    expect(['deferred', 'blocked']).toContain(result.replay);
  });
});

