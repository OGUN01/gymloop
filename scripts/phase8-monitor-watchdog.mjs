import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PHASE8_MONITOR_WATCHDOG } from '../packages/shared/src/config/constants.ts';

const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;
const INPUT_KEYS = ['evaluatedAt', 'mode', 'repository', 'runs'];
const RUN_KEYS = ['conclusion', 'createdAt', 'databaseId', 'displayTitle', 'event', 'headBranch', 'status'];

function hasExactKeys(value, expected) {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).sort().join(',') === expected.join(',');
}

function parseTime(value) {
  if (typeof value !== 'string' || !ISO_TIME.test(value)) throw new Error('Invalid watchdog time');
  const time = Date.parse(value);
  if (!Number.isFinite(time)) throw new Error('Invalid watchdog time');
  const canonical = new Date(time).toISOString();
  const expected = value.includes('.')
    ? value.replace(/\.(\d{1,3})Z$/, (_match, fraction) => `.${fraction.padEnd(PHASE8_MONITOR_WATCHDOG.isoFractionDigits, '0')}Z`)
    : value.replace(/Z$/, '.000Z');
  if (canonical !== expected) throw new Error('Invalid watchdog time');
  return time;
}

function validateRun(run, evaluatedMs) {
  if (!hasExactKeys(run, RUN_KEYS)
    || !Number.isSafeInteger(run.databaseId) || run.databaseId < 1
    || typeof run.status !== 'string'
    || (run.conclusion !== null && typeof run.conclusion !== 'string')
    || typeof run.event !== 'string'
    || typeof run.headBranch !== 'string'
    || typeof run.displayTitle !== 'string') {
    throw new Error('Invalid watchdog run');
  }
  const createdMs = parseTime(run.createdAt);
  if (createdMs > evaluatedMs) throw new Error('Future watchdog run');
  return createdMs;
}

export function evaluateMonitorCadence(input) {
  if (!hasExactKeys(input, INPUT_KEYS)
    || !['scheduled', 'force-test-missing'].includes(input.mode)
    || input.repository !== 'OGUN01/gymloop'
    || !Array.isArray(input.runs)) {
    throw new Error('Invalid watchdog evidence');
  }
  const evaluatedMs = parseTime(input.evaluatedAt);
  let latest = null;
  let latestMs = Number.NEGATIVE_INFINITY;
  for (const run of input.runs) {
    const createdMs = validateRun(run, evaluatedMs);
    if (run.status === 'completed' && run.conclusion === 'success'
      && (run.event === 'schedule' || run.event === 'workflow_dispatch')
      && run.headBranch === 'main'
      && run.displayTitle === PHASE8_MONITOR_WATCHDOG.productionTitle
      && createdMs > latestMs) {
      latest = run;
      latestMs = createdMs;
    }
  }

  const testOnly = input.mode === 'force-test-missing';
  const isFresh = latest !== null && evaluatedMs - latestMs <= PHASE8_MONITOR_WATCHDOG.maxGapMs;
  const base = { decision: testOnly || !isFresh ? 'alert' : 'healthy', testOnly, evaluatedAt: input.evaluatedAt };
  if (base.decision === 'healthy') return base;

  const lastSeen = latest
    ? `Last successful production run: https://github.com/${input.repository}/actions/runs/${latest.databaseId} (created ${latest.createdAt}).`
    : 'No completed successful production monitor run was found in the inspected history.';
  const issue = testOnly
    ? {
      key: 'phase8-monitor-missing-test',
      title: '[TEST] Missing production monitor run delivery',
      body: `TEST ONLY: the independent watchdog exercised its missing-run issue route.\n\n${lastSeen}\n\nClose this receipt after verification. This does not represent a production incident.`,
      labels: ['phase8-monitor-missing-test', 'phase8-monitor-test'],
    }
    : {
      key: 'phase8-monitor-missing',
      title: '[SEV-2] Production monitor run missing',
      body: `No successful production monitor run was created within the preceding 15 minutes.\n\n${lastSeen}\n\nTechnical Lead: acknowledge within 30 minutes, investigate the monitor schedule and run history, and escalate to the Incident Commander if ongoing. Stop new onboarding if unacknowledged after 30 minutes.`,
      labels: ['phase8-monitor-missing', 'production-alert', 'sev-2'],
    };
  return { ...base, issue };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    const args = process.argv.slice(PHASE8_MONITOR_WATCHDOG.cliArgCount);
    if (args.length !== PHASE8_MONITOR_WATCHDOG.cliArgCount || args[0] !== '--input') {
      throw new Error('Invalid watchdog arguments');
    }
    const input = JSON.parse(readFileSync(args[1], 'utf8'));
    process.stdout.write(`${JSON.stringify(evaluateMonitorCadence(input))}\n`);
  } catch {
    console.error('Production monitor watchdog evidence invalid');
    process.exitCode = 1;
  }
}
