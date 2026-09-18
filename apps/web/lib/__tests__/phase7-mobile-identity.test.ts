import { describe, expect, it } from 'vitest';
import { readRequestIdentity } from '../identity-session';

const USER_ID = '11111111-1111-4111-8111-111111111111';
const TENANT_ID = '22222222-2222-4222-8222-222222222222';
const MEMBER_ID = '33333333-3333-4333-8333-333333333333';

describe('Phase 7 mobile request identity boundary', () => {
  it('fails closed before the body is parsed when no credential transport is present', async () => {
    const request = new Request('https://gymloop.test/api/check-in', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: '{not json',
    });

    const session = await readRequestIdentity(request);

    expect(session).toMatchObject({ signedIn: false, identity: { kind: 'unlinked' } });
  });

  it.each([
    ['malformed bearer', 'Bearer definitely-not-a-jwt'],
    ['unclassified bearer', 'Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJub3QtYS11dWlkIn0.'],
    ['service-role bearer', 'Bearer service-role-secret-must-never-authenticate-a-user'],
  ])('refuses a %s without trusting its decoded contents', async (_label, authorization) => {
    const session = await readRequestIdentity(new Request('https://gymloop.test/api/check-in', {
      headers: { authorization },
    }));

    expect(session).toMatchObject({ signedIn: false, identity: { kind: 'unlinked' } });
  });

  it('refuses mixed cookie and bearer transports even when the bearer claims a complete member identity', async () => {
    const encodedClaims = btoa(JSON.stringify({
      sub: USER_ID,
      app_role: 'member',
      tenant_id: TENANT_ID,
      member_id: MEMBER_ID,
    }));
    const request = new Request('https://gymloop.test/api/check-in', {
      headers: {
        authorization: `Bearer eyJhbGciOiJub25lIn0.${encodedClaims}.not-a-signature`,
        cookie: 'sb-access-token=pretend-cookie',
      },
    });

    const session = await readRequestIdentity(request);

    expect(session).toMatchObject({ signedIn: false, identity: { kind: 'unlinked' } });
  });
});
