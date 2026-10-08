import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { describe, expect, test } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type HeldUnallocatedRecord = {
  review: Record<string, unknown>;
  run: Record<string, unknown>;
  nativeJobs: Record<string, unknown>[];
  guardianJobs: Record<string, unknown>[];
  artifactNames: unknown[];
  jobListingComplete: unknown;
  artifactListingComplete: unknown;
};

const heldUnallocatedModuleUrl = new URL('../../scripts/pgtap/unallocated-cancellation.mjs', import.meta.url).href;
let heldUnallocatedLoadError: unknown = null;
let heldUnallocatedVerifier: ((input: unknown) => { verified: boolean }) | null = null;
try {
  const loaded = await import(/* @vite-ignore */ heldUnallocatedModuleUrl);
  heldUnallocatedVerifier = loaded.verifyUnallocatedNativeCancellation;
} catch (error) {
  heldUnallocatedLoadError = error;
}

function requireHeldUnallocatedVerifier() {
  expect(heldUnallocatedLoadError, 'DBV-014 declared module must load').toBeNull();
  expect(heldUnallocatedVerifier, 'DBV-014 declared verifier must be callable').toBeTypeOf('function');
  return heldUnallocatedVerifier!;
}

function heldUnallocatedFixture(): HeldUnallocatedRecord {
  return {
    review: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: '37727415803-1',
      sourceSha: 'c477758882bed3d4cb6c22f5168d9734f792fed4',
      jobId: '113148970433',
      guardianJobId: '113148971431',
      completionKind: 'unallocated-cancellation',
      privateProofSha256: 'd'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      verifiedAt: '2026-10-08T04:26:53.001Z',
    },
    run: {
      id: '37727415803',
      attempt: '1',
      sourceSha: 'c477758882bed3d4cb6c22f5168d9734f792fed4',
      repositoryId: 173,
      repository: NATIVE_DB_VALIDATION.repository,
      headRepositoryId: 173,
      headRepository: NATIVE_DB_VALIDATION.repository,
      event: 'push',
      path: '.github/workflows/db.yml',
      branch: 'main',
      status: 'completed',
      conclusion: 'cancelled',
    },
    nativeJobs: [{
      id: 113148970433,
      runId: '37727415803',
      attempt: '1',
      sourceSha: 'c477758882bed3d4cb6c22f5168d9734f792fed4',
      name: NATIVE_DB_VALIDATION.job,
      status: 'completed',
      conclusion: 'cancelled',
      runnerId: null,
      runnerName: null,
      runnerGroupId: null,
      runnerGroupName: null,
      labels: [],
      steps: [],
      startedAt: '2026-10-08T04:26:53Z',
      completedAt: '2026-10-08T04:26:53Z',
    }],
    guardianJobs: [{
      id: 113148971431,
      runId: '37727415803',
      attempt: '1',
      sourceSha: 'c477758882bed3d4cb6c22f5168d9734f792fed4',
      name: 'timeout-guardian',
      status: 'completed',
      conclusion: 'cancelled',
      runnerId: null,
      runnerName: null,
      runnerGroupId: null,
      runnerGroupName: null,
      labels: ['ubuntu-latest'],
      steps: [],
      startedAt: '2026-10-08T04:26:53Z',
      completedAt: '2026-10-08T04:26:53Z',
    }],
    artifactNames: ['native-db-schema-37727415803-1'],
    jobListingComplete: true,
    artifactListingComplete: true,
  };
}

function heldUnallocatedClone<T>(value: T): T {
  return structuredClone(value);
}

function heldUnallocatedReplace(target: object, key: PropertyKey, value: unknown) {
  Object.defineProperty(target, key, { value, enumerable: true, configurable: true, writable: true });
}

