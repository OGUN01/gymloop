import assert from 'node:assert/strict';
import test from 'node:test';

import { evaluateMonitorCadence } from '../../scripts/phase8-monitor-watchdog.mjs';

const repository = 'OGUN01/gymloop';
const evaluatedAt = '2026-09-23T13:00:00.000Z';

function productionRun(overrides = {}) {
  return {
    databaseId: 501,
    createdAt: '2026-09-23T12:50:00.000Z',
    status: 'completed',
    conclusion: 'success',
    event: 'schedule',
    headBranch: 'main',
    displayTitle: 'Gymloop production monitor',
    ...overrides,
  };
}

function input(overrides = {}) {
  return {
    mode: 'scheduled',
    evaluatedAt,
    repository,
    runs: [productionRun()],
    ...overrides,
  };
}

function assertNoHealthyDecision(candidate) {
  let result;
  try {
    result = evaluateMonitorCadence(candidate);
  } catch (error) {
    assert.ok(error instanceof Error);
    return;
  }
  assert.equal(result.decision, 'alert');
}

test('a completed successful production run on main is healthy', () => {
  const result = evaluateMonitorCadence(input());
  assert.equal(result.decision, 'healthy');
  assert.equal(result.testOnly, false);
  assert.equal(result.evaluatedAt, evaluatedAt);
  assert.equal(Object.hasOwn(result, 'issue'), false);
  assert.doesNotThrow(() => JSON.stringify(result));
});

test('the 15-minute boundary is inclusive', () => {
  const result = evaluateMonitorCadence(input({
    runs: [productionRun({ createdAt: '2026-09-23T12:45:00.000Z' })],
  }));
  assert.equal(result.decision, 'healthy');
});

test('a run just beyond 15 minutes produces a production SEV-2 issue', () => {
  const result = evaluateMonitorCadence(input({
    runs: [productionRun({ createdAt: '2026-09-23T12:44:59.999Z' })],
  }));
  assert.equal(result.decision, 'alert');
  assert.equal(result.testOnly, false);
  assert.ok(result.issue);
  const issue = JSON.stringify(result.issue);
  assert.match(issue, /production-alert/);
  assert.match(issue, /phase8-monitor-missing/);
  assert.match(issue, /SEV-2/);
  assert.match(issue, /501/);
  assert.match(issue, /2026-09-23T12:44:59/);
});

test('no run produces an alert without inventing a last successful run', () => {
  const result = evaluateMonitorCadence(input({ runs: [] }));
  assert.equal(result.decision, 'alert');
  assert.equal(result.testOnly, false);
  assert.match(JSON.stringify(result.issue), /phase8-monitor-missing/);
});

test('newer failed or incomplete runs do not hide a stale successful run', () => {
  const result = evaluateMonitorCadence(input({
    runs: [
      productionRun({ databaseId: 503, createdAt: '2026-09-23T12:58:00.000Z', conclusion: 'failure' }),
      productionRun({ databaseId: 502, createdAt: '2026-09-23T12:57:00.000Z', status: 'in_progress', conclusion: null }),
      productionRun({ databaseId: 501, createdAt: '2026-09-23T12:40:00.000Z' }),
    ],
  }));
  assert.equal(result.decision, 'alert');
  const issue = JSON.stringify(result.issue);
  assert.match(issue, /501/);
  assert.match(issue, /2026-09-23T12:40/);
});

test('only the exact title and main branch qualify', () => {
  for (const run of [
    productionRun({ displayTitle: 'Gymloop production monitor TEST' }),
    productionRun({ headBranch: 'feature/test' }),
    productionRun({ event: 'pull_request' }),
  ]) {
    assertNoHealthyDecision(input({ runs: [run] }));
  }
});

test('an ordinary successful manual production run qualifies', () => {
  const result = evaluateMonitorCadence(input({
    runs: [productionRun({ event: 'workflow_dispatch' })],
  }));
  assert.equal(result.decision, 'healthy');
  assert.equal(result.testOnly, false);
});

test('manual TEST alert or failure titles cannot keep the production watchdog healthy', () => {
  for (const run of [
    productionRun({ databaseId: 601, event: 'workflow_dispatch', displayTitle: 'Gymloop production monitor TEST alert' }),
    productionRun({ databaseId: 602, event: 'workflow_dispatch', displayTitle: 'Gymloop production monitor TEST failure' }),
  ]) {
    assertNoHealthyDecision(input({ runs: [run] }));
  }
});

test('forced TEST mode alerts despite a fresh production run and never gets production-alert', () => {
  const result = evaluateMonitorCadence(input({ mode: 'force-test-missing' }));
  assert.equal(result.decision, 'alert');
  assert.equal(result.testOnly, true);
  const issue = JSON.stringify(result.issue);
  assert.match(issue, /TEST/i);
  assert.doesNotMatch(issue, /production-alert/);
  assert.doesNotMatch(issue, /phase8-monitor-missing\"/);
});

test('forced TEST mode still rejects invalid input', () => {
  for (const candidate of [
    input({ mode: 'force-test-missing', repository: 'elsewhere/gymloop' }),
    input({ mode: 'force-test-missing', evaluatedAt: 'not-a-time' }),
    input({ mode: 'force-test-missing', runs: [productionRun({ databaseId: 0 })] }),
  ]) {
    assert.throws(() => evaluateMonitorCadence(candidate));
  }
});

test('extra input fields and unsupported modes are rejected', () => {
  assert.throws(() => evaluateMonitorCadence(input({ secret: 'should-never-appear' })));
  assert.throws(() => evaluateMonitorCadence(input({ mode: 'test' })));
});

test('non-Gymloop repositories and malformed evaluation times are rejected', () => {
  for (const candidate of [
    input({ repository: 'OGUN01/another-repo' }),
    input({ repository: '../gymloop' }),
    input({ evaluatedAt: 'yesterday' }),
  ]) {
    assert.throws(() => evaluateMonitorCadence(candidate));
  }
});

test('malformed and future-dated run evidence cannot yield healthy', () => {
  for (const run of [
    productionRun({ databaseId: -1 }),
    productionRun({ databaseId: 'not-an-id' }),
    productionRun({ createdAt: 'unparseable' }),
    productionRun({ createdAt: '2026-09-23T13:00:00.001Z' }),
    productionRun({ token: 'untrusted-extra-field' }),
  ]) {
    assertNoHealthyDecision(input({ runs: [run] }));
  }
});

test('a valid recent run cannot mask malformed or future-dated evidence', () => {
  for (const run of [
    productionRun({ databaseId: null }),
    productionRun({ createdAt: '2026-09-23T13:02:00.000Z' }),
  ]) {
    assertNoHealthyDecision(input({ runs: [productionRun(), run] }));
  }
});

test('alert issue content excludes untrusted provider text', () => {
  let result;
  try {
    result = evaluateMonitorCadence(input({
      runs: [productionRun({
        databaseId: 777,
        createdAt: '2026-09-23T12:30:00.000Z',
        displayTitle: 'secret-token=canary-personal-data',
      })],
    }));
  } catch (error) {
    assert.ok(error instanceof Error);
    assert.doesNotMatch(error.message, /canary-personal-data/);
    return;
  }
  assert.equal(result.decision, 'alert');
  assert.doesNotMatch(JSON.stringify(result.issue), /canary-personal-data/);
});
