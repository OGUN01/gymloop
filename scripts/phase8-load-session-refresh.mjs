/** Pure, platform-free HARD-004 refresh-session guards shared by Node and k6. */

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const MARKER = /^PHASE8-LOAD-[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SESSION_KEYS = ['gymId', 'userId', 'token', 'refreshToken', 'expiresAt'];

function refuse() { throw new Error('HARD-004 refresh session is missing, mismatched or expired.'); }
function record(value) { return value !== null && typeof value === 'object' && !Array.isArray(value); }
function exactKeys(value, keys) {
  return record(value) && Object.keys(value).length === keys.length &&
    Object.keys(value).every((key) => keys.includes(key));
}
function nonblank(value) { return typeof value === 'string' && value.trim() !== ''; }
function validExpiry(value) { return Number.isSafeInteger(value) && value > 0; }
function validSession(session) {
  return exactKeys(session, SESSION_KEYS) && UUID.test(session.gymId) && UUID.test(session.userId) &&
    nonblank(session.token) && nonblank(session.refreshToken) &&
    session.token !== session.refreshToken && validExpiry(session.expiresAt);
}

/** Bind every private Auth session to the separately validated check-in fixture. */
export function validateRefreshFixture(refreshFixture, checkInFixture) {
  if (!exactKeys(refreshFixture, ['marker', 'gymSessions']) ||
      !record(checkInFixture) || !MARKER.test(refreshFixture.marker) ||
      refreshFixture.marker !== checkInFixture.marker ||
      !Array.isArray(refreshFixture.gymSessions) ||
      !Array.isArray(checkInFixture.gymFixtures) ||
      refreshFixture.gymSessions.length !== checkInFixture.gymFixtures.length ||
      checkInFixture.gymFixtures.length === 0) refuse();
  const gyms = new Map();
  const users = new Set();
  const accessTokens = new Set();
  const refreshTokens = new Set();
  for (const session of refreshFixture.gymSessions) {
    if (!validSession(session) || gyms.has(session.gymId) || users.has(session.userId) ||
        accessTokens.has(session.token) || refreshTokens.has(session.refreshToken)) refuse();
    gyms.set(session.gymId, session);
    users.add(session.userId);
    accessTokens.add(session.token);
    refreshTokens.add(session.refreshToken);
  }
  const order = [];
  const checkInGymIds = new Set();
  for (const gym of checkInFixture.gymFixtures) {
    if (!record(gym) || !UUID.test(gym.gymId) || !nonblank(gym.token) ||
        checkInGymIds.has(gym.gymId)) refuse();
    checkInGymIds.add(gym.gymId);
    const session = gyms.get(gym.gymId);
    if (session?.token !== gym.token) refuse();
    order.push({ ...session });
  }
  return order;
}

/** Trigger at the exact lead boundary; never trust a malformed local clock. */
export function refreshDue(session, nowSeconds, leadSeconds) {
  if (!record(session) || !validExpiry(session.expiresAt) ||
      !Number.isSafeInteger(nowSeconds) || nowSeconds < 0 ||
      !Number.isSafeInteger(leadSeconds) || leadSeconds <= 0) refuse();
  return nowSeconds >= session.expiresAt - leadSeconds;
}

/** Accept only a fresh Auth grant for the same synthetic user. */
export function rotateRefreshSession(session, authResponse, nowSeconds, leadSeconds) {
  if (!validSession(session) || !Number.isSafeInteger(nowSeconds) || nowSeconds < 0 ||
      !Number.isSafeInteger(leadSeconds) || leadSeconds <= 0 ||
      !record(authResponse) || !record(authResponse.user) ||
      authResponse.user.id !== session.userId ||
      !nonblank(authResponse.access_token) || authResponse.access_token === session.token ||
      !nonblank(authResponse.refresh_token) || authResponse.refresh_token === session.refreshToken ||
      authResponse.access_token === authResponse.refresh_token ||
      !validExpiry(authResponse.expires_at) ||
      authResponse.expires_at <= nowSeconds + leadSeconds) refuse();
  return { gymId: session.gymId, userId: session.userId,
    token: authResponse.access_token, refreshToken: authResponse.refresh_token,
    expiresAt: authResponse.expires_at };
}
