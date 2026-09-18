import { describe, expect, it, vi } from 'vitest';

const MEMBER_ID = '11111111-1111-4111-8111-111111111111';
const STAFF_ID = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';
const OTHER_MEMBER_ID = '22222222-2222-4222-8222-222222222222';
const TENANT_ID = '33333333-3333-4333-8333-333333333333';
const OTHER_TENANT_ID = '44444444-4444-4444-8444-444444444444';
const EVENT_ID = '55555555-5555-4555-8555-555555555555';

vi.mock('../supabase/server', () => ({
  createServerSupabase: async () => ({
    auth: {
      getClaims: async () => ({
        data: {
          claims: {
            sub: MEMBER_ID,
            app_role: 'front_desk',
            tenant_id: TENANT_ID,
            staff_id: STAFF_ID,
          },
        },
        error: null,
      }),
      getUser: async () => ({ data: { user: { id: MEMBER_ID } }, error: null }),
    },
  }),
}));

import { POST } from '../../app/api/check-in/route';

class ParseTrapRequest extends Request {
  parsed = false;

  override async json(): Promise<never> {
    this.parsed = true;
    throw new Error('the request body was reached');
  }
}

function trappedCheckIn(headers: HeadersInit, body = '{}'): ParseTrapRequest {
  return new ParseTrapRequest('http://localhost/api/check-in', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  });
}

describe('Phase 7 mobile credential boundary holdout', () => {
  it('rejects an ambiguous credential transport without touching the command payload', async () => {
    const request = trappedCheckIn({
      authorization: 'Bearer not-a-token',
      cookie: 'sb-test-auth-token=present',
    });

    const response = await POST(request);

    expect(response.status).toBe(401);
    expect(request.parsed).toBe(false);
  });

  it.each([
    ['a malformed bearer', 'Bearer not-a-token'],
    ['an unsigned member-shaped bearer', `Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiI${MEMBER_ID}",InRlbmFudF9pZCI6Ii${TENANT_ID}",Im1lbWJlcl9pZCI6Ii${MEMBER_ID}",ImFwcF9yb2xlIjoibWVtYmVyIn0.`],
    ['a service credential', 'Bearer eyJyb2xlIjoic2VydmljZV9yb2xlIn0.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.signature'],
  ])('does not parse a body after rejecting %s', async (_label, authorization) => {
    const request = trappedCheckIn({ authorization });

    const response = await POST(request);

    expect(response.status).toBe(401);
    expect(request.parsed).toBe(false);
  });

  it('does not let rejected mobile input select a member or tenant', async () => {
    const request = trappedCheckIn(
      { authorization: 'Bearer forged-member-token' },
      JSON.stringify({
        memberId: OTHER_MEMBER_ID,
        tenantId: OTHER_TENANT_ID,
        reason: 'I checked myself in',
        clientEventId: EVENT_ID,
      }),
    );

    const response = await POST(request);

    expect(response.status).toBe(401);
    expect(request.parsed).toBe(false);
  });
});
