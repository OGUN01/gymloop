import { randomUUID } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';

import {
  refreshDue,
  rotateRefreshSession,
  validateRefreshFixture,
} from '../phase8-load-session-refresh.mjs';

const MARKER = 'PHASE8-LOAD-11111111-2222-4333-8444-555555555555';
const NOW_SECONDS = 2_000_000_000;
const LEAD_SECONDS = 120;
const CHECK_IN_FIXTURE = {
  marker: MARKER,
  gymFixtures: Array.from({ length: 100 }, (_, gymIndex) => ({
    gymId: randomUUID(),
    token: `access-secret-${gymIndex}`,
    memberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
    ownedMemberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
  })),
  fixturePath: 'artifacts/phase8-load/check-in-fixture.json',
  baselineManifestPath: 'artifacts/phase8-load/baseline.json',
  cleanupManifestPath: 'artifacts/phase8-load/recovery.jsonl',
};
const SESSIONS = CHECK_IN_FIXTURE.gymFixtures.map((gym, index) => ({
  gymId: gym.gymId,
  userId: randomUUID(),
  token: gym.token,
  refreshToken: `refresh-secret-${index}`,
  expiresAt: NOW_SECONDS + 900,
}));
const REFRESH_FIXTURE = { marker: MARKER, gymSessions: SESSIONS };
const K6_SOURCE = readFileSync(new URL('../../tests/load/phase8-morning-checkin.js', import.meta.url), 'utf8');
const changedSession = (index: number, patch: Record<string, unknown>) => ({
  marker: MARKER,
  gymSessions: SESSIONS.map((session, current) => current === index ? { ...session, ...patch } : session),
});
const expectSecretFreeFailure = (operation: () => unknown, secrets: string[]) => {
  let caught: unknown;
  try { operation(); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(Error);
  const message = String(caught);
  for (const secret of secrets) expect(message.includes(secret)).toBe(false);
};

describe('HARD-004 refresh fixture binding', () => {
  it('returns exactly 100 bound sessions in check-in fixture order without mutating the input', () => {
    const unordered = { ...REFRESH_FIXTURE, gymSessions: [...SESSIONS].reverse() };
    const before = structuredClone(unordered);
    const validated = validateRefreshFixture(unordered, CHECK_IN_FIXTURE);
    expect(validated).toEqual(SESSIONS);
    expect(unordered).toEqual(before);
    expect(new Set(validated.map((session: { userId: string }) => session.userId)).size).toBe(100);
  });

  it('rejects a marker mismatch, missing gym, foreign gym and an access token bound to another gym', () => {
    const foreign = changedSession(1, { gymId: randomUUID() });
    for (const fixture of [
      { ...REFRESH_FIXTURE, marker: 'PHASE8-LOAD-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee' },
      { ...REFRESH_FIXTURE, gymSessions: SESSIONS.slice(1) },
      foreign,
      changedSession(1, { gymId: SESSIONS[0].gymId }),
      changedSession(1, { token: SESSIONS[0].token }),
      changedSession(1, { token: 'different-access-secret' }),
    ]) {
      expect(() => validateRefreshFixture(fixture, CHECK_IN_FIXTURE)).toThrow();
    }
  });

  it('rejects duplicate user, access and refresh identities rather than accepting 100 rows by count', () => {
    for (const fixture of [
      changedSession(1, { userId: SESSIONS[0].userId }),
      changedSession(1, { token: SESSIONS[0].token }),
      changedSession(1, { refreshToken: SESSIONS[0].refreshToken }),
    ]) {
      expect(() => validateRefreshFixture(fixture, CHECK_IN_FIXTURE)).toThrow();
    }
  });

  it('requires complete exact session credentials and an integer Unix expiry', () => {
    for (const fixture of [
      changedSession(0, { userId: '' }),
      changedSession(0, { token: '' }),
      changedSession(0, { refreshToken: '' }),
      changedSession(0, { refreshToken: undefined }),
      changedSession(0, { expiresAt: '2000000900' }),
      changedSession(0, { expiresAt: 2_000_000_900.5 }),
      changedSession(0, { expiresAt: Number.NaN }),
      changedSession(0, { unexpected: 'extra' }),
      { ...REFRESH_FIXTURE, unexpected: 'extra' },
    ]) {
      expect(() => validateRefreshFixture(fixture, CHECK_IN_FIXTURE)).toThrow();
    }
  });

  it('does not reveal access or refresh credentials when binding fails', () => {
    const secret = 'refresh-secret-sensitive-do-not-print';
    const bad = changedSession(0, { token: 'access-secret-sensitive-do-not-print', refreshToken: secret });
    expectSecretFreeFailure(() => validateRefreshFixture(bad, CHECK_IN_FIXTURE), [
      secret,
      'access-secret-sensitive-do-not-print',
      SESSIONS[0].token,
    ]);
  });
});

describe('HARD-004 refresh lead boundary', () => {
  const session = { ...SESSIONS[0], expiresAt: NOW_SECONDS + 900 };

  it('becomes due at the exact expiry-minus-lead second', () => {
    expect(refreshDue(session, session.expiresAt - LEAD_SECONDS - 1, LEAD_SECONDS)).toBe(false);
    expect(refreshDue(session, session.expiresAt - LEAD_SECONDS, LEAD_SECONDS)).toBe(true);
    expect(refreshDue(session, session.expiresAt - LEAD_SECONDS + 1, LEAD_SECONDS)).toBe(true);
    expect(refreshDue(session, session.expiresAt, LEAD_SECONDS)).toBe(true);
  });

  it('refuses nonpositive or noninteger lead times and malformed expiry', () => {
    for (const lead of [0, -1, 1.5, Number.NaN]) {
      expect(() => refreshDue(session, NOW_SECONDS, lead)).toThrow();
    }
    expect(() => refreshDue({ ...session, expiresAt: Number.NaN }, NOW_SECONDS, LEAD_SECONDS)).toThrow();
  });
});

describe('HARD-004 one-time refresh rotation', () => {
  const session = { ...SESSIONS[0], expiresAt: NOW_SECONDS + LEAD_SECONDS };
  const response = {
    access_token: 'new-access-secret',
    refresh_token: 'new-refresh-secret',
    expires_at: NOW_SECONDS + LEAD_SECONDS + 1,
    user: { id: session.userId },
  };

  it('preserves gym and Auth user identity while replacing both tokens and expiry', () => {
    const original = structuredClone(session);
    const next = rotateRefreshSession(session, response, NOW_SECONDS, LEAD_SECONDS);
    expect(next).toEqual({
      gymId: session.gymId,
      userId: session.userId,
      token: response.access_token,
      refreshToken: response.refresh_token,
      expiresAt: response.expires_at,
    });
    expect(session).toEqual(original);
    expect(refreshDue(next, NOW_SECONDS, LEAD_SECONDS)).toBe(false);
  });

  it('rejects a replayed refresh response and cross-user rotation', () => {
    const next = rotateRefreshSession(session, response, NOW_SECONDS, LEAD_SECONDS);
    expect(() => rotateRefreshSession(next, response, NOW_SECONDS, LEAD_SECONDS)).toThrow();
    expect(() => rotateRefreshSession(session, { ...response, user: { id: SESSIONS[1].userId } }, NOW_SECONDS, LEAD_SECONDS)).toThrow();
  });

  it('requires a fresh access token, different nonblank refresh token and expiry beyond the lead window', () => {
    for (const rejected of [
      { ...response, access_token: session.token },
      { ...response, access_token: '' },
      { ...response, refresh_token: session.refreshToken },
      { ...response, refresh_token: '' },
      { ...response, expires_at: NOW_SECONDS + LEAD_SECONDS },
      { ...response, expires_at: '2000000121' },
      { ...response, expires_at: NOW_SECONDS + LEAD_SECONDS + 1.5 },
    ]) {
      expect(() => rotateRefreshSession(session, rejected, NOW_SECONDS, LEAD_SECONDS)).toThrow();
    }
  });

  it('rejects failed and malformed Supabase grant payloads without exposing either token', () => {
    for (const rejected of [
      null,
      { error: 'invalid_grant', access_token: 'leaky-access-secret' },
      { ...response, user: undefined },
      { ...response, expires_at: undefined },
      { ...response, refresh_token: undefined },
    ]) {
      expectSecretFreeFailure(() => rotateRefreshSession(session, rejected, NOW_SECONDS, LEAD_SECONDS), [
        session.token,
        session.refreshToken,
        'new-access-secret',
        'new-refresh-secret',
        'leaky-access-secret',
      ]);
    }
  });
});

describe('HARD-004 k6 refresh transport', () => {
  it('opens a separate private refresh file and uses the fixed lead and Supabase refresh grant', () => {
    expect(K6_SOURCE.includes('PHASE8_LOAD_REFRESH_PATH')).toBe(true);
    expect(K6_SOURCE.includes('PHASE8_LOAD_REFRESH_LEAD_SECONDS')).toBe(true);
    expect((K6_SOURCE.match(/\bopen\s*\(/g) ?? []).length).toBeGreaterThanOrEqual(2);
    expect(/auth\/v1\/token/i.test(K6_SOURCE)).toBe(true);
    expect(/grant_type/i.test(K6_SOURCE) && /refresh_token/i.test(K6_SOURCE)).toBe(true);
    expect(/__ENV\.[A-Z0-9_]*(?:ACCESS_TOKEN|REFRESH_TOKEN)[A-Z0-9_]*/i.test(K6_SOURCE)).toBe(false);
  });
});
