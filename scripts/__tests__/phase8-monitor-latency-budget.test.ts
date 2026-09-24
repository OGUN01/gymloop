import { spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { PHASE8_MONITOR_LATENCY, PHASE8_PRELAUNCH_LOAD_LIMITS } from '../../packages/shared/src/config/constants.ts';

const MONITOR = new URL('../phase8-production-monitor.mjs', import.meta.url);
const WORKFLOW = new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url);
const EVALUATED_AT = '2026-09-22T10:05:00.000Z';
const COMMIT = '0123456789abcdef0123456789abcdef01234567';

const cleanups: string[] = [];

afterEach(() => {
  while (cleanups.length > 0) {
    const dir = cleanups.pop();
    if (dir !== undefined) rmSync(dir, { recursive: true, force: true });
  }
});

type Check = {
  observedAt: string;
  correlationId: string;
  ok: boolean;
  httpStatus: number;
  durationMs?: number;
};

/** Build a scheduled monitor input whose only signal is probe latency. */
function latencyInput(checks: Check[]) {
  return {
    mode: 'scheduled',
    evaluatedAt: EVALUATED_AT,
    evidence: {
      deploymentId: 'dpl_gymloop123',
      deploymentCommit: COMMIT,
      runId: '7654321',
      runAttempt: 1,
    },
    logQuery: {
      queryId: 'log-query-latency',
      environment: 'production',
      startedAt: '2026-09-22T10:00:00.000Z',
      endedAt: EVALUATED_AT,
      events: [],
    },
    endpointProbe: {
      probeId: 'health-latency',
      environment: 'production',
      checks,
    },
  };
}

function evaluate(checks: Check[]) {
  const dir = mkdtempSync(join(tmpdir(), 'gymloop-latency-'));
  cleanups.push(dir);
  const inputPath = join(dir, 'input.json');
  writeFileSync(inputPath, JSON.stringify(latencyInput(checks)), 'utf8');
  const result = spawnSync(process.execPath, [fileURLToPath(MONITOR), '--input', inputPath], {
    encoding: 'utf8',
    windowsHide: true,
  });
  let output: Record<string, unknown> | undefined;
  try {
    output = JSON.parse(result.stdout) as Record<string, unknown>;
  } catch {
    output = undefined;
  }
  return { ...result, output };
}

function measuredCheck(index: number, durationMs: number, ok = true): Check {
  return {
    observedAt: `2026-09-22T10:0${index}:00.000Z`,
    correlationId: `corr-latency-${index}`,
    ok,
    httpStatus: ok ? 200 : 503,
    durationMs,
  };
}

function latencyReason(output: Record<string, unknown> | undefined) {
  const reasons = (output?.reasons ?? []) as Array<Record<string, unknown>>;
  return reasons.find((reason) => reason.code === 'PROBE_LATENCY_P95_BUDGET');
}

function p95Of(durations: number[]) {
  const sorted = [...durations].sort((left, right) => left - right);
  const { p95Percentile, p95RankOffset } = PHASE8_PRELAUNCH_LOAD_LIMITS;
  const rank = p95Percentile * (sorted.length - p95RankOffset);
  const low = Math.floor(rank);
  const high = Math.ceil(rank);
  return sorted[low] + (sorted[high] - sorted[low]) * (rank - low);
}

describe('HARD-005 probe latency p95 budget', () => {
  it('stays healthy when successful probe p95 is under the frozen budget', () => {
    const result = evaluate([
      measuredCheck(1, 120),
      measuredCheck(2, 180),
      measuredCheck(3, 240),
    ]);

    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'healthy',
      severity: 'NONE',
      reasons: [],
    });
    expect(latencyReason(result.output)).toBeUndefined();
  });

  it('raises PROBE_LATENCY_P95_BUDGET with p95, budget and sample count when over budget', () => {
    const result = evaluate([
      measuredCheck(1, 2_500),
      measuredCheck(2, 2_500),
      measuredCheck(3, 2_500),
    ]);

    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'alert',
      severity: 'SEV-2',
      reasons: [{
        code: 'PROBE_LATENCY_P95_BUDGET',
        p95Ms: 2_500,
        budgetMs: PHASE8_MONITOR_LATENCY.p95BudgetMs,
        samples: 3,
      }],
      issue: {
        key: 'phase8-production-monitor',
        title: '[SEV-2] Gymloop production monitor alert',
        labels: expect.arrayContaining(['phase8-production-monitor', 'production-alert', 'sev-2']),
      },
    });
  });

  it('reports the interpolated p95 when the three measured samples are not identical', () => {
    const durations = [500, 2_500, 3_000];
    const result = evaluate(durations.map((durationMs, index) => measuredCheck(index + 1, durationMs)));

    expect(result.status).toBe(0);
    const reason = latencyReason(result.output);
    expect(reason).toMatchObject({
      code: 'PROBE_LATENCY_P95_BUDGET',
      budgetMs: PHASE8_MONITOR_LATENCY.p95BudgetMs,
      samples: 3,
    });
    expect(reason?.p95Ms).toBeCloseTo(p95Of(durations), 5);
  });

  it('does not evaluate the budget below the minimum sample count', () => {
    const result = evaluate([
      measuredCheck(1, 5_000),
      measuredCheck(2, 5_000),
    ]);

    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'healthy',
      severity: 'NONE',
      reasons: [],
    });
    expect(latencyReason(result.output)).toBeUndefined();
  });

  it('excludes failed checks from the p95 sample set', () => {
    const result = evaluate([
      measuredCheck(1, 2_500),
      measuredCheck(2, 2_500),
      measuredCheck(3, 2_500),
      measuredCheck(4, 1, false),
    ]);

    expect(result.status).toBe(0);
    const reason = latencyReason(result.output);
    expect(reason).toMatchObject({
      code: 'PROBE_LATENCY_P95_BUDGET',
      p95Ms: 2_500,
      budgetMs: PHASE8_MONITOR_LATENCY.p95BudgetMs,
      samples: 3,
    });
  });

  it('excludes successful checks that carry no measured duration', () => {
    const result = evaluate([
      measuredCheck(1, 2_500),
      measuredCheck(2, 2_500),
      {
        observedAt: '2026-09-22T10:03:00.000Z',
        correlationId: 'corr-latency-unmeasured',
        ok: true,
        httpStatus: 200,
      },
    ]);

    expect(result.status).toBe(0);
    expect(latencyReason(result.output)).toBeUndefined();
  });

  it('measures each production probe with a durationMs field in the workflow', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    expect(workflow).toMatch(/time_total/);
    expect(workflow).toMatch(/durationMs/);
  });
});
