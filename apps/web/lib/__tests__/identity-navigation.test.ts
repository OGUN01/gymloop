import { describe, expect, it } from 'vitest';
import { classifyIdentity, identityHome } from '../identity';

// NAV-001/002: authored from the frozen contract, without implementation access.
const userId = 'a6000000-0000-4000-8000-000000000001';
const tenantId = 'a6000000-0000-4000-8000-000000000002';
const staffId = 'a6000000-0000-4000-8000-000000000003';
const memberId = 'a6000000-0000-4000-8000-000000000004';
const impersonationSessionId = 'a6000000-0000-4000-8000-000000000005';
const shapes = [
  ...(['gym_owner', 'gym_manager', 'front_desk', 'trainer'] as const).map((role) => ({
    claims: { sub: userId, app_role: role, tenant_id: tenantId, staff_id: staffId },
    expected: { kind: 'staff', userId, tenantId, staffId, role }, home: '/console',
    required: ['sub', 'tenant_id', 'staff_id'], forbidden: ['member_id', 'impersonation_session_id'],
  })),
  { claims: { sub: userId, app_role: 'member', tenant_id: tenantId, member_id: memberId },
    expected: { kind: 'member', userId, tenantId, memberId }, home: '/member/add-ons',
    required: ['sub', 'tenant_id', 'member_id'], forbidden: ['staff_id', 'impersonation_session_id'] },
  ...(['super_admin', 'platform_support'] as const).map((role) => ({
    claims: { sub: userId, app_role: role }, expected: { kind: 'platform', userId, role }, home: '/platform',
    required: ['sub'], forbidden: ['tenant_id', 'staff_id', 'member_id', 'impersonation_session_id'],
  })),
  { claims: { sub: userId, app_role: 'gym_owner', tenant_id: tenantId, impersonation_session_id: impersonationSessionId },
    expected: { kind: 'impersonation', userId, tenantId, impersonationSessionId }, home: '/console',
    required: ['sub', 'tenant_id', 'impersonation_session_id'], forbidden: ['staff_id', 'member_id'] },
];

describe('complete identity and home contract', () => {
  for (const shape of shapes) {
    it(`classifies ${shape.expected.kind}/${shape.claims.app_role} without inventing facts`, () => {
      const claims = Object.freeze({ ...shape.claims, aud: 'authenticated', role: 'authenticated', exp: 9999999999, arbitrary: true });
      const identity = classifyIdentity(claims);
      expect(identity).toEqual(shape.expected);
      expect(identityHome(identity)).toBe(shape.home);
    });
    for (const field of shape.required) {
      it.each([undefined, null, '', 'not-uuid', 42, {}, `${userId}x`])(`refuses invalid ${shape.expected.kind}.${field}: %j`, (value) => {
        expect(classifyIdentity({ ...shape.claims, [field]: value })).toEqual({ kind: 'unlinked' });
      });
    }
    for (const field of shape.forbidden) {
      it(`permits null but rejects nonnull contradictory ${shape.expected.kind}.${field}`, () => {
        expect(classifyIdentity({ ...shape.claims, [field]: null })).toEqual(shape.expected);
        for (const value of [userId, '', 'bad', 0, false]) {
          expect(classifyIdentity({ ...shape.claims, [field]: value })).toEqual({ kind: 'unlinked' });
        }
      });
    }
  }
  it.each([null, undefined, [], 'staff', 1, {}, { sub: userId }, { sub: userId, app_role: 'owner' }])('fails closed on %j', (claims) => {
    const identity = classifyIdentity(claims);
    expect(identity).toEqual({ kind: 'unlinked' });
    expect(identityHome(identity)).toBe('/not-linked');
  });
  it('does not treat manager-with-preview or staff-plus-member as impersonation', () => {
    expect(classifyIdentity({ sub: userId, app_role: 'gym_manager', tenant_id: tenantId, impersonation_session_id: impersonationSessionId })).toEqual({ kind: 'unlinked' });
    expect(classifyIdentity({ ...shapes[0]?.claims, member_id: memberId })).toEqual({ kind: 'unlinked' });
  });
});
