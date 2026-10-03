import type { GymloopIdentity } from './identity';
import { requireAudience } from './identity-session';

export async function requireOriginalMember(original: Pick<Extract<GymloopIdentity, { kind: 'member' }>, 'userId' | 'tenantId' | 'memberId'>): Promise<Awaited<ReturnType<typeof requireAudience<'member'>>> | null> {
  try {
    const current = await requireAudience('member');
    if (current.identity.userId !== original.userId || current.identity.tenantId !== original.tenantId || current.identity.memberId !== original.memberId) return null;
    return current;
  } catch { return null; }
}
