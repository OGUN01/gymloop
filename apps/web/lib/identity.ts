import type { GymloopIdentity } from '@gymloop/shared';

export { classifyIdentity } from '@gymloop/shared';
export type { GymloopIdentity, PlatformRole, StaffRole } from '@gymloop/shared';

/** One destination for every complete identity, including support previews. */
export function identityHome(identity: GymloopIdentity) {
  switch (identity.kind) {
    case 'staff':
      return identity.role === 'front_desk' ? '/console/check-in' : '/console';
    case 'impersonation': return '/console';
    case 'member': return '/member';
    case 'platform': return '/platform';
    case 'unlinked': return '/not-linked';
  }
}
