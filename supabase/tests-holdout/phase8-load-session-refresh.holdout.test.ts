import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { describe, expect, it } from 'vitest'
import {
  validateRefreshFixture,
  refreshDue,
  rotateRefreshSession,
} from '../../scripts/phase8-load-session-refresh.mjs'

const marker = `PHASE8-LOAD-${randomUUID()}`
const expiry = 1_900_000_900
const leadSeconds = 120

function uuid(number: number) {
  return `00000000-0000-4000-8000-${number.toString(16).padStart(12, '0')}`
}

function checkInFixture() {
  const root = join(tmpdir(), 'gymloop-refresh-holdout')
  return {
    marker,
    fixturePath: join(root, 'checkins.json'),
    baselineManifestPath: join(root, 'baseline.json'),
    cleanupManifestPath: join(root, 'cleanup.json'),
    gymFixtures: Array.from({ length: 100 }, (_, gymIndex) => {
      const memberIds = Array.from({ length: 500 }, (_, memberIndex) => uuid(1_000 + gymIndex * 500 + memberIndex))
      return {
        gymId: uuid(gymIndex + 1),
        token: `HOLDOUT_ACCESS_SECRET_${gymIndex}`,
        memberIds,
        ownedMemberIds: [...memberIds].reverse(),
      }
    }),
  }
}

function refreshFixture(checkIns: ReturnType<typeof checkInFixture>) {
  return {
    marker: checkIns.marker,
    gymSessions: checkIns.gymFixtures.map((gym, index) => ({
      gymId: gym.gymId,
      userId: uuid(100_000 + index),
      token: gym.token,
      refreshToken: `HOLDOUT_REFRESH_SECRET_${index}`,
      expiresAt: expiry,
    })),
  }
}

function assertSafeRefusal(action: () => unknown, secrets: string[]) {
  let refusal: unknown
  try {
    action()
  } catch (error) {
    refusal = error
  }
  expect(refusal).toBeInstanceOf(Error)
  const message = String(refusal)
  for (const secret of secrets) expect(message.includes(secret)).toBe(false)
}

function authResponse(session: ReturnType<typeof refreshFixture>['gymSessions'][number], nowSeconds: number) {
  return {
    access_token: `HOLDOUT_NEW_ACCESS_${session.gymId}`,
    refresh_token: `HOLDOUT_NEW_REFRESH_${session.gymId}`,
    expires_at: nowSeconds + leadSeconds + 1,
    user: { id: session.userId },
  }
}

describe('HARD-004 refresh fixture binding holdout', () => {
  it('returns all 100 complete sessions in check-in order despite a reordered refresh file', () => {
    const checkIns = checkInFixture()
    const refresh = refreshFixture(checkIns)
    refresh.gymSessions.reverse()
    const sessions = validateRefreshFixture(refresh, checkIns)
    expect(sessions).toHaveLength(100)
    expect(sessions.map((session: { gymId: string }) => session.gymId)).toEqual(checkIns.gymFixtures.map((gym) => gym.gymId))
    for (let index = 0; index < sessions.length; index += 1) {
      expect(sessions[index].token).toBe(checkIns.gymFixtures[index].token)
      expect(sessions[index].refreshToken).toBe(`HOLDOUT_REFRESH_SECRET_${index}`)
      expect(sessions[index].expiresAt).toBe(expiry)
    }
  })

  it.each([
    ['wrong run marker', (value: ReturnType<typeof refreshFixture>) => { value.marker = `PHASE8-LOAD-${randomUUID()}` }],
    ['missing gym', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions.pop() }],
    ['duplicate gym', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[1].gymId = value.gymSessions[0].gymId }],
    ['duplicate Auth user', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[1].userId = value.gymSessions[0].userId }],
    ['duplicate access token', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[1].token = value.gymSessions[0].token }],
    ['duplicate refresh token', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[1].refreshToken = value.gymSessions[0].refreshToken }],
    ['blank access token', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[0].token = '  ' }],
    ['blank refresh token', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[0].refreshToken = '  ' }],
    ['missing Auth user', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[0].userId = '' }],
    ['fractional Unix expiry', (value: ReturnType<typeof refreshFixture>) => { value.gymSessions[0].expiresAt = expiry + 0.5 }],
  ])('rejects %s without revealing tokens', (_label, corrupt) => {
    const checkIns = checkInFixture()
    const refresh = refreshFixture(checkIns)
    corrupt(refresh)
    assertSafeRefusal(() => validateRefreshFixture(refresh, checkIns), [
      'HOLDOUT_ACCESS_SECRET_0',
      'HOLDOUT_REFRESH_SECRET_0',
    ])
  })

  it('rejects access tokens swapped between otherwise complete gym sessions', () => {
    const checkIns = checkInFixture()
    const refresh = refreshFixture(checkIns)
    const token = refresh.gymSessions[0].token
    refresh.gymSessions[0].token = refresh.gymSessions[1].token
    refresh.gymSessions[1].token = token
    assertSafeRefusal(() => validateRefreshFixture(refresh, checkIns), [
      'HOLDOUT_ACCESS_SECRET_0',
      'HOLDOUT_ACCESS_SECRET_1',
    ])
  })

  it('rejects unexpected top-level and session fields', () => {
    const checkIns = checkInFixture()
    const refresh = refreshFixture(checkIns)
    assertSafeRefusal(
      () => validateRefreshFixture({ ...refresh, extra: 'unsafe' }, checkIns),
      ['HOLDOUT_ACCESS_SECRET_0'],
    )
    assertSafeRefusal(
      () => validateRefreshFixture({
        ...refresh,
        gymSessions: [{ ...refresh.gymSessions[0], extra: 'unsafe' }, ...refresh.gymSessions.slice(1)],
      }, checkIns),
      ['HOLDOUT_ACCESS_SECRET_0'],
    )
  })
})

