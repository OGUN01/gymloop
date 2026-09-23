import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterEach, describe, expect, it } from 'vitest';

const SCRIPT = new URL('../phase8-production-monitor.mjs', import.meta.url);
const WORKFLOW = new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url);
const EVALUATED_AT = '2026-09-22T10:05:00.000Z';

type MonitorInput = {
  mode: 'force-test-alert' | 'scheduled';
  evaluatedAt: string;
  evidence: {
    deploymentId: string;
    deploymentCommit: string;
    runId: string;
    runAttempt: number;
  };
  logQuery: {
    queryId: string;
    environment: 'production';
    startedAt: string;
    endedAt: string;
    events: Array<Record<string, unknown>>;
  };
  endpointProbe: {
    probeId: string;
    environment: 'production';
    checks: Array<Record<string, unknown>>;
  };
};

const baseInput = (): MonitorInput => ({
  mode: 'scheduled',
  evaluatedAt: EVALUATED_AT,
  evidence: {
    deploymentId: 'dpl_gymloop123',
    deploymentCommit: '0123456789abcdef0123456789abcdef01234567',
    runId: '7654321',
    runAttempt: 1,
  },
  logQuery: {
    queryId: 'log-query-20260922T100500Z',
    environment: 'production',
    startedAt: '2026-09-22T10:00:00.000Z',
    endedAt: EVALUATED_AT,
    events: [],
  },
  endpointProbe: {
    probeId: 'health-20260922T100500Z',
    environment: 'production',
    checks: [],
  },
});

const temporaryDirectories: string[] = [];

