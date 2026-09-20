import { describe, expect, it, vi } from 'vitest';

vi.mock('expo-secure-store', () => ({}));

import { resolveOfflineQueueRecovery } from '../offline-check-in';

const QUEUED_SCOPE = {
  userId: '11111111-1111-4111-8111-111111111111',
  tenantId: '22222222-2222-4222-8222-222222222222',
  memberId: '33333333-3333-4333-8333-333333333333',
};

describe('offline queue recovery after a signed-out cold start', () => {
  it('retains a queued scope until the same verified member returns', () => {
    expect(resolveOfflineQueueRecovery({
      identity: null,
      queuedScope: QUEUED_SCOPE,
    })).toEqual({ queueScope: QUEUED_SCOPE, replay: false });

    expect(resolveOfflineQueueRecovery({
      identity: { kind: 'member', ...QUEUED_SCOPE },
      queuedScope: QUEUED_SCOPE,
    })).toEqual({ queueScope: QUEUED_SCOPE, replay: true });
  });

  it('does not offer a different verified member the queued command for replay', () => {
    expect(resolveOfflineQueueRecovery({
      identity: {
        kind: 'member',
        userId: '44444444-4444-4444-8444-444444444444',
        tenantId: QUEUED_SCOPE.tenantId,
        memberId: '55555555-5555-4555-8555-555555555555',
      },
      queuedScope: QUEUED_SCOPE,
    })).toEqual({ queueScope: null, replay: false });
  });
});
