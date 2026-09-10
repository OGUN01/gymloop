import type { Database } from '@gymloop/db';
import { UUID_PATTERN } from './keyset';

type AppRole = Database['public']['Enums']['app_role'];
export type StaffRole = Extract<AppRole, 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'>;
export type PlatformRole = Extract<AppRole, 'super_admin' | 'platform_support'>;

export type GymloopIdentity =
  | { kind: 'staff'; userId: string; tenantId: string; staffId: string; role: StaffRole }
  | { kind: 'member'; userId: string; tenantId: string; memberId: string }
  | { kind: 'platform'; userId: string; role: PlatformRole }
  | { kind: 'impersonation'; userId: string; tenantId: string; impersonationSessionId: string }
  | { kind: 'unlinked' };

function uuid(value: unknown): value is string {
  return typeof value === 'string' && UUID_PATTERN.test(value);
}

/** Classifies signature-verified claims; it does not verify a token itself. */
export function classifyIdentity(claims: unknown): GymloopIdentity {
  const unlinked = { kind: 'unlinked' } as const;
  if (!claims || typeof claims !== 'object' || Array.isArray(claims)) return unlinked;
  const facts = claims as Record<string, unknown>;
  const { sub, app_role: role, tenant_id: tenantId, staff_id: staffId,
    member_id: memberId, impersonation_session_id: previewId } = facts;
  if (!uuid(sub)) return unlinked;

  if (role === 'super_admin' || role === 'platform_support') {
    if (tenantId != null || staffId != null || memberId != null || previewId != null) return unlinked;
    return { kind: 'platform', userId: sub, role };
  }
  if (!uuid(tenantId)) return unlinked;

  if (role === 'member') {
    if (!uuid(memberId) || staffId != null || previewId != null) return unlinked;
    return { kind: 'member', userId: sub, tenantId, memberId };
  }
  if (role === 'gym_owner' && previewId != null) {
    if (!uuid(previewId) || staffId != null || memberId != null) return unlinked;
    return { kind: 'impersonation', userId: sub, tenantId, impersonationSessionId: previewId };
  }
  if (role === 'gym_owner' || role === 'gym_manager' || role === 'front_desk' || role === 'trainer') {
    if (!uuid(staffId) || memberId != null || previewId != null) return unlinked;
    return { kind: 'staff', userId: sub, tenantId, staffId, role };
  }
  return unlinked;
}

/** One destination for every complete identity, including support previews. */
export function identityHome(identity: GymloopIdentity) {
  switch (identity.kind) {
    case 'staff':
    case 'impersonation': return '/console';
    case 'member': return '/member/add-ons';
    case 'platform': return '/platform';
    case 'unlinked': return '/not-linked';
  }
}