describe('HARD-004 exact refresh boundary holdout', () => {
  const session = refreshFixture(checkInFixture()).gymSessions[0]

  it('turns due at the exact 120-second boundary', () => {
    expect(refreshDue(session, expiry - leadSeconds - 1, leadSeconds)).toBe(false)
    expect(refreshDue(session, expiry - leadSeconds, leadSeconds)).toBe(true)
    expect(refreshDue(session, expiry - 1, leadSeconds)).toBe(true)
    expect(refreshDue(session, expiry, leadSeconds)).toBe(true)
    expect(refreshDue(session, expiry + 1, leadSeconds)).toBe(true)
  })

  it.each([0, -1, 1.5, Number.NaN, Number.POSITIVE_INFINITY])('rejects a non-positive or non-integer lead of %s', (lead) => {
    assertSafeRefusal(() => refreshDue(session, expiry - leadSeconds, lead), [session.token, session.refreshToken])
  })
})

describe('HARD-004 one-time Supabase session rotation holdout', () => {
  const session = refreshFixture(checkInFixture()).gymSessions[0]
  const nowSeconds = expiry - leadSeconds

  it('keeps gym and Auth identity, rotates both tokens, and leaves the old session untouched', () => {
    const original = { ...session }
    const response = authResponse(session, nowSeconds)
    const rotated = rotateRefreshSession(session, response, nowSeconds, leadSeconds)
    expect(rotated).toEqual({
      gymId: session.gymId,
      userId: session.userId,
      token: response.access_token,
      refreshToken: response.refresh_token,
      expiresAt: response.expires_at,
    })
    expect(session).toEqual(original)
    assertSafeRefusal(
      () => rotateRefreshSession(rotated, response, nowSeconds, leadSeconds),
      [response.access_token, response.refresh_token],
    )
  })

  it.each([
    ['missing Auth response', (_response: ReturnType<typeof authResponse>) => null],
    ['failed grant', (_response: ReturnType<typeof authResponse>) => ({ error: 'invalid_grant' })],
    ['missing returned user', (response: ReturnType<typeof authResponse>) => ({ ...response, user: undefined })],
    ['different Auth user', (response: ReturnType<typeof authResponse>) => ({ ...response, user: { id: randomUUID() } })],
    ['reused access token', (response: ReturnType<typeof authResponse>) => ({ ...response, access_token: session.token })],
    ['blank new access token', (response: ReturnType<typeof authResponse>) => ({ ...response, access_token: '  ' })],
    ['reused one-time refresh token', (response: ReturnType<typeof authResponse>) => ({ ...response, refresh_token: session.refreshToken })],
    ['blank new refresh token', (response: ReturnType<typeof authResponse>) => ({ ...response, refresh_token: '  ' })],
    ['expiry at lead boundary', (response: ReturnType<typeof authResponse>) => ({ ...response, expires_at: nowSeconds + leadSeconds })],
    ['already expired return', (response: ReturnType<typeof authResponse>) => ({ ...response, expires_at: nowSeconds - 1 })],
    ['fractional returned expiry', (response: ReturnType<typeof authResponse>) => ({ ...response, expires_at: nowSeconds + leadSeconds + 0.5 })],
    ['string returned expiry', (response: ReturnType<typeof authResponse>) => ({ ...response, expires_at: String(nowSeconds + leadSeconds + 1) })],
  ])('refuses %s without exposing credentials', (_label, change) => {
    const response = change(authResponse(session, nowSeconds))
    assertSafeRefusal(() => rotateRefreshSession(session, response, nowSeconds, leadSeconds), [
      session.token,
      session.refreshToken,
      `HOLDOUT_NEW_ACCESS_${session.gymId}`,
      `HOLDOUT_NEW_REFRESH_${session.gymId}`,
    ])
  })
})
