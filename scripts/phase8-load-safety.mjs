/** HARD-004 local preflight. It never starts k6 or discovers a project. */
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const REQUIRED_CONFIRMATION = 'NON_PRODUCTION_LOAD_APPROVED';
const GYM_COUNT = 100;
const MEMBERS_PER_GYM = 500;
const TOTAL_MEMBER_CHECK_INS = 50_000;
const TENANT_ISOLATION_FLAG_COUNT = 2;
const HTTP_SUCCESS_MIN = 200;
const HTTP_SUCCESS_MAX = 299;
const workloadSources = new WeakMap();

function nonBlankString(value) { return typeof value === 'string' && value.trim() !== ''; }
function loadSafetyError(message) { return new Error(`HARD-004 load safety: ${message}`); }

function exactKeys(value, keys, label) {
  if (value === null || typeof value !== 'object' || Array.isArray(value) ||
      Object.keys(value).length !== keys.length || !keys.every((key) => Object.hasOwn(value, key))) {
    throw loadSafetyError(`${label} has an unexpected or missing field.`);
  }
}

function originOnly(value, label) {
  if (!nonBlankString(value)) throw loadSafetyError(`${label} is required.`);
  let url;
  try { url = new globalThis.URL(value); } catch { throw loadSafetyError(`${label} is not a valid URL.`); }
  if (url.protocol !== 'https:') throw loadSafetyError(`${label} must use HTTPS.`);
  if (url.username !== '' || url.password !== '' || url.pathname !== '/' || url.search !== '' || url.hash !== '') {
    throw loadSafetyError(`${label} must be an origin-only URL without credentials, path, query, or fragment.`);
  }
  return url.origin;
}

function positiveThreshold(thresholds) {
  if (thresholds === null || typeof thresholds !== 'object' || Array.isArray(thresholds) ||
      Object.keys(thresholds).length !== 1 || !Object.hasOwn(thresholds, 'p95Ms') ||
      typeof thresholds.p95Ms !== 'number' || !Number.isFinite(thresholds.p95Ms) || thresholds.p95Ms <= 0) {
    throw loadSafetyError('a caller-supplied finite positive p95 threshold is required.');
  }
  return thresholds.p95Ms;
}

function validatedFixtures(gymFixtures) {
  if (!Array.isArray(gymFixtures) || gymFixtures.length !== GYM_COUNT) {
    throw loadSafetyError(`exactly ${GYM_COUNT} caller-supplied gym fixtures are required.`);
  }
  const gymIds = new Set(); const tokens = new Set(); const memberIds = new Set();
  return gymFixtures.map((fixture) => {
    exactKeys(fixture, ['gymId', 'token', 'memberIds', 'ownedMemberIds'], 'a gym fixture');
    if (!nonBlankString(fixture.gymId) || !nonBlankString(fixture.token) || !Array.isArray(fixture.memberIds) ||
        !Array.isArray(fixture.ownedMemberIds) || fixture.memberIds.length !== MEMBERS_PER_GYM ||
        fixture.ownedMemberIds.length !== MEMBERS_PER_GYM) {
      throw loadSafetyError(`each fixture needs ${MEMBERS_PER_GYM} owned member ids and one gym identity.`);
    }
    if (gymIds.has(fixture.gymId) || tokens.has(fixture.token)) throw loadSafetyError('duplicate gym identity or token is not isolated.');
    gymIds.add(fixture.gymId); tokens.add(fixture.token);
    const owned = new Set(fixture.ownedMemberIds); const currentMembers = new Set(fixture.memberIds);
    if (owned.size !== MEMBERS_PER_GYM || currentMembers.size !== MEMBERS_PER_GYM) {
      throw loadSafetyError('duplicate member identity is not isolated.');
    }
    if ([...owned].some((memberId) => !nonBlankString(memberId)) || [...currentMembers].some((memberId) => !nonBlankString(memberId))) {
      throw loadSafetyError('each fixture member identity must be nonblank.');
    }
    for (const memberId of currentMembers) {
      if (memberIds.has(memberId)) throw loadSafetyError('duplicate or cross-owned member identity is not isolated.');
    }
    if (owned.size !== currentMembers.size || [...owned].some((memberId) => !currentMembers.has(memberId))) {
      throw loadSafetyError('each fixture member set must exactly equal its owned member set.');
    }
    for (const memberId of currentMembers) {
      memberIds.add(memberId);
    }
    return { gymId: fixture.gymId, memberIds: [...fixture.memberIds], ownedMemberIds: [...fixture.ownedMemberIds] };
  });
}

/** Validates the canonical non-production target and returns no credentials. */
export function assertSafeLoadTarget(target) {
  exactKeys(target, ['projectRef', 'observedApiProjectRef', 'observedSupabaseProjectRef', 'apiUrl', 'supabaseUrl', 'confirmation', 'credentials'], 'the target');
  if (!nonBlankString(target.projectRef) || !nonBlankString(target.observedApiProjectRef) || !nonBlankString(target.observedSupabaseProjectRef)) {
    throw loadSafetyError('configured and observed project references are required.');
  }
  const apiUrl = originOnly(target.apiUrl, 'the API URL');
  const supabaseUrl = originOnly(target.supabaseUrl, 'the Supabase URL');
  if (target.credentials === null || typeof target.credentials !== 'object' || target.credentials.kind !== 'non-production') {
    throw loadSafetyError('explicit non-production credentials are required.');
  }
  exactKeys(target.credentials, ['kind', 'present', 'projectRef'], 'the credentials');
  const references = [target.projectRef, target.observedApiProjectRef, target.observedSupabaseProjectRef, target.credentials.projectRef];
  if (references.some((reference) => reference === PRODUCTION_PROJECT_REF) || apiUrl.includes(PRODUCTION_PROJECT_REF) || supabaseUrl.includes(PRODUCTION_PROJECT_REF)) {
    throw loadSafetyError('the configured production project is never a load target.');
  }
  if (references.some((reference) => reference !== target.projectRef)) throw loadSafetyError('configured, observed, and credential project references must match.');
  if (new globalThis.URL(supabaseUrl).hostname !== `${target.projectRef}.supabase.co`) throw loadSafetyError('the Supabase origin hostname must match the project reference.');
  if (target.confirmation !== REQUIRED_CONFIRMATION || target.credentials.kind !== 'non-production' || target.credentials.present !== true) {
    throw loadSafetyError('explicit non-production credentials and confirmation are required.');
  }
  return { projectRef: target.projectRef, apiUrl, supabaseUrl, nonProduction: true };
}

