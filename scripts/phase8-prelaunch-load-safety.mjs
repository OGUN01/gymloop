/** HARD-004 same-Cloud prelaunch preflight. Validation only; no Cloud writes. */
import { resolve } from 'node:path';
import { PHASE8_PRELAUNCH_LOAD_LIMITS } from '../packages/shared/src/config/constants.ts';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const CONFIRMATION = 'PRELAUNCH_SHARED_LOAD_APPROVED';
const MODE = 'prelaunch-shared';
const {
  gymCount: GYM_COUNT, membersPerGym: MEMBERS_PER_GYM, checkInCount: CHECK_IN_COUNT,
  providerQuotaBytes: QUOTA_BYTES, abortBytes: ABORT_BYTES, maxQuotaAgeMs: MAX_QUOTA_AGE_MS,
  maxMonitorGapSeconds: MAX_MONITOR_GAP_SECONDS, httpStatusMin: HTTP_STATUS_MIN,
  httpSuccessMin: HTTP_SUCCESS_MIN, httpSuccessMax: HTTP_SUCCESS_MAX, httpStatusMax: HTTP_STATUS_MAX,
} = PHASE8_PRELAUNCH_LOAD_LIMITS;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function fail(message) { throw new Error(`HARD-004 prelaunch load safety: ${message}`); }
function nonBlank(value) { return typeof value === 'string' && value.trim() !== ''; }
function exactKeys(value, keys, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) fail(`${label} must be an object.`);
  const expected = new Set(keys);
  const actual = Object.keys(value);
  if (actual.length !== expected.size || actual.some((key) => !expected.has(key))) fail(`${label} has an unexpected or missing field.`);
}
function origin(value, label) {
  if (!nonBlank(value)) fail(`${label} is required.`);
  let url;
  try { url = new globalThis.URL(value); } catch { fail(`${label} is not a valid URL.`); }
  if (url.protocol !== 'https:' || url.username !== '' || url.password !== '' ||
      url.pathname !== '/' || url.search !== '' || url.hash !== '') {
    fail(`${label} must be a credential-free HTTPS origin.`);
  }
  return url.origin;
}
function localPath(value, label) {
  if (!nonBlank(value) || value.includes('\0') || /^[a-z][a-z\d+.-]*:\/\//i.test(value)) {
    fail(`${label} must be a nonblank local path.`);
  }
  return resolve(value);
}

/** Accept only the owner-authorized linked Cloud target, with no secret output. */
export function assertSafePrelaunchTarget(target) {
  exactKeys(target, ['mode', 'projectRef', 'observedApiProjectRef', 'observedSupabaseProjectRef',
    'apiUrl', 'supabaseUrl', 'confirmation', 'credentials', 'noLiveCustomers'], 'target');
  exactKeys(target.credentials, ['kind', 'present', 'projectRef'], 'credentials');
  if (target.mode !== MODE || target.projectRef !== PROJECT_REF ||
      target.observedApiProjectRef !== PROJECT_REF || target.observedSupabaseProjectRef !== PROJECT_REF ||
      target.credentials.kind !== MODE || target.credentials.present !== true ||
      target.credentials.projectRef !== PROJECT_REF || target.confirmation !== CONFIRMATION ||
      target.noLiveCustomers !== true) {
    fail('linked project, observed identities, owner assertion, credentials and confirmation must match.');
  }
  const apiUrl = origin(target.apiUrl, 'API URL');
  const supabaseUrl = origin(target.supabaseUrl, 'Supabase URL');
  if (supabaseUrl !== `https://${PROJECT_REF}.supabase.co`) fail('Supabase origin does not match the linked Cloud project.');
  return { mode: MODE, projectRef: PROJECT_REF, apiUrl, supabaseUrl };
}

/** Require a recent actual CLI size and the reviewed Free-plan abort ceiling. */
export function assertSafePrelaunchQuota(snapshot) {
  exactKeys(snapshot, ['observedAt', 'databaseBytes', 'providerQuotaBytes', 'maxDatabaseBytes'], 'quota snapshot');
  const observed = typeof snapshot.observedAt === 'string' ? new Date(snapshot.observedAt) : new Date(Number.NaN);
  const age = Date.now() - observed.getTime();
  if (!Number.isFinite(observed.getTime()) || observed.toISOString() !== snapshot.observedAt ||
      age < 0 || age > MAX_QUOTA_AGE_MS) fail('CLI database-size observation must be recent canonical UTC.');
  if (!Number.isSafeInteger(snapshot.databaseBytes) || snapshot.databaseBytes < 0 ||
      snapshot.databaseBytes >= ABORT_BYTES || snapshot.providerQuotaBytes !== QUOTA_BYTES ||
      snapshot.maxDatabaseBytes !== ABORT_BYTES) fail('database size or Free-plan quota is outside the safe bound.');
  return { observedAt: snapshot.observedAt, databaseBytes: snapshot.databaseBytes,
    providerQuotaBytes: QUOTA_BYTES, maxDatabaseBytes: ABORT_BYTES };
}

