/** HARD-005 deterministic production alert evaluator. */
import { readFileSync } from 'node:fs';
import { PHASE8_MONITOR_LATENCY, PHASE8_PRELAUNCH_LOAD_LIMITS } from '../packages/shared/src/config/constants.ts';

const SCHEMA_VERSION = 1;
const ALERT_WINDOW_MINUTES = 5;
const SECONDS_PER_MINUTE = 60;
const MILLISECONDS_PER_SECOND = 1_000;
const FIVE_MINUTES_MS = ALERT_WINDOW_MINUTES * SECONDS_PER_MINUTE * MILLISECONDS_PER_SECOND;
const SERVER_ERROR_MIN = 500;
const SERVER_ERROR_MAX = 599;
const SERVER_ERROR_THRESHOLD = 5;
const FAILED_PROBE_THRESHOLD = 3;
const HTTP_STATUS_MIN = 100;
const HTTP_STATUS_MAX = 599;
const MAX_CORRELATION_LENGTH = 128;
const SAFE_CORRELATION = /^[A-Za-z0-9][A-Za-z0-9._:-]*$/;
const COMMIT_SHA = /^[a-f0-9]{40}$/i;
const EXPECTED_ARGUMENT_COUNT = 4;
const MODES = new Set(['scheduled', 'force-test-alert']);
const CREDIBLE_SIGNALS = new Set([
  'cross_tenant_disclosure',
  'payment_integrity_failure',
  'credential_exposure',
  'destructive_data_loss',
]);

function monitorError() {
  return new Error('HARD-005 production monitor: invalid monitoring evidence.');
}

