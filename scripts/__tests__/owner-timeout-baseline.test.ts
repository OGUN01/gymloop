import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { verifyNativeWorkloadTeardown } from '../pgtap/workload-teardown.mjs';
import { exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock } from '../pgtap/data-record.mjs';

const ownerBaselineFixture = () => {
  const source = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const proof = '670d2d958425bb33d2e458e6218c1b4a53e84fd4978af2c791433871db2eeea2';
  const steps = [
    'Set up job', 'Run actions/checkout@v7', 'Run pnpm/action-setup@v6',
    'Run actions/setup-node@v7', 'Install the frozen owner-baseline adapter dependencies',
    'Run supabase/setup-cli@v3', 'Stage the accepted original workload teardown',
    'Read the existing owner-baseline retention limit',
    'Configure the owner-approved trial19 timeout baseline', 'Retain owner baseline configuration evidence',
    'Post Run supabase/setup-cli@v3', 'Post Run actions/setup-node@v7',
    'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job',
  ].map(name => ({ name, status: 'completed', conclusion: 'success' }));
  const common = {
    formatVersion: 1, authorityKind: 'owner-configured-timeout-baseline',
    targetRunId: '37857261809', targetRunAttempt: '1',
    targetSourceSha: '8072af53493867a093ea128dc306f375d3ca1789',
    targetNativeJobId: '113584968728', targetRunnerId: 39,
    maintenanceRunId: '40000000000', maintenanceRunAttempt: '1', maintenanceSourceSha: source,
    target: { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' },
    configured: { originalPresent: true, originalValue: '2min' },
  };
  const setReceipt = {
    ...common, setterJobId: 90001, before: { originalPresent: false, originalValue: null },
    beforeCapturedAt: '2026-10-09T11:01:00.000Z', requestedAt: '2026-10-09T11:02:00.000Z',
  };
  const baselineReceipt = {
    ...structuredClone(common), setterJobId: 90001, verifierJobId: 90002, setReceiptSha256: '',
    observed: { originalPresent: true, originalValue: '2min' }, verified: true,
    verifiedAt: '2026-10-09T11:04:00.000Z',
  };
  const setterJob = {
    id: 90001, runId: '40000000000', attempt: '1', sourceSha: source,
    name: 'owner-baseline-set', status: 'completed', conclusion: 'success', runnerId: 101,
    runnerName: 'GitHub Actions 101', runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'], steps,
    startedAt: '2026-10-09T11:00:00.000Z', completedAt: '2026-10-09T11:03:00.000Z',
  };
  const verifierJob = {
    ...structuredClone(setterJob), id: 90002, name: 'owner-baseline-verify', runnerId: 102,
    runnerName: 'GitHub Actions 102', startedAt: '2026-10-09T11:03:01.000Z', completedAt: '2026-10-09T11:05:00.000Z',
  };
  verifierJob.steps[8].name = 'Independently verify the owner-approved trial19 timeout baseline';
  verifierJob.steps[9].name = 'Retain independent owner baseline verification evidence';
  const targetRun = {
    id: '37857261809', attempt: '1', sourceSha: common.targetSourceSha,
    repositoryId: 1358473323, repository: 'OGUN01/gymloop', headRepositoryId: 1358473323,
    headRepository: 'OGUN01/gymloop', event: 'push', path: '.github/workflows/db.yml', branch: 'main',
    status: 'completed', conclusion: 'failure', actorLogin: 'historical-actor', triggeringActorLogin: 'historical-actor',
    startedAt: '2026-10-08T20:00:00.000Z', updatedAt: '2026-10-08T22:00:00.000Z',
  };
  const targetNativeJob = {
    id: 113584968728, runId: '37857261809', attempt: '1', sourceSha: common.targetSourceSha,
    name: 'pgtap', status: 'completed', conclusion: 'failure', runnerId: 39,
    runnerName: 'fitcruxx-db-trial19-20261009-8072af534938', runnerGroupName: 'Default',
    labels: ['self-hosted', 'Windows', 'X64', 'fitcruxx-db-win-x64-37857261809-1-8072af534938'],
    steps: [{ name: 'Validate the full native suite with outside-worker recovery custody', status: 'completed', conclusion: 'failure' }],
    startedAt: '2026-10-08T20:01:00.000Z', completedAt: '2026-10-08T21:59:00.000Z',
  };
  const targetGuardianJob = {
    id: 113585808843, runId: '37857261809', attempt: '1', sourceSha: common.targetSourceSha,
    name: 'timeout-guardian', status: 'completed', conclusion: 'failure', runnerId: 103,
    runnerName: 'GitHub Actions 103', runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'],
    steps: [
      { name: 'Find the exact armed receipt, including an earlier attempt of this run', status: 'completed', conclusion: 'failure' },
      { name: 'Run supabase link --project-ref "$PROJECT_REF" --yes', status: 'completed', conclusion: 'skipped' },
      { name: 'Restore and freshly verify only the captured role-global timeout', status: 'completed', conclusion: 'skipped' },
    ],
    startedAt: '2026-10-08T21:59:01.000Z', completedAt: '2026-10-08T22:00:00.000Z',
  };
  const maintenanceRun = {
    ...structuredClone(targetRun), id: '40000000000', sourceSha: source, event: 'workflow_dispatch',
    path: '.github/workflows/native-database-owner-baseline.yml', conclusion: 'success',
    actorLogin: 'OGUN01', triggeringActorLogin: 'OGUN01',
    startedAt: '2026-10-09T10:59:00.000Z', updatedAt: '2026-10-09T11:06:00.000Z',
  };
  const setArchive = {
    id: 901, name: 'native-db-owner-baseline-set-40000000000-1', runId: '40000000000', sourceSha: source,
    repositoryId: 1358473323, headRepositoryId: 1358473323, sizeBytes: 256,
    apiSha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    archiveSha256: 'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
    bodySha256: '', expired: false,
  };
  const baselineArchive = {
    ...structuredClone(setArchive), id: 902, name: 'native-db-owner-baseline-verified-40000000000-1',
    apiSha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
    archiveSha256: 'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
  };
  const review = {
    formatVersion: 1, authorityKind: common.authorityKind, targetRunId: common.targetRunId,
    targetRunAttempt: common.targetRunAttempt, targetSourceSha: common.targetSourceSha,
    targetNativeJobId: common.targetNativeJobId, targetRunnerId: common.targetRunnerId,
    maintenanceRunId: common.maintenanceRunId, maintenanceRunAttempt: common.maintenanceRunAttempt,
    maintenanceSourceSha: source, setterJobId: 90001, verifierJobId: 90002,
    setArtifactId: 901, setArchiveSha256: setArchive.archiveSha256,
    baselineArtifactId: 902, baselineArchiveSha256: baselineArchive.archiveSha256,
    teardownPrivateProofSha256: proof,
    privateProofSha256: 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
    reviewedAt: '2026-10-09T11:10:00.000Z',
  };
  const teardownReview = {
    formatVersion: 1, runId: '37857261809-1', sourceSha: common.targetSourceSha,
    jobId: '113584968728', runnerId: 39, runnerEnvironment: 'self-hosted', privateProofSha256: proof,
    nativeProcessesStopped: true, ownedContainersStopped: true, runnerDeregistered: true,
    verifiedAt: '2026-10-08T23:08:21.333Z',
  };
  const context = {
    targetRun, targetNativeJob, targetGuardianJob,
    targetArtifactNames: ['native-db-schema-37857261809-1', 'native-db-ci-job-37857261809-1', 'native-db-manifest-37857261809-1'],
    maintenanceRun, setterJob, verifierJob, jobListingComplete: true, artifactListingComplete: true,
  };
  const envelope = { review, setArchive, baselineArchive, setReceipt, baselineReceipt, teardownReview };
  const seal = () => {
    setArchive.bodySha256 = createHash('sha256').update(`${JSON.stringify(setReceipt)}\n`).digest('hex');
    baselineReceipt.setReceiptSha256 = setArchive.bodySha256;
    baselineArchive.bodySha256 = createHash('sha256').update(`${JSON.stringify(baselineReceipt)}\n`).digest('hex');
  };
  seal();
  return { context, envelope, seal };
};

describe('DBV-015 configured-state proof', () => {
  it('accepts complete independent official evidence while retaining failed original history', async () => {
    const { verifyOwnerConfiguredTimeoutBaseline } = await import('../pgtap/owner-timeout-baseline.mjs');
    const fixture = ownerBaselineFixture();
    expect(verifyOwnerConfiguredTimeoutBaseline(fixture.context, fixture.envelope)).toBe(true);
    expect(fixture.context.targetRun.conclusion).toBe('failure');
    expect(fixture.context.targetGuardianJob.conclusion).toBe('failure');
    expect(Object.hasOwn(fixture.envelope.baselineReceipt, 'restored')).toBe(false);
  });

  it('accepts canonical null-prototype records and the sole permitted skipped post step', async () => {
    const { verifyOwnerConfiguredTimeoutBaseline } = await import('../pgtap/owner-timeout-baseline.mjs');
    const fixture = ownerBaselineFixture();
    Object.setPrototypeOf(fixture.envelope.review, null);
    Object.setPrototypeOf(fixture.envelope.setReceipt.target, null);
    fixture.context.setterJob.steps[11].conclusion = 'skipped';
    fixture.context.verifierJob.steps[11].conclusion = 'skipped';
    fixture.context.maintenanceRun.startedAt = '2026-10-09T10:59:00Z';
    fixture.context.maintenanceRun.updatedAt = '2026-10-09T11:06:00Z';
    fixture.seal();
    expect(verifyOwnerConfiguredTimeoutBaseline(fixture.context, fixture.envelope)).toBe(true);
  });

  it.each([
    { name: 'another original run', mutate: (f: any) => { f.envelope.review.targetRunId = '37857261810'; } },
    { name: 'another original native job', mutate: (f: any) => { f.envelope.review.targetNativeJobId = '113584968729'; } },
    { name: 'a maintenance rerun', mutate: (f: any) => { f.context.maintenanceRun.attempt = '2'; } },
    { name: 'an unapproved owner', mutate: (f: any) => { f.context.maintenanceRun.triggeringActorLogin = 'someone-else'; } },
    { name: 'a fork identity', mutate: (f: any) => { f.context.maintenanceRun.headRepositoryId = 1358473324; } },
    { name: 'an untrusted event', mutate: (f: any) => { f.context.maintenanceRun.event = 'push'; } },
    { name: 'a different source', mutate: (f: any) => { f.context.maintenanceRun.sourceSha = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; } },
    { name: 'an original history rewritten successful', mutate: (f: any) => { f.context.targetGuardianJob.conclusion = 'success'; } },
    { name: 'missing physical closure', mutate: (f: any) => { f.envelope.teardownReview.runnerDeregistered = false; } },
    { name: 'substituted physical proof', mutate: (f: any) => { f.envelope.teardownReview.privateProofSha256 = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; } },
    { name: 'an incomplete job listing', mutate: (f: any) => { f.context.jobListingComplete = false; } },
    { name: 'an incomplete artifact listing', mutate: (f: any) => { f.context.artifactListingComplete = false; } },
    { name: 'extra original recovery custody', mutate: (f: any) => { f.context.targetArtifactNames.push('native-db-recovery-37857261809-1'); } },
    { name: 'duplicate original artifact custody', mutate: (f: any) => { f.context.targetArtifactNames.push(f.context.targetArtifactNames[0]); } },
    { name: 'an expired artifact', mutate: (f: any) => { f.envelope.baselineArchive.expired = true; } },
    { name: 'a mismatched archive digest', mutate: (f: any) => { f.envelope.setArchive.apiSha256 = f.envelope.baselineArchive.apiSha256; } },
    { name: 'a different artifact identity', mutate: (f: any) => { f.envelope.baselineArchive.id = 903; } },
    { name: 'an unsafe artifact size', mutate: (f: any) => { f.envelope.setArchive.sizeBytes = Number.MAX_SAFE_INTEGER + 1; } },
    { name: 'same worker for set and verification', mutate: (f: any) => { f.context.verifierJob.runnerId = 101; f.context.verifierJob.runnerName = 'GitHub Actions 101'; } },
    { name: 'a non-hosted worker', mutate: (f: any) => { f.context.setterJob.labels = ['self-hosted']; } },
    { name: 'a failed setter', mutate: (f: any) => { f.context.setterJob.conclusion = 'failure'; } },
    { name: 'a skipped effect', mutate: (f: any) => { f.context.setterJob.steps[8].conclusion = 'skipped'; } },
    { name: 'a failed post-job cleanup', mutate: (f: any) => { f.context.verifierJob.steps[12].conclusion = 'failure'; } },
    { name: 'an omitted post-job step', mutate: (f: any) => { f.context.setterJob.steps.splice(11, 1); } },
    { name: 'an extra maintenance step', mutate: (f: any) => { f.context.setterJob.steps.push({ name: 'extra', status: 'completed', conclusion: 'success' }); } },
    { name: 'reordered workflow steps', mutate: (f: any) => { [f.context.setterJob.steps[7], f.context.setterJob.steps[8]] = [f.context.setterJob.steps[8], f.context.setterJob.steps[7]]; } },
    { name: 'a guessed different baseline', mutate: (f: any) => { f.envelope.setReceipt.configured.originalValue = '120s'; } },
    { name: 'a failed fresh observation', mutate: (f: any) => { f.envelope.baselineReceipt.observed.originalValue = '1min'; } },
    { name: 'an unverified observation', mutate: (f: any) => { f.envelope.baselineReceipt.verified = false; } },
    { name: 'an inconsistent absent before value', mutate: (f: any) => { f.envelope.setReceipt.before.originalValue = '2min'; } },
    { name: 'capture after alteration request', mutate: (f: any) => { f.envelope.setReceipt.beforeCapturedAt = '2026-10-09T11:02:01.000Z'; } },
    { name: 'set outside provider execution', mutate: (f: any) => { f.envelope.setReceipt.requestedAt = '2026-10-09T11:03:01.000Z'; } },
    { name: 'verification before setter completion', mutate: (f: any) => { f.envelope.baselineReceipt.verifiedAt = '2026-10-09T11:02:00.000Z'; } },
    { name: 'verification outside its execution', mutate: (f: any) => { f.envelope.baselineReceipt.verifiedAt = '2026-10-09T11:05:01.000Z'; } },
    { name: 'review before official completion', mutate: (f: any) => { f.envelope.review.reviewedAt = '2026-10-09T11:05:00.000Z'; } },
    { name: 'a noncanonical review clock', mutate: (f: any) => { f.envelope.review.reviewedAt = '2026-10-09T11:10:00Z'; } },
    { name: 'restoration claims in a configured-state receipt', mutate: (f: any) => { f.envelope.baselineReceipt.restored = true; } },
    { name: 'alias receipt keys', mutate: (f: any) => { f.envelope.setReceipt.original = f.envelope.setReceipt.before; } },
    { name: 'unsafe positive job identity', mutate: (f: any) => { f.envelope.review.setterJobId = Number.MAX_SAFE_INTEGER + 1; } },
    { name: 'a noncanonical run identity', mutate: (f: any) => { f.envelope.review.maintenanceRunId = '040000000000'; } },
  ])('refuses $name independently of successful-looking surrounding evidence', async ({ mutate }) => {
    const { verifyOwnerConfiguredTimeoutBaseline } = await import('../pgtap/owner-timeout-baseline.mjs');
    const fixture = ownerBaselineFixture();
    mutate(fixture);
    fixture.seal();
    expect(verifyOwnerConfiguredTimeoutBaseline(fixture.context, fixture.envelope)).toBe(false);
  });

  it('checks actual canonical receipt body hashes', async () => {
    const { verifyOwnerConfiguredTimeoutBaseline } = await import('../pgtap/owner-timeout-baseline.mjs');
    const fixture = ownerBaselineFixture();
    fixture.envelope.setReceipt.before = { originalPresent: true, originalValue: '5min' };
    expect(verifyOwnerConfiguredTimeoutBaseline(fixture.context, fixture.envelope)).toBe(false);
  });

  it('refuses getters, sparse arrays and throwing proxies without evaluating evidence effects', async () => {
    const { verifyOwnerConfiguredTimeoutBaseline } = await import('../pgtap/owner-timeout-baseline.mjs');
    const fixture = ownerBaselineFixture();
    let calls = 0;
    Object.defineProperty(fixture.envelope.review, 'privateProofSha256', { enumerable: true, get: () => { calls += 1; return 'b'.repeat(64); } });
    expect(verifyOwnerConfiguredTimeoutBaseline(fixture.context, fixture.envelope)).toBe(false);
    expect(calls).toBe(0);
    const dense = ownerBaselineFixture();
    delete dense.context.setterJob.steps[3];
    expect(verifyOwnerConfiguredTimeoutBaseline(dense.context, dense.envelope)).toBe(false);
    const proxy = new Proxy({}, { getPrototypeOf: () => { throw new Error('synthetic denial'); } });
    expect(verifyOwnerConfiguredTimeoutBaseline(proxy, dense.envelope)).toBe(false);
  });
});

const ownerBaselineLoadBoundary = () => {
  const workflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const start = workflow.indexOf('async function readOwnerTimeoutBaseline(');
  expect(start).toBeGreaterThanOrEqual(0);
  const parsed = ts.createSourceFile('loader.js', workflow.slice(start), ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const declaration = parsed.statements.find(statement => ts.isFunctionDeclaration(statement) && statement.name?.text === 'readOwnerTimeoutBaseline');
  expect(declaration).toBeDefined();
  return { workflow, loader: declaration!.getText(parsed) };
};

const ownerBaselineAdapterFixture = async (command = 'owner-baseline-set') => {
  const fixture = ownerBaselineFixture();
  const constants = await import('../../packages/shared/src/config/constants');
  const source = readFileSync(new URL('../native-database-validation.mjs', import.meta.url), 'utf8');
  const parsed = ts.createSourceFile('adapter.js', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const declarations = ['configureOwnerTimeoutBaseline', 'options'].map(name => {
    const declaration = parsed.statements.find(statement => ts.isFunctionDeclaration(statement) && statement.name?.text === name);
    expect(declaration, 'declared owner boundary must exist').toBeDefined();
    return declaration!.getText(parsed);
  });
  const events: Array<{ kind: string; args: any[] }> = [];
  const runtime = {
    GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: 'OGUN01/gymloop', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/main', GITHUB_SHA: fixture.context.maintenanceRun.sourceSha,
    GITHUB_RUN_ID: '40000000000', GITHUB_RUN_ATTEMPT: '1',
    GITHUB_WORKFLOW_REF: 'OGUN01/gymloop/.github/workflows/native-database-owner-baseline.yml@refs/heads/main',
    GITHUB_JOB: command === 'owner-baseline-set' ? 'owner-baseline-set' : 'owner-baseline-verify',
    GITHUB_API_URL: 'https://api.github.com', GITHUB_TOKEN: 'synthetic-token-never-used',
    RUNNER_ENVIRONMENT: 'github-hosted', RUNNER_OS: 'Linux', RUNNER_TEMP: '/synthetic/temp',
    RUNNER_WORKSPACE: '/synthetic', GITHUB_WORKSPACE: '/synthetic/work',
  };
  const opts = {
    command, '--receipt': `/synthetic/private/${command === 'owner-baseline-set' ? 'owner-baseline-set.json' : 'owner-baseline-verified.json'}`,
    '--out-dir': '/synthetic/private', '--source-sha': runtime.GITHUB_SHA,
    '--approval': 'trial19-owner-baseline-2026-10-09', '--teardown-file': '/synthetic/teardown.json',
  };
  const rawJob = (job: any) => ({
    id: job.id, run_id: Number(job.runId), run_attempt: Number(job.attempt), head_sha: job.sourceSha,
    name: job.name, status: job.status, conclusion: job.conclusion, runner_id: job.runnerId,
    runner_name: job.runnerName, runner_group_name: job.runnerGroupName, labels: job.labels,
    steps: job.steps, started_at: job.startedAt, completed_at: job.completedAt,
  });
  const rawRun = (run: any) => ({
    id: Number(run.id), run_attempt: Number(run.attempt), head_sha: run.sourceSha, event: run.event,
    head_branch: run.branch, status: run.status, conclusion: run.conclusion, path: run.path,
    repository: { id: run.repositoryId, full_name: run.repository, owner: { login: 'OGUN01' } },
    head_repository: { id: run.headRepositoryId, full_name: run.headRepository },
    actor: { login: run.actorLogin }, triggering_actor: { login: run.triggeringActorLogin },
    run_started_at: run.startedAt, updated_at: run.updatedAt,
  });
  const rawArtifact = (archive: any) => ({
    id: archive.id, name: archive.name, expired: archive.expired, size_in_bytes: archive.sizeBytes,
    digest: `sha256:${archive.apiSha256}`, workflow_run: {
      id: Number(archive.runId), head_sha: archive.sourceSha,
      repository_id: archive.repositoryId, head_repository_id: archive.headRepositoryId,
    },
  });
  const currentRun: any = rawRun(fixture.context.maintenanceRun);
  currentRun.status = 'in_progress';
  currentRun.conclusion = null;
  const targetRun = rawRun(fixture.context.targetRun);
  const targetJobs = [rawJob(fixture.context.targetNativeJob), rawJob(fixture.context.targetGuardianJob)];
  const targetArtifacts = fixture.context.targetArtifactNames.map((name, index) => ({
    id: 1000 + index, name, expired: false, size_in_bytes: 256,
    digest: `sha256:${'c'.repeat(64)}`, workflow_run: {
      id: 37857261809, head_sha: fixture.context.targetRun.sourceSha, repository_id: 1358473323, head_repository_id: 1358473323,
    },
  }));
  const currentJobs = [rawJob(fixture.context.setterJob), rawJob(fixture.context.verifierJob)];
  const currentArtifacts = [rawArtifact(fixture.envelope.setArchive)];
  const workflowRuns = [currentRun];
  const teardown = [fixture.envelope.teardownReview];
  const controls: any = { before: { originalPresent: false, originalValue: null }, observed: { originalPresent: true, originalValue: '2min' }, writeFails: false, alterFails: false, source: runtime.GITHUB_SHA, cli: '2.110.0', linkedRef: 'pecxrpskmfeuyzngvewq', apiMutation: null };
  const sandbox: any = {
    Buffer, URL, console: { log() {}, error() {} },
    NATIVE_DB_VALIDATION: constants.NATIVE_DB_VALIDATION,
    NATIVE_DB_OWNER_BASELINE: (constants as any).NATIVE_DB_OWNER_BASELINE,
    target: { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' },
    exact: (value: any, keys: string[]) => value !== null && typeof value === 'object' && !Array.isArray(value)
      && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key)),
    validOriginal: (value: any) => value !== null && typeof value === 'object'
      && Object.keys(value).length === 2 && typeof value.originalPresent === 'boolean'
      && (value.originalPresent ? typeof value.originalValue === 'string' && value.originalValue.length > 0 : value.originalValue === null),
    sourceString: (value: any) => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value),
    sameTimeout: (left: any, right: any) => left.originalPresent === right.originalPresent && left.originalValue === right.originalValue,
    hash: (bytes: any) => createHash('sha256').update(bytes).digest('hex'),
    jsonBytes: (value: any) => Buffer.from(`${JSON.stringify(value)}\n`),
    refuse: (code: string) => new Error(code), verifyNativeWorkloadTeardown, exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock,
    checked: async (...args: any[]) => {
      events.push({ kind: 'checked', args });
      if (args[0] === 'git') return `${controls.source}\n`;
      if (args[1]?.includes('--version')) return `${controls.cli}\n`;
      return '';
    },
    artifactApi: async (_runtime: any, path: string, status: number) => {
      expect(status).toBe(200);
      events.push({ kind: 'api', args: [path] });
      const canonical = path.replace(/^\//, '');
      let body: any;
      if (canonical === 'actions/runs/37857261809/attempts/1') body = targetRun;
      else if (canonical === 'actions/runs/40000000000/attempts/1') body = currentRun;
      else if (/^actions\/runs\/37857261809\/attempts\/1\/jobs\?page=\d+$/.test(canonical)) body = { total_count: targetJobs.length, jobs: canonical.endsWith('page=1') ? targetJobs : [] };
      else if (/^actions\/runs\/40000000000\/attempts\/1\/jobs\?page=\d+$/.test(canonical)) body = { total_count: currentJobs.length, jobs: canonical.endsWith('page=1') ? currentJobs : [] };
      else if (/^actions\/runs\/37857261809\/artifacts\?page=\d+$/.test(canonical)) body = { total_count: targetArtifacts.length, artifacts: canonical.endsWith('page=1') ? targetArtifacts : [] };
      else if (/^actions\/runs\/40000000000\/artifacts\?page=\d+$/.test(canonical)) body = { total_count: currentArtifacts.length, artifacts: canonical.endsWith('page=1') ? currentArtifacts : [] };
      else if (/^actions\/workflows\/native-database-owner-baseline\.yml\/runs\?page=\d+$/.test(canonical)) body = { total_count: workflowRuns.length, workflow_runs: canonical.endsWith('page=1') ? workflowRuns : [] };
      else throw new Error('undeclared synthetic API path');
      if (controls.apiMutation) body = controls.apiMutation(canonical, structuredClone(body));
      return new Response(JSON.stringify(body));
    },
    boundedResponseBytes: async (response: Response, maximum: number) => {
      expect(maximum).toBeLessThanOrEqual(65536);
      return Buffer.from(await response.arrayBuffer());
    },
    readFile: async (path: string, encoding?: string) => {
      events.push({ kind: 'read', args: [path] });
      const text = path.endsWith('project-ref') ? `${controls.linkedRef}\n` : `${JSON.stringify(teardown)}\n`;
      return encoding === 'utf8' ? text : Buffer.from(text);
    },
    privateWrite: async (...args: any[]) => {
      events.push({ kind: 'write', args });
      if (controls.writeFails) throw new Error('synthetic exclusive custody failure');
    },
    queryTimeout: async (...args: any[]) => {
      events.push({ kind: 'query', args });
      return structuredClone(command === 'owner-baseline-set' ? controls.before : controls.observed);
    },
    alterTimeout: async (...args: any[]) => {
      events.push({ kind: 'alter', args });
      if (controls.alterFails) throw new Error('synthetic alteration failure');
    },
    readReceiptArtifact: async (...args: any[]) => {
      events.push({ kind: 'download', args });
      return { value: fixture.envelope.setReceipt, hash: fixture.envelope.setArchive.bodySha256, archiveSha256: fixture.envelope.setArchive.archiveSha256 };
    },
  };
  const boundary: any = vm.compileFunction(`${declarations.join('\n')}\nreturn ({ configureOwnerTimeoutBaseline, options });`, [], { contextExtensions: [sandbox] })();
  return { ...fixture, runtime, opts, events, controls, targetRun, currentRun, targetJobs, targetArtifacts, currentJobs, currentArtifacts, workflowRuns, teardown, boundary,
    invoke: () => boundary.configureOwnerTimeoutBaseline(runtime, opts, '/synthetic/private', '/synthetic/work') };
};

describe('DBV-015 controlled adapter admission and custody', () => {
  it('captures canonical private intent before exactly one fixed configuration effect', async () => {
    const fixture = await ownerBaselineAdapterFixture();
    await expect(fixture.invoke()).resolves.toBeUndefined();
    const kinds = fixture.events.map(event => event.kind);
    expect(kinds.filter(kind => kind === 'query')).toHaveLength(1);
    expect(kinds.filter(kind => kind === 'alter')).toHaveLength(1);
    expect(kinds.indexOf('query')).toBeLessThan(kinds.indexOf('write'));
    expect(kinds.indexOf('write')).toBeLessThan(kinds.indexOf('alter'));
    const alteration = fixture.events.find(event => event.kind === 'alter')!;
    expect(alteration.args).toEqual(['/synthetic/work', '/synthetic/private', {
      target: { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' },
      setting: { originalPresent: true, originalValue: '2min' },
    }]);
    const write = fixture.events.find(event => event.kind === 'write')!;
    expect(write.args[0]).toBe(fixture.opts['--receipt']);
    expect(write.args[1].toString()).toBe(`${JSON.stringify(JSON.parse(write.args[1].toString()))}\n`);
    const receipt = JSON.parse(write.args[1].toString());
    expect(receipt.before).toEqual({ originalPresent: false, originalValue: null });
    expect(receipt.authorityKind).toBe('owner-configured-timeout-baseline');
    expect(Object.hasOwn(receipt, 'restored')).toBe(false);
    const link = fixture.events.find(event => event.kind === 'checked' && event.args[1]?.[0] === 'link')!;
    expect(link.args[1]).toEqual(['link', '--project-ref', 'pecxrpskmfeuyzngvewq', '--yes']);
    expect(link.args[2]).toMatchObject({ cwd: '/synthetic/work' });
    expect(JSON.stringify(link.args[2])).toContain('60000');
  });

  it.each([
    { name: 'non-Actions execution', mutate: (f: any) => { f.runtime.GITHUB_ACTIONS = 'false'; } },
    { name: 'non-hosted execution', mutate: (f: any) => { f.runtime.RUNNER_ENVIRONMENT = 'self-hosted'; } },
    { name: 'wrong command job', mutate: (f: any) => { f.runtime.GITHUB_JOB = 'owner-baseline-verify'; } },
    { name: 'missing owner approval', mutate: (f: any) => { f.opts['--approval'] = ''; } },
    { name: 'a rerun', mutate: (f: any) => { f.runtime.GITHUB_RUN_ATTEMPT = '2'; } },
    { name: 'source disagreement', mutate: (f: any) => { f.controls.source = 'eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'; } },
    { name: 'wrong pinned CLI', mutate: (f: any) => { f.controls.cli = '2.109.0'; } },
    { name: 'wrong authenticated dispatch owner', mutate: (f: any) => { f.currentRun.actor.login = 'someone-else'; } },
    { name: 'failed original physical closure', mutate: (f: any) => { f.teardown[0].ownedContainersStopped = false; } },
    { name: 'duplicate physical receipt', mutate: (f: any) => { f.teardown.push(structuredClone(f.teardown[0])); } },
    { name: 'conflicting original recovery custody', mutate: (f: any) => { f.targetArtifacts.push({ ...f.targetArtifacts[0], id: 2000, name: 'native-db-recovery-37857261809-1' }); } },
    { name: 'a prior main owner dispatch', mutate: (f: any) => { f.workflowRuns.push({ ...structuredClone(f.currentRun), id: 39999999999, status: 'completed', conclusion: 'failure' }); } },
    { name: 'prematurely empty exhaustive job page', mutate: (f: any) => { f.controls.apiMutation = (path: string, body: any) => path.includes('/37857261809/attempts/1/jobs?') ? { total_count: 3, jobs: body.jobs } : body; } },
  ])('refuses $name before project link, query or alteration', async ({ mutate }) => {
    const fixture = await ownerBaselineAdapterFixture();
    mutate(fixture);
    await expect(fixture.invoke()).rejects.toBeInstanceOf(Error);
    expect(fixture.events.filter(event => ['query', 'alter', 'write'].includes(event.kind))).toHaveLength(0);
    expect(fixture.events.filter(event => event.kind === 'checked' && event.args[1]?.[0] === 'link')).toHaveLength(0);
  });

  it('refuses exclusive receipt failure without altering and retains one failed alteration intent without replay', async () => {
    const denied = await ownerBaselineAdapterFixture();
    denied.controls.writeFails = true;
    await expect(denied.invoke()).rejects.toBeInstanceOf(Error);
    expect(denied.events.filter(event => event.kind === 'alter')).toHaveLength(0);
    const failed = await ownerBaselineAdapterFixture();
    failed.controls.alterFails = true;
    await expect(failed.invoke()).rejects.toBeInstanceOf(Error);
    expect(failed.events.filter(event => event.kind === 'write')).toHaveLength(1);
    expect(failed.events.filter(event => event.kind === 'alter')).toHaveLength(1);
  });

  it('independently downloads successful setter evidence before a fresh read and never calls alteration', async () => {
    const fixture = await ownerBaselineAdapterFixture('owner-baseline-verify');
    await expect(fixture.invoke()).resolves.toBeUndefined();
    const kinds = fixture.events.map(event => event.kind);
    expect(kinds.filter(kind => kind === 'query')).toHaveLength(1);
    expect(kinds.filter(kind => kind === 'alter')).toHaveLength(0);
    expect(kinds.indexOf('download')).toBeLessThan(kinds.indexOf('query'));
    const write = fixture.events.find(event => event.kind === 'write')!;
    const receipt = JSON.parse(write.args[1].toString());
    expect(receipt.observed).toEqual({ originalPresent: true, originalValue: '2min' });
    expect(receipt.verified).toBe(true);
    expect(receipt.setReceiptSha256).toBe(fixture.envelope.setArchive.bodySha256);
  });

  it('retains the block when the independent observed setting differs', async () => {
    const fixture = await ownerBaselineAdapterFixture('owner-baseline-verify');
    fixture.controls.observed.originalValue = '1min';
    await expect(fixture.invoke()).rejects.toBeInstanceOf(Error);
    expect(fixture.events.filter(event => event.kind === 'alter' || event.kind === 'write')).toHaveLength(0);
  });

  it('admits only the two exact explicit owner flag records and rejects duplicates or cross-command flags', async () => {
    const fixture = await ownerBaselineAdapterFixture();
    const flags = ['--receipt', '/synthetic/private/owner-baseline-set.json', '--out-dir', '/synthetic/private',
      '--source-sha', fixture.runtime.GITHUB_SHA, '--approval', 'trial19-owner-baseline-2026-10-09', '--teardown-file', '/synthetic/teardown.json'];
    for (const command of ['owner-baseline-set', 'owner-baseline-verify']) {
      expect(fixture.boundary.options([command, ...flags], fixture.runtime)).toMatchObject({ command, '--approval': 'trial19-owner-baseline-2026-10-09' });
      for (const extra of [['--manifest', '/synthetic/manifest.json'], ['--approval', 'trial19-owner-baseline-2026-10-09'], ['--unknown', 'x'], ['--target-run', '37857261809']]) {
        expect(() => fixture.boundary.options([command, ...flags, ...extra], fixture.runtime)).toThrow();
      }
      expect(() => fixture.boundary.options([command, ...flags.slice(0, -2)], fixture.runtime)).toThrow();
    }
    expect(() => fixture.boundary.options(['prepare', '--manifest', '/synthetic/manifest.json', '--out-dir', '/synthetic/private', '--approval', 'trial19-owner-baseline-2026-10-09'], fixture.runtime)).toThrow();
  });
});

describe('DBV-015 fixed maintenance workflow and preflight boundary', () => {
  it('has only dispatch input, exact serialization, two separately hosted ordered jobs and bounded pinned setup', () => {
    const workflow = readFileSync(new URL('../../.github/workflows/native-database-owner-baseline.yml', import.meta.url), 'utf8');
    expect(workflow).toMatch(/^name: Native database owner timeout baseline\s*$/m);
    expect(workflow).toMatch(/workflow_dispatch:/);
    expect(workflow).not.toMatch(/^\s+(?:push|pull_request|schedule|workflow_call):/m);
    expect(workflow).toMatch(/approval:[\s\S]*?required: true[\s\S]*?type: string/);
    expect(workflow).toContain('trial19-owner-baseline-2026-10-09');
    expect(workflow).toContain('db-${{ github.ref }}');
    expect(workflow).toMatch(/cancel-in-progress: false/);
    expect(workflow).toMatch(/contents: read/);
    expect(workflow).toMatch(/actions: read/);
    expect(workflow).toContain("github.repository == 'OGUN01/gymloop'");
    expect(workflow).toContain("github.ref == 'refs/heads/main'");
    const names = [...workflow.matchAll(/^  ([a-z][a-z-]+):\s*$/gm)].map(match => match[1]);
    expect(names.filter(name => name.startsWith('owner-baseline-'))).toEqual(['owner-baseline-set', 'owner-baseline-verify']);
    expect(workflow).toMatch(/owner-baseline-verify:[\s\S]*?needs: owner-baseline-set/);
    expect(workflow.match(/runs-on: ubuntu-latest/g)).toHaveLength(2);
    for (const action of ['actions/checkout@v7', 'pnpm/action-setup@v6', 'actions/setup-node@v7', 'supabase/setup-cli@v3']) {
      expect(workflow.match(new RegExp(`uses: ${action.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}`, 'g'))).toHaveLength(2);
    }
    expect(workflow.match(/node-version: ['"]?24['"]?/g)).toHaveLength(2);
    expect(workflow.match(/version: ['"]?2\.110\.0['"]?/g)).toHaveLength(2);
    expect(workflow.match(/--ignore-scripts/g)).toHaveLength(2);
    expect(workflow.match(/--frozen-lockfile/g)).toHaveLength(2);
    expect(workflow).not.toMatch(/--manifest|--target-|workflow_run|continue-on-error: true/);
  });

  it('retains distinct fixed artifacts and invokes only explicit bounded owner command arguments', () => {
    const workflow = readFileSync(new URL('../../.github/workflows/native-database-owner-baseline.yml', import.meta.url), 'utf8');
    expect(workflow.match(/uses: actions\/upload-artifact@v5/g)).toHaveLength(2);
    expect(workflow.match(/if-no-files-found: error/g)).toHaveLength(2);
    expect(workflow).not.toMatch(/overwrite: true/);
    expect(workflow).toContain('native-db-owner-baseline-set-');
    expect(workflow).toContain('native-db-owner-baseline-verified-');
    expect(workflow).toContain('owner-baseline-set.json');
    expect(workflow).toContain('owner-baseline-verified.json');
    expect(workflow).toMatch(/Retain owner baseline configuration evidence[\s\S]*?if:.*always\(\)/);
    for (const flag of ['--receipt', '--out-dir', '--source-sha', '--approval', '--teardown-file']) {
      expect(workflow.match(new RegExp(flag, 'g'))).toHaveLength(2);
    }
    expect(workflow.match(/NATIVE_DB_WORKLOAD_TEARDOWN_RECEIPTS/g)).toHaveLength(2);
    expect(workflow).toContain('Configure the owner-approved trial19 timeout baseline');
    expect(workflow).toContain('Independently verify the owner-approved trial19 timeout baseline');
    expect(workflow.match(/name: Install the frozen owner-baseline adapter dependencies/g)).toHaveLength(2);
    expect(workflow.match(/name: Stage the accepted original workload teardown/g)).toHaveLength(2);
    expect(workflow.match(/name: Read the existing owner-baseline retention limit/g)).toHaveLength(2);
  });

  it('stages outside owner review and consumes the named pure verifier at the narrow loader', () => {
    const { workflow, loader } = ownerBaselineLoadBoundary();
    expect(workflow).toContain("NATIVE_DB_OWNER_BASELINE_RECEIPTS || '[]'");
    expect(workflow).toContain('.dbv/operator-owner-baselines.json');
    expect(loader).toContain('verifyOwnerConfiguredTimeoutBaseline');
    expect(loader).toContain('ownerBaselineReviews');
    expect(loader).toContain('operatorReceipts');
    expect(loader).toContain('readArtifact');
    expect(loader).toContain('setArtifactId');
    expect(loader).toContain('baselineArtifactId');
    expect(loader).toContain('jobListingComplete');
    expect(loader).toContain('artifactListingComplete');
    expect(loader).not.toMatch(/supabase|alterTimeout|process\.env|return true;[\s\S]*?verifyOwnerConfiguredTimeoutBaseline/);
    expect(workflow).toContain('verifiedOwnerBaselines');
    expect(workflow).toContain('scripts/pgtap/owner-timeout-baseline.mjs');
    expect(workflow).toContain('native-database-owner-baseline.yml');
  });
});
