import { createHash } from 'node:crypto';
import { readFileSync as ownerHeldNativeReadFileSync } from 'node:fs';
import { join } from 'node:path';
import { runInThisContext } from 'node:vm';
import { describe, expect, it } from 'vitest';
import { exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock } from '../../scripts/pgtap/data-record.mjs';
import { verifyNativeWorkloadTeardown } from '../../scripts/pgtap/workload-teardown.mjs';

const ownerHeldHash = (value: unknown) => createHash('sha256').update(`${JSON.stringify(value)}\n`).digest('hex');
const ownerHeldStepNames = [
  'Set up job', 'Run actions/checkout@v7', 'Run pnpm/action-setup@v6', 'Run actions/setup-node@v7',
  'Install the frozen owner-baseline adapter dependencies', 'Run supabase/setup-cli@v3',
  'Stage the accepted original workload teardown', 'Read the existing owner-baseline retention limit',
  '', '', 'Post Run supabase/setup-cli@v3', 'Post Run actions/setup-node@v7',
  'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job',
];

const ownerHeldFixture = () => {
  const targetSourceSha = '8072af53493867a093ea128dc306f375d3ca1789';
  const maintenanceSourceSha = 'd'.repeat(40);
  const target = { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' };
  const configured = { originalPresent: true, originalValue: '2min' };
  const run = {
    id: '47857261809', attempt: '1', sourceSha: maintenanceSourceSha,
    repositoryId: 1358473323, repository: 'OGUN01/gymloop', headRepositoryId: 1358473323,
    headRepository: 'OGUN01/gymloop', event: 'workflow_dispatch',
    path: '.github/workflows/native-database-owner-baseline.yml', branch: 'main',
    status: 'completed', conclusion: 'success', actorLogin: 'OGUN01', triggeringActorLogin: 'OGUN01',
    startedAt: '2026-10-09T12:00:00Z', updatedAt: '2026-10-09T12:04:00Z',
  };
  const job = {
    id: 223584968728, runId: run.id, attempt: run.attempt, sourceSha: maintenanceSourceSha,
    name: 'owner-baseline-set', status: 'completed', conclusion: 'success', runnerId: 51,
    runnerName: 'GitHub Actions 51', runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'],
    steps: ownerHeldStepNames.map((name, index) => ({
      name: index === 8 ? 'Configure the owner-approved trial19 timeout baseline'
        : index === 9 ? 'Retain owner baseline configuration evidence' : name,
      status: 'completed', conclusion: index === 11 ? 'skipped' : 'success',
    })),
    startedAt: '2026-10-09T12:00:00Z', completedAt: '2026-10-09T12:01:00Z',
  };
  const verifierJob = {
    ...job, id: 223585808843, name: 'owner-baseline-verify', runnerId: 52,
    runnerName: 'GitHub Actions 52',
    steps: ownerHeldStepNames.map((name, index) => ({
      name: index === 8 ? 'Independently verify the owner-approved trial19 timeout baseline'
        : index === 9 ? 'Retain independent owner baseline verification evidence' : name,
      status: 'completed', conclusion: 'success',
    })),
    startedAt: '2026-10-09T12:02:00Z', completedAt: '2026-10-09T12:03:00Z',
  };
  const common = {
    formatVersion: 1, authorityKind: 'owner-configured-timeout-baseline',
    targetRunId: '37857261809', targetRunAttempt: '1', targetSourceSha,
    targetNativeJobId: '113584968728', targetRunnerId: 39,
    maintenanceRunId: run.id, maintenanceRunAttempt: run.attempt, maintenanceSourceSha, target, configured,
  };
  const setReceipt = {
    ...common, setterJobId: job.id, before: { originalPresent: false, originalValue: null },
    beforeCapturedAt: '2026-10-09T12:00:10.000Z', requestedAt: '2026-10-09T12:00:11.000Z',
  };
  const baselineReceipt = {
    ...common, setterJobId: job.id, verifierJobId: verifierJob.id,
    setReceiptSha256: ownerHeldHash(setReceipt), observed: { ...configured }, verified: true,
    verifiedAt: '2026-10-09T12:02:30.000Z',
  };
  const setArchive = {
    id: 6135849687, name: `native-db-owner-baseline-set-${run.id}-1`,
    runId: run.id, sourceSha: maintenanceSourceSha, repositoryId: 1358473323, headRepositoryId: 1358473323,
    sizeBytes: 1400, apiSha256: 'a'.repeat(64), archiveSha256: 'a'.repeat(64),
    bodySha256: ownerHeldHash(setReceipt), expired: false,
  };
  const baselineArchive = {
    ...setArchive, id: 6135858088, name: `native-db-owner-baseline-verified-${run.id}-1`,
    sizeBytes: 1500, apiSha256: 'b'.repeat(64), archiveSha256: 'b'.repeat(64),
    bodySha256: ownerHeldHash(baselineReceipt),
  };
  const teardownReview = {
    formatVersion: 1, runId: '37857261809-1', sourceSha: targetSourceSha, jobId: '113584968728',
    runnerId: 39, runnerEnvironment: 'self-hosted',
    privateProofSha256: '670d2d958425bb33d2e458e6218c1b4a53e84fd4978af2c791433871db2eeea2',
    nativeProcessesStopped: true, ownedContainersStopped: true, runnerDeregistered: true,
    verifiedAt: '2026-10-08T23:08:21.333Z',
  };
  const review = {
    formatVersion: 1, authorityKind: common.authorityKind,
    targetRunId: common.targetRunId, targetRunAttempt: common.targetRunAttempt,
    targetSourceSha, targetNativeJobId: common.targetNativeJobId, targetRunnerId: 39,
    maintenanceRunId: run.id, maintenanceRunAttempt: run.attempt, maintenanceSourceSha,
    setterJobId: job.id, verifierJobId: verifierJob.id,
    setArtifactId: setArchive.id, setArchiveSha256: setArchive.archiveSha256,
    baselineArtifactId: baselineArchive.id, baselineArchiveSha256: baselineArchive.archiveSha256,
    teardownPrivateProofSha256: teardownReview.privateProofSha256, privateProofSha256: 'c'.repeat(64),
    reviewedAt: '2026-10-09T12:05:00.000Z',
  };
  const targetRun = {
    ...run, id: common.targetRunId, sourceSha: targetSourceSha, event: 'push',
    path: '.github/workflows/db.yml', conclusion: 'failure',
    actorLogin: 'prior-public-owner', triggeringActorLogin: 'prior-public-owner',
    startedAt: '2026-10-08T10:00:00Z', updatedAt: '2026-10-08T12:00:00Z',
  };
  const targetNativeJob = {
    ...job, id: 113584968728, runId: common.targetRunId, sourceSha: targetSourceSha, name: 'pgtap',
    conclusion: 'failure', runnerId: 39, runnerName: 'fitcruxx-db-trial19-20261009-8072af534938',
    runnerGroupName: 'Default',
    labels: ['self-hosted', 'Windows', 'X64', 'fitcruxx-db-win-x64-37857261809-1-8072af534938'],
    steps: [{ name: 'Validate the full native suite with outside-worker recovery custody', status: 'completed', conclusion: 'failure' }],
    startedAt: '2026-10-08T10:00:00Z', completedAt: '2026-10-08T11:00:00Z',
  };
  const targetGuardianJob = {
    ...job, id: 113585808843, runId: common.targetRunId, sourceSha: targetSourceSha,
    name: 'timeout-guardian', conclusion: 'failure',
    steps: [
      { name: 'Find the exact armed receipt, including an earlier attempt of this run', status: 'completed', conclusion: 'failure' },
      { name: 'Run supabase link --project-ref "$PROJECT_REF" --yes', status: 'completed', conclusion: 'skipped' },
      { name: 'Restore and freshly verify only the captured role-global timeout', status: 'completed', conclusion: 'skipped' },
    ],
    startedAt: '2026-10-08T11:01:00Z', completedAt: '2026-10-08T12:00:00Z',
  };
  return {
    context: { targetRun, targetNativeJob, targetGuardianJob,
      targetArtifactNames: ['native-db-schema-37857261809-1', 'native-db-ci-job-37857261809-1', 'native-db-manifest-37857261809-1'],
      maintenanceRun: run, setterJob: job, verifierJob, jobListingComplete: true, artifactListingComplete: true },
    envelope: { review, setArchive, baselineArchive, setReceipt, baselineReceipt, teardownReview },
  };
};

const readFileSync = ((...args: Parameters<typeof ownerHeldNativeReadFileSync>) => {
  const original = ownerHeldNativeReadFileSync(...args);
  const workflowPath = new URL('../../.github/workflows/native-database-owner-baseline.yml', import.meta.url);
  if (typeof original !== 'string' || String(args[0]) !== String(workflowPath)) return original;
  const declaration = ownerHeldConstants.NATIVE_DB_OWNER_BASELINE;
  const jobsStart = original.match(/^jobs:[ \t]*\r?$/m);
  if (!jobsStart || [...original.matchAll(/^jobs:[ \t]*\r?$/gm)].length !== 1) throw new Error('workflow observation refuses');
  const beforeJobs = original.slice(0, jobsStart.index);
  const globalEnv = [...beforeJobs.matchAll(/^env:[ \t]*\r?\n((?:[ \t]+[^\r\n]*(?:\r?\n|$))*)/gm)];
  if (globalEnv.length > 1) throw new Error('workflow observation refuses');
  const globalBindings = [...(globalEnv[0]?.[1] ?? '').matchAll(/^ {2}BASELINE_DIRECTORY:[ \t]*([^\r\n]*)\r?$/gm)];
  if (globalBindings.length > 1) throw new Error('workflow observation refuses');
  const jobsText = original.slice(jobsStart.index);
  const jobs = [...jobsText.matchAll(/^ {2}([A-Za-z][A-Za-z0-9_-]*):[ \t]*\r?$/gm)];
  if (jobs.length !== 2 || new Set(jobs.map(job => job[1])).size !== jobs.length
    || !jobs.every(job => [declaration.setJob, declaration.verifyJob].includes(job[1]))) throw new Error('workflow observation refuses');
  let observed = original;
  for (const [index, job] of jobs.entries()) {
    const body = jobsText.slice(job.index, jobs[index + 1]?.index ?? jobsText.length);
    const envs = [...body.matchAll(/^ {4}env:[ \t]*\r?\n((?:[ \t]{6,}[^\r\n]*(?:\r?\n|$))*)/gm)];
    if (envs.length > 1) throw new Error('workflow observation refuses');
    const bindings = [...(envs[0]?.[1] ?? '').matchAll(/^ {6}BASELINE_DIRECTORY:[ \t]*([^\r\n]*)\r?$/gm)];
    if (bindings.length > 1) throw new Error('workflow observation refuses');
    const lines = body.split(/\r?\n/);
    const commandIndexes = lines.flatMap((line, lineIndex) => new RegExp(`^[ \\t]+node[ \\t]+scripts/native-database-validation\\.mjs[ \\t]+${job[1]}(?:[ \\t]|$)`).test(line) ? [lineIndex] : []);
    if (commandIndexes.length !== 1) throw new Error('workflow observation refuses');
    const first = commandIndexes[0];
    let commandStepStart = first;
    while (commandStepStart >= 0 && !/^ {6}- /.test(lines[commandStepStart])) commandStepStart--;
    if (commandStepStart < 0) throw new Error('workflow observation refuses');
    let commandStepEnd = commandStepStart + 1;
    while (commandStepEnd < lines.length && !/^ {6}- /.test(lines[commandStepEnd])) commandStepEnd++;
    const commandStep = lines.slice(commandStepStart, commandStepEnd).join('\n');
    const stepEnvs = [...commandStep.matchAll(/^ {8}env:[ \t]*\r?\n((?:[ \t]{10,}[^\r\n]*(?:\r?\n|$))*)/gm)];
    const stepBindings = [...(stepEnvs[0]?.[1] ?? '').matchAll(/^ {10}BASELINE_DIRECTORY:[ \t]*([^\r\n]*)\r?$/gm)];
    if (stepEnvs.length > 1 || stepBindings.length > 1 || stepBindings.length + bindings.length + globalBindings.length !== 1) throw new Error('workflow observation refuses');
    const rawBinding = stepBindings[0]?.[1] ?? bindings[0]?.[1] ?? globalBindings[0]?.[1];
    if (typeof rawBinding !== 'string') throw new Error('workflow observation refuses');
    let binding = rawBinding.trim();
    if (binding.startsWith('"') && binding.endsWith('"')) {
      try { binding = JSON.parse(binding); } catch { throw new Error('workflow observation refuses'); }
    } else if (binding.startsWith("'") && binding.endsWith("'")) binding = binding.slice(1, -1).replaceAll("''", "'");
    if (typeof binding !== 'string' || !/^\$\{\{\s*runner\.temp\s*\}\}(?:\/(?:[A-Za-z0-9._-]|\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\})+)*$/.test(binding)
      || binding.split('/').slice(1).some(part => part === '.' || part === '..')) throw new Error('workflow observation refuses');
    const directory = binding.replace(/\$\{\{\s*runner\.temp\s*\}\}/g, '$RUNNER_TEMP')
      .replace(/\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\}/g, expression => expression.replace(/\s/g, ''));
    let last = first;
    while (/\\[ \t]*$/.test(lines[last])) {
      last++;
      if (last >= lines.length || !/^[ \t]+\S/.test(lines[last])) throw new Error('workflow observation refuses');
    }
    const rawCommand = lines.slice(first, last + 1).join(body.includes('\r\n') ? '\r\n' : '\n');
    const command = rawCommand.replace(/[ \t]*\\[ \t]*\r?\n[ \t]*/g, ' ');
    if (/[`;|&]|\$\(/.test(command)) throw new Error('workflow observation refuses');
    const flags: Record<string, string> = {};
    for (const flag of ['--receipt', '--out-dir']) {
      const values = [...command.matchAll(new RegExp(`${flag}[ \\t]+(?:"([^"\\r\\n]*)"|'([^'\\r\\n]*)'|([^ \\t\\r\\n]+))`, 'g'))];
      if (values.length !== 1) throw new Error('workflow observation refuses');
      flags[flag] = (values[0][1] ?? values[0][2] ?? values[0][3])
        .replace(/\$\{\{\s*env\.BASELINE_DIRECTORY\s*\}\}|\$\{BASELINE_DIRECTORY\}|\$BASELINE_DIRECTORY\b/g, directory)
        .replace(/\$\{\{\s*runner\.temp\s*\}\}|\$\{RUNNER_TEMP\}/g, '$RUNNER_TEMP')
        .replace(/\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\}/g, expression => expression.replace(/\s/g, ''));
    }
    const receipt = flags['--receipt'];
    const basename = receipt.split('/').at(-1);
    if (flags['--out-dir'] !== directory || ![`${directory}/${basename}`, `.dbv/${basename}`].includes(receipt)
      || basename !== (job[1] === declaration.setJob ? declaration.setFilename : declaration.verifiedFilename)) throw new Error('workflow observation refuses');
    const uploadLines = lines.flatMap((line, lineIndex) => /^[ \t]+uses:[ \t]+actions\/upload-artifact@v5[ \t]*$/.test(line) ? [lineIndex] : []);
    if (uploadLines.length !== 1) throw new Error('workflow observation refuses');
    let uploadStart = uploadLines[0];
    while (uploadStart >= 0 && !/^ {6}- /.test(lines[uploadStart])) uploadStart--;
    if (uploadStart < 0) throw new Error('workflow observation refuses');
    let uploadEnd = uploadStart + 1;
    while (uploadEnd < lines.length && !/^ {6}- /.test(lines[uploadEnd])) uploadEnd++;
    const uploadStep = lines.slice(uploadStart, uploadEnd).join('\n');
    const uploadPaths = lines.slice(uploadStart, uploadEnd).flatMap(line => {
      const match = line.match(/^ {10}path:[ \t]*([^\r\n]+)$/);
      return match ? [match[1].trim()] : [];
    });
    if (uploadPaths.length !== 1) throw new Error('workflow observation refuses');
    let upload = uploadPaths[0];
    if ((upload.startsWith('"') && upload.endsWith('"')) || (upload.startsWith("'") && upload.endsWith("'"))) upload = upload.slice(1, -1);
    if (/\$\{\{\s*env\.BASELINE_DIRECTORY\s*\}\}|\$\{BASELINE_DIRECTORY\}|\$BASELINE_DIRECTORY\b/.test(upload)) {
      const uploadEnvs = [...uploadStep.matchAll(/^ {8}env:[ \t]*\r?\n((?:[ \t]{10,}[^\r\n]*(?:\r?\n|$))*)/gm)];
      const uploadBindings = [...(uploadEnvs[0]?.[1] ?? '').matchAll(/^ {10}BASELINE_DIRECTORY:[ \t]*([^\r\n]*)\r?$/gm)];
      if (uploadEnvs.length > 1 || uploadBindings.length > 1 || uploadBindings.length + bindings.length + globalBindings.length !== 1) throw new Error('workflow observation refuses');
      let uploadBinding = uploadBindings[0]?.[1] ?? bindings[0]?.[1] ?? globalBindings[0]?.[1];
      if (uploadBinding === undefined) throw new Error('workflow observation refuses');
      uploadBinding = uploadBinding.trim();
      if (uploadBinding.startsWith('"') && uploadBinding.endsWith('"')) {
        try { uploadBinding = JSON.parse(uploadBinding); } catch { throw new Error('workflow observation refuses'); }
      } else if (uploadBinding.startsWith("'") && uploadBinding.endsWith("'")) uploadBinding = uploadBinding.slice(1, -1).replaceAll("''", "'");
      if (typeof uploadBinding !== 'string' || !/^\$\{\{\s*runner\.temp\s*\}\}(?:\/(?:[A-Za-z0-9._-]|\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\})+)*$/.test(uploadBinding)
        || uploadBinding.split('/').slice(1).some(part => part === '.' || part === '..')) throw new Error('workflow observation refuses');
      const uploadDirectory = uploadBinding.replace(/\$\{\{\s*runner\.temp\s*\}\}/g, '$RUNNER_TEMP')
      .replace(/\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\}/g, expression => expression.replace(/\s/g, ''));
      upload = upload.replace(/\$\{\{\s*env\.BASELINE_DIRECTORY\s*\}\}|\$\{BASELINE_DIRECTORY\}|\$BASELINE_DIRECTORY\b/g, uploadDirectory);
    }
    upload = upload.replace(/\$\{\{\s*runner\.temp\s*\}\}|\$\{RUNNER_TEMP\}/g, '$RUNNER_TEMP')
        .replace(/\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\}/g, expression => expression.replace(/\s/g, ''));
    if (upload !== receipt) throw new Error('workflow observation refuses');
    const expanded = command.replace(/\$\{\{\s*env\.BASELINE_DIRECTORY\s*\}\}|\$\{BASELINE_DIRECTORY\}|\$BASELINE_DIRECTORY\b/g, directory)
      .replace(/\$\{\{\s*runner\.temp\s*\}\}|\$\{RUNNER_TEMP\}/g, '$RUNNER_TEMP')
        .replace(/\$\{\{\s*github\.(?:run_id|run_attempt)\s*\}\}/g, expression => expression.replace(/\s/g, ''));
    observed = observed.replace(body, body.replace(rawCommand, expanded));
  }
  return observed;
}) as typeof ownerHeldNativeReadFileSync;
const ownerHeldExtract = (path: string, name: string) => {
  const source = readFileSync(new URL(path, import.meta.url), 'utf8');
  const match = source.match(new RegExp(`^([ \\t]*)(?:async )?function ${name}\\([^\\n]*\\) \\{[\\s\\S]*?^\\1\\}`, 'm'));
  if (!match) throw new Error('declared narrow helper is absent');
  return match[0];
};
const ownerHeldReadLoader = () => ownerHeldExtract('../../.github/workflows/db.yml', 'readOwnerTimeoutBaseline');
const ownerHeldModule = await import(/* @vite-ignore */ new URL('../../scripts/pgtap/owner-timeout-baseline.mjs', import.meta.url).href).catch(() => ({}));
const ownerHeldVerifier = (ownerHeldModule as Record<string, unknown>).verifyOwnerConfiguredTimeoutBaseline as ((context: unknown, envelope: unknown) => boolean) | undefined;
const ownerHeldConstants = await import(/* @vite-ignore */ new URL('../../packages/shared/src/config/constants.ts', import.meta.url).href);
const ownerHeldFields = (fixture: ReturnType<typeof ownerHeldFixture>) => [
  fixture.context, fixture.envelope, fixture.context.targetRun, fixture.context.targetNativeJob,
  fixture.context.targetGuardianJob, fixture.context.maintenanceRun, fixture.context.setterJob,
  fixture.context.verifierJob, fixture.envelope.review, fixture.envelope.setArchive,
  fixture.envelope.baselineArchive, fixture.envelope.setReceipt, fixture.envelope.baselineReceipt,
  fixture.envelope.teardownReview, fixture.envelope.setReceipt.target, fixture.envelope.setReceipt.configured,
  fixture.envelope.setReceipt.before, fixture.envelope.baselineReceipt.observed,
];

