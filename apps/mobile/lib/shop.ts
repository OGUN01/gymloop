import { shopRefusalMessage, type GymloopIdentity } from '@gymloop/shared';

export function shopCacheScope(identity: GymloopIdentity): string | null {
  if (!identity || identity.kind !== 'member') return null;
  const parts = [identity.userId, identity.tenantId, identity.memberId];
  if (parts.some(value => typeof value !== 'string' || value.trim().length === 0)) return null;
  return parts.join(':');
}
export function reserveOutcomeMessage(code: string): string { return shopRefusalMessage(code); }
export function heldUntilLabel(expiresAt: string, timeZone: string): string {
  return new Intl.DateTimeFormat('en-IN', { timeZone, day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }).format(new Date(expiresAt));
}
