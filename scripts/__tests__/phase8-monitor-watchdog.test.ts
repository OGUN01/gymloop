import { spawnSync } from 'node:child_process';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';

const repository = 'OGUN01/gymloop';
const evaluatedAt = '2026-09-23T13:30:00.000Z';
const boundaryAt = '2026-09-23T13:15:00.000Z';
const staleAt = '2026-09-23T13:14:59.999Z';
const privateData = 'Bearer private-token member@example.com';
const workflowPath = new URL('../../.github/workflows/phase8-monitor-watchdog.yml', import.meta.url);
const scriptPath = new URL('../phase8-monitor-watchdog.mjs', import.meta.url);
const temporaryDirectories: string[] = [];

type Run = {
  databaseId: number;
  createdAt: string;
  status: string;
  conclusion: string | null;
  event: string;
  headBranch: string;
  displayTitle: string;
};

const productionRun = (createdAt = boundaryAt): Run => ({
  databaseId: 35860000001,
  createdAt,
  status: 'completed',
  conclusion: 'success',
  event: 'schedule',
  headBranch: 'main',
  displayTitle: 'Gymloop production monitor',
});

const input = (runs: Run[] = [], mode = 'scheduled') => ({ mode, evaluatedAt, repository, runs });

const evaluate = async (candidate: unknown) => {
  const module = await import('../phase8-monitor-watchdog.mjs');
  expect(typeof module.evaluateMonitorCadence).toBe('function');
  return module.evaluateMonitorCadence(candidate);
};

const runCli = (candidate: unknown) => {
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-watchdog-'));
  temporaryDirectories.push(directory);
  const inputPath = join(directory, 'input.json');
  writeFileSync(inputPath, JSON.stringify(candidate), 'utf8');
  return spawnSync(process.execPath, [fileURLToPath(scriptPath), '--input', inputPath], {
    encoding: 'utf8',
    windowsHide: true,
  });
};

afterEach(() => {
  while (temporaryDirectories.length > 0) rmSync(temporaryDirectories.pop()!, { recursive: true, force: true });
});