const ownerHeldControlledRealm = (source: string, dependencies: Record<string, unknown>) => {
  const names = Object.keys(dependencies);
  const invoke = runInThisContext(`(function(${names.join(',')}, ownerHeldSource) { return eval(ownerHeldSource); })`) as (...values: unknown[]) => unknown;
  return invoke(...names.map(name => dependencies[name]), source);
};
const ownerHeldAdapterPorts = (command: 'owner-baseline-set' | 'owner-baseline-verify') => {
  const fixture = ownerHeldFixture();
  const now = command === 'owner-baseline-set' ? '2026-10-09T12:00:11.000Z' : '2026-10-09T12:02:30.000Z';
  const events: { kind: string; value: unknown }[] = [];
  const control = { rejectWrite: false, rejectAlter: false, before: fixture.envelope.setReceipt.before,
    observed: fixture.envelope.baselineReceipt.observed, setHash: fixture.envelope.setArchive.bodySha256,
    setArchiveHash: fixture.envelope.setArchive.archiveSha256, projectRef: 'pecxrpskmfeuyzngvewq', version: '2.110.0' };
  const runtime = {
    GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: 'OGUN01/gymloop', GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: 'refs/heads/main', GITHUB_SHA: fixture.context.maintenanceRun.sourceSha,
    GITHUB_RUN_ID: fixture.context.maintenanceRun.id, GITHUB_RUN_ATTEMPT: '1',
    GITHUB_WORKFLOW_REF: 'OGUN01/gymloop/.github/workflows/native-database-owner-baseline.yml@refs/heads/main',
    GITHUB_JOB: command, GITHUB_API_URL: 'https://synthetic.invalid', GITHUB_TOKEN: 'synthetic-never-a-key',
    RUNNER_ENVIRONMENT: 'github-hosted', RUNNER_OS: 'Linux', RUNNER_TEMP: '/private',
    RUNNER_WORKSPACE: '/workspace', GITHUB_WORKSPACE: '/workspace',
  };
  const rawRun = (run: typeof fixture.context.maintenanceRun) => ({
    id: Number(run.id), run_attempt: Number(run.attempt), head_sha: run.sourceSha,
    event: run.event, head_branch: run.branch, path: run.path, status: run.status, conclusion: run.conclusion,
    repository: { id: run.repositoryId, full_name: run.repository, owner: { login: 'OGUN01' } },
    head_repository: { id: run.headRepositoryId, full_name: run.headRepository },
    actor: { login: run.actorLogin }, triggering_actor: { login: run.triggeringActorLogin },
    run_started_at: run.startedAt, updated_at: run.updatedAt,
  });
  const rawJob = (job: typeof fixture.context.setterJob) => ({
    id: job.id, run_id: Number(job.runId), run_attempt: Number(job.attempt), head_sha: job.sourceSha,
    name: job.name, status: job.status, conclusion: job.conclusion, runner_id: job.runnerId,
    runner_name: job.runnerName, runner_group_name: job.runnerGroupName, labels: job.labels, steps: job.steps,
    started_at: job.startedAt, completed_at: job.completedAt,
  });
  const currentRun = { ...rawRun(fixture.context.maintenanceRun), status: 'in_progress', conclusion: null };
  const currentJob = rawJob(command === 'owner-baseline-set' ? fixture.context.setterJob : fixture.context.verifierJob);
  currentJob.status = 'in_progress';
  currentJob.conclusion = null;
  const currentJobs = command === 'owner-baseline-set' ? [currentJob] : [rawJob(fixture.context.setterJob), currentJob];
  const setArtifact = {
    id: fixture.envelope.setArchive.id, name: fixture.envelope.setArchive.name, expired: false,
    size_in_bytes: fixture.envelope.setArchive.sizeBytes, digest: `sha256:${fixture.envelope.setArchive.apiSha256}`,
    workflow_run: { id: Number(runtime.GITHUB_RUN_ID), head_sha: runtime.GITHUB_SHA,
      repository_id: 1358473323, head_repository_id: 1358473323 },
  };
  const payloads: Record<string, unknown> = {
    [`actions/runs/${runtime.GITHUB_RUN_ID}/attempts/1`]: currentRun,
    'actions/runs/37857261809/attempts/1': rawRun(fixture.context.targetRun),
    'actions/runs/37857261809/attempts/1/jobs?page=1': { total_count: 2, jobs: [rawJob(fixture.context.targetNativeJob), rawJob(fixture.context.targetGuardianJob)] },
    'actions/runs/37857261809/artifacts?page=1': { total_count: 3, artifacts: fixture.context.targetArtifactNames.map((name, index) => ({
      id: index + 1, name, expired: false, size_in_bytes: 100, digest: `sha256:${'a'.repeat(64)}`,
      workflow_run: { id: 37857261809, head_sha: fixture.context.targetRun.sourceSha,
        repository_id: 1358473323, head_repository_id: 1358473323 },
    })) },
    [`actions/runs/${runtime.GITHUB_RUN_ID}/attempts/1/jobs?page=1`]: { total_count: currentJobs.length, jobs: currentJobs },
    [`actions/runs/${runtime.GITHUB_RUN_ID}/artifacts?page=1`]: { total_count: command === 'owner-baseline-set' ? 0 : 1, artifacts: command === 'owner-baseline-set' ? [] : [setArtifact] },
    'actions/workflows/native-database-owner-baseline.yml/runs?page=1': { total_count: 1, workflow_runs: [currentRun] },
  };
  const exact = (value: unknown, fields: string[]) => Boolean(exactNativeDataRecord(value, fields));
  const ports = {
    exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock,
    NATIVE_DB_OWNER_BASELINE: ownerHeldConstants.NATIVE_DB_OWNER_BASELINE,
    NATIVE_DB_VALIDATION: ownerHeldConstants.NATIVE_DB_VALIDATION,
    target: fixture.envelope.setReceipt.target, exact,
    validOriginal: (value: { originalPresent: unknown; originalValue: unknown }) => exact(value, ['originalPresent', 'originalValue'])
      && (value.originalPresent === true ? typeof value.originalValue === 'string' && value.originalValue.length > 0
        : value.originalPresent === false && value.originalValue === null),
    sourceString: (value: unknown) => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value),
    sameTimeout: (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b),
    hash: (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex'),
    jsonBytes: (value: unknown) => Buffer.from(`${JSON.stringify(value)}\n`),
    refuse: (code: string) => new Error(code), join, Buffer, verifyNativeWorkloadTeardown,
    Date: class extends Date { constructor(value: string | number = now) { super(value); } static now() { return Date.parse(now); } },
    checked: async (program: string, args: string[], options: unknown) => {
      events.push({ kind: program === 'supabase' && args[0] === 'link' ? 'link' : 'checked', value: { program, args, options } });
      if (program === 'git' && args.join(' ') === 'rev-parse HEAD') return `${runtime.GITHUB_SHA}\n`;
      if (program === 'supabase' && args.join(' ') === '--version') return `${control.version}\n`;
      if (program === 'supabase' && args.join(' ') === 'link --project-ref pecxrpskmfeuyzngvewq --yes') return '';
      throw new Error('unexpected bounded command');
    },
    artifactApi: async (_runtime: unknown, path: string, expectedStatus: number) => {
      events.push({ kind: 'api', value: { path, expectedStatus } });
      if (!Object.hasOwn(payloads, path)) throw new Error('unexpected official API path');
      return { bytes: Buffer.from(JSON.stringify(payloads[path])), status: 200 };
    },
    boundedResponseBytes: async (response: { bytes: Buffer }, maximumBytes: number) => {
      if (maximumBytes !== 65536 || response.bytes.length > maximumBytes) throw new Error('wrong byte bound');
      return response.bytes;
    },
    readFile: async (path: string, encoding?: string) => {
      events.push({ kind: 'read', value: path });
      const body = path.endsWith('project-ref') ? `${control.projectRef}\n` : `${JSON.stringify([fixture.envelope.teardownReview])}\n`;
      return encoding ? body : Buffer.from(body);
    },
    privateWrite: async (path: string, bytes: Buffer) => {
      events.push({ kind: 'write', value: { path, bytes: bytes.toString('utf8') } });
      if (control.rejectWrite) throw new Error('exclusive file refuses');
    },
    queryTimeout: async (_workdir: string, _directory: string, target: unknown) => {
      events.push({ kind: 'query', value: target });
      return command === 'owner-baseline-set' ? control.before : control.observed;
    },
    alterTimeout: async (_workdir: string, _directory: string, value: unknown) => {
      events.push({ kind: 'alter', value });
      if (control.rejectAlter) throw new Error('bounded alter rejects');
    },
    readReceiptArtifact: async (_runtime: unknown, artifact: unknown, filename: string) => {
      events.push({ kind: 'download', value: { artifact, filename } });
      return { value: fixture.envelope.setReceipt, hash: control.setHash, archiveSha256: control.setArchiveHash };
    },
  };
  const argv = [command, '--receipt', `/private/${command === 'owner-baseline-set' ? 'owner-baseline-set.json' : 'owner-baseline-verified.json'}`,
    '--out-dir', '/private', '--source-sha', runtime.GITHUB_SHA, '--approval', 'trial19-owner-baseline-2026-10-09', '--teardown-file', '/private/teardown.json'];
  return { fixture, events, runtime, control, payloads, argv,
    invoke: async () => ownerHeldControlledRealm(`${ownerHeldExtract('../../scripts/native-database-validation.mjs', 'configureOwnerTimeoutBaseline')}\n${ownerHeldExtract('../../scripts/native-database-validation.mjs', 'options')}\nconfigureOwnerTimeoutBaseline(runtime,options(argv,runtime),'/private','/workspace')`, { ...ports, runtime, argv }),
    options: (input: string[]) => ownerHeldControlledRealm(`${ownerHeldExtract('../../scripts/native-database-validation.mjs', 'options')}\noptions(argv,runtime)`, { ...ports, runtime, argv: input }),
  };
};

