import { describe, expect, it } from 'vitest';

const MEMBER_A = '11111111-1111-4111-8111-111111111111';
const MEMBER_B = '22222222-2222-4222-8222-222222222222';
const TENANT = '33333333-3333-4333-8333-333333333333';

describe('independent mobile restart scope holdout', () => {
  it('ATT-007/NAV-001 preserves a same-member queued command across reauthentication', async () => {
    const { resolveMobileStartup } = await import('../../../apps/mobile/lib/session');
    const cachedIdentity = { userId: MEMBER_A, tenantId: TENANT, memberId: MEMBER_A, role: 'member' };
    const decision = resolveMobileStartup({
      cachedIdentity,
      refresh: { ok: true, identity: cachedIdentity },
      queuedCommand: { userId: MEMBER_A, tenantId: TENANT, memberId: MEMBER_A },
    });

    expect(decision.identity).toEqual(cachedIdentity);
    expect(decision.replay).toBe(true);
    expect(decision.capability).toBe(true);
  });

  it('ATT-007/NAV-001 refuses a queued command when verified identity changes member scope', async () => {
    const { resolveMobileStartup } = await import('../../../apps/mobile/lib/session');
    const cachedIdentity = { userId: MEMBER_A, tenantId: TENANT, memberId: MEMBER_A, role: 'member' };
    const verifiedIdentity = { userId: MEMBER_B, tenantId: TENANT, memberId: MEMBER_B, role: 'member' };
    const decision = resolveMobileStartup({
      cachedIdentity,
      refresh: { ok: true, identity: verifiedIdentity },
      queuedCommand: { userId: MEMBER_A, tenantId: TENANT, memberId: MEMBER_A },
    });

    expect(decision.replay).toBe(false);
    expect(decision.capability).toBe(false);
  });
});