/** Validate the private 100 × 500 fixture without returning its identities. */
export function assertSafePrelaunchFixture(fixture) {
  exactKeys(fixture, ['marker', 'gymFixtures', 'fixturePath', 'baselineManifestPath', 'cleanupManifestPath'], 'fixture');
  if (typeof fixture.marker !== 'string' || !fixture.marker.startsWith('PHASE8-LOAD-') ||
      !UUID.test(fixture.marker.slice('PHASE8-LOAD-'.length))) fail('a fresh run marker is required.');
  const paths = [
    localPath(fixture.fixturePath, 'fixture path'),
    localPath(fixture.baselineManifestPath, 'baseline manifest path'),
    localPath(fixture.cleanupManifestPath, 'cleanup manifest path'),
  ];
  if (new Set(paths).size !== paths.length) fail('fixture and recovery paths must be distinct.');
  if (!Array.isArray(fixture.gymFixtures) || fixture.gymFixtures.length !== GYM_COUNT) fail('exactly 100 gyms are required.');
  const gymIds = new Set(); const tokens = new Set(); const memberIds = new Set();
  for (const gym of fixture.gymFixtures) {
    exactKeys(gym, ['gymId', 'token', 'memberIds', 'ownedMemberIds'], 'gym fixture');
    if (!nonBlank(gym.gymId) || !nonBlank(gym.token) || gymIds.has(gym.gymId) || tokens.has(gym.token)) {
      fail('gym or bearer-token identity is missing or duplicated.');
    }
    gymIds.add(gym.gymId); tokens.add(gym.token);
    if (!Array.isArray(gym.memberIds) || !Array.isArray(gym.ownedMemberIds) ||
        gym.memberIds.length !== MEMBERS_PER_GYM || gym.ownedMemberIds.length !== MEMBERS_PER_GYM) {
      fail('each gym needs exactly 500 owned members.');
    }
    const current = new Set(gym.memberIds); const owned = new Set(gym.ownedMemberIds);
    if (current.size !== MEMBERS_PER_GYM || owned.size !== MEMBERS_PER_GYM ||
        [...current].some((id) => !nonBlank(id) || memberIds.has(id) || !owned.has(id)) ||
        [...owned].some((id) => !nonBlank(id) || !current.has(id))) {
      fail('member identities must be unique, nonblank and exactly owned by their gym.');
    }
    for (const id of current) memberIds.add(id);
  }
  return { marker: fixture.marker, fixturePath: fixture.fixturePath,
    baselineManifestPath: fixture.baselineManifestPath, cleanupManifestPath: fixture.cleanupManifestPath,
    gyms: GYM_COUNT, membersPerGym: MEMBERS_PER_GYM, totalMembers: CHECK_IN_COUNT };
}

/** A pass needs measured load, isolation, live size monitoring and full cleanup. */
export function summarizePrelaunchResult(input) {
  exactKeys(input, ['status', 'target', 'quota', 'fixture', 'rawResultPath', 'thresholds',
    'measured', 'monitor', 'cleanup'], 'result');
  if (!['prepared', 'blocked', 'passed'].includes(input.status)) fail('unknown result status.');
  if (!nonBlank(input.rawResultPath)) fail('a raw result path is required.');
  const rawResultPath = input.rawResultPath;
  if (input.status !== 'passed') return { status: input.status, rawResultPath };
  try {
    const target = assertSafePrelaunchTarget(input.target);
    const quota = assertSafePrelaunchQuota(input.quota);
    const fixture = assertSafePrelaunchFixture(input.fixture);
    exactKeys(input.thresholds, ['p95Ms'], 'thresholds');
    exactKeys(input.measured, ['p95Ms', 'completedCheckIns', 'crossTenantReadDenied', 'crossTenantMutationStatus'], 'measurement');
    exactKeys(input.monitor, ['completed', 'maxObservedDatabaseBytes', 'maxGapSeconds'], 'size monitor');
    exactKeys(input.cleanup, ['completed', 'preexistingUnchanged', 'syntheticRemainderCount', 'authRemainderCount'], 'cleanup');
    const threshold = input.thresholds.p95Ms;
    const measured = input.measured;
    const monitor = input.monitor;
    const cleanup = input.cleanup;
    if (typeof threshold !== 'number' || !Number.isFinite(threshold) || threshold <= 0 ||
        typeof measured.p95Ms !== 'number' || !Number.isFinite(measured.p95Ms) || measured.p95Ms < 0 ||
        measured.p95Ms > threshold || measured.completedCheckIns !== CHECK_IN_COUNT ||
        measured.crossTenantReadDenied !== true ||
        !Number.isInteger(measured.crossTenantMutationStatus) || measured.crossTenantMutationStatus < HTTP_STATUS_MIN ||
        measured.crossTenantMutationStatus > HTTP_STATUS_MAX ||
        (measured.crossTenantMutationStatus >= HTTP_SUCCESS_MIN && measured.crossTenantMutationStatus <= HTTP_SUCCESS_MAX) ||
        monitor.completed !== true || !Number.isSafeInteger(monitor.maxObservedDatabaseBytes) ||
        monitor.maxObservedDatabaseBytes < 0 || monitor.maxObservedDatabaseBytes >= ABORT_BYTES ||
        typeof monitor.maxGapSeconds !== 'number' || !Number.isFinite(monitor.maxGapSeconds) ||
        monitor.maxGapSeconds < 0 || monitor.maxGapSeconds > MAX_MONITOR_GAP_SECONDS ||
        cleanup.completed !== true || cleanup.preexistingUnchanged !== true ||
        cleanup.syntheticRemainderCount !== 0 || cleanup.authRemainderCount !== 0) {
      return { status: 'blocked', rawResultPath };
    }
    return { status: 'passed', rawResultPath, target, quota, fixture, thresholds: { p95Ms: threshold },
      measured: { ...measured }, monitor: { ...monitor }, cleanup: { ...cleanup } };
  } catch {
    return { status: 'blocked', rawResultPath };
  }
}
