/**
 * HARD-004's local safety boundary. This module deliberately neither starts k6
 * nor discovers a Supabase project: both actions would turn an incomplete
 * safety check into traffic. The operator supplies a reviewed JSON target to
 * the k6 command only after this preflight succeeds.
 */

import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

const PRODUCTION_PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const REQUIRED_CONFIRMATION = 'NON_PRODUCTION_LOAD_APPROVED';
const MORNING_CHECK_IN_WORKLOAD = Object.freeze({
  gyms: 100,
  membersPerGym: 500,
  totalMembers: 50_000,
  spike: Object.freeze({ name: 'morning_check_in_spike' }),
});

function nonBlankString(value) {
  return typeof value === 'string' && value.trim() !== '';
}

function loadSafetyError(message) {
  return new Error(`HARD-004 load safety: ${message}`);
}

/**
 * Refuse a target unless an operator has identified a distinct project and
 * explicitly confirmed non-production credentials. URL resolution is an
 * infrastructure fact, so a supplied resolvedProjectRef is checked rather
 * than guessed with a network call.
 */
export function assertSafeLoadTarget(target) {
  if (target === null || typeof target !== 'object') {
    throw loadSafetyError('a target object is required before any network activity.');
  }
  if (!nonBlankString(target.projectRef)) {
    throw loadSafetyError('an explicit non-production project reference is required.');
  }
  if (!nonBlankString(target.apiUrl)) {
    throw loadSafetyError('an explicit API URL is required.');
  }
  let apiUrl;
  try {
    apiUrl = new globalThis.URL(target.apiUrl);
  } catch {
    throw loadSafetyError('the API URL is not valid.');
  }
  if (apiUrl.protocol !== 'https:') {
    throw loadSafetyError('the API URL must use HTTPS.');
  }
  const projectReferences = [target.projectRef, target.resolvedProjectRef, apiUrl.hostname];
  if (projectReferences.some((reference) => reference === PRODUCTION_PROJECT_REF ||
      (typeof reference === 'string' && reference.includes(PRODUCTION_PROJECT_REF)))) {
    throw loadSafetyError('the configured production project is never a load target.');
  }
  if (target.credentials === null || typeof target.credentials !== 'object' ||
      target.credentials.kind !== 'non-production' || target.credentials.present !== true) {
    throw loadSafetyError('explicit non-production credentials are required.');
  }
  if (target.confirmation !== REQUIRED_CONFIRMATION) {
    throw loadSafetyError('explicit non-production confirmation is required.');
  }
  return {
    projectRef: target.projectRef,
    apiUrl: apiUrl.toString(),
    nonProduction: true,
  };
}

/** Builds the fixed workload only after the operator supplies a real p95 bar. */
export function buildMorningCheckInWorkload(options = undefined) {
  const thresholds = options?.thresholds;
  if (thresholds === null || typeof thresholds !== 'object' ||
      typeof thresholds.p95Ms !== 'number' || !Number.isFinite(thresholds.p95Ms) || thresholds.p95Ms <= 0) {
    throw loadSafetyError('a caller-supplied positive p95 threshold is required.');
  }
  const tenantIsolation = options?.tenantIsolation;
  if (tenantIsolation !== undefined &&
      (tenantIsolation === null || typeof tenantIsolation !== 'object' ||
       tenantIsolation.denyCrossTenantRead !== true || tenantIsolation.denyCrossTenantMutation !== true)) {
    throw loadSafetyError('both cross-tenant denial assertions are required when isolation is configured.');
  }
  return {
    ...MORNING_CHECK_IN_WORKLOAD,
    thresholds: { p95Ms: thresholds.p95Ms },
    tenantIsolation: tenantIsolation === undefined ? undefined : {
      denyCrossTenantRead: true,
      denyCrossTenantMutation: true,
    },
  };
}

/** Produces ledger-ready metadata; it does not infer a pass from a file path. */
export function summarizeRawResult(result) {
  if (result === null || typeof result !== 'object' || !nonBlankString(result.rawResultPath)) {
    throw loadSafetyError('a caller-selected raw result path is required.');
  }
  if (!nonBlankString(result.status)) {
    throw loadSafetyError('an explicit result status is required.');
  }
  return { rawResultPath: result.rawResultPath, status: result.status };
}

/**
 * Checks every local input needed before an operator invokes k6. The returned
 * command intentionally contains no credential values: k6 receives those
 * from the operator's secret injector, not a command line or log.
 */
export function preflightLoadRun(config) {
  if (config === null || typeof config !== 'object') {
    throw loadSafetyError('a reviewed run configuration is required.');
  }
  const target = assertSafeLoadTarget(config.target);
  const workload = buildMorningCheckInWorkload({
    thresholds: config.thresholds,
    tenantIsolation: config.tenantIsolation,
  });
  const result = summarizeRawResult({ rawResultPath: config.rawResultPath, status: 'prepared' });
  if (!nonBlankString(config.fixturePath)) {
    throw loadSafetyError('a caller-selected isolated fixture path is required.');
  }
  return {
    target,
    workload,
    fixturePath: config.fixturePath,
    rawResultPath: result.rawResultPath,
    command: `k6 run --out json=${result.rawResultPath} tests/load/phase8-morning-checkin.js`,
  };
}

function main() {
  const configPath = process.argv[2];
  if (!nonBlankString(configPath)) {
    throw loadSafetyError('pass the reviewed load-run JSON file as the only argument.');
  }
  let config;
  try {
    config = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch {
    throw loadSafetyError('the reviewed load-run JSON file could not be read.');
  }
  const preflight = preflightLoadRun(config);
  console.log(JSON.stringify({
    projectRef: preflight.target.projectRef,
    apiUrl: preflight.target.apiUrl,
    workload: preflight.workload,
    fixturePath: preflight.fixturePath,
    rawResultPath: preflight.rawResultPath,
    command: preflight.command,
  }));
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) main();
