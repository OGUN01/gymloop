import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const SCRIPT_PATH = resolve(process.cwd(), 'scripts/phase8-production-monitor.mjs');
const WORKFLOW_PATH = resolve(process.cwd(), '.github/workflows/phase8-production-monitor.yml');
const EVALUATED_AT = '2026-09-22T12:05:00.000Z';
const WINDOW_START = '2026-09-22T12:00:00.000Z';
const PRODUCTION_DEPLOYMENT = 'dpl_phase8_production';
const WORKFLOW_RUN_ID = '202609221205';
const DEPLOYMENT_COMMIT = '0123456789abcdef0123456789abcdef01234567';

type JsonObject = Record<string, unknown>;

type MonitorResult = {
  readonly parsed?: JsonObject;
  readonly status: number | null;
  readonly stderr: string;
  readonly stdout: string;
};

const healthyChecks = () => [
  { httpStatus: 200, observedAt: '2026-09-22T12:03:00.000Z', ok: true },
  { httpStatus: 200, observedAt: '2026-09-22T12:04:00.000Z', ok: true },
  { httpStatus: 200, observedAt: EVALUATED_AT, ok: true },
];

const baseline = (): JsonObject => ({
  endpointProbe: {
    checks: healthyChecks(),
    environment: 'production',
    probeId: 'production-sign-in',
  },
  evaluatedAt: EVALUATED_AT,
  evidence: {
    deploymentCommit: DEPLOYMENT_COMMIT,
    deploymentId: PRODUCTION_DEPLOYMENT,
    runAttempt: 1,
    runId: WORKFLOW_RUN_ID,
  },
  logQuery: {
    endedAt: EVALUATED_AT,
    environment: 'production',
    events: [],
    queryId: 'production-five-minute-logs',
    startedAt: WINDOW_START,
  },
  mode: 'scheduled',
});

function runMonitor(input: unknown): MonitorResult {
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-monitor-holdout-'));
  const inputPath = join(directory, 'input.json');
  writeFileSync(inputPath, JSON.stringify(input) ?? 'null', 'utf8');

  try {
    const result = spawnSync(process.execPath, [SCRIPT_PATH, '--input', inputPath], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: {},
      timeout: 10_000,
    });
    let parsed: JsonObject | undefined;
    try {
      parsed = JSON.parse(result.stdout) as JsonObject;
    } catch {
      parsed = undefined;
    }
    return {
      parsed,
      status: result.status,
      stderr: result.stderr,
      stdout: result.stdout,
    };
  } finally {
    rmSync(directory, { force: true, recursive: true });
  }
}

function expectDecision(result: MonitorResult, severity: string | null): JsonObject {
  expect(result.status).toBe(0);
  expect(result.parsed).toEqual(expect.any(Object));
  expect(result.parsed?.decision).toEqual(expect.any(String));
  expect(result.parsed?.severity).toBe(severity);
  return result.parsed ?? {};
}

function testFlag(output: JsonObject): unknown {
  return output.testOnly;
}

function expectRejectedWithoutEcho(result: MonitorResult, sentinel: string): void {
  expect(result.status).not.toBe(0);
  expect(result.stdout.trim() === '').toBe(true);
  expect(result.stderr.includes(sentinel)).toBe(false);
  expect(result.parsed).toBeUndefined();
}

function workflowSource(): string {
  return readFileSync(WORKFLOW_PATH, 'utf8');
}

function stepSources(source: string): readonly string[] {
  const starts = [...source.matchAll(/^(\s*)- (?:name|uses|run):\s*.+$/gm)];
  return starts.map((start, index) => {
    const next = starts[index + 1];
    return source.slice(start.index, next?.index ?? source.length);
  });
}

