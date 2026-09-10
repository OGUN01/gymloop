// Independent NAV-001/002 holdout, authored from frozen contract dc391b4.
// Implementation and visible-test authors must not read this file.
import { describe, expect, it } from 'vitest';

const ids = {
  user: '15ec9d81-62ea-40d9-b570-8abec6ad0d5e',
  tenant: '38c40de7-40b7-43d2-ae61-7d2d4f874caa',
  staff: '4ea893bf-c8ca-4954-8f63-bf97ef574377',
  member: '5fa15acd-4768-41ea-b9f2-3a467ddcd6cf',
  preview: '6bd180b5-1327-4538-97ce-e9ae8d821d01',
};

const examples = [
  ...['gym_owner', 'gym_manager', 'front_desk', 'trainer'].map((role) => ({
    label: role,
    claims: { sub: ids.user, app_role: role, tenant_id: ids.tenant, staff_id: ids.staff },
    identity: { kind: 'staff', userId: ids.user, tenantId: ids.tenant, staffId: ids.staff, role },
    home: '/console',
    required: ['sub', 'tenant_id', 'staff_id'],
    forbidden: ['member_id', 'impersonation_session_id'],
  })),
  {
    label: 'member',
    claims: { sub: ids.user, app_role: 'member', tenant_id: ids.tenant, member_id: ids.member },
    identity: { kind: 'member', userId: ids.user, tenantId: ids.tenant, memberId: ids.member },
    home: '/member/add-ons',
    required: ['sub', 'tenant_id', 'member_id'],
    forbidden: ['staff_id', 'impersonation_session_id'],
  },
  ...['super_admin', 'platform_support'].map((role) => ({
    label: role,
    claims: { sub: ids.user, app_role: role },
    identity: { kind: 'platform', userId: ids.user, role },
    home: '/platform',
    required: ['sub'],
    forbidden: ['tenant_id', 'staff_id', 'member_id', 'impersonation_session_id'],
  })),
  {
    label: 'support preview',
    claims: {
      sub: ids.user, app_role: 'gym_owner', tenant_id: ids.tenant,
      impersonation_session_id: ids.preview,
    },
    identity: {
      kind: 'impersonation', userId: ids.user, tenantId: ids.tenant,
      impersonationSessionId: ids.preview,
    },
    home: '/console',
    required: ['sub', 'tenant_id', 'impersonation_session_id'],
    forbidden: ['staff_id', 'member_id'],
  },
];

async function classifier() {
  return import('../../../apps/web/lib/identity.ts');
}

describe('independent complete identity and home contract', () => {
  for (const example of examples) {
    it(`${example.label}: one exact identity and one working home`, async () => {
      const { classifyIdentity, identityHome } = await classifier();
      const identity = classifyIdentity(example.claims);
      expect(identity).toEqual(example.identity);
      expect(identityHome(identity)).toBe(example.home);
    });

    it(`${example.label}: reserved facts are inert and input is not mutated`, async () => {
      const { classifyIdentity } = await classifier();
      const claims = Object.freeze({
        ...example.claims,
        role: 'authenticated', aud: ['authenticated'], exp: 2090000000,
        aal: 'aal2', session_id: ids.preview,
        user_metadata: Object.freeze({ app_role: 'super_admin', tenant_id: ids.tenant }),
        custom_fact: ['unrelated', { nested: true }],
      });
      const before = JSON.stringify(claims);
      expect(classifyIdentity(claims)).toEqual(example.identity);
      expect(JSON.stringify(claims)).toBe(before);
    });

    it(`${example.label}: absent and JSON-null forbidden facts are equivalent`, async () => {
      const { classifyIdentity } = await classifier();
      const nullable = Object.fromEntries(example.forbidden.map((key) => [key, null]));
      expect(classifyIdentity({ ...example.claims, ...nullable })).toEqual(example.identity);
    });

    for (const key of example.required) {
      it(`${example.label}: ${key} must be a UUID, not a truthy identifier`, async () => {
        const { classifyIdentity, identityHome } = await classifier();
        for (const value of [undefined, null, '', ' ', 'not-a-uuid', 42, true, {}, [], `${ids.user} `]) {
          const claims = { ...example.claims, [key]: value };
          const identity = classifyIdentity(claims);
          expect(identity, `${key}=${JSON.stringify(value)}`).toEqual({ kind: 'unlinked' });
          expect(identityHome(identity)).toBe('/not-linked');
        }
      });
    }

    for (const key of example.forbidden) {
      it(`${example.label}: contradictory ${key} never gains another identity`, async () => {
        const { classifyIdentity } = await classifier();
        for (const value of [ids.member, '', 'malformed', 0, false, [], {}]) {
          expect(classifyIdentity({ ...example.claims, [key]: value }), `${key}=${JSON.stringify(value)}`)
            .toEqual({ kind: 'unlinked' });
        }
      });
    }
  }

  it('unknown, missing and wrong-type roles do not inherit staff permissions', async () => {
    const { classifyIdentity } = await classifier();
    for (const role of [undefined, null, '', 'owner', 'GYM_OWNER', 'authenticated', 1, ['gym_owner']]) {
      expect(classifyIdentity({ ...examples[0].claims, app_role: role })).toEqual({ kind: 'unlinked' });
    }
  });

  it('non-record claims produce only unlinked identity', async () => {
    const { classifyIdentity, identityHome } = await classifier();
    for (const claims of [undefined, null, false, 0, '', 'signed-looking-token', [], [examples[0].claims]]) {
      const identity = classifyIdentity(claims);
      expect(identity).toEqual({ kind: 'unlinked' });
      expect(identityHome(identity)).toBe('/not-linked');
    }
  });

  it('a complete preview is not a staff identity even with a platform-looking reserved role', async () => {
    const { classifyIdentity } = await classifier();
    expect(classifyIdentity({ ...examples.at(-1).claims, role: 'super_admin' }))
      .toEqual(examples.at(-1).identity);
    expect(classifyIdentity({ ...examples.at(-1).claims, app_role: 'gym_manager' }))
      .toEqual({ kind: 'unlinked' });
  });

  it('valid UUID case is accepted without treating casing as another identity', async () => {
    const { classifyIdentity } = await classifier();
    const result = classifyIdentity({
      ...examples[0].claims,
      sub: ids.user.toUpperCase(), tenant_id: ids.tenant.toUpperCase(), staff_id: ids.staff.toUpperCase(),
    });
    expect(result.kind).toBe('staff');
    expect(result.userId.toLowerCase()).toBe(ids.user);
    expect(result.tenantId.toLowerCase()).toBe(ids.tenant);
    expect(result.staffId.toLowerCase()).toBe(ids.staff);
  });
});
