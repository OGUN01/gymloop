import { describe, expect, it } from 'vitest';
import { POST } from '../route';

const MEMBER_ID = '33333333-3333-4333-8333-333333333333';
const OTHER_MEMBER_ID = '44444444-4444-4444-8444-444444444444';
const EVENT_ID = '55555555-5555-4555-8555-555555555555';

function checkIn(body: string, headers: HeadersInit = {}) {
  return new Request('https://gymloop.test/api/check-in', {
    method: 'POST',
    headers: { 'content-type': 'application/json', ...headers },
    body,
  });
}

describe('Phase 7 member check-in transport', () => {
  it.each([
    ['missing credential', checkIn('{not json')],
    ['malformed bearer', checkIn('{not json', { authorization: 'Bearer not-a-jwt' })],
    ['mixed cookie and bearer', checkIn('{not json', {
      authorization: 'Bearer not-a-jwt', cookie: 'sb-access-token=pretend-cookie',
    })],
  ])('refuses %s before attempting to parse the body', async (_label, request) => {
    const response = await POST(request);

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({ ok: false });
  });

  it('does not let an unverified caller choose a member, token, or offline event', async () => {
    const response = await POST(checkIn(JSON.stringify({
      memberId: OTHER_MEMBER_ID,
      token: 'unverified-gate-token',
      clientEventId: EVENT_ID,
      offlineRecordedAt: '2026-09-18T08:00:00.000Z',
    })));

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({ ok: false });
  });

  it('keeps the public assisted-check-in shape separate from member self check-in', async () => {
    const response = await POST(checkIn(JSON.stringify({
      memberId: MEMBER_ID,
      reason: 'member cannot self-assist',
      clientEventId: EVENT_ID,
    })));

    expect(response.status).toBe(401);
    await expect(response.json()).resolves.toMatchObject({ ok: false });
  });
});
