import type { GymloopIdentity } from '@gymloop/shared';

type LinkedIdentity = Exclude<GymloopIdentity, { kind: 'unlinked' }>;
type MemberIdentity = Extract<GymloopIdentity, { kind: 'member' }>;
export type MobileStartupRefresh =
  | { kind: 'verified'; identity: GymloopIdentity }
  | { kind: 'network_error' }
  | { kind: 'invalid' };
export type MobileStartupState = {
  identity: GymloopIdentity;
  queueScope: Pick<MemberIdentity, 'userId' | 'tenantId' | 'memberId'> | null;
  replay: 'ready' | 'deferred' | 'blocked';
};
type PersistedMemberIdentity = Pick<MemberIdentity, 'userId' | 'tenantId' | 'memberId'> & { role: 'member' };
type OfflineStartupProbe = {
  cachedIdentity: LinkedIdentity | PersistedMemberIdentity | null;
  refresh:
    | { ok: false; transient: boolean }
    | { ok: true; identity: LinkedIdentity | PersistedMemberIdentity };
  offlineClaim?: unknown;
};
type OfflineStartupDecision = {
  identity: GymloopIdentity | PersistedMemberIdentity;
  signedOut: boolean;
  replay: boolean;
  capability: boolean;
};

function sameOfflineIdentity(
  cached: LinkedIdentity | PersistedMemberIdentity | null,
  verified: LinkedIdentity | PersistedMemberIdentity,
): boolean {
  if (cached === null) return true;
  const cachedKind = 'kind' in cached ? cached.kind : cached.role;
  const verifiedKind = 'kind' in verified ? verified.kind : verified.role;
  if (cachedKind !== 'member' || verifiedKind !== 'member') {
    return cachedKind === verifiedKind && cached.userId === verified.userId;
  }
  const cachedMember = 'kind' in cached ? (cached.kind === 'member' ? cached : null) : cached;
  const verifiedMember = 'kind' in verified ? (verified.kind === 'member' ? verified : null) : verified;
  return cachedMember !== null
    && verifiedMember !== null
    && cachedMember.userId === verifiedMember.userId
    && cachedMember.tenantId === verifiedMember.tenantId
    && cachedMember.memberId === verifiedMember.memberId;
}

function memberScope(identity: GymloopIdentity): MobileStartupState['queueScope'] {
  if (identity.kind !== 'member') return null;
  return { userId: identity.userId, tenantId: identity.tenantId, memberId: identity.memberId };
}

/**
 * Pure cold-start decision. A transient network failure may retain only the
 * last encrypted, authenticated device identity. It never authorizes a server
 * request: bearer verification and RLS still run at the API/database boundary.
 */
export function resolveMobileStartup(input: OfflineStartupProbe): OfflineStartupDecision;
export function resolveMobileStartup(input: {
  cachedIdentity: LinkedIdentity | null;
  refresh: MobileStartupRefresh;
}): MobileStartupState;
export function resolveMobileStartup(input: {
  cachedIdentity: LinkedIdentity | PersistedMemberIdentity | null;
  refresh: MobileStartupRefresh | OfflineStartupProbe['refresh'];
  offlineClaim?: unknown;
}): MobileStartupState | OfflineStartupDecision {
  if ('ok' in input.refresh) {
    const refresh = input.refresh;
    if (refresh.ok) {
      const sameIdentity = sameOfflineIdentity(input.cachedIdentity, refresh.identity);
      return { identity: refresh.identity, signedOut: false, replay: sameIdentity, capability: sameIdentity };
    }
    const cachedIdentity = input.cachedIdentity;
    const retain = refresh.transient && cachedIdentity !== null;
    return {
      identity: retain && cachedIdentity !== null ? cachedIdentity : { kind: 'unlinked' },
      signedOut: !retain,
      replay: false,
      capability: false,
    };
  }
  const cachedIdentity = input.cachedIdentity as LinkedIdentity | null;
  if (input.refresh.kind === 'verified') {
    const identity = input.refresh.identity;
    return {
      identity,
      queueScope: memberScope(identity),
      replay: identity.kind === 'unlinked' ? 'blocked' : 'ready',
    };
  }
  if (input.refresh.kind === 'network_error' && cachedIdentity !== null) {
    return {
      identity: cachedIdentity,
      queueScope: memberScope(cachedIdentity),
      replay: 'deferred',
    };
  }
  return {
    identity: { kind: 'unlinked' },
    queueScope: null,
    replay: input.refresh.kind === 'network_error' ? 'deferred' : 'blocked',
  };
}