/** Validates the complete caller-owned 100 × 500 workload without synthesis. */
export function buildMorningCheckInWorkload(options = undefined) {
  const p95Ms = positiveThreshold(options?.thresholds);
  const tenantIsolation = options?.tenantIsolation ?? { denyCrossTenantRead: true, denyCrossTenantMutation: true };
  if (tenantIsolation === null || typeof tenantIsolation !== 'object' || Array.isArray(tenantIsolation) ||
      Object.keys(tenantIsolation).length !== TENANT_ISOLATION_FLAG_COUNT || tenantIsolation.denyCrossTenantRead !== true || tenantIsolation.denyCrossTenantMutation !== true) {
    throw loadSafetyError('both cross-tenant denial assertions must be exactly true.');
  }
  const safeFixtures = validatedFixtures(options?.gymFixtures);
  const workload = { gyms: GYM_COUNT, membersPerGym: MEMBERS_PER_GYM, totalMembers: TOTAL_MEMBER_CHECK_INS,
    spike: { name: 'morning_check_in_spike' }, thresholds: { p95Ms },
    tenantIsolation: { denyCrossTenantRead: true, denyCrossTenantMutation: true }, gymFixtures: safeFixtures };
  workloadSources.set(workload, { thresholds: options.thresholds, tenantIsolation, gymFixtures: options.gymFixtures });
  return workload;
}

function has2xx(status) { return typeof status === 'number' && Number.isInteger(status) && status >= HTTP_SUCCESS_MIN && status <= HTTP_SUCCESS_MAX; }

/** A pass requires real measured evidence, never a status string alone. */
export function summarizeRawResult(input) {
  if (input === null || typeof input !== 'object' || !nonBlankString(input.rawResultPath) || !nonBlankString(input.status)) {
    throw loadSafetyError('a raw result path and requested status are required.');
  }
  if (input.status === 'prepared' || input.status === 'blocked') return { rawResultPath: input.rawResultPath, status: input.status };
  if (input.status !== 'passed') throw loadSafetyError('only prepared, blocked, or evidence-backed passed status is allowed.');
  try {
    const target = assertSafeLoadTarget(input.target);
    const threshold = positiveThreshold(input.thresholds);
    const measured = input.measured !== null && typeof input.measured === 'object' ? input.measured : input.measured === true ? input : null;
    const readDenied = measured?.crossTenantReadDenied ?? input.tenantIsolation?.denyCrossTenantRead;
    const mutationStatus = measured?.crossTenantMutationStatus;
    const legacyMutationDenied = input.measured === true && input.tenantIsolation?.denyCrossTenantMutation === true;
    if (typeof measured?.p95Ms !== 'number' || !Number.isFinite(measured.p95Ms) || measured.p95Ms > threshold ||
        measured.completedCheckIns !== TOTAL_MEMBER_CHECK_INS || readDenied !== true ||
        (mutationStatus === undefined ? !legacyMutationDenied : has2xx(mutationStatus))) return { rawResultPath: input.rawResultPath, status: 'blocked' };
    return { rawResultPath: input.rawResultPath, status: 'passed', projectRef: target.projectRef, apiUrl: target.apiUrl, supabaseUrl: target.supabaseUrl, completedCheckIns: TOTAL_MEMBER_CHECK_INS };
  } catch { return { rawResultPath: input.rawResultPath, status: 'blocked' }; }
}

/** Revalidates untrusted configuration immediately before an operator invokes k6. */
export function preflightLoadRun(config) {
  if (config === null || typeof config !== 'object') throw loadSafetyError('a reviewed run configuration is required.');
  const target = assertSafeLoadTarget(config.target);
  const source = workloadSources.get(config.workload);
  const workload = buildMorningCheckInWorkload(source ?? config.workload);
  if (!nonBlankString(config.rawResultPath)) throw loadSafetyError('a caller-selected raw result path is required.');
  if (Array.isArray(config.mutationStatuses) && config.mutationStatuses.some(has2xx)) throw loadSafetyError('a cross-tenant mutation 2xx response is a failure.');
  return { target, workload, rawResultPath: config.rawResultPath, command: `k6 run --out json=${config.rawResultPath} tests/load/phase8-morning-checkin.js` };
}

function main() {
  const configPath = process.argv[2];
  if (!nonBlankString(configPath)) throw loadSafetyError('pass a reviewed load-run JSON file.');
  let config; try { config = JSON.parse(readFileSync(configPath, 'utf8')); } catch { throw loadSafetyError('the reviewed load-run JSON file could not be read.'); }
  console.log(JSON.stringify(preflightLoadRun(config)));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