describe('DBV-014 held unallocated native cancellation', () => {
  test('declares the separate sole module export and exact verdict', async () => {
    const verify = requireHeldUnallocatedVerifier();
    const loaded = await import(/* @vite-ignore */ heldUnallocatedModuleUrl);
    expect(Object.keys(loaded)).toEqual(['verifyUnallocatedNativeCancellation']);
    expect(verify(heldUnallocatedFixture())).toStrictEqual({ verified: true });
  });

  test.each([{ labels: [] }, { labels: ['ubuntu-latest'] }])('accepts original no-assignment native labels $labels', ({ labels }) => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.nativeJobs[0].labels = labels;
    const before = heldUnallocatedClone(input);
    expect(verify(input)).toStrictEqual({ verified: true });
    expect(input).toStrictEqual(before);
  });

  test('accepts trusted workflow_dispatch and equivalent provider second/millisecond clocks', () => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.run.event = 'workflow_dispatch';
    input.nativeJobs[0].completedAt = '2026-10-08T04:26:53.000Z';
    input.guardianJobs[0].startedAt = '2026-10-08T04:26:53.000Z';
    expect(verify(input)).toStrictEqual({ verified: true });
  });

  test('accepts exact enumerable null-prototype records', () => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    for (const record of [input, input.review, input.run, ...input.nativeJobs, ...input.guardianJobs]) Object.setPrototypeOf(record, null);
    expect(verify(input)).toStrictEqual({ verified: true });
  });

  test.each([null, undefined, false, true, '', 'record', 1, [], () => null].map(value => ({ value })))('refuses primitive/nonrecord input $value', ({ value }) => {
    const verify = requireHeldUnallocatedVerifier();
    expect(verify(value)).toStrictEqual({ verified: false });
  });

  test.each([
    ['formatVersion', '1'], ['formatVersion', 0], ['formatVersion', null],
    ['runId', '037727415803-1'], ['runId', '37727415803-01'], ['runId', '0-1'],
    ['runId', '37727415803-0'], ['runId', '37727415803-1-1'], ['runId', 37727415803],
    ['sourceSha', 'C477758882bed3d4cb6c22f5168d9734f792fed4'], ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['sourceSha', 'c477758882bed3d4cb6c22f5168d9734f792fed'], ['sourceSha', null],
    ['jobId', '0113148970433'], ['jobId', '113148971431'], ['jobId', 113148970433],
    ['guardianJobId', '113148970433'], ['guardianJobId', '113148971431 '], ['guardianJobId', null],
    ['completionKind', 'github-hosted-job-decommission'], ['completionKind', 'unallocated-cancellation '],
    ['privateProofSha256', 'D'.repeat(NATIVE_DB_VALIDATION.digestHexLength)], ['privateProofSha256', 'z'.repeat(NATIVE_DB_VALIDATION.digestHexLength)],
    ['privateProofSha256', 'd'], ['privateProofSha256', null],
    ['verifiedAt', '2026-10-08T04:26:53.000Z'], ['verifiedAt', '2026-10-08T04:26:52.999Z'],
    ['verifiedAt', '2026-10-08T04:26:54Z'], ['verifiedAt', '2026-10-08T04:26:54.00Z'],
    ['verifiedAt', '2026-10-08T04:26:54.001+00:00'], ['verifiedAt', '1969-12-31T23:59:59.999Z'],
    ['verifiedAt', '2026-02-30T04:26:54.001Z'], ['verifiedAt', '+010000-01-01T00:00:00.000Z'], ['verifiedAt', null],
  ])('refuses review binding/value %s=%j', (key, value) => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.review[key as string] = value;
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  test.each([
    ['id', '37727415804'], ['id', '037727415803'], ['id', 37727415803],
    ['attempt', '2'], ['attempt', '01'], ['attempt', 1],
    ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['repositoryId', 0], ['repositoryId', '173'], ['repositoryId', Number.MAX_SAFE_INTEGER + 1],
    ['headRepositoryId', 174], ['headRepositoryId', null],
    ['repository', 'OGUN01/other'], ['repository', 'ogun01/gymloop'],
    ['headRepository', 'fork/gymloop'], ['headRepository', null],
    ['event', 'pull_request'], ['event', 'schedule'],
    ['path', '.github/workflows/other.yml'], ['path', '.github/workflows/db.yml@refs/heads/main'],
    ['branch', 'refs/heads/main'], ['branch', 'other'],
    ['status', 'in_progress'], ['conclusion', 'failure'], ['conclusion', 'success'], ['conclusion', null],
  ])('refuses original run identity %s=%j', (key, value) => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.run[key as string] = value;
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  test.each(['nativeJobs', 'guardianJobs'] as const)('refuses missing and duplicate %s pairs', side => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input[side] = [];
    expect(verify(input)).toStrictEqual({ verified: false });
    input[side] = [heldUnallocatedFixture()[side][0], heldUnallocatedFixture()[side][0]];
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  for (const side of ['nativeJobs', 'guardianJobs'] as const) {
    test.each([
      ['id', 0], ['id', '113148970433'], ['id', Number.MAX_SAFE_INTEGER + 1], ['id', 113148970432],
      ['runId', '37727415804'], ['runId', '037727415803'], ['attempt', '2'], ['attempt', 1],
      ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)], ['name', 'different-job'],
      ['status', 'queued'], ['status', 'in_progress'], ['conclusion', 'failure'], ['conclusion', 'success'],
      ['runnerId', 0], ['runnerId', 101], ['runnerName', ''], ['runnerName', 'GitHub Actions 101'],
      ['runnerGroupId', 0], ['runnerGroupId', 1], ['runnerGroupName', ''], ['runnerGroupName', 'GitHub Actions'],
      ['steps', [{ name: 'Set up job', status: 'completed', conclusion: 'success' }]], ['steps', null],
      ['startedAt', null], ['completedAt', null], ['startedAt', '2026-10-08T04:26:52Z'],
      ['completedAt', '2026-10-08T04:26:54Z'], ['startedAt', '2026-02-30T04:26:53Z'],
      ['completedAt', '2026-10-08T04:26:53+00:00'], ['startedAt', '1969-12-31T23:59:59Z'],
      ['completedAt', '+010000-01-01T00:00:00.000Z'], ['startedAt', '2026-10-08T04:26:53.00Z'],
    ])(`refuses ${side} job field %s=%j`, (key, value) => {
      const verify = requireHeldUnallocatedVerifier();
      const input = heldUnallocatedFixture();
      input[side][0][key as string] = value;
      expect(verify(input)).toStrictEqual({ verified: false });
    });

    test.each(['runnerId', 'runnerName', 'runnerGroupId', 'runnerGroupName'])(`refuses absent explicit ${side} %s`, key => {
      const verify = requireHeldUnallocatedVerifier();
      const input = heldUnallocatedFixture();
      delete input[side][0][key];
      expect(verify(input)).toStrictEqual({ verified: false });
    });

    test.each([['self-hosted'], ['windows'], ['ubuntu-latest', 'self-hosted'], ['ubuntu-latest', 'ubuntu-latest'], ['Ubuntu-latest'], [null]].map(labels => ({ labels })))(`refuses incompatible ${side} labels $labels`, ({ labels }) => {
      const verify = requireHeldUnallocatedVerifier();
      const input = heldUnallocatedFixture();
      input[side][0].labels = labels;
      expect(verify(input)).toStrictEqual({ verified: false });
    });
  }

  test('refuses missing guardian hosted selector and exchanged native/guardian identity', () => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.guardianJobs[0].labels = [];
    expect(verify(input)).toStrictEqual({ verified: false });
    const exchanged = heldUnallocatedFixture();
    [exchanged.nativeJobs, exchanged.guardianJobs] = [exchanged.guardianJobs, exchanged.nativeJobs];
    expect(verify(exchanged)).toStrictEqual({ verified: false });
  });

  test('review must follow both jobs even when their cancellation instants differ', () => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.guardianJobs[0].startedAt = '2026-10-08T04:26:53.002Z';
    input.guardianJobs[0].completedAt = '2026-10-08T04:26:53.002Z';
    expect(verify(input)).toStrictEqual({ verified: false });
    input.review.verifiedAt = '2026-10-08T04:26:53.003Z';
    expect(verify(input)).toStrictEqual({ verified: true });
  });

  test.each(['jobListingComplete', 'artifactListingComplete'] as const)('requires strict complete %s', key => {
    const verify = requireHeldUnallocatedVerifier();
    for (const value of [false, null, undefined, 'true', 1, [], {}]) {
      const input = heldUnallocatedFixture();
      input[key] = value;
      expect(verify(input)).toStrictEqual({ verified: false });
    }
  });

  test.each(['native-db-manifest', 'native-db-recovery', 'native-db-client-smoke', 'native-db-final', 'native-db-private', 'native-db-private-custody', 'native-db-timing-boundary', 'native-db-ci-job'])('refuses complete listing bound %s custody irrespective of expired retention', prefix => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.artifactNames.push(`${prefix}-37727415803-1`);
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  test.each(['native-db-restoration-37727415803-1', 'native-db-restoration-37727415803-1-closed', 'native-db-restoration-37727415803-1-'])('refuses exact or suffixed restoration %s', name => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.artifactNames.push(name);
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  test('permits schema and unrelated prior-attempt names without treating them as recovery', () => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.artifactNames.push('native-db-recovery-37727415803-2', 'native-db-private-37727415802-1', 'native-db-restoration-37727415803-10', 'unrelated-artifact');
    expect(verify(input)).toStrictEqual({ verified: true });
  });

  test.each([null, 1, '', {}, new String('artifact')])('refuses nonprimitive/nonempty artifact names %j', name => {
    const verify = requireHeldUnallocatedVerifier();
    const input = heldUnallocatedFixture();
    input.artifactNames.push(name);
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  for (const location of ['input', 'review', 'run', 'native', 'guardian'] as const) {
    test.each(['missing', 'extra', 'symbol', 'prototype', 'hidden', 'accessor'])(`rejects ${location} closed-record %s descriptors without getter effects`, kind => {
      const verify = requireHeldUnallocatedVerifier();
      const input = heldUnallocatedFixture();
      const record = location === 'input' ? input : location === 'native' ? input.nativeJobs[0] : location === 'guardian' ? input.guardianJobs[0] : input[location];
      const key = Object.keys(record)[0];
      let reads = 0;
      if (kind === 'missing') Reflect.deleteProperty(record, key);
      if (kind === 'extra') heldUnallocatedReplace(record, 'unknown', true);
      if (kind === 'symbol') heldUnallocatedReplace(record, Symbol('hidden-custody'), true);
      if (kind === 'prototype') Object.setPrototypeOf(record, { inherited: true });
      if (kind === 'hidden') Object.defineProperty(record, key, { enumerable: false });
      if (kind === 'accessor') Object.defineProperty(record, key, { enumerable: true, get() { reads += 1; throw new Error('getter execution'); } });
      expect(verify(input)).toStrictEqual({ verified: false });
      expect(reads).toBe(0);
    });
  }

  for (const location of ['nativeJobs', 'guardianJobs', 'artifactNames', 'nativeLabels', 'guardianLabels', 'nativeSteps', 'guardianSteps'] as const) {
    test.each(['extra', 'symbol', 'prototype', 'hidden-extra', 'hole', 'accessor'])(`rejects ${location} nonordinary arrays %s without getter effects`, kind => {
      const verify = requireHeldUnallocatedVerifier();
      const input = heldUnallocatedFixture();
      const array = location === 'nativeLabels' ? input.nativeJobs[0].labels : location === 'guardianLabels' ? input.guardianJobs[0].labels : location === 'nativeSteps' ? input.nativeJobs[0].steps : location === 'guardianSteps' ? input.guardianJobs[0].steps : input[location];
      let reads = 0;
      if (kind === 'extra') heldUnallocatedReplace(array as object, 'custody', true);
      if (kind === 'symbol') heldUnallocatedReplace(array as object, Symbol('custody'), true);
      if (kind === 'prototype') Object.setPrototypeOf(array as object, Object.create(Array.prototype));
      if (kind === 'hidden-extra') Object.defineProperty(array, 'custody', { value: true, enumerable: false });
      if (kind === 'hole') { (array as unknown[]).push(undefined); Reflect.deleteProperty(array as object, String((array as unknown[]).length - 1)); }
      if (kind === 'accessor') Object.defineProperty(array, '0', { enumerable: true, configurable: true, get() { reads += 1; throw new Error('array getter execution'); } });
      expect(verify(input)).toStrictEqual({ verified: false });
      expect(reads).toBe(0);
    });
  }

  test.each(['getPrototypeOf', 'ownKeys', 'getOwnPropertyDescriptor'] as const)('reflection exception %s returns false', trap => {
    const verify = requireHeldUnallocatedVerifier();
    const input = new Proxy(heldUnallocatedFixture(), { [trap]() { throw new Error('inert reflection failure'); } });
    expect(() => verify(input)).not.toThrow();
    expect(verify(input)).toStrictEqual({ verified: false });
  });

  test.each([
    ['1970-01-01T00:00:00.000Z', false, 0],
    ['1970-01-01T00:00:00Z', true, 0],
    ['1970-01-01T00:00:00Z', false, null],
    ['2026-10-08T04:26:53.001Z', false, Date.parse('2026-10-08T04:26:53.001Z')],
    ['2026-02-30T00:00:00.000Z', false, null],
    ['2026-10-08T04:26:53.00Z', true, null],
    ['2026-10-08T04:26:53+00:00', true, null],
    ['1969-12-31T23:59:59.999Z', true, null],
    ['+010000-01-01T00:00:00.000Z', true, null],
    [null, true, null],
  ])('shared evidence clock preserves canonical UTC and strict mode (%j,%j)', async (value, provider, expected) => {
    requireHeldUnallocatedVerifier();
    const loaded = await import('../../scripts/pgtap/data-record.mjs');
    expect(loaded.nativeEvidenceClock).toBeTypeOf('function');
    expect(loaded.nativeEvidenceClock(value, provider)).toBe(expected);
  });

  test('clock default retains millisecond requirement and new absence record does not widen old classifiers', async () => {
    requireHeldUnallocatedVerifier();
    const clocks = await import('../../scripts/pgtap/data-record.mjs');
    expect(clocks.nativeEvidenceClock('1970-01-01T00:00:00Z')).toBeNull();
    const hosted = await import('../../scripts/pgtap/hosted-completion.mjs');
    const teardown = await import('../../scripts/pgtap/workload-teardown.mjs');
    const unarmed = await import('../../scripts/pgtap/unarmed-precheck.mjs');
    const input = heldUnallocatedFixture();
    const expected = { runId: input.review.runId, sourceSha: input.review.sourceSha, jobId: input.review.jobId, runnerId: null, runnerEnvironment: 'github-hosted' };
    expect(hosted.verifyHostedNativeWorkloadCompletion(expected, input.nativeJobs[0], input.review)).toBe(false);
    expect(teardown.verifyNativeWorkloadTeardown(expected, input.review)).toBe(false);
    expect(unarmed.verifyUnarmedNativePrecheck(input)).toStrictEqual({ verified: false });
  });
});

async function executeHeldUnallocatedPreflight(input = heldUnallocatedFixture(), options: Record<string, unknown> = {}) {
  requireHeldUnallocatedVerifier();
  const root = new URL('../../', import.meta.url);
  const workflow = await readFile(new URL('.github/workflows/db.yml', root), 'utf8');
  const marker = "name: Require the previous armed attempt's verified restoration";
  const start = workflow.indexOf(marker);
  const boundary = workflow.indexOf('\n  pgtap-rollback:', start);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(boundary).toBeGreaterThan(start);
  const block = workflow.slice(start, boundary);
  const scalar = block.indexOf('          script: |');
  expect(scalar).toBeGreaterThanOrEqual(0);
  const lines = block.slice(scalar).split(/\r?\n/).slice(1);
  const finish = lines.findIndex(line => line.trim() !== '' && !line.startsWith('            '));
  const body = (finish < 0 ? lines : lines.slice(0, finish)).map(line => line.slice('            '.length)).join('\n');
  const events: string[] = [];
  const baseline = {
    id: Number(NATIVE_DB_VALIDATION.legacyBaselineRunId), run_attempt: 1,
    head_sha: NATIVE_DB_VALIDATION.legacyBaselineSourceSha,
    event: 'push', path: '.github/workflows/db.yml', head_branch: 'main', status: 'completed', conclusion: 'success',
    repository: { id: 173, full_name: NATIVE_DB_VALIDATION.repository },
    head_repository: { id: 173, full_name: NATIVE_DB_VALIDATION.repository },
  };
  const prior = {
    id: Number(input.run.id), run_attempt: Number(input.run.attempt), head_sha: input.run.sourceSha,
    event: input.run.event, path: input.run.path, head_branch: input.run.branch, status: input.run.status, conclusion: input.run.conclusion,
    repository: { id: input.run.repositoryId, full_name: input.run.repository },
    head_repository: { id: input.run.headRepositoryId, full_name: input.run.headRepository },
  };
  const jobs = [...input.nativeJobs, ...input.guardianJobs].map(job => ({
    id: job.id, run_id: Number(job.runId), run_attempt: Number(job.attempt), head_sha: job.sourceSha,
    name: job.name, status: job.status, conclusion: job.conclusion,
    runner_id: job.runnerId, runner_name: job.runnerName, runner_group_id: job.runnerGroupId, runner_group_name: job.runnerGroupName,
    labels: job.labels, steps: job.steps, started_at: job.startedAt, completed_at: job.completedAt,
  }));
  const extraJobs = ['changes', 'pgtap-rollback', 'drift', 'database-recovery-preflight', 'migrate', 'seed-dry-run', 'archive'].map(name => ({
    id: 173, run_id: Number(input.run.id), run_attempt: Number(input.run.attempt), head_sha: input.run.sourceSha,
    name, status: 'completed', conclusion: 'skipped', runner_id: null, runner_name: null, runner_group_id: null, runner_group_name: null, labels: [], steps: [],
    started_at: '2026-10-08T04:26:53Z', completed_at: '2026-10-08T04:26:53Z',
  }));
  const oldJobs = [NATIVE_DB_VALIDATION.job, 'timeout-guardian'].map((name, index) => ({
    id: index === 0 ? 113148970430 : 113148971430, run_id: 37727415802, run_attempt: 1,
    head_sha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), name, status: 'completed', conclusion: 'failure',
    runner_id: 123, runner_name: 'GitHub Actions 123', runner_group_id: 1, runner_group_name: 'GitHub Actions', labels: ['ubuntu-latest'],
    steps: [{ name: 'Run native validation', status: 'completed', conclusion: 'failure' }],
    started_at: '2026-10-08T04:25:53Z', completed_at: '2026-10-08T04:26:53Z',
  }));
  const original = options.originalRun ? { ...prior, ...(options.originalRun as object) } : prior;
  const reviews = options.reviews ?? [input.review];
  const artifactNames = input.artifactNames;
  const artifacts = artifactNames.map((name, index) => ({
    id: index + 1, name, expired: options.expired === true,
    workflow_run: { id: prior.id, head_sha: prior.head_sha, head_branch: 'main' }, size_in_bytes: 1,
    digest: `sha256:${'d'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}`,
  }));
  const extraRun = { ...prior, id: 37727415802, head_sha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), conclusion: 'failure' };
  const actions = {
    async getWorkflowRun(request: Record<string, unknown>) {
      events.push(`latest:${request.run_id}`);
      return { data: String(request.run_id) === NATIVE_DB_VALIDATION.legacyBaselineRunId ? baseline : { ...prior, head_sha: 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), status: 'completed', conclusion: 'success' } };
    },
    async getWorkflowRunAttempt(request: Record<string, unknown>) {
      events.push(`attempt:${request.run_id}:${request.attempt_number}`);
      return { data: String(request.run_id) === String(extraRun.id) ? extraRun : original };
    },
    async listJobsForWorkflowRunAttempt(request: Record<string, unknown>) {
      events.push(`jobs:${request.run_id}:${request.attempt_number}`);
      const value = String(request.run_id) === NATIVE_DB_VALIDATION.legacyBaselineRunId
        ? ['migrate', NATIVE_DB_VALIDATION.job, 'seed-dry-run'].map(name => ({ name, status: 'completed', conclusion: 'success', head_sha: baseline.head_sha }))
        : String(request.run_id) === String(extraRun.id) ? oldJobs : [...jobs, ...extraJobs, ...(options.extraJobs as object[] ?? [])];
      return { data: { jobs: value, total_count: options.incompleteJobs === true ? value.length + 1 : value.length } };
    },
    async listWorkflowRunArtifacts(request: Record<string, unknown>) {
      events.push(`artifacts:${request.run_id}`);
      const value = String(request.run_id) === String(extraRun.id) ? [{ ...artifacts[0], name: 'native-db-recovery-37727415802-1', expired: true }] : artifacts;
      return { data: { artifacts: value, total_count: options.incompleteArtifacts === true ? value.length + 1 : value.length } };
    },
    async listWorkflowRuns() { throw new Error('iterator port required'); },
    async downloadArtifact() { events.push('forbidden-download'); throw new Error('absence class may not download artifacts'); },
  };
  const paginate = Object.assign(async (method: (request: Record<string, unknown>) => Promise<{ data: Record<string, unknown> }>, request: Record<string, unknown>) => {
    const response = await method(request);
    return response.data.jobs ?? response.data.artifacts ?? [];
  }, {
    async *iterator(method: unknown, request: Record<string, unknown>) {
      if (method === actions.listWorkflowRuns) {
        events.push('runs');
        yield { data: options.olderArmed === true ? [prior, extraRun, baseline] : [prior, baseline] };
      } else {
        const response = await (method as (request: Record<string, unknown>) => Promise<{ data: Record<string, unknown> }>)(request);
        yield { ...response, data: Object.assign((response.data.jobs ?? response.data.artifacts) as object, { total_count: response.data.total_count }) };
      }
    },
  });
  const context = { repo: { owner: 'OGUN01', repo: 'gymloop' }, runId: 37727415804, sha: 'f'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), eventName: 'push' };
  const core = { info(message: unknown) { events.push(`info:${String(message)}`); } };
  async function heldUnallocatedImport(specifier: string) {
    events.push(`import:${specifier}`);
    if (specifier === 'node:fs/promises') return { readFile: async (path: string, encoding: string) => {
      events.push(`file:${path}`);
      if (path === '.dbv/current-attempt.txt') return '1\n';
      if (path === '.dbv/operator-workload-teardowns.json') return JSON.stringify(reviews);
      if (path === '.dbv/operator-unarmed-prechecks.json' || path === '.dbv/operator-timeout-recoveries.json') return '[]';
      return readFile(path, encoding as 'utf8');
    } };
    if (specifier === 'node:child_process') return { execFileSync() { events.push('forbidden-exec'); throw new Error('absence class may not execute native tools'); } };
    const target = /^[a-z]:[\\/]/i.test(specifier) ? pathToFileURL(specifier).href : specifier.startsWith('./') || specifier.startsWith('../') ? new URL(specifier, root).href : specifier;
    return import(/* @vite-ignore */ target);
  }
  const invoke = new Function('github', 'context', 'core', 'heldUnallocatedImport', 'fetch', `return (async () => {${body.replaceAll('await import(', 'await heldUnallocatedImport(')}\n})();`);
  let error: unknown = null;
  try {
    await invoke({ rest: { actions }, paginate }, context, core, heldUnallocatedImport, async () => { events.push('forbidden-fetch'); throw new Error('absence class may not fetch artifacts'); });
  } catch (caught) {
    error = caught;
  }
  return { error, events };
}

