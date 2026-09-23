import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const SCRIPT_PATH = resolve(process.cwd(), 'scripts/phase8-production-monitor.mjs');
const EVALUATED_AT = '2026-09-23T03:00:00Z';
const WINDOW_START = '2026-09-23T02:55:00Z';
const DEPLOYMENT_COMMIT = '0123456789abcdef0123456789abcdef01234567';

type JsonObject = Record<string, unknown>;

type CliResult = {
  readonly output?: JsonObject;
  readonly status: number | null;
  readonly stderr: string;
  readonly stdout: string;
};

function inputWith(events: readonly JsonObject[]): JsonObject {
  return {
    endpointProbe: {
      checks: [
        { httpStatus: 200, observedAt: '2026-09-23T02:58:00Z', ok: true },
        { httpStatus: 200, observedAt: '2026-09-23T02:59:00Z', ok: true },
        { httpStatus: 200, observedAt: EVALUATED_AT, ok: true },
      ],
      environment: 'production',
      probeId: 'production-sign-in',
    },
    evaluatedAt: EVALUATED_AT,
    evidence: {
      deploymentCommit: DEPLOYMENT_COMMIT,
      deploymentId: 'dpl_phase8_production',
      runAttempt: 1,
      runId: '35859870821',
    },
    logQuery: {
      endedAt: EVALUATED_AT,
      environment: 'production',
      events,
      queryId: 'production-five-minute-logs',
      startedAt: WINDOW_START,
    },
    mode: 'scheduled',
  };
}

function runCli(input: unknown): CliResult {
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-monitor-provider-holdout-'));
  const inputPath = join(directory, 'input.json');
  writeFileSync(inputPath, JSON.stringify(input), 'utf8');

  try {
    const result = spawnSync(process.execPath, [SCRIPT_PATH, '--input', inputPath], {
      cwd: process.cwd(),
      encoding: 'utf8',
      env: {},
      timeout: 10_000,
    });
    let output: JsonObject | undefined;
    try {
      output = JSON.parse(result.stdout) as JsonObject;
    } catch {
      output = undefined;
    }
    return {
      output,
      status: result.status,
      stderr: result.stderr,
      stdout: result.stdout,
    };
  } finally {
    rmSync(directory, { force: true, recursive: true });
  }
}

function expectAccepted(result: CliResult, severity: string): JsonObject {
  expect(result.status).toBe(0);
  expect(result.output).toEqual(expect.any(Object));
  expect(result.output?.severity).toBe(severity);
  return result.output ?? {};
}

describe('independent HARD-005 provider-row compatibility holdout', () => {
  it('accepts a benign provider row with second-precision UTC time and null optional status and signal', () => {
    const result = runCli(inputWith([{
      credible: false,
      httpStatus: null,
      message: 'ordinary provider diagnostic that must not be copied',
      observedAt: '2026-09-23T02:59:30Z',
      signal: null,
    }]));

    const output = expectAccepted(result, 'NONE');
    expect(output.issue).toBeUndefined();
    expect(result.stdout).not.toContain('ordinary provider diagnostic');
  });

  it('counts five provider 5xx rows while accepting null signal values', () => {
    const result = runCli(inputWith([
      { credible: false, httpStatus: 500, observedAt: '2026-09-23T02:55:00Z', signal: null },
      { credible: false, httpStatus: 501, observedAt: '2026-09-23T02:56:00Z', signal: null },
      { credible: false, httpStatus: 502, observedAt: '2026-09-23T02:57:00Z', signal: null },
      { credible: false, httpStatus: 503, observedAt: '2026-09-23T02:58:00Z', signal: null },
      { credible: false, httpStatus: 504, observedAt: EVALUATED_AT, signal: null },
    ]));

    const output = expectAccepted(result, 'SEV-2');
    expect(output.reasons).toContainEqual(expect.objectContaining({
      code: 'API_5XX_THRESHOLD',
      count: 5,
    }));
  });

  it('classifies a credible security signal while accepting a null HTTP status', () => {
    const result = runCli(inputWith([{
      credible: true,
      httpStatus: null,
      observedAt: '2026-09-23T02:59:30Z',
      signal: 'cross_tenant_disclosure',
    }]));

    const output = expectAccepted(result, 'SEV-1');
    expect(output.reasons).toEqual([{
      code: 'CREDIBLE_SECURITY_INTEGRITY_SIGNAL',
      count: 1,
    }]);
  });

  it.each([
    { credible: false, httpStatus: '500', observedAt: '2026-09-23T02:59:30Z', signal: null },
    { credible: false, httpStatus: null, observedAt: 'not-an-instant', signal: null },
    { credible: 'false', httpStatus: null, observedAt: '2026-09-23T02:59:30Z', signal: null },
    { credible: true, httpStatus: null, observedAt: '2026-09-23T02:59:30Z', signal: 42 },
  ])('fails closed for malformed non-null provider evidence %#', (event) => {
    const sentinel = 'member@example.com-Bearer-sensitive-value';
    const result = runCli(inputWith([{ ...event, message: sentinel }]));

    expect(result.status).not.toBe(0);
    expect(result.output).toBeUndefined();
    expect(result.stdout.trim()).toBe('');
    expect(result.stderr).not.toContain(sentinel);
  });
});