const runMonitor = (input: unknown) => {
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-monitor-'));
  temporaryDirectories.push(directory);
  const inputPath = join(directory, 'input.json');
  writeFileSync(inputPath, JSON.stringify(input), 'utf8');
  const result = spawnSync(process.execPath, [fileURLToPath(SCRIPT), '--input', inputPath], {
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
};

const fiveServerErrors = () => Array.from({ length: 5 }, (_, index) => ({
  observedAt: `2026-09-22T10:0${index}:00.000Z`,
  correlationId: `corr-server-${index}`,
  httpStatus: 500 + index,
}));

afterEach(() => {
  while (temporaryDirectories.length > 0) {
    const directory = temporaryDirectories.pop();
    if (directory !== undefined) rmSync(directory, { recursive: true, force: true });
  }
});

describe('HARD-005 production monitor decision', () => {
  it('returns a deterministic healthy result below every threshold', () => {
    const input = baseInput();
    input.logQuery.events = fiveServerErrors().slice(0, 4);
    input.endpointProbe.checks = [
      { observedAt: '2026-09-22T10:03:00.000Z', correlationId: 'corr-health-1', ok: false, httpStatus: 503 },
      { observedAt: '2026-09-22T10:04:00.000Z', correlationId: 'corr-health-2', ok: false, httpStatus: 503 },
    ];

    const first = runMonitor(input);
    const second = runMonitor(input);
    expect(first.status).toBe(0);
    expect(second.status).toBe(0);
    expect(first.output).toEqual(second.output);
    expect(first.output).toMatchObject({
      schemaVersion: 1,
      decision: 'healthy',
      severity: 'NONE',
      testOnly: false,
      evaluatedAt: EVALUATED_AT,
      reasons: [],
      evidence: {
        deploymentId: input.evidence.deploymentId,
        deploymentCommit: input.evidence.deploymentCommit,
        runId: input.evidence.runId,
        runAttempt: input.evidence.runAttempt,
        logQueryId: input.logQuery.queryId,
        endpointProbeId: input.endpointProbe.probeId,
      },
    });
    expect(first.output).not.toHaveProperty('issue');
  });

  it.each([
    'cross_tenant_disclosure',
    'payment_integrity_failure',
    'credential_exposure',
    'destructive_data_loss',
  ])('raises SEV-1 for one credible %s signal', (signal) => {
    const input = baseInput();
    input.logQuery.events = [{
      observedAt: '2026-09-22T10:04:30.000Z',
      correlationId: 'corr-security-1',
      signal,
      credible: true,
    }];

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'alert',
      severity: 'SEV-1',
      testOnly: false,
      reasons: [{ code: 'CREDIBLE_SECURITY_INTEGRITY_SIGNAL', count: 1 }],
      evidence: { correlationIds: ['corr-security-1'] },
      issue: {
        key: 'phase8-production-monitor',
        title: '[SEV-1] Gymloop production monitor alert',
        labels: expect.arrayContaining(['phase8-production-monitor', 'production-alert', 'sev-1']),
      },
    });
  });

  it('does not raise a security alert for an unconfirmed or unknown classification', () => {
    const input = baseInput();
    input.logQuery.events = [
      {
        observedAt: '2026-09-22T10:04:00.000Z',
        correlationId: 'corr-security-unconfirmed',
        signal: 'cross_tenant_disclosure',
        credible: false,
      },
      {
        observedAt: '2026-09-22T10:04:30.000Z',
        correlationId: 'corr-unknown',
        signal: 'generic_error',
        credible: true,
      },
    ];

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({ decision: 'healthy', reasons: [] });
  });

  it('raises SEV-2 at five 5xx events in the inclusive five-minute window', () => {
    const input = baseInput();
    input.logQuery.events = fiveServerErrors();

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'alert',
      severity: 'SEV-2',
      reasons: [{ code: 'API_5XX_THRESHOLD', count: 5, windowMinutes: 5 }],
      evidence: {
        fiveMinute5xxCount: 5,
        correlationIds: [
          'corr-server-0',
          'corr-server-1',
          'corr-server-2',
          'corr-server-3',
          'corr-server-4',
        ],
      },
      issue: {
        title: '[SEV-2] Gymloop production monitor alert',
        labels: expect.arrayContaining(['phase8-production-monitor', 'production-alert', 'sev-2']),
      },
    });
    const issue = result.output?.issue as Record<string, unknown> | undefined;
    expect(issue?.body).toEqual(expect.any(String));
    for (const evidence of [
      input.evidence.deploymentId,
      input.evidence.deploymentCommit,
      input.evidence.runId,
      input.logQuery.queryId,
      input.endpointProbe.probeId,
      'corr-server-0',
    ]) {
      expect(issue?.body).toContain(evidence);
    }
  });

  it('ignores 4xx responses and 5xx events older than the five-minute window', () => {
    const input = baseInput();
    input.logQuery.events = [
      ...fiveServerErrors().slice(0, 4),
      { observedAt: '2026-09-22T09:59:59.999Z', correlationId: 'corr-too-old', httpStatus: 599 },
      { observedAt: '2026-09-22T10:04:59.000Z', correlationId: 'corr-client', httpStatus: 499 },
    ];

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'healthy',
      evidence: { fiveMinute5xxCount: 4 },
    });
  });

  it('raises SEV-2 only after the last three production health probes fail consecutively', () => {
    const input = baseInput();
    input.endpointProbe.checks = [
      { observedAt: '2026-09-22T10:01:00.000Z', correlationId: 'corr-health-0', ok: true, httpStatus: 200 },
      { observedAt: '2026-09-22T10:02:00.000Z', correlationId: 'corr-health-1', ok: false, httpStatus: 503 },
      { observedAt: '2026-09-22T10:03:00.000Z', correlationId: 'corr-health-2', ok: false, httpStatus: 503 },
      { observedAt: '2026-09-22T10:04:00.000Z', correlationId: 'corr-health-3', ok: false, httpStatus: 503 },
    ];

    const alert = runMonitor(input);
    expect(alert.status).toBe(0);
    expect(alert.output).toMatchObject({
      decision: 'alert',
      severity: 'SEV-2',
      reasons: [{ code: 'HEALTHCHECK_CONSECUTIVE_FAILURES', count: 3 }],
      evidence: {
        consecutiveHealthCheckFailures: 3,
        correlationIds: ['corr-health-1', 'corr-health-2', 'corr-health-3'],
      },
    });

    input.endpointProbe.checks.splice(2, 0, {
      observedAt: '2026-09-22T10:02:30.000Z', correlationId: 'corr-health-recovered', ok: true, httpStatus: 200,
    });
    const recovered = runMonitor(input);
    expect(recovered.status).toBe(0);
    expect(recovered.output).toMatchObject({ decision: 'healthy', reasons: [] });
  });

  it('uses SEV-1 precedence and a stable reason order when thresholds overlap', () => {
    const input = baseInput();
    input.logQuery.events = [
      ...fiveServerErrors().reverse(),
      {
        observedAt: '2026-09-22T10:04:45.000Z',
        correlationId: 'corr-security-1',
        signal: 'payment_integrity_failure',
        credible: true,
      },
    ];
    input.endpointProbe.checks = [
      { observedAt: '2026-09-22T10:02:00.000Z', correlationId: 'corr-health-1', ok: false, httpStatus: 503 },
      { observedAt: '2026-09-22T10:03:00.000Z', correlationId: 'corr-health-2', ok: false, httpStatus: 503 },
      { observedAt: '2026-09-22T10:04:00.000Z', correlationId: 'corr-health-3', ok: false, httpStatus: 503 },
    ];

    const result = runMonitor(input);
    expect(result.output).toMatchObject({
      decision: 'alert',
      severity: 'SEV-1',
      reasons: [
        { code: 'CREDIBLE_SECURITY_INTEGRITY_SIGNAL', count: 1 },
        { code: 'API_5XX_THRESHOLD', count: 5, windowMinutes: 5 },
        { code: 'HEALTHCHECK_CONSECUTIVE_FAILURES', count: 3 },
      ],
    });
  });

  it('emits only whitelisted, redacted evidence and never repeats raw log or probe payloads', () => {
    const input = baseInput();
    input.logQuery.events = [{
      observedAt: '2026-09-22T10:04:30.000Z',
      correlationId: 'member@example.com',
      signal: 'credential_exposure',
      credible: true,
      message: 'Bearer production-secret-token',
      authorization: 'Bearer production-secret-token',
      email: 'member@example.com',
      phone: '+919999999999',
      context: { password: 'raw-password', memberName: 'Private Member' },
    }];
    input.endpointProbe.checks = [{
      observedAt: '2026-09-22T10:04:50.000Z',
      correlationId: 'corr-safe-1',
      ok: true,
      httpStatus: 200,
      responseBody: 'service_role=raw-service-key',
    }];

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    const serialized = JSON.stringify(result.output);
    for (const forbidden of [
      'production-secret-token',
      'member@example.com',
      '+919999999999',
      'raw-password',
      'Private Member',
      'raw-service-key',
    ]) {
      expect(serialized).not.toContain(forbidden);
    }
    expect(result.output).toMatchObject({
      evidence: {
        deploymentId: input.evidence.deploymentId,
        deploymentCommit: input.evidence.deploymentCommit,
        runId: input.evidence.runId,
        correlationIds: ['[REDACTED]'],
      },
    });
    expect(serialized).toContain('CREDIBLE_SECURITY_INTEGRITY_SIGNAL');
  });

  it('supports an explicit manual delivery test without labelling it as a production incident', () => {
    const input = baseInput();
    input.mode = 'force-test-alert';

    const result = runMonitor(input);
    expect(result.status).toBe(0);
    expect(result.output).toMatchObject({
      decision: 'alert',
      severity: 'TEST',
      testOnly: true,
      reasons: [{ code: 'TEST_DELIVERY', count: 1 }],
      issue: {
        key: 'phase8-production-monitor-test',
        title: '[TEST] Gymloop production monitor delivery check',
        labels: expect.arrayContaining([
          'phase8-production-monitor-test',
          'phase8-monitor-test',
        ]),
      },
    });
    expect(result.output).not.toMatchObject({
      issue: { labels: expect.arrayContaining(['production-alert']) },
    });
  });

  it('keeps TEST and production issue identities disjoint', () => {
    const productionInput = baseInput();
    productionInput.logQuery.events = [{
      observedAt: '2026-09-22T10:04:30.000Z',
      correlationId: 'corr-production-alert',
      signal: 'cross_tenant_disclosure',
      credible: true,
    }];
    const testInput = baseInput();
    testInput.mode = 'force-test-alert';

    const production = runMonitor(productionInput);
    const deliveryTest = runMonitor(testInput);
    expect(production.status).toBe(0);
    expect(deliveryTest.status).toBe(0);
    const productionIssue = production.output?.issue as { key?: string; labels?: string[] } | undefined;
    const testIssue = deliveryTest.output?.issue as { key?: string; labels?: string[] } | undefined;
    expect(productionIssue?.key).not.toBe(testIssue?.key);
    expect(productionIssue?.labels).toContain(productionIssue?.key);
    expect(testIssue?.labels).toContain(testIssue?.key);
    expect(productionIssue?.labels).not.toContain(testIssue?.key);
    expect(testIssue?.labels).not.toContain(productionIssue?.key);
  });

  it('fails closed on missing run/deployment evidence, malformed time, or a non-production source', () => {
    const missingEvidence = baseInput() as MonitorInput & { evidence?: MonitorInput['evidence'] };
    delete missingEvidence.evidence;
    const malformedTime = baseInput();
    malformedTime.evaluatedAt = 'not-a-time';
    malformedTime.logQuery.events = [{ message: 'production-secret-token' }];
    const stagingLogs = baseInput() as MonitorInput & { logQuery: MonitorInput['logQuery'] & { environment: string } };
    stagingLogs.logQuery.environment = 'staging';
    const stagingProbe = baseInput() as MonitorInput & { endpointProbe: MonitorInput['endpointProbe'] & { environment: string } };
    stagingProbe.endpointProbe.environment = 'staging';

    for (const input of [missingEvidence, malformedTime, stagingLogs, stagingProbe]) {
      const result = runMonitor(input);
      expect(result.status).not.toBe(0);
      expect(result.output).toBeUndefined();
      expect(result.stderr).not.toContain('production-secret-token');
    }
  });
});