describe('independent DBV-015 exact configured-state authority', () => {
  it('accepts complete synthetic evidence with mandatory skipped node post and unchanged failed history', () => {
    const fixture = ownerHeldFixture();
    expect(typeof ownerHeldVerifier).toBe('function');
    expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(true);
  });

  it('accepts provider clocks with milliseconds and exact null-prototype snapshots', () => {
    const fixture = ownerHeldFixture();
    fixture.context.setterJob.steps[11].conclusion = 'success';
    fixture.context.maintenanceRun.updatedAt = '2026-10-09T12:04:00.000Z';
    for (const record of ownerHeldFields(fixture)) Object.setPrototypeOf(record, null);
    expect(typeof ownerHeldVerifier).toBe('function');
    expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(true);
  });

  it('rejects every exact record alias, omitted key, symbol, accessor and exotic prototype without reading a getter', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    for (const index of ownerHeldFields(ownerHeldFixture()).keys()) {
      for (const shape of ['extra', 'missing', 'symbol', 'accessor', 'prototype']) {
        const fixture = ownerHeldFixture();
        const record = ownerHeldFields(fixture)[index] as Record<string | symbol, unknown>;
        let getterRead = false;
        if (shape === 'extra') record.alias = true;
        if (shape === 'missing') delete record[Object.keys(record)[0]];
        if (shape === 'symbol') record[Symbol('alias')] = true;
        if (shape === 'accessor') Object.defineProperty(record, Object.keys(record)[0], { enumerable: true, get() { getterRead = true; throw new Error('no getter'); } });
        if (shape === 'prototype') Object.setPrototypeOf(record, { alias: true });
        expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false);
        expect(getterRead).toBe(false);
      }
    }
  });

  it('fails closed on throwing object traps and never throws outward', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    const fixture = ownerHeldFixture();
    const trapped = new Proxy(fixture.context, { ownKeys() { throw new Error('private trap'); } });
    expect(() => ownerHeldVerifier?.(trapped, fixture.envelope)).not.toThrow();
    expect(ownerHeldVerifier?.(trapped, fixture.envelope)).toBe(false);
  });

  it('requires dense own-data arrays for original custody, hosted labels and ordered steps', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    for (const field of ['artifacts', 'labels', 'steps']) {
      for (const shape of ['hole', 'extra', 'getter', 'subclass']) {
        const fixture = ownerHeldFixture();
        const array = field === 'artifacts' ? fixture.context.targetArtifactNames
          : field === 'labels' ? fixture.context.setterJob.labels : fixture.context.setterJob.steps;
        if (shape === 'hole') delete array[0];
        if (shape === 'extra') Object.defineProperty(array, 'alias', { enumerable: true, value: true });
        if (shape === 'getter') Object.defineProperty(array, '0', { enumerable: true, get() { throw new Error('no getter'); } });
        if (shape === 'subclass') Object.setPrototypeOf(array, Object.create(Array.prototype));
        expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false);
      }
    }
  });

  it('binds original identity and refuses additional conflicting custody even when configuration succeeds', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    const changes: ((fixture: ReturnType<typeof ownerHeldFixture>) => void)[] = [
      f => { f.context.targetRun.id = '37857261810'; },
      f => { f.context.targetRun.attempt = '2'; },
      f => { f.context.targetRun.sourceSha = 'e'.repeat(40); },
      f => { f.context.targetRun.conclusion = 'success'; },
      f => { f.context.targetRun.event = 'workflow_dispatch'; },
      f => { f.context.targetRun.branch = 'other'; },
      f => { f.context.targetRun.repositoryId = 1358473324; },
      f => { f.context.targetNativeJob.id = 113584968729; },
      f => { f.context.targetNativeJob.runnerId = 40; },
      f => { f.context.targetNativeJob.steps.push({ ...f.context.targetNativeJob.steps[0] }); },
      f => { f.context.targetGuardianJob.id = 113585808844; },
      f => { f.context.targetGuardianJob.conclusion = 'success'; },
      f => { f.context.targetGuardianJob.steps[1].conclusion = 'success'; },
      f => { f.context.targetArtifactNames.push('native-db-recovery-37857261809-1'); },
      f => { f.context.targetArtifactNames.push('native-db-private-37857261809-1'); },
      f => { f.context.targetArtifactNames.pop(); },
      f => { f.context.targetArtifactNames[0] = f.context.targetArtifactNames[1]; },
    ];
    for (const change of changes) { const fixture = ownerHeldFixture(); change(fixture); expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false); }
  });

  it('requires one owner dispatch, exact current source and exhaustive authenticated listings', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    const changes: ((fixture: ReturnType<typeof ownerHeldFixture>) => void)[] = [
      f => { f.context.maintenanceRun.attempt = '2'; },
      f => { f.context.maintenanceRun.sourceSha = 'e'.repeat(40); },
      f => { f.context.maintenanceRun.event = 'push'; },
      f => { f.context.maintenanceRun.path = '.github/workflows/db.yml'; },
      f => { f.context.maintenanceRun.branch = 'other'; },
      f => { f.context.maintenanceRun.actorLogin = 'other'; },
      f => { f.context.maintenanceRun.triggeringActorLogin = 'other'; },
      f => { f.context.maintenanceRun.headRepositoryId = 1358473324; },
      f => { f.context.maintenanceRun.headRepository = 'other/gymloop'; },
      f => { f.context.maintenanceRun.status = 'in_progress'; },
      f => { f.context.maintenanceRun.conclusion = 'failure'; },
      f => { f.context.jobListingComplete = false; },
      f => { f.context.artifactListingComplete = false; },
      f => { f.envelope.review.authorityKind = 'restoration'; },
    ];
    for (const change of changes) { const fixture = ownerHeldFixture(); change(fixture); expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false); }
  });

  it('requires different authentic hosted workers and exact step completion including post-job cleanup', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    for (const side of ['setterJob', 'verifierJob'] as const) {
      for (const change of ['failure', 'self-hosted', 'runner-name', 'same-worker', 'same-job', 'omitted-post', 'reordered', 'duplicate', 'effect-skipped', 'post-failed', 'extra-step']) {
        const fixture = ownerHeldFixture();
        const job = fixture.context[side];
        if (change === 'failure') job.conclusion = 'failure';
        if (change === 'self-hosted') job.labels = ['self-hosted'];
        if (change === 'runner-name') job.runnerName = 'untrusted';
        if (change === 'same-worker') job.runnerId = fixture.context[side === 'setterJob' ? 'verifierJob' : 'setterJob'].runnerId;
        if (change === 'same-job') job.id = fixture.context[side === 'setterJob' ? 'verifierJob' : 'setterJob'].id;
        if (change === 'omitted-post') job.steps.splice(11, 1);
        if (change === 'reordered') [job.steps[0], job.steps[1]] = [job.steps[1], job.steps[0]];
        if (change === 'duplicate') job.steps.push({ ...job.steps[0] });
        if (change === 'effect-skipped') job.steps[8].conclusion = 'skipped';
        if (change === 'post-failed') job.steps[10].conclusion = 'failure';
        if (change === 'extra-step') job.steps.push({ name: 'additional authority', status: 'completed', conclusion: 'success' });
        expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false);
      }
    }
  });

  it('requires every official archive identity and actual archive/body digest to agree with outside review', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    for (const side of ['setArchive', 'baselineArchive'] as const) {
      for (const change of ['id', 'name', 'source', 'run', 'repository', 'headRepository', 'zero-size', 'unsafe-size', 'api-digest', 'archive-digest', 'body-digest', 'expired']) {
        const fixture = ownerHeldFixture(); const archive = fixture.envelope[side];
        if (change === 'id') archive.id = 6135849699;
        if (change === 'name') archive.name = 'recovery.json';
        if (change === 'source') archive.sourceSha = 'e'.repeat(40);
        if (change === 'run') archive.runId = '47857261810';
        if (change === 'repository') archive.repositoryId = 1358473324;
        if (change === 'headRepository') archive.headRepositoryId = 1358473324;
        if (change === 'zero-size') archive.sizeBytes = 0;
        if (change === 'unsafe-size') archive.sizeBytes = Number.MAX_SAFE_INTEGER + 1;
        if (change === 'api-digest') archive.apiSha256 = 'e'.repeat(64);
        if (change === 'archive-digest') archive.archiveSha256 = 'e'.repeat(64);
        if (change === 'body-digest') archive.bodySha256 = 'e'.repeat(64);
        if (change === 'expired') archive.expired = true;
        expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false);
      }
    }
  });

  it('rejects missing configuration, a guessed original and substitutes for fresh physical proof', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    const changes: ((fixture: ReturnType<typeof ownerHeldFixture>) => void)[] = [
      f => { f.envelope.setReceipt.configured.originalValue = '120000'; },
      f => { f.envelope.baselineReceipt.observed.originalValue = '0'; },
      f => { f.envelope.baselineReceipt.verified = false; },
      f => { f.envelope.baselineReceipt.setReceiptSha256 = 'e'.repeat(64); },
      f => { f.envelope.setReceipt.before = { originalPresent: true, originalValue: null }; },
      f => { f.envelope.review.teardownPrivateProofSha256 = 'e'.repeat(64); },
      f => { f.envelope.teardownReview.privateProofSha256 = 'e'.repeat(64); },
      f => { f.envelope.teardownReview.nativeProcessesStopped = false; },
      f => { f.envelope.teardownReview.ownedContainersStopped = false; },
      f => { f.envelope.teardownReview.runnerDeregistered = false; },
      f => { f.envelope.review.privateProofSha256 = 'C'.repeat(64); },
      f => { f.envelope.review.targetRunAttempt = '01'; },
    ];
    for (const change of changes) { const fixture = ownerHeldFixture(); change(fixture); expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false); }
  });

  it('uses canonical real clocks and the required capture/set/verify/review chronology', () => {
    expect(typeof ownerHeldVerifier).toBe('function');
    const changes: ((fixture: ReturnType<typeof ownerHeldFixture>) => void)[] = [
      f => { f.envelope.setReceipt.beforeCapturedAt = '2026-10-09T12:00:10Z'; },
      f => { f.envelope.setReceipt.beforeCapturedAt = '2026-02-30T12:00:10.000Z'; },
      f => { f.envelope.setReceipt.beforeCapturedAt = '2026-10-09T12:00:12.000Z'; },
      f => { f.envelope.setReceipt.requestedAt = '2026-10-09T12:01:00.001Z'; },
      f => { f.envelope.setReceipt.beforeCapturedAt = '2026-10-09T11:59:59.999Z'; },
      f => { f.envelope.baselineReceipt.verifiedAt = '2026-10-09T12:00:59.999Z'; },
      f => { f.envelope.baselineReceipt.verifiedAt = '2026-10-09T12:01:59.999Z'; },
      f => { f.envelope.baselineReceipt.verifiedAt = '2026-10-09T12:03:00.001Z'; },
      f => { f.envelope.review.reviewedAt = '2026-10-09T12:03:59.999Z'; },
      f => { f.context.maintenanceRun.updatedAt = '2026-10-09T12:04:00+00:00'; },
    ];
    for (const change of changes) { const fixture = ownerHeldFixture(); change(fixture); expect(ownerHeldVerifier?.(fixture.context, fixture.envelope)).toBe(false); }
  });
});

