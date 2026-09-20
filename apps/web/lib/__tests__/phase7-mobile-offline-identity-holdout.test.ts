import { describe, expect, it } from 'vitest';

const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const TENANT_ID = '33333333-3333-4333-8333-333333333333';
const EVENT_ID = '55555555-5555-4555-8555-555555555555';

describe('Phase 7 mobile offline identity holdout', () => {
  it('GL017/GL018/GL046 retains the member queue across offline cold start and replays only after verified reconnect', async () => {
    const { resolveMobileStartup } = await import('../../../mobile/lib/session');
    const cached = { userId: MEMBER_ID, tenantId: TENANT_ID, memberId: MEMBER_ID, role: 'member' as const };
    const offline = resolveMobileStartup({ cachedIdentity: cached, refresh: { ok: false, transient: true } });
    expect(offline.identity).toEqual(cached);
    expect(offline.signedOut).toBe(false);
    expect(offline.replay).toBe(false);

    const verified = resolveMobileStartup({ cachedIdentity: cached, refresh: { ok: true, identity: cached } });
    expect(verified.identity).toEqual(cached);
    expect(verified.replay).toBe(true);

    const forged = resolveMobileStartup({ cachedIdentity: cached, refresh: { ok: false, transient: true }, offlineClaim: { memberId: EVENT_ID } });
    expect(forged.capability).toBe(false);
  });
});
