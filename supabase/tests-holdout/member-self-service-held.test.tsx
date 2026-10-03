import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SLF_LIMITS } from '@gymloop/shared';
import {
  requestMemberFreeze,
  cancelMemberFreezeRequest,
  adoptMemberFreezeRequest,
  approveMemberFreezeRequest,
  rejectMemberFreezeRequest,
  expireMemberFreezeRequest,
  readMemberFreezeRequest,
  readMemberFreezeRequests,
  readStaffFreezeRequests,
} from '../../apps/web/lib/member-freeze-requests';
import {
  requestMemberFreeze as nativeRequestMemberFreeze,
  readMemberFreezeRequests as nativeReadMemberFreezeRequests,
} from '../../apps/mobile/lib/member-freeze-requests';

// Independent holdout author. Every expectation below is derived only from the
// frozen SLF contract (openspec/changes/member-self-service/proposal.md) and
// its bar (docs/design/v2/slf-bar.md). No implementation, visible test or
// registry file was read. The SLF feature does not exist yet, so resolving the
// future web/mobile adapter modules fails and the whole suite is RED until the
// implementation lands; when it lands these assertions must hold unchanged.

const iso = (value: string) => value;

beforeEach(() => {
  vi.restoreAllMocks();
});

describe('SLF_LIMITS contract constants', () => {
  it('carries the frozen reason/decision-reason/open-request bounds', () => {
    expect(SLF_LIMITS.reasonMax).toBe(2000);
    expect(SLF_LIMITS.decisionReasonMax).toBe(200);
    expect(SLF_LIMITS.openRequestsPerMember).toBe(1);
  });

  it('clamps pagination to the existing member page-size constants', () => {
    expect(SLF_LIMITS.pageDefault).toBeDefined();
    expect(SLF_LIMITS.pageMax).toBeDefined();
    expect(SLF_LIMITS.pageMax).toBeGreaterThanOrEqual(SLF_LIMITS.pageDefault);
  });
});

describe('SLF-003 identity revalidation', () => {
  it('gives a forged member claim no SLF authority', async () => {
    await expect(
      readMemberFreezeRequests({ actor: { kind: 'member', memberId: 'forged', verified: false } }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });

  it('gives a live access token alone nothing for an unlinked actor', async () => {
    await expect(
      readMemberFreezeRequests({ actor: { kind: 'member', verified: true, linked: false } }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });

  it('refuses platform, trainer and impersonating identities without target facts', async () => {
    for (const kind of ['platform', 'trainer', 'impersonating'] as const) {
      await expect(
        readMemberFreezeRequest({ actor: { kind }, requestId: '81900000-0000-4000-8000-000000000001' }),
      ).rejects.toMatchObject({ code: 'not_permitted' });
      // The refusal must not reveal whether any request exists.
      await expect(
        readMemberFreezeRequest({ actor: { kind }, requestId: '81900000-0000-4000-8000-00000000dead' }),
      ).rejects.toMatchObject({ code: 'not_permitted' });
    }
  });

  it('revalidates the current binding before replay: a stale unlinked actor cannot replay', async () => {
    await expect(
      cancelMemberFreezeRequest({
        actor: { kind: 'member', verified: true, linked: false },
        requestId: '81900000-0000-4000-8000-000000000002',
        commandKey: '81900000-0000-4000-8000-000000000003',
      }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });
});

describe('SLF-002 pending-membership precision', () => {
  it('disables freeze creation and the renewal shortcut for a pending membership while reads stay available', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      membershipStatus: 'pending',
    });
    expect(surface.canRequestFreeze).toBe(false);
    expect(surface.canRenewViaPay).toBe(false);
    expect(surface.canReadPlan).toBe(true);
    expect(surface.canReadReceipts).toBe(true);
    expect(surface.canReadHistory).toBe(true);
    expect(typeof surface.deskContactCopy).toBe('string');
    expect(surface.deskContactCopy.length).toBeGreaterThan(0);
  });

  it('never invents a member-level pending status; a pending request leaves the membership status untouched', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      requestStatus: 'requested',
    });
    expect(surface.membershipStatus).not.toBe('pending');
    expect(Object.hasOwn(surface, 'memberPending')).toBe(false);
  });
});

