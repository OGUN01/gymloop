import { describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.js';

type Verifier = (input: unknown) => { verified: boolean };
type RecordValue = Record<string, unknown>;

const refusalStep = 'Validate the full native suite with outside-worker recovery custody';
const discoveryStep = 'Find the exact armed receipt, including an earlier attempt of this run';
const cleanupNames = ['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job'];
const caseNames = ['success', 'assertion-failure', 'missing-plan', 'extra-plan', 'broken-plan', 'malformed', 'truncated', 'client-error', 'connection-loss'];
const digest = (letter: string) => letter.repeat(NATIVE_DB_VALIDATION.digestHexLength);
const step = (name: string, conclusion = 'success') => ({ name, status: 'completed', conclusion });

function fixture() {
  const sourceSha = 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
  const runId = '88';
  const attempt = '2';
  const job = (id: number, runnerId: number, name: string, steps: ReturnType<typeof step>[]) => ({
    id, runId, attempt, sourceSha, name, status: 'completed', conclusion: 'failure', runnerId,
    runnerName: `GitHub Actions ${runnerId}`, runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'], steps,
  });
  return {
    review: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId, runAttempt: attempt, sourceSha,
      nativeJobId: 101, guardianJobId: 102, runnerId: 501, adapterSha256: digest('b'), workflowSha256: digest('c'),
      smokeArtifactId: 201, smokeArchiveSha256: digest('d'), privateProofSha256: digest('e'), reviewedAt: '2026-10-07T09:00:00.000Z',
    },
    run: { id: runId, attempt, sourceSha, event: 'push', branch: 'main', status: 'completed', conclusion: 'failure' },
    nativeJob: job(101, 501, 'pgtap', [step('Set up job'), step(refusalStep, 'failure'), step('Retain client-only smoke metadata'), ...cleanupNames.map(name => step(name))]),
    guardianJob: job(102, 502, 'timeout-guardian', [step('Set up job'), step(discoveryStep, 'failure'), step('Run supabase link --project-ref "$PROJECT_REF" --yes', 'skipped'), step('Restore and freshly verify only the captured role-global timeout', 'skipped'), step('Download artifact', 'skipped'), step('Download artifact', 'skipped'), ...cleanupNames.map(name => step(name))]),
    smokeArchive: { id: 201, name: `native-db-client-smoke-${runId}-${attempt}`, runId, sourceSha, apiSha256: digest('d'), archiveSha256: digest('d'), expired: false },
    smoke: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion, sourceSha, cliVersion: NATIVE_DB_VALIDATION.cliVersion,
      clientDigest: NATIVE_DB_VALIDATION.clientDigest, runnerOs: 'Linux', network: 'host', nativeClientImage: NATIVE_DB_VALIDATION.nativeClientImage,
      nativeClientImageId: `sha256:${digest('f')}`, imageSelectionSource: 'https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/shared/legacy-docker-registry.ts',
      firstDirectoryCwd: true, readOnlyBinds: true, reportingLines: [...NATIVE_DB_VALIDATION.reportingLines], stubSha256: digest('b'), capturedAt: '2026-10-07T08:00:00.000Z',
      cases: caseNames.map(name => ({
        name, exitCode: 1, completed: true, signal: null, nativeMs: 0, stdoutSha256: digest('c'), stderrSha256: digest('d'),
        timerCount: 2, rawTapPresent: false, inputsUnchanged: true, checkPassed: name !== 'success',
        fileMetadata: [
          { path: 'supabase/tests/.proverc', sha256: digest('b'), byteLength: 1 },
          { path: 'supabase/tests-holdout/independent.pg', sha256: digest('c'), byteLength: 1 },
          { path: `supabase/tests/${name === 'client-error' || name === 'connection-loss' ? name : 'visible'}.sql`, sha256: digest('d'), byteLength: 1 },
        ],
      })), accepted: false,
    },
    sourceHashes: { adapterSha256: digest('b'), workflowSha256: digest('c') },
    recoveryArtifactPresent: false, artifactListingComplete: true,
  };
}

function location(input: unknown, path: string[]): { owner: RecordValue; key: string } {
  const key = path.at(-1);
  if (!key) throw new Error('Fixture path is empty.');
  let owner = input as RecordValue;
  for (const name of path.slice(0, -1)) owner = owner[name] as RecordValue;
  return { owner, key };
}

function change(input: unknown, path: string, value: unknown): void {
  const { owner, key } = location(input, path.split('.'));
  owner[key] = value;
}

function freeze(value: unknown): void {
  if (value === null || typeof value !== 'object') return;
  for (const child of Object.values(value)) freeze(child);
  Object.freeze(value);
}

