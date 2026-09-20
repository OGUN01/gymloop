import { describe, expect, it, vi } from 'vitest';

vi.mock('expo-secure-store', () => ({}));

import { resolveMobileStartup } from '../session';

const MEMBER_IDENTITY = {
  kind: 'member' as const,
  userId: '11111111-1111-4111-8111-111111111111',
  tenantId: '22222222-2222-4222-8222-222222222222',
  memberId: '33333333-3333-4333-8333-333333333333',
};

describe('mobile cold-start session resolution', () => {
  it('keeps a persisted member scope and its offline queue when refresh is unavailable', () => {
    expect(resolveMobileStartup({
      cachedIdentity: MEMBER_IDENTITY,
      refresh: { kind: 'network_error' },
    })).toEqual({
      identity: MEMBER_IDENTITY,
      queueScope: {
        userId: MEMBER_IDENTITY.userId,
        tenantId: MEMBER_IDENTITY.tenantId,
        memberId: MEMBER_IDENTITY.memberId,
      },
      replay: 'deferred',
    });
  });
});