describe('independent DBV-015 declared adapter and preflight boundaries', () => {
  it('accepts only the new exact option set and refuses duplicate, absent, manifest, target and unknown flags', () => {
    for (const command of ['owner-baseline-set', 'owner-baseline-verify'] as const) {
      const harness = ownerHeldAdapterPorts(command);
      expect(() => harness.options(harness.argv)).not.toThrow();
      for (const input of [
        [...harness.argv, '--approval', 'trial19-owner-baseline-2026-10-09'],
        harness.argv.slice(0, -2), [...harness.argv, '--manifest', '/private/manifest.json'],
        [...harness.argv, '--project-ref', 'pecxrpskmfeuyzngvewq'], [...harness.argv, '--unknown', 'yes'],
        harness.argv.map(value => value === 'trial19-owner-baseline-2026-10-09' ? 'other' : value),
      ]) expect(() => harness.options(input)).toThrow();
    }
    const ordinary = ownerHeldAdapterPorts('owner-baseline-set');
    expect(() => ordinary.options(ordinary.argv.map((value, index) => index === 0 ? 'run' : value))).toThrow();
  });

  it('admits exact setter custody and writes canonical intent before its one fixed alteration', async () => {
    const harness = ownerHeldAdapterPorts('owner-baseline-set');
    await expect(harness.invoke()).resolves.toBeUndefined();
    const order = harness.events.map(event => event.kind);
    expect(order.filter(kind => kind === 'query')).toHaveLength(1);
    expect(order.filter(kind => kind === 'alter')).toHaveLength(1);
    expect(order.indexOf('query')).toBeLessThan(order.indexOf('write'));
    expect(order.indexOf('write')).toBeLessThan(order.indexOf('alter'));
    expect(harness.events.find(event => event.kind === 'alter')?.value).toEqual({
      target: harness.fixture.envelope.setReceipt.target, setting: { originalPresent: true, originalValue: '2min' },
    });
    const write = harness.events.find(event => event.kind === 'write')?.value as { bytes: string };
    const receipt = JSON.parse(write.bytes);
    expect(write.bytes).toBe(`${JSON.stringify(receipt)}\n`);
    expect(receipt.before).toEqual(harness.control.before);
    expect(receipt.authorityKind).toBe('owner-configured-timeout-baseline');
    expect(receipt).not.toHaveProperty('restored');
  });

  it('retains pre-effect refusal for wrong authority, source, worker, attempt, incomplete listing and prior dispatch', async () => {
    for (const change of ['approval', 'source', 'worker', 'attempt', 'cli', 'current-owner', 'incomplete', 'replay']) {
      const harness = ownerHeldAdapterPorts('owner-baseline-set');
      if (change === 'approval') harness.argv[harness.argv.indexOf('--approval') + 1] = 'other';
      if (change === 'source') harness.argv[harness.argv.indexOf('--source-sha') + 1] = 'e'.repeat(40);
      if (change === 'worker') harness.runtime.RUNNER_ENVIRONMENT = 'self-hosted';
      if (change === 'attempt') harness.runtime.GITHUB_RUN_ATTEMPT = '2';
      if (change === 'cli') harness.control.version = '2.109.0';
      if (change === 'current-owner') (harness.payloads[`actions/runs/${harness.runtime.GITHUB_RUN_ID}/attempts/1`] as { actor: { login: string } }).actor.login = 'other';
      if (change === 'incomplete') (harness.payloads['actions/runs/37857261809/attempts/1/jobs?page=1'] as { total_count: number }).total_count = 3;
      if (change === 'replay') {
        const listing = harness.payloads['actions/workflows/native-database-owner-baseline.yml/runs?page=1'] as { total_count: number; workflow_runs: unknown[] };
        listing.total_count = 2; listing.workflow_runs.push({ ...(listing.workflow_runs[0] as object), id: 47857261810 });
      }
      await expect(harness.invoke()).rejects.toThrow();
      expect(harness.events.some(event => ['link', 'query', 'alter', 'write'].includes(event.kind))).toBe(false);
    }
  });

  it('refuses setter custody failure before alteration and bounded alteration failure without replay', async () => {
    const writeFailure = ownerHeldAdapterPorts('owner-baseline-set');
    writeFailure.control.rejectWrite = true;
    await expect(writeFailure.invoke()).rejects.toThrow();
    expect(writeFailure.events.some(event => event.kind === 'alter')).toBe(false);
    const alterFailure = ownerHeldAdapterPorts('owner-baseline-set');
    alterFailure.control.rejectAlter = true;
    await expect(alterFailure.invoke()).rejects.toThrow();
    expect(alterFailure.events.filter(event => event.kind === 'alter')).toHaveLength(1);
  });

  it('independently downloads exact setter custody and performs one fresh query without an alteration', async () => {
    const harness = ownerHeldAdapterPorts('owner-baseline-verify');
    await expect(harness.invoke()).resolves.toBeUndefined();
    const order = harness.events.map(event => event.kind);
    expect(order.indexOf('download')).toBeLessThan(order.indexOf('link'));
    expect(order.filter(kind => kind === 'query')).toHaveLength(1);
    expect(order).not.toContain('alter');
    const receipt = JSON.parse((harness.events.find(event => event.kind === 'write')?.value as { bytes: string }).bytes);
    expect(receipt.observed).toEqual({ originalPresent: true, originalValue: '2min' });
    expect(receipt.verified).toBe(true);
    expect(receipt.setReceiptSha256).toBe(harness.control.setHash);
  });

  it('refuses counterfeit setter bytes before link and wrong observed configuration without success receipt', async () => {
    const counterfeit = ownerHeldAdapterPorts('owner-baseline-verify');
    counterfeit.control.setHash = 'e'.repeat(64);
    await expect(counterfeit.invoke()).rejects.toThrow();
    expect(counterfeit.events.some(event => ['link', 'query', 'alter', 'write'].includes(event.kind))).toBe(false);
    const wrongObserved = ownerHeldAdapterPorts('owner-baseline-verify');
    wrongObserved.control.observed = { originalPresent: true, originalValue: '0' };
    await expect(wrongObserved.invoke()).rejects.toThrow();
    expect(wrongObserved.events.some(event => ['alter', 'write'].includes(event.kind))).toBe(false);
  });
  it('declares body-only set/verify adapter extraction and the exact command option extension', () => {
    const helper = ownerHeldExtract('../../scripts/native-database-validation.mjs', 'configureOwnerTimeoutBaseline');
    const options = ownerHeldExtract('../../scripts/native-database-validation.mjs', 'options');
    expect(helper).toContain('queryTimeout');
    expect(helper).toContain('verifyNativeWorkloadTeardown');
    expect(options).toContain('owner-baseline-set');
    expect(options).toContain('owner-baseline-verify');
    expect(options).toContain('--approval');
    expect(options).toContain('--teardown-file');
  });

  it('has a declared narrow loader that consumes outside reviews and complete official evidence through the pure verifier', () => {
    const loader = ownerHeldReadLoader();
    expect(loader).toContain('ownerBaselineReviews');
    expect(loader).toContain('operatorReceipts');
    expect(loader).toContain('verifyOwnerConfiguredTimeoutBaseline');
    expect(loader).toContain('readArtifact');
    expect(loader).toContain('jobs');
    expect(loader).toContain('artifacts');
  });

  it('declares exactly the reviewed sequential hosted maintenance workflow, authority flags and custodial artifact policy', () => {
    const workflow = readFileSync(new URL('../../.github/workflows/native-database-owner-baseline.yml', import.meta.url), 'utf8');
    expect(workflow).toContain('name: Native database owner timeout baseline');
    expect(workflow).toContain('workflow_dispatch:');
    expect(workflow).toContain('trial19-owner-baseline-2026-10-09');
    expect(workflow).toContain('cancel-in-progress: false');
    expect(workflow).toContain('group: db-${{ github.ref }}');
    expect(workflow).toContain('owner-baseline-set:');
    expect(workflow).toContain('owner-baseline-verify:');
    expect(workflow).toMatch(/needs:\s*owner-baseline-set/);
    expect(workflow.match(/runs-on:\s*ubuntu-latest/g)).toHaveLength(2);
    expect(workflow.match(/uses:\s*actions\/checkout@v7/g)).toHaveLength(2);
    expect(workflow.match(/uses:\s*pnpm\/action-setup@v6/g)).toHaveLength(2);
    expect(workflow.match(/uses:\s*actions\/setup-node@v7/g)).toHaveLength(2);
    expect(workflow.match(/uses:\s*supabase\/setup-cli@v3/g)).toHaveLength(2);
    expect(workflow.match(/version:\s*2\.110\.0/g)).toHaveLength(2);
    expect(workflow.match(/uses:\s*actions\/upload-artifact@v5/g)).toHaveLength(2);
    expect(workflow.match(/if-no-files-found:\s*error/g)).toHaveLength(2);
    expect(workflow).toContain('--ignore-scripts');
    expect(workflow).toContain('owner-baseline-set --receipt');
    expect(workflow).toContain('owner-baseline-verify --receipt');
    expect(workflow).toContain('--approval');
    expect(workflow).toContain('--teardown-file');
    expect(workflow).not.toContain('--manifest');
    expect(workflow).not.toContain('workflow_call:');
    expect(workflow).not.toContain('schedule:');
    expect(workflow).not.toContain('overwrite: true');
  });
});
