import { beforeEach, describe, expect, it, vi } from 'vitest';
import { resolveNativeMobileSession, signOutMobile } from '../native-session';

const store = vi.hoisted(() => ({
  value: null as string | null,
  holdNextIdentityWrite: false,
  pendingWrite: null as null | (() => void),
  writeStarted: null as null | (() => void),
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: async (key: string) => key === 'gymloop.authenticated-identity' ? store.value : null,
  setItemAsync: async (key: string, value: string) => {
    if (key !== 'gymloop.authenticated-identity') return;
    if (store.holdNextIdentityWrite) {
      store.holdNextIdentityWrite = false;
      await new Promise<void>((done) => {
        // Release performs the physical write, rather than merely delaying its result.
        store.pendingWrite = () => { store.value = value; done(); };
        store.writeStarted?.();
      });
    } else store.value = value;
  },
  deleteItemAsync: async (key: string) => { if (key === 'gymloop.authenticated-identity') store.value = null; },
}));
vi.mock('expo-web-browser', () => ({ maybeCompleteAuthSession: () => undefined }));
vi.mock('../offline-check-in', async (original) => ({ ...await original<Record<string, unknown>>(), clearOfflineCheckIns: async () => undefined }));

const USER = '11111111-1111-4111-8111-111111111111';
const TENANT = '22222222-2222-4222-8222-222222222222';
const OLD = '33333333-3333-4333-8333-333333333333';
const NEW = '44444444-4444-4444-8444-444444444444';
function client(memberId: string) {
  return { auth: {
    getClaims: async () => ({ data: { claims: { role: 'authenticated', sub: USER, app_role: 'member', tenant_id: TENANT, member_id: memberId } }, error: null }),
    signOut: vi.fn(async () => ({ error: null })),
  } } as unknown as Parameters<typeof resolveNativeMobileSession>[0];
}
const session = { access_token: 'verified-remotely', user: { id: USER }, refresh_token: 'refresh', token_type: 'bearer', expires_in: 3600 } as Parameters<typeof resolveNativeMobileSession>[1];
async function settleCache() { for (let i = 0; i < 24; i += 1) await Promise.resolve(); }
function delayWrite() {
  store.holdNextIdentityWrite = true;
  return new Promise<void>((done) => { store.writeStarted = done; });
}
beforeEach(() => { store.value = null; store.holdNextIdentityWrite = false; store.pendingWrite = null; store.writeStarted = null; });

describe('HARD-011 device-wide native identity cache ordering across auth clients', () => {
  it('physically late client A cache write cannot resurrect identity after client B signs out', async () => {
    const started = delayWrite();
    const oldResolution = resolveNativeMobileSession(client(OLD), session);
    await started;
    await signOutMobile(client(NEW));
    expect(store.value).toBeNull();
    store.pendingWrite!();
    await oldResolution;
    await settleCache();
    expect(store.value).toBeNull();
  });

  it('physically late client A cache write cannot replace client B newer verified member', async () => {
    const started = delayWrite();
    const oldResolution = resolveNativeMobileSession(client(OLD), session);
    await started;
    const newest = await resolveNativeMobileSession(client(NEW), session);
    expect(newest.identity).toMatchObject({ kind: 'member', memberId: NEW });
    expect(newest.replay).toBe('ready');
    store.pendingWrite!();
    await oldResolution;
    await settleCache();
    expect(JSON.parse(store.value!)).toMatchObject({ kind: 'member', memberId: NEW });
    expect(store.value).not.toContain(OLD);
  });
});