function nullRecords(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(nullRecords);
  if (value === null || typeof value !== 'object') return value;
  return Object.assign(Object.create(null), Object.fromEntries(Object.entries(value).map(([key, child]) => [key, nullRecords(child)])));
}

async function verifier(): Promise<Verifier> {
  const module = await vi.importActual<RecordValue>('../../scripts/pgtap/unarmed-precheck.mjs');
  expect(Object.keys(module)).toEqual(['verifyUnarmedNativePrecheck']);
  expect(typeof module.verifyUnarmedNativePrecheck).toBe('function');
  return module.verifyUnarmedNativePrecheck as Verifier;
}

const changes: { path: string; value: unknown }[] = [
  ...['review', 'run', 'nativeJob', 'guardianJob', 'smokeArchive', 'smoke'].map(prefix => ({ path: `${prefix}.sourceSha`, value: 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) })),
  ...['review.runId', 'run.id', 'nativeJob.runId', 'guardianJob.runId', 'smokeArchive.runId'].map(path => ({ path, value: '89' })),
  ...['review.runAttempt', 'run.attempt', 'nativeJob.attempt', 'guardianJob.attempt'].map(path => ({ path, value: '3' })),
  ...['review.nativeJobId', 'review.guardianJobId', 'review.runnerId', 'review.smokeArtifactId', 'nativeJob.id', 'nativeJob.runnerId', 'guardianJob.id', 'smokeArchive.id'].map(path => ({ path, value: 999 })),
  ...['review.adapterSha256', 'review.workflowSha256', 'review.smokeArchiveSha256', 'sourceHashes.adapterSha256', 'sourceHashes.workflowSha256', 'smokeArchive.apiSha256', 'smokeArchive.archiveSha256'].map(path => ({ path, value: digest('f') })),
  { path: 'review.formatVersion', value: 0 }, { path: 'review.privateProofSha256', value: digest('E') }, { path: 'review.reviewedAt', value: '2026-02-30T09:00:00.000Z' },
  { path: 'run.event', value: 'pull_request' }, { path: 'run.branch', value: 'refs/heads/main' }, { path: 'run.status', value: 'in_progress' }, { path: 'run.conclusion', value: 'success' },
  ...['nativeJob', 'guardianJob'].flatMap(prefix => [
    { path: `${prefix}.name`, value: 'unrelated' }, { path: `${prefix}.status`, value: 'queued' }, { path: `${prefix}.conclusion`, value: 'cancelled' },
    { path: `${prefix}.runnerName`, value: 'GitHub Actions 0501' }, { path: `${prefix}.runnerGroupName`, value: 'Default' }, { path: `${prefix}.labels`, value: ['self-hosted', 'ubuntu-latest'] },
  ]),
  { path: 'smokeArchive.name', value: 'native-db-client-smoke-88-1' }, { path: 'smokeArchive.expired', value: true }, { path: 'smokeArchive.expired', value: 0 },
  { path: 'recoveryArtifactPresent', value: true }, { path: 'recoveryArtifactPresent', value: 0 }, { path: 'artifactListingComplete', value: false }, { path: 'artifactListingComplete', value: 1 },
  { path: 'smoke.formatVersion', value: 0 }, { path: 'smoke.cliVersion', value: '2.109.0' }, { path: 'smoke.clientDigest', value: `sha256:${digest('a')}` },
  { path: 'smoke.runnerOs', value: 'Windows' }, { path: 'smoke.network', value: 'bridge' }, { path: 'smoke.nativeClientImage', value: 'supabase/pg_prove:latest' },
  { path: 'smoke.nativeClientImageId', value: digest('a') }, { path: 'smoke.imageSelectionSource', value: 'https://example.com/registry' },
  { path: 'smoke.firstDirectoryCwd', value: false }, { path: 'smoke.firstDirectoryCwd', value: 'true' }, { path: 'smoke.readOnlyBinds', value: false }, { path: 'smoke.readOnlyBinds', value: 1 }, { path: 'smoke.reportingLines', value: [...NATIVE_DB_VALIDATION.reportingLines].reverse() },
  { path: 'smoke.stubSha256', value: 'bad' }, { path: 'smoke.capturedAt', value: '2026-10-07T08:00:00Z' }, { path: 'smoke.accepted', value: true }, { path: 'smoke.accepted', value: 0 },
  { path: 'smoke.cases.0.checkPassed', value: true }, { path: 'smoke.cases.1.completed', value: false }, { path: 'smoke.cases.1.completed', value: 1 }, { path: 'smoke.cases.1.signal', value: 'SIGTERM' },
  { path: 'smoke.cases.1.exitCode', value: 2 }, { path: 'smoke.cases.1.nativeMs', value: 0.5 }, { path: 'smoke.cases.1.timerCount', value: -1 },
  { path: 'smoke.cases.1.stdoutSha256', value: digest('C') }, { path: 'smoke.cases.1.stderrSha256', value: null }, { path: 'smoke.cases.1.rawTapPresent', value: 0 },
  { path: 'smoke.cases.1.inputsUnchanged', value: false }, { path: 'smoke.cases.1.checkPassed', value: 'true' },
  { path: 'smoke.cases.7.fileMetadata.2.path', value: 'supabase/tests/visible.sql' }, { path: 'smoke.cases.8.fileMetadata.2.path', value: 'supabase/tests/client-error.sql' },
  { path: 'smoke.cases.0.fileMetadata.0.byteLength', value: 0 }, { path: 'smoke.cases.0.fileMetadata.0.sha256', value: 'bad' },
  { path: 'nativeJob.id', value: Number.MAX_SAFE_INTEGER + 1 }, { path: 'review.runAttempt', value: '02' }, { path: 'guardianJob.runnerId', value: 0 },
];