describe('HARD-005 GitHub issue destination', () => {
  it('runs on a five-minute schedule and offers a clearly named manual test-alert input', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    expect(workflow).toMatch(/schedule:\s*\n\s*- cron:\s*['"]\*\/5 \* \* \* \*['"]/);
    expect(workflow).toMatch(/workflow_dispatch:[\s\S]*force_test_alert:[\s\S]*type:\s*boolean[\s\S]*default:\s*false/);
  });

  it('grants only repository read and issue write access', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    const permissions = /^permissions:\s*$(.*?)(?=^[A-Za-z_-]+:)/ms.exec(workflow)?.[1] ?? '';
    expect(permissions).toMatch(/^\s+contents:\s*read\s*$/m);
    expect(permissions).toMatch(/^\s+issues:\s*write\s*$/m);
    expect(permissions).not.toMatch(/^\s+(?!contents:|issues:)[A-Za-z-]+:/m);
  });

  it('queries production logs, performs production probes, and passes an input file to the monitor', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    expect(workflow).toMatch(/vercel\s+logs[\s\S]*(?:--environment\s+production|--environment=production)/i);
    expect(workflow).toMatch(/curl[\s\S]*https:\/\/gymloop-phi\.vercel\.app/i);
    expect(workflow).toMatch(/phase8-production-monitor\.mjs\s+--input\s+[^\r\n]+/);
    expect(workflow).toMatch(/force_test_alert/);
  });

  it('bounds the Vercel log query instead of following the deployment indefinitely', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    const logCommand = /^\s*vercel\s+logs[^\r\n]*$/m.exec(workflow)?.[0] ?? '';
    expect(logCommand).toMatch(/--since(?:=|\s+)5m(?:\s|$)/);
    expect(logCommand).toMatch(/--no-follow(?:\s|$)/);
  });

  it('creates or updates a labeled GitHub issue using a body file', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    expect(workflow).toMatch(/GH_TOKEN:\s*\$\{\{\s*github\.token\s*\}\}/);
    expect(workflow).toMatch(/\.issue\.key/);
    expect(workflow).toMatch(/gh\s+issue\s+list[\s\S]*--label[ ="']+\$?\{?issue_key\}?/i);
    expect(workflow).toMatch(/gh\s+issue\s+create[\s\S]*--body-file/i);
    expect(workflow).toMatch(/gh\s+issue\s+edit[\s\S]*--body-file/i);
    expect(workflow).toMatch(/\.issue\.body/);
    expect(workflow).toMatch(/phase8-monitor-test/);
    expect(workflow).toMatch(/production-alert/);
  });

  it('keeps provider credentials out of global environment and command arguments', () => {
    const workflow = readFileSync(WORKFLOW, 'utf8');
    const topLevelEnv = /^env:\s*$(.*?)(?=^(?:permissions|jobs):)/ms.exec(workflow)?.[1] ?? '';
    expect(topLevelEnv).not.toMatch(/secrets\./);
    expect(workflow).not.toMatch(/--token[ =]+\$\{\{\s*secrets\./i);
    expect(workflow).not.toMatch(/(?:echo|printf|cat)[^\r\n]*\$\{\{\s*secrets\./i);
    expect(workflow).toMatch(/VERCEL_TOKEN:\s*\$\{\{\s*secrets\.VERCEL_TOKEN\s*\}\}/);
  });
});