describe('SLF-004 request creation bounds', () => {
  it('accepts an inclusive span wholly inside the live membership starting no earlier than gym-local today', async () => {
    const result = await requestMemberFreeze({
      actor: { kind: 'member', verified: true, linked: true },
      membershipId: '81900000-0000-4000-8000-000000000010',
      startsOn: iso('2026-10-05'),
      endsOn: iso('2026-10-11'),
      reason: ' travel ',
      requestKey: '81900000-0000-4000-8000-000000000011',
      gymLocalToday: iso('2026-10-05'),
      membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
    });
    expect(result.status).toBe('requested');
    expect(result.reason).toBe('travel'); // trimmed
    expect(result.replayed).toBe(false);
  });

  it('refuses a start earlier than gym-local today and a span leaving the membership', async () => {
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-10-04'),
        endsOn: iso('2026-10-11'),
        reason: 'travel',
        requestKey: '81900000-0000-4000-8000-000000000012',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
      }),
    ).rejects.toMatchObject({ code: 'invalid_request' });
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-12-30'),
        endsOn: iso('2027-01-05'),
        reason: 'travel',
        requestKey: '81900000-0000-4000-8000-000000000013',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
      }),
    ).rejects.toMatchObject({ code: 'invalid_request' });
  });

  it('creates no pause, charge, receipt, granted period or membership change', async () => {
    const result = await requestMemberFreeze({
      actor: { kind: 'member', verified: true, linked: true },
      membershipId: '81900000-0000-4000-8000-000000000010',
      startsOn: iso('2026-10-05'),
      endsOn: iso('2026-10-11'),
      reason: 'travel',
      requestKey: '81900000-0000-4000-8000-000000000014',
      gymLocalToday: iso('2026-10-05'),
      membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
    });
    expect(result.sourcePauseId).toBeNull();
    expect(result.membershipEndsOn).toBe(iso('2026-12-31'));
    expect(result.grantedPeriodsDelta).toBe(0);
    expect(result.chargeCreated).toBe(false);
    expect(result.receiptCreated).toBe(false);
  });
});

describe('SLF-005 overlap predicate exactness', () => {
  const base = {
    actor: { kind: 'member', verified: true, linked: true },
    membershipId: '81900000-0000-4000-8000-000000000010',
    reason: 'travel',
  };

  it('refuses an overlapping effective request and accepts adjacent intervals sharing no date', async () => {
    await expect(
      requestMemberFreeze({
        ...base,
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-10'),
        requestKey: '81900000-0000-4000-8000-000000000020',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        existingRequests: [{ startsOn: iso('2026-10-10'), endsOn: iso('2026-10-15'), status: 'requested' }],
      }),
    ).rejects.toMatchObject({ code: 'overlap_conflict' });
    await expect(
      requestMemberFreeze({
        ...base,
        startsOn: iso('2026-10-16'),
        endsOn: iso('2026-10-20'),
        requestKey: '81900000-0000-4000-8000-000000000021',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        existingRequests: [{ startsOn: iso('2026-10-10'), endsOn: iso('2026-10-15'), status: 'requested' }],
      }),
    ).resolves.toMatchObject({ status: 'requested' });
  });

  it('does not reserve days for cancelled, rejected or expired requests or rejected source pauses', async () => {
    for (const status of ['cancelled', 'rejected', 'expired'] as const) {
      await expect(
        requestMemberFreeze({
          ...base,
          startsOn: iso('2026-10-05'),
          endsOn: iso('2026-10-10'),
          requestKey: `81900000-0000-4000-8000-00000000003${status.length}`,
          gymLocalToday: iso('2026-10-05'),
          membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
          existingRequests: [{ startsOn: iso('2026-10-06'), endsOn: iso('2026-10-08'), status }],
        }),
      ).resolves.toMatchObject({ status: 'requested' });
    }
    await expect(
      requestMemberFreeze({
        ...base,
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-10'),
        requestKey: '81900000-0000-4000-8000-000000000039',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        existingSourcePauses: [{ startsOn: iso('2026-10-06'), endsOn: iso('2026-10-08'), rejectedAt: iso('2026-10-04T00:00:00Z') }],
      }),
    ).resolves.toMatchObject({ status: 'requested' });
  });

  it('a different membership id does not bypass conflict with the member currently relevant interval', async () => {
    await expect(
      requestMemberFreeze({
        ...base,
        membershipId: '81900000-0000-4000-8000-000000000099',
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-10'),
        requestKey: '81900000-0000-4000-8000-000000000040',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        existingRequests: [{ membershipId: '81900000-0000-4000-8000-000000000010', startsOn: iso('2026-10-07'), endsOn: iso('2026-10-09'), status: 'requested' }],
      }),
    ).rejects.toMatchObject({ code: 'overlap_conflict' });
  });
});