describe('DBV-014 held opaque workflow integration', () => {
  test.each([{ labels: [] }, { labels: ['ubuntu-latest'] }])('only exact reviewed cancelled pair clears both scoped branches ($labels)', async ({ labels }) => {
    const input = heldUnallocatedFixture();
    input.nativeJobs[0].labels = labels;
    const result = await executeHeldUnallocatedPreflight(input);
    expect(result.error).toBeNull();
    expect(result.events.some(event => event.includes('unallocated-cancellation.mjs'))).toBe(true);
    expect(result.events).toContain('attempt:37727415803:1');
    expect(result.events.some(event => event.startsWith('forbidden-'))).toBe(false);
  });

  test.each(['missing', 'duplicate', 'wrong-kind', 'wrong-proof'])('administrator review %s refuses', async kind => {
    const input = heldUnallocatedFixture();
    const review = { ...input.review };
    if (kind === 'wrong-kind') review.completionKind = 'github-hosted-job-decommission';
    if (kind === 'wrong-proof') review.privateProofSha256 = 'bad';
    const reviews = kind === 'missing' ? [] : kind === 'duplicate' ? [review, review] : [review];
    const result = await executeHeldUnallocatedPreflight(input, { reviews });
    expect(result.error).not.toBeNull();
  });

  test.each(['native', 'guardian', 'both'])('assigned %s job never receives the pair exemption', async side => {
    const input = heldUnallocatedFixture();
    if (side !== 'guardian') input.nativeJobs[0].runnerId = 123;
    if (side !== 'native') input.guardianJobs[0].runnerName = 'GitHub Actions 123';
    const result = await executeHeldUnallocatedPreflight(input);
    expect(result.error).not.toBeNull();
  });

  test.each(['native', 'guardian'])('executed %s job never receives the pair exemption', async side => {
    const input = heldUnallocatedFixture();
    (side === 'native' ? input.nativeJobs : input.guardianJobs)[0].steps = [{ name: 'Set up job', status: 'completed', conclusion: 'success' }];
    const result = await executeHeldUnallocatedPreflight(input);
    expect(result.error).not.toBeNull();
  });

  test.each(['native', 'guardian'])('missing %s pair member refuses', async side => {
    const input = heldUnallocatedFixture();
    if (side === 'native') input.nativeJobs = [];
    else input.guardianJobs = [];
    const result = await executeHeldUnallocatedPreflight(input);
    expect(result.error).not.toBeNull();
  });

  test.each(['nativeJobs', 'guardianJobs'] as const)('duplicate %s pair member refuses', async side => {
    const input = heldUnallocatedFixture();
    input[side].push(heldUnallocatedClone(input[side][0]));
    const result = await executeHeldUnallocatedPreflight(input);
    expect(result.error).not.toBeNull();
  });

  test.each(['incompleteJobs', 'incompleteArtifacts'])('does not trust an incomplete %s listing', async key => {
    const result = await executeHeldUnallocatedPreflight(heldUnallocatedFixture(), { [key]: true });
    expect(result.error).not.toBeNull();
  });

  test.each(['native-db-recovery', 'native-db-private-custody', 'native-db-ci-job', 'native-db-restoration'])('expired bound %s artifact still conflicts', async prefix => {
    const input = heldUnallocatedFixture();
    input.artifactNames.push(`${prefix}-37727415803-1`);
    const result = await executeHeldUnallocatedPreflight(input, { expired: true });
    expect(result.error).not.toBeNull();
  });

  test.each([
    { head_sha: 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { run_attempt: 2 }, { id: 37727415805 }, { head_branch: 'other' }, { event: 'pull_request' },
    { head_repository: { id: 174, full_name: NATIVE_DB_VALIDATION.repository } },
    { status: 'in_progress', conclusion: null },
  ])('uses exact selected-attempt metadata instead of latest-run guesses %j', async originalRun => {
    const result = await executeHeldUnallocatedPreflight(heldUnallocatedFixture(), { originalRun });
    expect(result.error).not.toBeNull();
  });

  test('current reviewed pair cannot exempt an older armed failure', async () => {
    const result = await executeHeldUnallocatedPreflight(heldUnallocatedFixture(), { olderArmed: true });
    expect(result.error).not.toBeNull();
  });

  test('both database workflow path filters include the new native input', async () => {
    requireHeldUnallocatedVerifier();
    const workflow = await readFile(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    const filters = [...workflow.matchAll(/^    paths:\r?\n((?:      .*\r?\n)+)/gm)];
    expect(filters.length).toBe(2);
    for (const filter of filters) expect(filter[1]).toContain('scripts/pgtap/unallocated-cancellation.mjs');
  });
});

async function executeHeldUnallocatedClassification(changed: string, diffAvailable = true) {
  requireHeldUnallocatedVerifier();
  const workflow = await readFile(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const start = workflow.indexOf('      - name: Decide whether the suite can run here');
  const end = workflow.indexOf('      - name: Resolve source-bound online readiness or hosted fallback', start);
  expect(start).toBeGreaterThanOrEqual(0);
  expect(end).toBeGreaterThan(start);
  const block = workflow.slice(start, end);
  const scalar = block.indexOf('        run: |');
  expect(scalar).toBeGreaterThanOrEqual(0);
  const lines = block.slice(scalar).split(/\r?\n/).slice(1);
  const finish = lines.findIndex(line => line.trim() !== '' && !line.startsWith('          '));
  const body = (finish < 0 ? lines : lines.slice(0, finish)).map(line => line.slice('          '.length)).join('\n');
  const directory = join(tmpdir(), `held-unallocated-classification-${randomUUID()}`).replaceAll('\\', '/');
  const output = `${directory}/github-output.txt`;
  await mkdir(directory);
  await writeFile(output, '', { flag: 'wx' });
  const replacements: Record<string, string> = {
    'github.repository': NATIVE_DB_VALIDATION.repository,
    'github.ref': 'refs/heads/main',
    'github.event_name': 'push',
    'needs.migrate.outputs.schema_ready': 'true',
    'github.event.before': 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    'github.sha': 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
  };
  const compiled = body.replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_match, expression: string) => {
    expect(Object.hasOwn(replacements, expression.trim())).toBe(true);
    return replacements[expression.trim()];
  });
  const prefix = `git() { case "$1" in cat-file) return 0 ;; diff) ${diffAvailable ? `printf '%s\\n' '${changed.replaceAll("'", "'\\''")}'` : 'return 1'} ;; *) return 1 ;; esac; }; export GITHUB_OUTPUT='${output}';\n`;
  const result = await new Promise<{ error: unknown; stdout: string; stderr: string }>(resolve => {
    execFile(process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash', ['--noprofile', '--norc', '-c', prefix + compiled], { windowsHide: true, cwd: directory }, (error, stdout, stderr) => resolve({ error, stdout, stderr }));
  });
  return { ...result, output: await readFile(output, 'utf8') };
}

describe('DBV-014 held native workflow input classification', () => {
  test('new verifier is a native validation input on trusted schema-ready main', async () => {
    const result = await executeHeldUnallocatedClassification('scripts/pgtap/unallocated-cancellation.mjs');
    expect(result.error).toBeNull();
    expect(result.output.split(/\r?\n/)).toContain('run=true');
  });

  test('uncomputable changed-file input still requires fresh native validation', async () => {
    const result = await executeHeldUnallocatedClassification('', false);
    expect(result.error).toBeNull();
    expect(result.output.split(/\r?\n/)).toContain('run=true');
  });
});