describe('independent HARD-005 production monitor holdout', () => {
  it.each([
    'cross_tenant_disclosure',
    'payment_integrity_failure',
    'credential_exposure',
    'destructive_data_loss',
  ])('creates a SEV-1 decision for the confirmed credible %s signal', (classification) => {
    const input = baseline();
    (input.logQuery as JsonObject).events = [{
      credible: true,
      correlationId: 'corr-phase8-safe',
      observedAt: EVALUATED_AT,
      signal: classification,
    }];

    const output = expectDecision(runMonitor(input), 'SEV-1');

    expect(testFlag(output)).toBe(false);
    expect(output.issue).toEqual(expect.any(Object));
    expect(output.reasons).toEqual([{ code: 'CREDIBLE_SECURITY_INTEGRITY_SIGNAL', count: 1 }]);
    expect(JSON.stringify(output.reasons)).not.toContain(classification);
  });

  it('does not classify unknown or unconfirmed event rows as security incidents', () => {
    const input = baseline();
    (input.logQuery as JsonObject).events = [
      { credible: true, observedAt: EVALUATED_AT, signal: 'unknown_security_shape' },
      { credible: false, observedAt: EVALUATED_AT, signal: 'cross_tenant_disclosure' },
    ];

    const output = expectDecision(runMonitor(input), 'NONE');

    expect(output.issue).toBeUndefined();
    expect(JSON.stringify(output.reasons)).not.toMatch(/SEV-1|cross_tenant_disclosure/i);
  });

  it('uses an inclusive preceding five-minute window and requires five HTTP 5xx events', () => {
    const input = baseline();
    (input.logQuery as JsonObject).events = [
      { httpStatus: 500, observedAt: WINDOW_START },
      { httpStatus: 501, observedAt: '2026-09-22T12:01:00.000Z' },
      { httpStatus: 502, observedAt: '2026-09-22T12:02:00.000Z' },
      { httpStatus: 503, observedAt: '2026-09-22T12:03:00.000Z' },
      { httpStatus: 504, observedAt: EVALUATED_AT },
      { httpStatus: 500, observedAt: '2026-09-22T11:59:59.999Z' },
    ];

    expectDecision(runMonitor(input), 'SEV-2');

    (input.logQuery as JsonObject).events = ((input.logQuery as JsonObject).events as unknown[]).slice(0, 4);
    expectDecision(runMonitor(input), 'NONE');
  });

  it('creates SEV-2 only when the latest three ordered production probes fail', () => {
    const input = baseline();
    (input.endpointProbe as JsonObject).checks = [
      { httpStatus: 200, observedAt: '2026-09-22T12:02:00.000Z', ok: true },
      { httpStatus: 503, observedAt: '2026-09-22T12:03:00.000Z', ok: false },
      { httpStatus: 503, observedAt: '2026-09-22T12:04:00.000Z', ok: false },
      { httpStatus: 503, observedAt: EVALUATED_AT, ok: false },
    ];

    expectDecision(runMonitor(input), 'SEV-2');

    (input.endpointProbe as JsonObject).checks = [
      { httpStatus: 503, observedAt: '2026-09-22T12:03:00.000Z', ok: false },
      { httpStatus: 200, observedAt: '2026-09-22T12:04:00.000Z', ok: true },
      { httpStatus: 503, observedAt: EVALUATED_AT, ok: false },
    ];
    expectDecision(runMonitor(input), 'NONE');
  });

  it('gives a credible signal SEV-1 precedence over simultaneous SEV-2 thresholds', () => {
    const input = baseline();
    (input.logQuery as JsonObject).events = [
      { credible: true, observedAt: EVALUATED_AT, signal: 'payment_integrity_failure' },
      ...Array.from({ length: 5 }, (_, index) => ({
        httpStatus: 500,
        observedAt: `2026-09-22T12:0${index}:00.000Z`,
      })),
    ];
    (input.endpointProbe as JsonObject).checks = [
      { httpStatus: 503, observedAt: '2026-09-22T12:03:00.000Z', ok: false },
      { httpStatus: 503, observedAt: '2026-09-22T12:04:00.000Z', ok: false },
      { httpStatus: 503, observedAt: EVALUATED_AT, ok: false },
    ];

    expectDecision(runMonitor(input), 'SEV-1');
  });

  it('fails closed without JSON or input echo for invalid evidence and production identity', () => {
    const sentinel = 'member@example.com-Bearer-secret-token';
    const cases: unknown[] = [
      null,
      {},
      { ...baseline(), mode: 'manual' },
      { ...baseline(), evaluatedAt: 'not-an-instant', unsafe: sentinel },
      { ...baseline(), evidence: { deploymentCommit: 'not-a-commit', deploymentId: sentinel, runAttempt: 1, runId: WORKFLOW_RUN_ID } },
      { ...baseline(), logQuery: { endedAt: EVALUATED_AT, environment: 'preview', events: [], queryId: sentinel, startedAt: WINDOW_START } },
      { ...baseline(), endpointProbe: { checks: [], environment: 'preview', probeId: sentinel } },
      { ...baseline(), evidence: undefined, unsafe: sentinel },
    ];

    for (const input of cases) expectRejectedWithoutEcho(runMonitor(input), sentinel);
  });

  it('emits deterministic output with only whitelisted top-level evidence and redacts unsafe correlations', () => {
    const input = baseline();
    (input.logQuery as JsonObject).events = [{
      authorization: 'Bearer credential-value',
      credible: true,
      context: { password: 'password-value', secret: 'secret-value' },
      correlationId: 'member@example.com/token-value',
      email: 'member@example.com',
      message: 'response-body-value phone +919876543210',
      observedAt: EVALUATED_AT,
      phone: '+919876543210',
      responseBody: 'response-body-value',
      signal: 'credential_exposure',
      token: 'token-value',
    }];

    const first = runMonitor(input);
    const second = runMonitor(input);
    const output = expectDecision(first, 'SEV-1');

    expect(second.status).toBe(0);
    expect(second.stdout).toBe(first.stdout);
    expect(Object.keys(output).every((key) => [
      'schemaVersion',
      'decision',
      'severity',
      'testOnly',
      'evaluatedAt',
      'reasons',
      'evidence',
      'issue',
    ].includes(key))).toBe(true);
    expect(Object.hasOwn(output, 'testOnly')).toBe(true);
    expect(first.stdout).toContain('[REDACTED]');
    for (const unsafe of [
      'credential-value',
      'password-value',
      'secret-value',
      'member@example.com',
      '+919876543210',
      'response-body-value',
      'token-value',
    ]) expect(first.stdout.includes(unsafe)).toBe(false);
  });

  it('creates a distinct TEST-only forced-delivery issue without production severity or label', () => {
    const input = { ...baseline(), mode: 'force-test-alert' };

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.parsed).toEqual(expect.any(Object));
    const output = result.parsed ?? {};
    const issue = output.issue as JsonObject;
    const issueSource = JSON.stringify(issue);

    expect(output.decision).toEqual(expect.any(String));
    expect(['SEV-1', 'SEV-2']).not.toContain(output.severity);
    expect(testFlag(output)).toBe(true);
    expect(issue.key).toEqual(expect.any(String));
    expect(issue.body).toEqual(expect.any(String));
    expect(issueSource).toMatch(/TEST/i);
    expect(issueSource).not.toMatch(/SEV-[12]|production-alert/i);
  });

  it('schedules the frozen destination every five minutes with least privilege and a step-scoped Vercel token', () => {
    const source = workflowSource();
    const steps = stepSources(source);
    const vercelSteps = steps.filter((step) => /secrets\.VERCEL_TOKEN/.test(step));
    const permissions = /^permissions:\s*$([\s\S]*?)(?=^\S)/m.exec(source)?.[1] ?? '';

    expect(/schedule:\s*\n\s*- cron:\s*['"]?\*\/5 \* \* \* \*['"]?/m.test(source)).toBe(true);
    expect(/workflow_dispatch:/m.test(source)).toBe(true);
    expect(/^\s*contents:\s*read\s*$/m.test(permissions)).toBe(true);
    expect(/^\s*issues:\s*write\s*$/m.test(permissions)).toBe(true);
    expect([...permissions.matchAll(/^\s*([\w-]+):\s*(\S+)\s*$/gm)].map((match) => match[1]).sort()).toEqual(['contents', 'issues']);
    expect(vercelSteps.length).toBeGreaterThan(0);
    for (const step of vercelSteps) expect(/vercel\s+logs/i.test(step)).toBe(true);
    expect(/secrets\.VERCEL_TOKEN/.test(vercelSteps.reduce((remaining, step) => remaining.replace(step, ''), source))).toBe(false);
  });

  it('collects production logs and three production health probes into the frozen file-input CLI', () => {
    const source = workflowSource();

    expect(/vercel\s+logs[\s\S]*--environment(?:=|\s+)production/i.test(source)).toBe(true);
    expect(/vercel\s+logs[\s\S]*(?:--since(?:=|\s+)5m|5\s*minutes?)/i.test(source)).toBe(true);
    expect(/(?:seq\s+1\s+3|1\.\.3|\bin\s+1\s+2\s+3\b|(?:health|probe)[^\n]*(?:count|attempts?)\s*[:=]\s*3|(?:count|attempts?)[^\n]*(?:health|probe)[^\n]*[:=]\s*3|(?:curl|Invoke-WebRequest)[\s\S]*(?:curl|Invoke-WebRequest)[\s\S]*(?:curl|Invoke-WebRequest))/i.test(source)).toBe(true);
    expect(/phase8-production-monitor\.mjs[\s\S]*--input\s+[^\s]+/i.test(source)).toBe(true);
    expect(/(?:environment[^\n]*production|production[^\n]*environment)/i.test(source)).toBe(true);
  });

  it('creates or updates the keyed issue from its body file and keeps forced delivery test-only', () => {
    const source = workflowSource();

    expect(/\.issue\.key/.test(source)).toBe(true);
    expect(/\.issue\.body/.test(source)).toBe(true);
    expect(/gh\s+issue\s+(?:list|view)/i.test(source)).toBe(true);
    expect(/gh\s+issue\s+create[\s\S]*--body-file\b/i.test(source)).toBe(true);
    expect(/gh\s+issue\s+edit[\s\S]*--body-file\b/i.test(source)).toBe(true);
    expect(/force-test-alert[\s\S]*TEST/i.test(source)).toBe(true);
    expect(/gh\s+issue\s+(?:create|edit)[^\n]*--body(?:\s|=)(?!-file)/i.test(source)).toBe(false);

    const issueSteps = stepSources(source).filter((step) => /gh\s+issue\s+(?:create|edit)/i.test(step));
    expect(issueSteps.length).toBeGreaterThan(0);
    for (const step of issueSteps) {
      expect(/(?:GH_TOKEN|GITHUB_TOKEN):\s*\$\{\{/.test(step)).toBe(true);
    }
  });
});