describe('SLF-006/007 two-staff adoption and approval boundary', () => {
  const request = { requestId: '81900000-0000-4000-8000-000000000050', revision: 1 };

  it('the adopter cannot approve their own adopted request', async () => {
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000051', role: 'gym_manager', active: true },
        ...request,
        expectedRevision: 1,
        commandKey: '81900000-0000-4000-8000-000000000052',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000051',
        configuredApproverRole: 'gym_manager',
      }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });

  it('approval requires the current role to exactly equal the current configured role; owner rank does not override', async () => {
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000053', role: 'gym_owner', active: true },
        ...request,
        expectedRevision: 1,
        commandKey: '81900000-0000-4000-8000-000000000054',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000055',
        configuredApproverRole: 'gym_manager',
      }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000053', role: 'gym_owner', active: true },
        ...request,
        expectedRevision: 1,
        commandKey: '81900000-0000-4000-8000-000000000056',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000055',
        configuredApproverRole: 'gym_owner',
      }),
    ).resolves.toMatchObject({ status: 'approved' });
  });

  it('a configured-role change between adoption and approval is honoured at approval time', async () => {
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000057', role: 'gym_manager', active: true },
        ...request,
        expectedRevision: 1,
        commandKey: '81900000-0000-4000-8000-000000000058',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000055',
        configuredApproverRole: 'front_desk',
      }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });

  it('a solo owner sees the truthful no-approver state, never a silently enabled Approve', async () => {
    const queue = await readStaffFreezeRequests({
      actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000059', role: 'gym_owner', active: true },
      staffCount: 1,
      configuredApproverRole: 'gym_manager',
    });
    expect(queue.rows[0].canApprove).toBe(false);
    expect(queue.rows[0].soloOwnerTruth).toBe(true);
  });
});

describe('SLF-008/009 rejection and withdrawal', () => {
  it('rejection records the actual actor and reason and never rewrites an approved source pause', async () => {
    await expect(
      rejectMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000060', role: 'front_desk', active: true },
        requestId: '81900000-0000-4000-8000-000000000061',
        expectedRevision: 1,
        reason: 'Dates clash with camp',
        commandKey: '81900000-0000-4000-8000-000000000062',
        sourcePauseApproved: false,
      }),
    ).resolves.toMatchObject({ status: 'rejected', decisionReason: 'Dates clash with camp' });
    await expect(
      rejectMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000060', role: 'front_desk', active: true },
        requestId: '81900000-0000-4000-8000-000000000063',
        expectedRevision: 1,
        reason: 'Dates clash with camp',
        commandKey: '81900000-0000-4000-8000-000000000064',
        sourcePauseApproved: true,
      }),
    ).rejects.toMatchObject({ code: 'invalid_state' });
  });

  it('withdrawal needs a valid binding, not current freeze-creation eligibility', async () => {
    await expect(
      cancelMemberFreezeRequest({
        actor: { kind: 'member', verified: true, linked: true },
        requestId: '81900000-0000-4000-8000-000000000065',
        commandKey: '81900000-0000-4000-8000-000000000066',
        membershipStatus: 'pending',
      }),
    ).resolves.toMatchObject({ status: 'cancelled' });
  });

  it('a closed request never regains an approval, including a direct staff source-pause approval', async () => {
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000067', role: 'gym_manager', active: true },
        requestId: '81900000-0000-4000-8000-000000000065',
        expectedRevision: 2,
        commandKey: '81900000-0000-4000-8000-000000000068',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000055',
        configuredApproverRole: 'gym_manager',
        requestStatus: 'cancelled',
      }),
    ).rejects.toMatchObject({ code: 'invalid_state' });
  });
});

describe('SLF-010 expiry at reads without writes', () => {
  it('an unapproved request whose start day elapsed reads as expired and the read writes nothing', async () => {
    const read = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000070',
      persistedStatus: 'requested',
      startsOn: iso('2026-10-01'),
      gymLocalToday: iso('2026-10-05'),
    });
    expect(read.effectiveStatus).toBe('expired');
    expect(read.persistedStatus).toBe('requested'); // closure not materialized by a read
    expect(read.wroteOnRead).toBe(false);
  });

  it('a renewed or replaced membership never retargets an old request', async () => {
    await expect(
      adoptMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000071', role: 'front_desk', active: true },
        requestId: '81900000-0000-4000-8000-000000000070',
        expectedRevision: 1,
        commandKey: '81900000-0000-4000-8000-000000000072',
        requestMembershipId: '81900000-0000-4000-8000-000000000010',
        currentMembershipId: '81900000-0000-4000-8000-000000000099',
      }),
    ).rejects.toMatchObject({ code: 'request_unavailable' });
  });
});

