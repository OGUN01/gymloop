import type { GymloopIdentity } from '@gymloop/shared';

export { classifyIdentity } from '@gymloop/shared';
export type { GymloopIdentity, PlatformRole, StaffRole } from '@gymloop/shared';

/** One destination for every complete identity, including support previews. */
export function identityHome(identity: GymloopIdentity) {
  switch (identity.kind) {
    case 'staff':
    case 'impersonation': return '/console';
    case 'member': return '/member';
    case 'platform': return '/platform';
    case 'unlinked': return '/not-linked';
  }
}