describe('HARD-005 independent missed-run watchdog', () => {
  it('treats a completed successful production run started exactly 15 minutes ago as healthy', async () => {
    const result = await evaluate(input([productionRun()]));
    expect(result).toMatchObject({ decision: 'healthy', testOnly: false, evaluatedAt });
    expect(result).not.toHaveProperty('issue');
    expect(JSON.stringify(result)).not.toContain(privateData);
  });

  it('accepts a recent production workflow-dispatch run as cadence evidence', async () => {
    const result = await evaluate(input([{ ...productionRun('2026-09-23T13:29:00.000Z'), event: 'workflow_dispatch' }]));
    expect(result.decision).toBe('healthy');
    expect(result).not.toHaveProperty('issue');
  });

  it('alerts on an empty history and on a successful run one millisecond older than the inclusive boundary', async () => {
    const empty = await evaluate(input());
    expect(empty).toMatchObject({ decision: 'alert', testOnly: false, evaluatedAt });
    expect(empty.issue.labels).toEqual(expect.arrayContaining(['production-alert', 'phase8-monitor-missing']));
    expect(`${empty.issue.title} ${empty.issue.body}`).toMatch(/SEV-2/i);

    const stale = await evaluate(input([productionRun(staleAt)]));
    expect(stale.decision).toBe('alert');
    expect(stale.issue.labels).toEqual(expect.arrayContaining(['production-alert', 'phase8-monitor-missing']));
    expect(stale.issue.body).toContain('35860000001');
    expect(stale.issue.body).toContain(staleAt);
    expect(JSON.stringify(stale.issue)).not.toContain(privateData);
  });

  it('ignores recent incomplete, unsuccessful, other-branch, other-title and TEST runs', async () => {
    const recent = productionRun('2026-09-23T13:29:00.000Z');
    const unqualified = [
      { ...recent, databaseId: 35860000002, status: 'in_progress', conclusion: null },
      { ...recent, databaseId: 35860000003, conclusion: 'failure' },
      { ...recent, databaseId: 35860000004, headBranch: 'preview' },
      { ...recent, databaseId: 35860000005, displayTitle: 'Gymloop production monitor TEST alert' },
      { ...recent, databaseId: 35860000006, displayTitle: 'Gymloop production monitor TEST failure' },
    ];
    const result = await evaluate(input([productionRun(staleAt), ...unqualified]));
    expect(result.decision).toBe('alert');
    expect(result.issue.body).toContain('35860000001');
    expect(result.issue.body).not.toContain('35860000002');
    expect(result.issue.body).not.toContain('35860000006');
  });

  it('uses the most recent qualifying successful run for a stale alert, irrespective of API ordering', async () => {
    const older = { ...productionRun('2026-09-23T12:55:00.000Z'), databaseId: 35860000007 };
    const newer = { ...productionRun('2026-09-23T13:10:00.000Z'), databaseId: 35860000008 };
    const result = await evaluate(input([newer, older]));
    expect(result.decision).toBe('alert');
    expect(result.issue.body).toContain('35860000008');
    expect(result.issue.body).toContain(newer.createdAt);
    expect(result.issue.body).not.toContain('35860000007');
  });

  it('keeps the forced missing-run receipt TEST-only even when recent production evidence is healthy', async () => {
    const result = await evaluate(input([productionRun('2026-09-23T13:29:00.000Z')], 'force-test-missing'));
    expect(result).toMatchObject({ decision: 'alert', testOnly: true, evaluatedAt });
    expect(result.issue.labels).toEqual(expect.arrayContaining([expect.stringMatching(/test/i)]));
    expect(result.issue.labels).not.toContain('production-alert');
    expect(`${result.issue.title} ${result.issue.body}`).toMatch(/TEST/i);
  });

  it.each([
    ['extra top-level field', { ...input(), providerLog: privateData }],
    ['extra run field', input([{ ...productionRun(), providerLog: privateData } as Run])],
    ['unknown mode', input([], 'bypass')],
    ['foreign repository', { ...input(), repository: `OTHER/gymloop?token=${privateData}` }],
    ['invalid evaluated time', { ...input(), evaluatedAt: 'yesterday' }],
    ['future run', input([productionRun('2026-09-23T13:30:00.001Z')])],
    ['invalid run time', input([productionRun('not-a-date')])],
    ['zero run identity', input([{ ...productionRun(), databaseId: 0 }])],
    ['fractional run identity', input([{ ...productionRun(), databaseId: 1.5 }])],
    ['missing run identity', input([{ ...productionRun(), databaseId: undefined } as unknown as Run])],
  ])('rejects %s rather than presenting untrusted evidence as healthy', async (_case, candidate) => {
    await expect(Promise.resolve().then(() => evaluate(candidate))).rejects.toThrow();
  });

  it('prints a single JSON decision from the required file-input CLI', () => {
    const result = runCli(input([productionRun()]));
    expect(result.status).toBe(0);
    expect(result.stderr).toBe('');
    expect(JSON.parse(result.stdout)).toMatchObject({ decision: 'healthy', testOnly: false, evaluatedAt });
  });

  it('exits nonzero with no JSON or untrusted data when CLI input is malformed', () => {
    const result = runCli({ ...input(), providerLog: privateData });
    expect(result.status).not.toBe(0);
    expect(result.stdout).toBe('');
    expect(`${result.stdout} ${result.stderr}`).not.toContain(privateData);
  });
});

describe('HARD-005 watchdog workflow wiring', () => {
  it('has an independent offset five-minute schedule and manual TEST route', () => {
    expect(existsSync(workflowPath)).toBe(true);
    const workflow = readFileSync(workflowPath, 'utf8');
    expect(workflow).toMatch(/schedule:\s*\r?\n\s*-\s*cron:\s*['"]?[0-4]\/5 \* \* \* \*['"]?/);
    expect(workflow).not.toMatch(/cron:\s*['"]?\*\/5 \* \* \* \*['"]?/);
    expect(workflow).toMatch(/workflow_dispatch:/);
    expect(workflow).toMatch(/force_test_missing/);
    expect(workflow).toMatch(/phase8-monitor-watchdog\.mjs/);
    expect(workflow).toMatch(/phase8-production-monitor\.yml/);
  });

  it('keeps watchdog failure visible and escalates from a separate dependent job', () => {
    expect(existsSync(workflowPath)).toBe(true);
    const workflow = readFileSync(workflowPath, 'utf8');
    expect(workflow).not.toMatch(/continue-on-error:\s*true/);
    expect(workflow).toMatch(/always\(\)/);
    expect(workflow).toMatch(/needs\.[a-z][a-z0-9_-]*\.result\s*!=\s*['"]success['"]/);
    expect(workflow).toMatch(/phase8-monitor-failure\.mjs/);
    expect(workflow).toMatch(/--mode/);
    expect(workflow).toMatch(/gh\s+issue\s+(?:list|create|edit)/);
    expect(workflow).toMatch(/--body-file/);
  });
});