describe('DBV-005/007 independent exact unarmed hosted refusal classification', () => {
  it('accepts the complete review while preserving failed jobs and duplicate optional skipped steps', async () => {
    const verify = await verifier();
    const input = fixture();
    const before = JSON.stringify(input);
    freeze(input);
    expect(verify(input)).toEqual({ verified: true });
    expect(JSON.stringify(input)).toBe(before);
  });

  it('accepts null-prototype records, dispatch, unordered metadata, and permitted zero native exit', async () => {
    const input = fixture();
    input.run.event = 'workflow_dispatch';
    input.smoke.cases[0]!.exitCode = 0;
    input.smoke.cases[1]!.checkPassed = false;
    for (const testCase of input.smoke.cases) testCase.fileMetadata.reverse();
    expect((await verifier())(nullRecords(input))).toEqual({ verified: true });
  });

  it.each(changes)('refuses inconsistent or invalid $path ($value)', async ({ path, value }) => {
    const input = fixture();
    change(input, path, value);
    const before = JSON.stringify(input);
    freeze(input);
    expect((await verifier())(input)).toEqual({ verified: false });
    expect(JSON.stringify(input)).toBe(before);
  });

  it('refuses self-consistent noncanonical source, run and attempt identities', async () => {
    const verify = await verifier();
    for (const [field, value] of [['sourceSha', 'A'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)], ['sourceSha', digest('a')], ['runId', '088'], ['attempt', '02']]) {
      const input = fixture();
      if (field === 'sourceSha') for (const prefix of ['review', 'run', 'nativeJob', 'guardianJob', 'smokeArchive', 'smoke']) change(input, `${prefix}.sourceSha`, value);
      if (field === 'runId') for (const path of ['review.runId', 'run.id', 'nativeJob.runId', 'guardianJob.runId', 'smokeArchive.runId']) change(input, path, value);
      if (field === 'attempt') for (const path of ['review.runAttempt', 'run.attempt', 'nativeJob.attempt', 'guardianJob.attempt']) change(input, path, value);
      input.smokeArchive.name = `native-db-client-smoke-${input.review.runId}-${input.review.runAttempt}`;
      expect(verify(input)).toEqual({ verified: false });
    }
  });

  it('refuses missing required keys and extra top-level keys', async () => {
    const verify = await verifier();
    for (const path of ['review', 'smoke', 'recoveryArtifactPresent', 'review.privateProofSha256', 'smokeArchive.apiSha256', 'sourceHashes.workflowSha256', 'smoke.cases.0.stderrSha256', 'guardianJob.steps.0.status']) {
      const input = fixture();
      const { owner, key } = location(input, path.split('.'));
      delete owner[key];
      expect(verify(input)).toEqual({ verified: false });
    }
    const input = fixture();
    Object.defineProperty(input, 'extra', { enumerable: true, value: 'untrusted' });
    expect(verify(input)).toEqual({ verified: false });
  });

  it.each(['nativeJob', 'guardianJob'])('requires every real post-job cleanup on %s', async jobName => {
    const verify = await verifier();
    for (const name of cleanupNames) {
      const input = fixture();
      const job = input[jobName as 'nativeJob' | 'guardianJob'];
      const cleanup = job.steps.find(item => item.name === name)!;
      cleanup.conclusion = 'skipped';
      expect(verify(input)).toEqual({ verified: false });
      job.steps = job.steps.filter(item => item.name !== name);
      expect(verify(input)).toEqual({ verified: false });
    }
  });

  it.each([
    ['nativeJob', refusalStep, 'success'], ['nativeJob', 'Retain client-only smoke metadata', 'skipped'],
    ['guardianJob', discoveryStep, 'skipped'], ['guardianJob', 'Run supabase link --project-ref "$PROJECT_REF" --yes', 'success'],
    ['guardianJob', 'Restore and freshly verify only the captured role-global timeout', 'success'],
  ])('requires exact mandatory step verdicts for %s / %s', async (jobName, name, conclusion) => {
    const input = fixture();
    const job = input[jobName as 'nativeJob' | 'guardianJob'];
    job.steps.find(item => item.name === name)!.conclusion = conclusion;
    expect((await verifier())(input)).toEqual({ verified: false });
  });

  it('refuses duplicate mandatory steps, additional failure, and unfinished optional steps', async () => {
    const verify = await verifier();
    for (const damaged of ['duplicate', 'failure', 'unfinished']) {
      const input = fixture();
      input.guardianJob.steps.push(damaged === 'duplicate' ? step('Complete job') : step('Unexpected operation', damaged === 'failure' ? 'failure' : 'skipped'));
      if (damaged === 'unfinished') input.guardianJob.steps.at(-1)!.status = 'in_progress';
      expect(verify(input)).toEqual({ verified: false });
    }
  });

  it.each(['nativeJob.labels', 'guardianJob.steps', 'smoke.reportingLines', 'smoke.cases', 'smoke.cases.0.fileMetadata'])('refuses sparse or decorated arrays at %s', async path => {
    const verify = await verifier();
    for (const damage of ['sparse', 'extra', 'symbol', 'prototype']) {
      const input = fixture();
      const { owner, key } = location(input, path.split('.'));
      const array = owner[key] as unknown[];
      if (damage === 'sparse') delete array[0];
      if (damage === 'extra') Object.defineProperty(array, 'extra', { value: true });
      if (damage === 'symbol') Object.defineProperty(array, Symbol('extra'), { value: true });
      if (damage === 'prototype') Object.setPrototypeOf(array, Object.create(Array.prototype));
      expect(verify(input)).toEqual({ verified: false });
    }
  });

  it('refuses reordered cases, duplicate paths, and extra record keys', async () => {
    const verify = await verifier();
    const reordered = fixture();
    reordered.smoke.cases.reverse();
    expect(verify(reordered)).toEqual({ verified: false });
    const duplicate = fixture();
    duplicate.smoke.cases[0]!.fileMetadata[1]!.path = duplicate.smoke.cases[0]!.fileMetadata[0]!.path;
    expect(verify(duplicate)).toEqual({ verified: false });
    for (const path of ['review', 'sourceHashes', 'nativeJob.steps.0', 'smoke.cases.0', 'smoke.cases.0.fileMetadata.0']) {
      const input = fixture();
      const { owner, key } = location(input, `${path}.extra`.split('.'));
      owner[key] = true;
      expect(verify(input)).toEqual({ verified: false });
    }
  });

  it.each(['review', 'smoke.cases.0', 'smoke.cases.0.fileMetadata.0', 'nativeJob.steps.0'])('refuses custom record prototypes at %s', async path => {
    const input = fixture();
    const { owner, key } = location(input, path.split('.'));
    Object.setPrototypeOf(owner[key] as object, {});
    expect((await verifier())(input)).toEqual({ verified: false });
  });

  it.each(['review', 'review.sourceSha', 'smoke.cases.0', 'smoke.cases.0.fileMetadata.0.path'])('refuses accessors at %s without invoking them', async path => {
    const input = fixture();
    const { owner, key } = location(input, path.split('.'));
    let calls = 0;
    Object.defineProperty(owner, key, { enumerable: true, get: () => { calls += 1; throw new Error('Getter must remain inert.'); } });
    expect((await verifier())(input)).toEqual({ verified: false });
    expect(calls).toBe(0);
  });

  it('refuses non-enumerable keys and symbolic record keys', async () => {
    const verify = await verifier();
    const hidden = fixture();
    Object.defineProperty(hidden.review, 'sourceSha', { enumerable: false });
    expect(verify(hidden)).toEqual({ verified: false });
    const symbolic = fixture();
    Object.defineProperty(symbolic.review, Symbol('authority'), { value: true });
    expect(verify(symbolic)).toEqual({ verified: false });
  });

  it('is total for invalid primitives, hostile reflection and revoked proxies', async () => {
    const verify = await verifier();
    const revoked = Proxy.revocable(fixture(), {});
    revoked.revoke();
    const trap = () => { throw new Error('Reflection refused.'); };
    const inputs: unknown[] = [undefined, null, false, 1, 'review', [], new Date(), () => fixture(), revoked.proxy,
      new Proxy(fixture(), { ownKeys: trap }), new Proxy(fixture(), { getPrototypeOf: trap }), new Proxy(fixture(), { getOwnPropertyDescriptor: trap })];
    for (const input of inputs) expect(verify(input)).toEqual({ verified: false });
  });
});