function record(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function nonBlank(value) {
  return typeof value === 'string' && value.trim() !== '';
}

function exactKeys(value, keys) {
  if (!record(value) || Object.keys(value).length !== keys.length ||
      !keys.every((key) => Object.hasOwn(value, key))) throw monitorError();
}

function timestamp(value) {
  if (!nonBlank(value)) throw monitorError();
  const parsed = Date.parse(value);
  if (!Number.isFinite(parsed)) throw monitorError();
  const canonical = new Date(parsed).toISOString();
  if (canonical !== value && canonical.replace('.000Z', 'Z') !== value) throw monitorError();
  return parsed;
}

function integer(value, minimum = undefined, maximum = undefined) {
  if (!Number.isInteger(value) || (minimum !== undefined && value < minimum) ||
      (maximum !== undefined && value > maximum)) throw monitorError();
  return value;
}

function safeCorrelation(value) {
  return nonBlank(value) && value.length <= MAX_CORRELATION_LENGTH && SAFE_CORRELATION.test(value)
    ? value
    : '[REDACTED]';
}

function validateInput(input) {
  exactKeys(input, ['mode', 'evaluatedAt', 'evidence', 'logQuery', 'endpointProbe']);
  if (!MODES.has(input.mode)) throw monitorError();
  const evaluatedAtMs = timestamp(input.evaluatedAt);

  exactKeys(input.evidence, ['deploymentId', 'deploymentCommit', 'runId', 'runAttempt']);
  if (!nonBlank(input.evidence.deploymentId) || !COMMIT_SHA.test(input.evidence.deploymentCommit) ||
      !nonBlank(input.evidence.runId)) throw monitorError();
  integer(input.evidence.runAttempt, 1);

  exactKeys(input.logQuery, ['queryId', 'environment', 'startedAt', 'endedAt', 'events']);
  if (!nonBlank(input.logQuery.queryId) || input.logQuery.environment !== 'production' ||
      !Array.isArray(input.logQuery.events)) throw monitorError();
  const queryStartedAtMs = timestamp(input.logQuery.startedAt);
  const queryEndedAtMs = timestamp(input.logQuery.endedAt);
  if (queryStartedAtMs > queryEndedAtMs || queryEndedAtMs !== evaluatedAtMs ||
      queryStartedAtMs > evaluatedAtMs - FIVE_MINUTES_MS) throw monitorError();

  exactKeys(input.endpointProbe, ['probeId', 'environment', 'checks']);
  if (!nonBlank(input.endpointProbe.probeId) || input.endpointProbe.environment !== 'production' ||
      !Array.isArray(input.endpointProbe.checks)) throw monitorError();

  const events = input.logQuery.events.map((event) => {
    if (!record(event)) throw monitorError();
    const observedAtMs = timestamp(event.observedAt);
    const httpStatus = event.httpStatus === undefined || event.httpStatus === null
      ? undefined
      : integer(event.httpStatus, HTTP_STATUS_MIN, HTTP_STATUS_MAX);
    const signal = event.signal === undefined || event.signal === null ? undefined : event.signal;
    const credible = event.credible === undefined ? false : event.credible;
    if (signal !== undefined && typeof signal !== 'string') throw monitorError();
    if (typeof credible !== 'boolean') throw monitorError();
    return {
      observedAtMs,
      correlationId: safeCorrelation(event.correlationId),
      httpStatus,
      signal,
      credible,
    };
  });

  const checks = input.endpointProbe.checks.map((check) => {
    if (!record(check) || typeof check.ok !== 'boolean') throw monitorError();
    return {
      observedAtMs: timestamp(check.observedAt),
      correlationId: safeCorrelation(check.correlationId),
      ok: check.ok,
      httpStatus: integer(check.httpStatus, 0, HTTP_STATUS_MAX),
      durationMs: check.durationMs === undefined || check.durationMs === null
        ? undefined
        : integer(check.durationMs, 0),
    };
  }).sort((left, right) => left.observedAtMs - right.observedAtMs);

  return { input, evaluatedAtMs, events, checks };
}

function unique(values) {
  return [...new Set(values)];
}

function issueFor(severity, testOnly, reasons, evidence, evaluatedAt) {
  const key = testOnly ? 'phase8-production-monitor-test' : 'phase8-production-monitor';
  const title = testOnly
    ? '[TEST] Gymloop production monitor delivery check'
    : `[${severity}] Gymloop production monitor alert`;
  const labels = testOnly
    ? ['phase8-production-monitor-test', 'phase8-monitor-test']
    : ['phase8-production-monitor', 'production-alert', severity.toLowerCase()];
  const reasonLines = reasons.map((reason) => {
    if (reason.p95Ms !== undefined) {
      return `- ${reason.code}: p95 ${reason.p95Ms}ms over ${reason.budgetMs}ms budget (${reason.samples} samples)`;
    }
    return `- ${reason.code}: ${reason.count}`;
  }).join('\n');
  const correlations = evidence.correlationIds.length > 0 ? evidence.correlationIds.join(', ') : 'none';
  const body = [
    `Monitor result: ${severity}`,
    `Evaluated at: ${evaluatedAt}`,
    `Deployment: ${evidence.deploymentId}`,
    `Commit: ${evidence.deploymentCommit}`,
    `Workflow run: ${evidence.runId} attempt ${evidence.runAttempt}`,
    `Log query: ${evidence.logQueryId}`,
    `Endpoint probe: ${evidence.endpointProbeId}`,
    `Correlation IDs: ${correlations}`,
    '',
    'Reasons:',
    reasonLines,
    '',
    testOnly ? 'This is a delivery test. It is not a production incident.' : 'Production alert; follow the operational monitoring runbook.',
  ].join('\n');
  return { key, title, labels, body };
}

/** Interpolated percentile over already-sorted measured durations. */
function probeP95(sortedDurations) {
  const { p95Percentile, p95RankOffset } = PHASE8_PRELAUNCH_LOAD_LIMITS;
  const position = p95Percentile * (sortedDurations.length - p95RankOffset);
  const floorIndex = Math.floor(position);
  const ceilIndex = Math.ceil(position);
  return sortedDurations[floorIndex]
    + (sortedDurations[ceilIndex] - sortedDurations[floorIndex]) * (position - floorIndex);
}

function evaluate(input) {
  const validated = validateInput(input);
  const windowStart = validated.evaluatedAtMs - FIVE_MINUTES_MS;
  const inWindow = (observedAtMs) => observedAtMs >= windowStart && observedAtMs <= validated.evaluatedAtMs;
  const securityEvents = validated.events.filter((event) =>
    inWindow(event.observedAtMs) && event.credible === true && CREDIBLE_SIGNALS.has(event.signal));
  const serverErrors = validated.events.filter((event) =>
    inWindow(event.observedAtMs) && event.httpStatus !== undefined &&
    event.httpStatus >= SERVER_ERROR_MIN && event.httpStatus <= SERVER_ERROR_MAX);
  const lastChecks = validated.checks.slice(-FAILED_PROBE_THRESHOLD);
  const consecutiveFailures = lastChecks.length === FAILED_PROBE_THRESHOLD && lastChecks.every((check) => !check.ok)
    ? FAILED_PROBE_THRESHOLD
    : 0;

  const measuredDurations = validated.checks
    .filter((check) => check.ok && check.durationMs !== undefined)
    .map((check) => check.durationMs)
    .sort((left, right) => left - right);
  const latencySamples = measuredDurations.length;
  const latencyP95 = latencySamples > 0 ? probeP95(measuredDurations) : 0;
  const latencyBreached = latencySamples >= PHASE8_MONITOR_LATENCY.minSamples
    && latencyP95 > PHASE8_MONITOR_LATENCY.p95BudgetMs;

  const reasons = [];
  if (securityEvents.length > 0) reasons.push({ code: 'CREDIBLE_SECURITY_INTEGRITY_SIGNAL', count: securityEvents.length });
  if (serverErrors.length >= SERVER_ERROR_THRESHOLD) {
    reasons.push({ code: 'API_5XX_THRESHOLD', count: serverErrors.length, windowMinutes: ALERT_WINDOW_MINUTES });
  }
  if (consecutiveFailures === FAILED_PROBE_THRESHOLD) {
    reasons.push({ code: 'HEALTHCHECK_CONSECUTIVE_FAILURES', count: FAILED_PROBE_THRESHOLD });
  }
  if (latencyBreached) {
    reasons.push({
      code: 'PROBE_LATENCY_P95_BUDGET',
      p95Ms: latencyP95,
      budgetMs: PHASE8_MONITOR_LATENCY.p95BudgetMs,
      samples: latencySamples,
    });
  }

  const forceTest = input.mode === 'force-test-alert';
  if (forceTest) reasons.splice(0, reasons.length, { code: 'TEST_DELIVERY', count: 1 });
  const decision = forceTest || reasons.length > 0 ? 'alert' : 'healthy';
  const severity = forceTest ? 'TEST' : securityEvents.length > 0 ? 'SEV-1' : decision === 'alert' ? 'SEV-2' : 'NONE';
  const triggeredHealthChecks = consecutiveFailures === FAILED_PROBE_THRESHOLD ? lastChecks : [];
  const correlationIds = unique([
    ...securityEvents.map((event) => event.correlationId),
    ...serverErrors.map((event) => event.correlationId),
    ...triggeredHealthChecks.map((check) => check.correlationId),
  ]);
  const evidence = {
    deploymentId: input.evidence.deploymentId,
    deploymentCommit: input.evidence.deploymentCommit,
    runId: input.evidence.runId,
    runAttempt: input.evidence.runAttempt,
    logQueryId: input.logQuery.queryId,
    endpointProbeId: input.endpointProbe.probeId,
    fiveMinute5xxCount: serverErrors.length,
    consecutiveHealthCheckFailures: consecutiveFailures,
    correlationIds,
  };
  const output = {
    schemaVersion: SCHEMA_VERSION,
    decision,
    severity,
    testOnly: forceTest,
    evaluatedAt: input.evaluatedAt,
    reasons,
    evidence,
  };
  if (decision === 'alert') output.issue = issueFor(severity, forceTest, reasons, evidence, input.evaluatedAt);
  return output;
}

function main() {
  const inputFlag = process.argv[2];
  const inputPath = process.argv[3];
  if (inputFlag !== '--input' || !nonBlank(inputPath) || process.argv.length !== EXPECTED_ARGUMENT_COUNT) throw monitorError();
  let input;
  try {
    input = JSON.parse(readFileSync(inputPath, 'utf8'));
  } catch {
    throw monitorError();
  }
  process.stdout.write(`${JSON.stringify(evaluate(input))}\n`);
}

try {
  main();
} catch {
  process.stderr.write('HARD-005 production monitor: invalid monitoring evidence.\n');
  process.exitCode = 1;
}