describe('SLF-013 replay and races', () => {
  const key = '81900000-0000-4000-8000-000000000080';

  it('an exact authorized replay precedes revision and eligibility checks and appends nothing', async () => {
    const first = await requestMemberFreeze({
      actor: { kind: 'member', verified: true, linked: true },
      membershipId: '81900000-0000-4000-8000-000000000010',
      startsOn: iso('2026-10-05'),
      endsOn: iso('2026-10-11'),
      reason: 'travel',
      requestKey: key,
      gymLocalToday: iso('2026-10-05'),
      membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
    });
    const replay = await requestMemberFreeze({
      actor: { kind: 'member', verified: true, linked: true },
      membershipId: '81900000-0000-4000-8000-000000000010',
      startsOn: iso('2026-10-05'),
      endsOn: iso('2026-10-11'),
      reason: 'travel',
      requestKey: key,
      gymLocalToday: iso('2026-10-05'),
      membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
      membershipStatusNow: 'pending', // eligibility changed since; replay still answers
    });
    expect(replay.replayed).toBe(true);
    expect(replay.requestId).toBe(first.requestId);
    expect(replay.auditAppended).toBe(false);
  });

  it('changed facts or actor under the same key conflict without leaking stored facts', async () => {
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-10-06'),
        endsOn: iso('2026-10-11'),
        reason: 'travel',
        requestKey: key,
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
      }),
    ).rejects.toMatchObject({ code: 'idempotency_conflict' });
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true, memberId: '81900000-0000-4000-8000-000000000099' },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-11'),
        reason: 'travel',
        requestKey: key,
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
      }),
    ).rejects.toMatchObject({ code: 'not_permitted' });
  });

  it('a stale revision refuses before effects, and a fresh command on terminal state conflicts', async () => {
    await expect(
      approveMemberFreezeRequest({
        actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000081', role: 'gym_manager', active: true },
        requestId: '81900000-0000-4000-8000-000000000050',
        expectedRevision: 99,
        commandKey: '81900000-0000-4000-8000-000000000082',
        adoptedByStaffId: '81900000-0000-4000-8000-000000000055',
        configuredApproverRole: 'gym_manager',
      }),
    ).rejects.toMatchObject({ code: 'stale_conflict' });
    await expect(
      cancelMemberFreezeRequest({
        actor: { kind: 'member', verified: true, linked: true },
        requestId: '81900000-0000-4000-8000-000000000050',
        commandKey: '81900000-0000-4000-8000-000000000083',
        requestStatus: 'approved',
      }),
    ).rejects.toMatchObject({ code: 'invalid_state' });
  });

  it('an unknown commit outcome keeps the original key for reconciliation', async () => {
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-11'),
        reason: 'travel',
        requestKey: '81900000-0000-4000-8000-000000000084',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        outcome: 'unknown',
      }),
    ).resolves.toMatchObject({ outcome: 'unknown', requestKey: '81900000-0000-4000-8000-000000000084' });
  });
});

describe('SLF-017 online-only behaviour', () => {
  it('refuses every command offline and queues nothing', async () => {
    const offline = { online: false };
    await expect(
      requestMemberFreeze({
        actor: { kind: 'member', verified: true, linked: true },
        membershipId: '81900000-0000-4000-8000-000000000010',
        startsOn: iso('2026-10-05'),
        endsOn: iso('2026-10-11'),
        reason: 'travel',
        requestKey: '81900000-0000-4000-8000-000000000090',
        gymLocalToday: iso('2026-10-05'),
        membershipSpan: { startsOn: iso('2026-01-01'), endsOn: iso('2026-12-31') },
        ...offline,
      }),
    ).rejects.toMatchObject({ code: 'offline' });
    expect(nativeRequestMemberFreeze.queueDepth).toBe(0);
  });

  it('persists no commands, reasons, retry evidence or private data', async () => {
    expect(nativeRequestMemberFreeze.persistedKeys).toEqual([]);
    expect(nativeReadMemberFreezeRequests.persistedPayloads).toEqual([]);
  });

  it('clears reads and retry state on sign-out, rebinding or tenant change, and discards late responses from a previous identity', async () => {
    const state = nativeReadMemberFreezeRequests.stateFor({ memberId: '81900000-0000-4000-8000-000000000095' });
    state.onIdentityChange({ memberId: '81900000-0000-4000-8000-000000000096' });
    expect(state.rows).toEqual([]);
    expect(state.pendingKeys).toEqual([]);
    const late = { identity: '81900000-0000-4000-8000-000000000095', rows: ['stale'] };
    expect(state.acceptsLateResponse(late)).toBe(false);
  });

  it('reconciles the same request/key on reconnect or unknown outcome before presenting success', async () => {
    const state = nativeReadMemberFreezeRequests.stateFor({ memberId: '81900000-0000-4000-8000-000000000095' });
    expect(state.reconcileKey).toBe('same-key');
  });
});

describe('SLF-018 state copy matrix', () => {
  it('gives every required state distinct copy and a specific next action', async () => {
    const states = [
      'loading', 'noHeldMembership', 'emptyHistory', 'pendingMembership', 'awaitingAdoption',
      'awaitingApproval', 'scheduled', 'covering', 'elapsed', 'cancelled', 'rejected', 'expired',
      'validation', 'overlap', 'limit', 'stale', 'permission', 'unavailable', 'retryable', 'offline',
    ] as const;
    const copies = await Promise.all(
      states.map(state => readMemberFreezeRequests({ actor: { kind: 'member', verified: true, linked: true }, state }),
      ),
    );
    const copyTexts = copies.map(copy => `${copy.title}\u0000${copy.action}`);
    expect(new Set(copyTexts).size).toBe(states.length);
    for (const copy of copies) {
      expect(copy.title.length).toBeGreaterThan(0);
      expect(copy.action.length).toBeGreaterThan(0);
    }
  });

  it('never shows a fake success or an approval countdown before the real decision', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      requestStatus: 'requested',
    });
    expect(surface.showsCountdown).toBe(false);
    expect(surface.showsGuaranteedApproval).toBe(false);
  });
});

describe('SLF-016 PAY renewal boundary', () => {
  it('renewal opens only the frozen PAY destination; SLF adds no second endpoint', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
    });
    expect(surface.renewDestination).toBe('/member/buy');
    expect(surface.renewEndpointsOwnedBySlF).toEqual([]);
  });

  it('unavailable PAY stays desk-assisted and only a ledger receipt shows success', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      payAvailable: false,
    });
    expect(surface.renewDestination).toBeNull();
    expect(surface.deskRenewalPath).toBe(true);
    expect(surface.successRequiresLedgerReceipt).toBe(true);
  });
});

describe('SLF-015 surface audit and lockscreen rules', () => {
  it('the member reason never reaches lockscreen notification text', async () => {
    const events = await readStaffFreezeRequests({
      actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000091', role: 'gym_manager', active: true },
      notificationPreviewFor: 'requested',
    });
    expect(events.notificationPreviewContainsReason).toBe(false);
  });
});

describe('bar: structural criteria', () => {
  it('exposes cancel only before approval and never words it as cancelling the membership', async () => {
    const open = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      requestStatus: 'requested',
    });
    expect(open.canCancel).toBe(true);
    expect(open.cancelLabel).toBe('Cancel request');
    const approved = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
      requestStatus: 'approved',
    });
    expect(approved.canCancel).toBe(false);
    expect(String(approved.cancelLabel ?? '')).not.toMatch(/membership/i);
  });

  it('the desk queue shows two distinct actions and money renders tabularly from the shared formatters', async () => {
    const queue = await readStaffFreezeRequests({
      actor: { kind: 'staff', staffId: '81900000-0000-4000-8000-000000000092', role: 'gym_manager', active: true },
    });
    expect(queue.actions).toEqual(['adopt', 'approve']);
    expect(queue.moneyUsesSharedFormatter).toBe(true);
  });

  it('uses word-plus-mark status, not colour alone, in both themes', async () => {
    const surface = await readMemberFreezeRequest({
      actor: { kind: 'member', verified: true, linked: true },
      requestId: '81900000-0000-4000-8000-000000000004',
    });
    expect(surface.statusRender.mode).toBe('word-plus-mark');
    expect(surface.statusRender.themes).toEqual(['light', 'dark']);
  });
});
