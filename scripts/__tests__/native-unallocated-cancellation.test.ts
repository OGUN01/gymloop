import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {describe, expect, it, vi} from 'vitest';
import {NATIVE_DB_VALIDATION as limits} from '../../packages/shared/src/config/constants';

type VisibleUnallocatedRecord = Record<string, unknown>;

const visibleUnallocatedModuleUrl = new URL('../pgtap/unallocated-cancellation.mjs', import.meta.url);
let visibleUnallocatedLoadError: unknown;
let visibleUnallocatedVerifier: ((input: unknown) => {verified: boolean}) | undefined;
let visibleUnallocatedClockLoadError: unknown;
let visibleUnallocatedClock: ((value: unknown, provider?: boolean) => number | null) | undefined;

try {
  visibleUnallocatedVerifier = (await import(visibleUnallocatedModuleUrl.href)).verifyUnallocatedNativeCancellation;
} catch (error) {
  visibleUnallocatedLoadError = error;
}
try {
  visibleUnallocatedClock = (await import(new URL('../pgtap/data-record.mjs', import.meta.url).href)).nativeEvidenceClock;
} catch (error) {
  visibleUnallocatedClockLoadError = error;
}

function requireVisibleUnallocatedVerifier() {
  expect(visibleUnallocatedLoadError, 'DBV-014 must supply its separate pure module').toBeUndefined();
  expect(typeof visibleUnallocatedVerifier, 'DBV-014 must supply its named verifier').toBe('function');
  return visibleUnallocatedVerifier!;
}

function requireVisibleUnallocatedClock() {
  expect(visibleUnallocatedClockLoadError, 'the unchanged shared evidence clock must load').toBeUndefined();
  expect(typeof visibleUnallocatedClock, 'the shared clock must be exported from data-record.mjs').toBe('function');
  return visibleUnallocatedClock!;
}

function visibleUnallocatedFixture() {
  return {
    review: {
      formatVersion: limits.formatVersion,
      runId: '48000001234-7',
      sourceSha: 'b'.repeat(limits.sourceShaLength),
      jobId: '145001234501',
      guardianJobId: '145001234502',
      completionKind: 'unallocated-cancellation',
      privateProofSha256: 'c'.repeat(limits.digestHexLength),
      verifiedAt: '2026-10-08T07:08:09.001Z',
    },
    run: {
      id: '48000001234',
      attempt: '7',
      sourceSha: 'b'.repeat(limits.sourceShaLength),
      repositoryId: 190123456,
      repository: limits.repository,
      headRepositoryId: 190123456,
      headRepository: limits.repository,
      event: 'push',
      path: '.github/workflows/db.yml',
      branch: 'main',
      status: 'completed',
      conclusion: 'cancelled',
    },
    nativeJobs: [{
      id: 145001234501,
      runId: '48000001234',
      attempt: '7',
      sourceSha: 'b'.repeat(limits.sourceShaLength),
      name: String(limits.job),
      status: 'completed',
      conclusion: 'cancelled',
      runnerId: null,
      runnerName: null,
      runnerGroupId: null,
      runnerGroupName: null,
      labels: [] as unknown[],
      steps: [] as unknown[],
      startedAt: '2026-10-08T07:08:09Z',
      completedAt: '2026-10-08T07:08:09Z',
    }],
    guardianJobs: [{
      id: 145001234502,
      runId: '48000001234',
      attempt: '7',
      sourceSha: 'b'.repeat(limits.sourceShaLength),
      name: 'timeout-guardian',
      status: 'completed',
      conclusion: 'cancelled',
      runnerId: null,
      runnerName: null,
      runnerGroupId: null,
      runnerGroupName: null,
      labels: ['ubuntu-latest'] as unknown[],
      steps: [] as unknown[],
      startedAt: '2026-10-08T07:08:09Z',
      completedAt: '2026-10-08T07:08:09Z',
    }],
    artifactNames: [] as unknown[],
    jobListingComplete: true,
    artifactListingComplete: true,
  };
}

function visibleUnallocatedClone<T>(value: T): T {
  return structuredClone(value);
}

function visibleUnallocatedReplace(path: string, value: unknown) {
  const fixture = visibleUnallocatedFixture();
  const parts = path.split('.');
  let target: VisibleUnallocatedRecord = fixture as unknown as VisibleUnallocatedRecord;
  for (const key of parts.slice(0, -1)) target = target[key] as VisibleUnallocatedRecord;
  target[parts.at(-1)!] = value;
  return fixture;
}

async function executeVisibleUnallocatedPreflight(options: {
  pair?: ReturnType<typeof visibleUnallocatedFixture>;
  reviews?: unknown[];
  artifactNames?: unknown[];
  artifactTotal?: unknown;
  jobsTotal?: unknown;
  mutateRun?: VisibleUnallocatedRecord;
  olderAssigned?: boolean;
  currentAttempt?: string;
} = {}) {
  const pair = options.pair ?? visibleUnallocatedFixture();
  const failures: string[] = [];
  const forbiddenCalls: string[] = [];
  const observedAttempts: {runId: unknown; attempt: unknown}[] = [];
  const baseline = {
    id: Number(limits.legacyBaselineRunId), run_attempt: 1,
    head_sha: limits.legacyBaselineSourceSha, event: 'push', head_branch: 'main',
    status: 'completed', conclusion: 'success', path: '.github/workflows/db.yml',
    repository: {id: pair.run.repositoryId, full_name: limits.repository},
    head_repository: {id: pair.run.headRepositoryId, full_name: limits.repository},
  };
  const previous = {
    id: Number(pair.run.id), run_attempt: Number(pair.run.attempt),
    head_sha: pair.run.sourceSha, event: pair.run.event, head_branch: pair.run.branch,
    status: pair.run.status, conclusion: pair.run.conclusion, path: pair.run.path,
    repository: {id: pair.run.repositoryId, full_name: pair.run.repository},
    head_repository: {id: pair.run.headRepositoryId, full_name: pair.run.headRepository},
    ...options.mutateRun,
  };
  const current = {
    ...baseline, id: 48000009999, run_attempt: Number(options.currentAttempt ?? '1'),
    head_sha: 'd'.repeat(limits.sourceShaLength), status: 'in_progress', conclusion: null,
  };
  const jobs = [...pair.nativeJobs, ...pair.guardianJobs].map((job) => ({
    id: job.id, run_id: Number(job.runId), run_attempt: Number(job.attempt),
    head_sha: job.sourceSha, name: job.name, status: job.status, conclusion: job.conclusion,
    runner_id: job.runnerId, runner_name: job.runnerName,
    runner_group_id: job.runnerGroupId, runner_group_name: job.runnerGroupName,
    labels: job.labels, steps: job.steps, started_at: job.startedAt, completed_at: job.completedAt,
  }));
  const artifacts = (options.artifactNames ?? pair.artifactNames).map((name, index) => ({
    id: pair.run.repositoryId + index, name, expired: true,
    digest: `sha256:${pair.review.privateProofSha256}`, size_in_bytes: 1,
    workflow_run: {id: previous.id, head_sha: previous.head_sha,
      repository_id: pair.run.repositoryId, head_repository_id: pair.run.headRepositoryId},
  }));
  const api = {
    getWorkflowRun: vi.fn(async (args: VisibleUnallocatedRecord) => ({
      data: String(args.run_id) === limits.legacyBaselineRunId ? baseline
        : String(args.run_id) === String(current.id) ? current : previous,
    })),
    getWorkflowRunAttempt: vi.fn(async (args: VisibleUnallocatedRecord) => {
      observedAttempts.push({runId: args.run_id, attempt: args.attempt_number});
      return {data: {
        ...(String(args.run_id) === String(current.id) ? current : previous),
        ...(Number(args.attempt_number) === Number(pair.run.attempt) ? {} : {run_attempt: Number(args.attempt_number)}),
      }};
    }),
    listWorkflowRuns: vi.fn(async () => ({data: {workflow_runs: [previous, baseline]}})),
    listJobsForWorkflowRunAttempt: vi.fn(async (args: VisibleUnallocatedRecord) => {
      const selectedJobs = String(args.run_id) === limits.legacyBaselineRunId
        ? ['migrate', limits.job, 'seed-dry-run'].map((name) => ({
          ...jobs[0], id: pair.run.repositoryId + name.length,
          run_id: baseline.id, run_attempt: 1, head_sha: baseline.head_sha,
          name, status: 'completed', conclusion: 'success',
        }))
        : String(args.run_id) !== String(previous.id) ? []
          : Number(args.attempt_number) === Number(pair.run.attempt) ? jobs
            : options.olderAssigned && Number(args.attempt_number) === Number(pair.run.attempt) - 1
              ? [{...jobs[0], id: pair.run.repositoryId, run_attempt: Number(args.attempt_number),
                runner_id: pair.run.repositoryId, runner_name: `GitHub Actions ${pair.run.repositoryId}`,
                runner_group_id: pair.run.repositoryId, runner_group_name: 'GitHub Actions',
                labels: ['ubuntu-latest'], conclusion: 'failure',
                steps: [{name: 'Set up job', status: 'completed', conclusion: 'success'}]}] : [];
      return {data: {
        total_count: String(args.run_id) === String(previous.id) && Number(args.attempt_number) === Number(pair.run.attempt)
          ? options.jobsTotal ?? selectedJobs.length : selectedJobs.length,
        jobs: selectedJobs,
      }};
    }),
    listWorkflowRunArtifacts: vi.fn(async (args: VisibleUnallocatedRecord) => ({data: {
      total_count: options.artifactTotal ?? artifacts.length,
      artifacts: Number(args.page ?? 1) === 1 && String(args.run_id) === String(previous.id) ? artifacts : [],
    }})),
    downloadArtifact: vi.fn(async () => {
      forbiddenCalls.push('artifact-download');
      throw new Error('Absence-class fixture never supplies artifact bodies');
    }),
  };
  const github = {
    rest: {actions: api},
    request: vi.fn(async () => {
      forbiddenCalls.push('request');
      throw new Error('Undeclared network operation refused');
    }),
    paginate: Object.assign(async (method: unknown, args: VisibleUnallocatedRecord) => {
      if (method === api.listWorkflowRuns) return [previous, baseline];
      if (method === api.listJobsForWorkflowRunAttempt) return (await api.listJobsForWorkflowRunAttempt(args)).data.jobs;
      if (method === api.listWorkflowRunArtifacts) return (await api.listWorkflowRunArtifacts(args)).data.artifacts;
      throw new Error('Undeclared pagination operation refused');
    }, {iterator: async function* (method: unknown, args: VisibleUnallocatedRecord) {
      if (method === api.listWorkflowRuns) yield {data: [previous, baseline]};
      else if (method === api.listJobsForWorkflowRunAttempt) yield {data: (await api.listJobsForWorkflowRunAttempt(args)).data.jobs};
      else if (method === api.listWorkflowRunArtifacts) yield {data: (await api.listWorkflowRunArtifacts(args)).data.artifacts};
      else throw new Error('Undeclared pagination iterator refused');
    }}),
  };
  const source = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const marker = "Require the previous armed attempt's verified restoration";
  const markerOffset = source.indexOf(marker);
  expect(markerOffset, 'the public named recovery preflight step must exist').toBeGreaterThanOrEqual(0);
  const step = source.slice(markerOffset, source.indexOf('\n  pgtap-rollback:', markerOffset));
  const scriptOffset = step.indexOf('          script: |');
  expect(scriptOffset, 'the named step must expose its existing script scalar').toBeGreaterThanOrEqual(0);
  const script = step.slice(scriptOffset + '          script: |'.length)
    .split(/\r?\n/).filter((line) => line.startsWith('            ')).map((line) => line.slice('            '.length)).join('\n');
  const readFileDeclaration = /const\s*\{\s*readFile\s*\}\s*=\s*await\s+import\(['"]node:fs\/promises['"]\)\s*;/g;
  expect([...script.matchAll(readFileDeclaration)], 'the approved inert filesystem port occurs once').toHaveLength(1);
  const executable = script.replace(readFileDeclaration, '').replaceAll('await import(', 'await visibleUnallocatedImport(');
  const sandbox = {
    github,
    context: {repo: {owner: 'OGUN01', repo: 'gymloop'}, runId: current.id, sha: current.head_sha, eventName: 'push'},
    core: {info: vi.fn(), warning: vi.fn(), setFailed: (message: unknown) => failures.push(String(message))},
    readFile: async (path: string, encoding?: string) => {
      if (path === '.dbv/current-attempt.txt') return encoding === undefined ? Buffer.from(options.currentAttempt ?? '1', 'utf8') : options.currentAttempt ?? '1';
      if (path === '.dbv/operator-workload-teardowns.json') return encoding === undefined ? Buffer.from(JSON.stringify(options.reviews ?? [pair.review]), 'utf8') : JSON.stringify(options.reviews ?? [pair.review]);
      if (path === '.dbv/operator-unarmed-prechecks.json' || path === '.dbv/operator-timeout-recoveries.json') return encoding === undefined ? Buffer.from('[]', 'utf8') : '[]';
      if (path === '.dbv/operator-owner-baselines.json' && (encoding === undefined || encoding === 'utf8')) return encoding === undefined ? Buffer.from('[]\n', 'utf8') : '[]\n';
      throw new Error('Undeclared filesystem read refused');
    },
    process: {cwd: () => fileURLToPath(new URL('../../', import.meta.url))},
    fetch: vi.fn(async () => {forbiddenCalls.push('fetch'); throw new Error('Network refused');}),
    Buffer, URL, AbortSignal, console: {log: vi.fn(), error: vi.fn()},
  };
  const visibleUnallocatedImport = async (specifier: string) => {
    if (specifier === 'node:fs/promises') return {readFile: sandbox.readFile};
    if (specifier === 'node:child_process') return {execFileSync: () => {
      forbiddenCalls.push('process-execution');
      throw new Error('Native process execution refused');
    }};
    return import(/^[A-Za-z]:[\\/]/.test(specifier) ? pathToFileURL(specifier).href : specifier);
  };
  let thrown: unknown;
  try {
    await new Function(...Object.keys(sandbox), 'visibleUnallocatedImport', `return (async () => {${executable}\n})()`)(
      ...Object.values(sandbox), visibleUnallocatedImport,
    );
  } catch (error) {
    thrown = error;
  }
  return {failed: failures.length > 0 || thrown !== undefined, failures, thrown, forbiddenCalls, observedAttempts};
}

function executeVisibleUnallocatedSelector(options: {paths?: string[]; computable?: boolean} = {}) {
  const source = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  const markerOffset = source.indexOf('Decide whether the suite can run here');
  expect(markerOffset, 'the public native-selector step must exist').toBeGreaterThanOrEqual(0);
  const step = source.slice(markerOffset, source.indexOf('Resolve source-bound online readiness or hosted fallback', markerOffset));
  const runOffset = step.indexOf('run: |');
  expect(runOffset, 'the selector retains its Bash observation boundary').toBeGreaterThanOrEqual(0);
  let executable = step.slice(runOffset + 'run: |'.length).split(/\r?\n/)
    .filter((line) => line.startsWith('          ')).map((line) => line.slice('          '.length)).join('\n');
  for (const [expression, value] of [
    ['github.repository', limits.repository], ['github.ref', limits.mainRef],
    ['github.event_name', 'push'], ['needs.migrate.outputs.schema_ready', 'true'],
    ['github.event.before', 'a'.repeat(limits.sourceShaLength)], ['github.sha', 'b'.repeat(limits.sourceShaLength)],
  ]) {
    executable = executable.replace(new RegExp(`\\$\\{\\{\\s*${expression.replaceAll('.', '\\.')}\\s*\\}\\}`, 'g'), value);
  }
  expect(executable, 'declared inputs completely bind the opaque selector').not.toContain('${{');
  const paths = options.paths ?? ['scripts/pgtap/unallocated-cancellation.mjs'];
  expect(paths.every((path) => /^[a-zA-Z0-9_./-]+$/.test(path))).toBe(true);
  const prelude = [
    'set -euo pipefail', 'task_output=$(mktemp)', 'trap \'cat "$task_output"; rm -f -- "$task_output"\' EXIT',
    'export GITHUB_OUTPUT="$task_output"', 'git() {',
    '  case "$1" in',
    `    cat-file) return ${options.computable === false ? '1' : '0'} ;;`,
    `    diff) printf '%s\\n' ${paths.length > 0 ? paths.map((path) => `'${path}'`).join(' ') : "''"} ;;`,
    '    *) return 1 ;;', '  esac', '}',
  ].join('\n');
  return execFileSync(process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash', ['-c', `${prelude}\n${executable}`], {
    cwd: fileURLToPath(new URL('../../', import.meta.url)), encoding: 'utf8',
  });
}

describe('DBV-014 reviewed unallocated cancellation public boundary', () => {
  it('exports only the separately named pure verifier', async () => {
    requireVisibleUnallocatedVerifier();
    expect(Object.keys(await import(visibleUnallocatedModuleUrl.href))).toEqual(['verifyUnallocatedNativeCancellation']);
  });

  it.each([
    {label: 'unmaterialized selector labels', labels: []},
    {label: 'resolved ordinary hosted labels', labels: ['ubuntu-latest']},
  ])('accepts the exact never-assigned pair with $label', ({labels}) => {
    const fixture = visibleUnallocatedFixture();
    fixture.nativeJobs[0].labels = labels;
    const before = visibleUnallocatedClone(fixture);
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
    expect(fixture).toEqual(before);
  });

  it('accepts the independently selected trusted dispatch event', () => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('run.event', 'workflow_dispatch'))).toEqual({verified: true});
  });

  it('accepts exact records with null prototypes', () => {
    const fixture = visibleUnallocatedFixture();
    for (const record of [fixture, fixture.review, fixture.run, fixture.nativeJobs[0], fixture.guardianJobs[0]]) {
      Object.setPrototypeOf(record, null);
    }
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });

  it('accepts canonical positive run/attempt strings without rounding their identity', () => {
    const fixture = visibleUnallocatedFixture();
    fixture.review.runId = '9007199254740993-9007199254740995';
    for (const record of [fixture.run, fixture.nativeJobs[0], fixture.guardianJobs[0]]) {
      record.attempt = '9007199254740995';
    }
    fixture.run.id = '9007199254740993';
    fixture.nativeJobs[0].runId = fixture.run.id;
    fixture.guardianJobs[0].runId = fixture.run.id;
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });

  it('accepts positive safe upper-bound repository and distinct job identities', () => {
    const fixture = visibleUnallocatedFixture();
    fixture.run.repositoryId = Number.MAX_SAFE_INTEGER;
    fixture.run.headRepositoryId = Number.MAX_SAFE_INTEGER;
    fixture.nativeJobs[0].id = Number.MAX_SAFE_INTEGER;
    fixture.guardianJobs[0].id = Number.MAX_SAFE_INTEGER - 1;
    fixture.review.jobId = String(fixture.nativeJobs[0].id);
    fixture.review.guardianJobId = String(fixture.guardianJobs[0].id);
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });

  it.each([
    undefined, null, false, true, '', 'reviewed', 0, 1, -1, NaN, Infinity,
    1n, Symbol('input'), [], () => undefined, new Date('2026-10-08T00:00:00.000Z'),
  ].map((input) => ({input})))('refuses non-record input $input without throwing', ({input}) => {
    expect(requireVisibleUnallocatedVerifier()(input)).toEqual({verified: false});
  });

  it.each([
    ['review.formatVersion', '1'], ['review.formatVersion', 0],
    ['review.completionKind', 'github-hosted-job-decommission'],
    ['review.completionKind', 'unallocated-cancellation '],
    ['review.privateProofSha256', 'C'.repeat(limits.digestHexLength)],
    ['review.privateProofSha256', 'c'.repeat(limits.digestHexLength - 1)],
    ['review.privateProofSha256', 'c'.repeat(limits.digestHexLength + 1)],
    ['review.privateProofSha256', 'z'.repeat(limits.digestHexLength)],
    ['review.privateProofSha256', null], ['review.privateProofSha256', {}],
    ['run.repository', 'OGUN01/other'], ['run.repository', 'ogun01/gymloop'],
    ['run.headRepository', 'OGUN01/other'], ['run.headRepositoryId', 190123457],
    ['run.event', 'pull_request'], ['run.event', 'schedule'],
    ['run.event', 'workflow_dispatch '], ['run.path', '.github/workflows/seed.yml'],
    ['run.path', '.github/workflows/db.yml@main'], ['run.branch', 'feature/main'],
    ['run.branch', 'refs/heads/main'], ['run.status', 'in_progress'],
    ['run.status', 'queued'], ['run.conclusion', 'failure'],
    ['run.conclusion', 'success'], ['run.conclusion', null],
    ['nativeJobs.0.name', 'timeout-guardian'], ['guardianJobs.0.name', limits.job],
    ['nativeJobs.0.status', 'queued'], ['guardianJobs.0.status', 'in_progress'],
    ['nativeJobs.0.conclusion', 'failure'], ['nativeJobs.0.conclusion', 'success'],
    ['guardianJobs.0.conclusion', 'skipped'], ['guardianJobs.0.conclusion', null],
    ['review.runId', '48000001234-8'], ['review.jobId', '145001234502'],
    ['review.guardianJobId', '145001234501'], ['run.id', '48000001235'],
    ['run.attempt', '8'], ['nativeJobs.0.runId', '48000001235'],
    ['guardianJobs.0.runId', '48000001235'], ['nativeJobs.0.attempt', '8'],
    ['guardianJobs.0.attempt', '8'], ['nativeJobs.0.id', 145001234503],
    ['guardianJobs.0.id', 145001234503],
    ...['review.sourceSha', 'run.sourceSha', 'nativeJobs.0.sourceSha', 'guardianJobs.0.sourceSha']
      .flatMap((path) => [
        [path, 'a'.repeat(limits.sourceShaLength)],
        [path, 'B'.repeat(limits.sourceShaLength)],
        [path, 'b'.repeat(limits.sourceShaLength - 1)],
        [path, 'b'.repeat(limits.sourceShaLength + 1)],
        [path, 'g'.repeat(limits.sourceShaLength)],
        [path, null],
      ]),
  ].map(([path, value]) => ({path, value})))('refuses binding or vocabulary mismatch at $path = $value', ({path, value}) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it('refuses a pair sharing a job identity even when both review bindings agree', () => {
    const fixture = visibleUnallocatedFixture();
    fixture.guardianJobs[0].id = fixture.nativeJobs[0].id;
    fixture.review.guardianJobId = fixture.review.jobId;
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: false});
  });

  it.each(['review.runId', 'review.jobId', 'review.guardianJobId', 'run.id', 'run.attempt', 'nativeJobs.0.runId', 'nativeJobs.0.attempt', 'guardianJobs.0.runId', 'guardianJobs.0.attempt']
    .flatMap((path) => ['', '0', '-1', '+7', '07', '7.0', '7e0', ' 7', '7 ', null, 1, false].map((value) => [path, value])))('refuses noncanonical decimal identity at %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['run.repositoryId', 'run.headRepositoryId', 'nativeJobs.0.id', 'guardianJobs.0.id']
    .flatMap((path) => [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '190123456', null, true, 1n].map((value) => [path, value])))('refuses nonpositive or unsafe numeric identity at %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['nativeJobs.0', 'guardianJobs.0'].flatMap((job) =>
    ['runnerId', 'runnerName', 'runnerGroupId', 'runnerGroupName'].flatMap((field) =>
      [0, 1, '', 'GitHub Actions', false, undefined, {}].map((value) => [`${job}.${field}`, value]))))('refuses any non-null assignment field at %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['nativeJobs', 'guardianJobs'].flatMap((path) => [
    [path, []], [path, null], [path, {}], [path, 'one'],
  ]))('refuses a missing or nonarray job collection at %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['nativeJobs', 'guardianJobs'])('refuses duplicate jobs in %s', (path) => {
    const fixture = visibleUnallocatedFixture();
    fixture[path as 'nativeJobs' | 'guardianJobs'].push(visibleUnallocatedClone(fixture[path as 'nativeJobs' | 'guardianJobs'][0]));
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: false});
  });

  it.each(['nativeJobs.0.steps', 'guardianJobs.0.steps'].flatMap((path) => [
    [path, [{name: 'Set up job', status: 'completed', conclusion: 'success'}]],
    [path, [{name: 'Set up job', status: 'completed', conclusion: 'skipped'}]],
    [path, [null]], [path, {}], [path, null],
  ]))('refuses execution or malformed steps at %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each([
    ['nativeJobs.0.labels', ['self-hosted']], ['nativeJobs.0.labels', ['ubuntu-24.04']],
    ['nativeJobs.0.labels', ['ubuntu-latest', 'ubuntu-latest']],
    ['nativeJobs.0.labels', ['ubuntu-latest', 'self-hosted']],
    ['nativeJobs.0.labels', ['Ubuntu-latest']], ['nativeJobs.0.labels', ['']],
    ['nativeJobs.0.labels', null], ['nativeJobs.0.labels', {}],
    ['guardianJobs.0.labels', []], ['guardianJobs.0.labels', ['self-hosted']],
    ['guardianJobs.0.labels', ['ubuntu-latest', 'ubuntu-latest']],
    ['guardianJobs.0.labels', ['ubuntu-latest', 'Linux']],
    ['guardianJobs.0.labels', [new String('ubuntu-latest')]],
    ['guardianJobs.0.labels', null], ['guardianJobs.0.labels', {}],
  ])('refuses incompatible labels at %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['jobListingComplete', 'artifactListingComplete'].flatMap((path) =>
    [false, undefined, null, 1, 'true', {}].map((value) => [path, value])))('refuses incomplete listing evidence at %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['native-db-manifest', 'native-db-recovery', 'native-db-client-smoke', 'native-db-final', 'native-db-private', 'native-db-private-custody', 'native-db-timing-boundary', 'native-db-ci-job'])('refuses exact same-attempt custody %s even when only its retained name survives expiry', (prefix) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('artifactNames', [`${prefix}-48000001234-7`]))).toEqual({verified: false});
  });

  it.each(['native-db-restoration-48000001234-7', 'native-db-restoration-48000001234-7-1', 'native-db-restoration-48000001234-7-48000009999-1', 'native-db-restoration-48000001234-7-'])('refuses exact or suffixed restoration custody %s', (name) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('artifactNames', [name]))).toEqual({verified: false});
  });

  it.each([
    ['native-db-schema-48000001234-7'],
    ['native-db-recovery-48000001234-6', 'native-db-private-custody-48000001234-6'],
    ['native-db-restoration-48000001234-70', 'native-db-restoration-48000001234-6-1'],
    ['native-db-manifest-48000001235-7'],
    ['native-db-final-48000001234-7-extra'],
    ['unrelated-artifact', 'native-db-schema-48000001234-7'],
  ].map((names) => ({names})))('permits unrelated/schema/other-attempt artifact names $names', ({names}) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('artifactNames', names))).toEqual({verified: true});
  });

  it.each([null, {}, '', [''], [null], [1], [true], [new String('artifact')], ['safe', undefined]].map((names) => ({names})))('refuses malformed complete artifact names $names', ({names}) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('artifactNames', names))).toEqual({verified: false});
  });
});

describe('DBV-014 exact inert records and arrays', () => {
  it.each(['', 'review', 'run', 'nativeJobs.0', 'guardianJobs.0'].flatMap((path) =>
    ['missing', 'unknown', 'symbol', 'nonenumerable', 'accessor', 'custom-prototype', 'reflection-error'].map((mode) => [path, mode])))('refuses %s record with %s without evaluating accessors', (path, mode) => {
    const fixture = visibleUnallocatedFixture();
    let target: VisibleUnallocatedRecord = fixture as unknown as VisibleUnallocatedRecord;
    let parent: VisibleUnallocatedRecord | undefined;
    let finalKey: string | undefined;
    for (const key of (path as string).split('.').filter(Boolean)) {
      parent = target;
      finalKey = key;
      target = target[key] as VisibleUnallocatedRecord;
    }
    const key = Object.keys(target)[0];
    const getter = vi.fn(() => {throw new Error('Accessor must stay inert');});
    if (mode === 'missing') delete target[key];
    if (mode === 'unknown') target.extra = true;
    if (mode === 'symbol') Object.defineProperty(target, Symbol('extra'), {value: true});
    if (mode === 'nonenumerable') Object.defineProperty(target, key, {enumerable: false});
    if (mode === 'accessor') Object.defineProperty(target, key, {get: getter});
    if (mode === 'custom-prototype') Object.setPrototypeOf(target, {inherited: true});
    const input = mode === 'reflection-error'
      ? new Proxy(target, {ownKeys() {throw new Error('Reflection refused');}})
      : fixture;
    if (mode === 'reflection-error' && parent && finalKey) parent[finalKey] = input;
    expect(requireVisibleUnallocatedVerifier()(mode === 'reflection-error' && !parent ? input : fixture)).toEqual({verified: false});
    expect(getter).not.toHaveBeenCalled();
  });

  it.each([
    ...Object.keys(visibleUnallocatedFixture()).map((key) => ['', key]),
    ...Object.keys(visibleUnallocatedFixture().review).map((key) => ['review', key]),
    ...Object.keys(visibleUnallocatedFixture().run).map((key) => ['run', key]),
    ...Object.keys(visibleUnallocatedFixture().nativeJobs[0]).map((key) => ['nativeJobs.0', key]),
    ...Object.keys(visibleUnallocatedFixture().guardianJobs[0]).map((key) => ['guardianJobs.0', key]),
  ])('requires own explicit field %s.%s', (path, key) => {
    const fixture = visibleUnallocatedFixture();
    let target: VisibleUnallocatedRecord = fixture as unknown as VisibleUnallocatedRecord;
    for (const part of path.split('.').filter(Boolean)) target = target[part] as VisibleUnallocatedRecord;
    delete target[key];
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: false});
  });

  it.each(['nativeJobs', 'guardianJobs', 'artifactNames', 'nativeJobs.0.labels', 'guardianJobs.0.labels', 'nativeJobs.0.steps', 'guardianJobs.0.steps']
    .flatMap((path) => ['hole', 'extra', 'symbol', 'accessor', 'nonenumerable', 'custom-prototype', 'reflection-error'].map((mode) => [path, mode])))('refuses %s array with %s without evaluating element getters', (path, mode) => {
    const fixture = visibleUnallocatedFixture();
    let parent: VisibleUnallocatedRecord = fixture as unknown as VisibleUnallocatedRecord;
    const parts = path.split('.');
    for (const part of parts.slice(0, -1)) parent = parent[part] as VisibleUnallocatedRecord;
    const key = parts.at(-1)!;
    const target = parent[key] as unknown[];
    const getter = vi.fn(() => {throw new Error('Array accessor must stay inert');});
    if (mode === 'hole') target.length += 1;
    if (mode === 'extra') Object.defineProperty(target, 'extra', {value: true, enumerable: true});
    if (mode === 'symbol') Object.defineProperty(target, Symbol('extra'), {value: true});
    if (mode === 'accessor') Object.defineProperty(target, '0', {get: getter, enumerable: true, configurable: true});
    if (mode === 'nonenumerable') Object.defineProperty(target, '0', {value: target[0], enumerable: false, configurable: true});
    if (mode === 'custom-prototype') Object.setPrototypeOf(target, Object.create(Array.prototype));
    if (mode === 'reflection-error') parent[key] = new Proxy(target, {getOwnPropertyDescriptor() {throw new Error('Array reflection refused');}});
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: false});
    expect(getter).not.toHaveBeenCalled();
  });
});

describe('DBV-014 original provider cancellation clocks', () => {
  it.each([
    {started: '2026-10-08T07:08:09Z', completed: '2026-10-08T07:08:09.000Z'},
    {started: '2026-10-08T07:08:09.000Z', completed: '2026-10-08T07:08:09Z'},
    {started: '2026-10-08T07:08:09.000Z', completed: '2026-10-08T07:08:09.000Z'},
  ])('accepts equal parsed provider instants $started/$completed', ({started, completed}) => {
    const fixture = visibleUnallocatedFixture();
    for (const job of [fixture.nativeJobs[0], fixture.guardianJobs[0]]) {
      job.startedAt = started;
      job.completedAt = completed;
    }
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });

  it('accepts independently timed zero-duration jobs when review follows both', () => {
    const fixture = visibleUnallocatedFixture();
    fixture.nativeJobs[0].startedAt = '2026-10-08T07:08:08.999Z';
    fixture.nativeJobs[0].completedAt = fixture.nativeJobs[0].startedAt;
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });

  it.each(['nativeJobs.0.startedAt', 'nativeJobs.0.completedAt', 'guardianJobs.0.startedAt', 'guardianJobs.0.completedAt', 'review.verifiedAt']
    .flatMap((path) => [null, undefined, 0, new Date('2026-10-08T07:08:09.000Z'),
      '2026-10-08T07:08:09.00Z', '2026-10-08T07:08:09.0000Z', '2026-10-08T07:08:09+00:00',
      '2026-10-08t07:08:09.000z', '2026-10-08 07:08:09.000Z', '2026-02-30T07:08:09.000Z',
      '2026-10-08T24:00:00.000Z', '2026-10-08T07:08:60.000Z', '+010000-10-08T07:08:09.000Z',
      '1969-12-31T23:59:59.999Z', '2026-10-08T07:08:09.000Z '].map((value) => [path, value])))('refuses invalid canonical clock %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path as string, value))).toEqual({verified: false});
  });

  it.each(['nativeJobs.0.startedAt', 'guardianJobs.0.startedAt'].flatMap((path) =>
    ['2026-10-08T07:08:08.999Z', '2026-10-08T07:08:09.001Z'].map((value) => [path, value])))('refuses nonzero provider duration at %s = %s', (path, value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace(path, value))).toEqual({verified: false});
  });

  it.each(['2026-10-08T07:08:09Z', '2026-10-08T07:08:09.000Z', '2026-10-08T07:08:08.999Z'])('requires canonical millisecond review strictly after both completions: %s', (value) => {
    expect(requireVisibleUnallocatedVerifier()(visibleUnallocatedReplace('review.verifiedAt', value))).toEqual({verified: false});
  });

  it.each(['nativeJobs', 'guardianJobs'])('requires review after %s completion even with equal provider clocks', (collection) => {
    const fixture = visibleUnallocatedFixture();
    fixture[collection as 'nativeJobs' | 'guardianJobs'][0].startedAt = fixture.review.verifiedAt;
    fixture[collection as 'nativeJobs' | 'guardianJobs'][0].completedAt = fixture.review.verifiedAt;
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: false});
  });

  it('allows epoch-zero completion followed by a strictly later canonical review', () => {
    const fixture = visibleUnallocatedFixture();
    for (const job of [fixture.nativeJobs[0], fixture.guardianJobs[0]]) {
      job.startedAt = '1970-01-01T00:00:00Z';
      job.completedAt = '1970-01-01T00:00:00.000Z';
    }
    fixture.review.verifiedAt = '1970-01-01T00:00:00.001Z';
    expect(requireVisibleUnallocatedVerifier()(fixture)).toEqual({verified: true});
  });
});

describe('DBV-014 mechanically shared native evidence clock', () => {
  it.each([
    ['1970-01-01T00:00:00.000Z', undefined, '1970-01-01T00:00:00.000Z'],
    ['2024-02-29T12:34:56.789Z', false, '2024-02-29T12:34:56.789Z'],
    ['2026-10-08T07:08:09Z', true, '2026-10-08T07:08:09.000Z'],
    ['2026-10-08T07:08:09.123Z', true, '2026-10-08T07:08:09.123Z'],
    ['9999-12-31T23:59:59.999Z', false, '9999-12-31T23:59:59.999Z'],
  ])('preserves canonical native evidence clock %s mode %s', (value, mode, canonical) => {
    expect(requireVisibleUnallocatedClock()(value, mode as boolean | undefined)).toBe(Date.parse(canonical as string));
  });

  it('defaults to millisecond-only review mode', () => {
    expect(requireVisibleUnallocatedClock()('2026-10-08T07:08:09Z')).toBeNull();
  });

  it.each([undefined, null, 0, true, new String('2026-10-08T07:08:09.000Z'), new Date('2026-10-08T07:08:09.000Z'),
    '2023-02-29T12:00:00.000Z', '2026-02-30T00:00:00.000Z', '2026-10-08T24:00:00.000Z',
    '2026-10-08T07:08:60.000Z', '1969-12-31T23:59:59.999Z', '+002026-10-08T07:08:09.000Z',
    '2026-10-08T07:08:09.00Z', '2026-10-08T07:08:09.0000Z', '2026-10-08T07:08:09+00:00',
    '2026-10-08T07:08:09.000z', '2026-10-08T07:08:09.000Z\n'])('refuses malformed/nonprimitive clock %s in both declared modes', (value) => {
    expect(requireVisibleUnallocatedClock()(value, false)).toBeNull();
    expect(requireVisibleUnallocatedClock()(value, true)).toBeNull();
  });
});

describe('DBV-014 workflow integration and narrowly scoped exemptions', () => {
  it('requires native validation when the new verifier path changes on trusted main', () => {
    expect(executeVisibleUnallocatedSelector()).toMatch(/^run=true$/m);
  });

  it('requires native validation when the original changed-file diff cannot be computed', () => {
    expect(executeVisibleUnallocatedSelector({computable: false})).toMatch(/^run=true$/m);
  });

  it.each(['push', 'pull_request'])('classifies the new module in the %s DB trigger paths', (event) => {
    const source = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    const block = source.match(new RegExp(`  ${event}:\\r?\\n([\\s\\S]*?)(?=\\r?\\n  [a-z_]+:|\\r?\\n[a-z_]+:)`))?.[1];
    expect(block, 'the existing DB event path block must exist').toContain('scripts/pgtap/unallocated-cancellation.mjs');
  });

  it('allows the reviewed exact never-assigned native and guardian pair without any artifact body or native call', async () => {
    requireVisibleUnallocatedVerifier();
    const result = await executeVisibleUnallocatedPreflight();
    expect(result).toMatchObject({failed: false, failures: [], thrown: undefined, forbiddenCalls: []});
    expect(result.observedAttempts).toContainEqual({runId: Number(visibleUnallocatedFixture().run.id), attempt: Number(visibleUnallocatedFixture().run.attempt)});
  });

  it('allows resolved hosted native labels through the same two exact exceptions', async () => {
    requireVisibleUnallocatedVerifier();
    const pair = visibleUnallocatedReplace('nativeJobs.0.labels', ['ubuntu-latest']);
    expect(await executeVisibleUnallocatedPreflight({pair})).toMatchObject({failed: false, forbiddenCalls: []});
  });

  it('permits a same-attempt schema-only artifact without downloading its body', async () => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({artifactNames: ['native-db-schema-48000001234-7']}))
      .toMatchObject({failed: false, forbiddenCalls: []});
  });

  it.each([
    {label: 'absent review', reviews: []},
    {label: 'duplicate review', reviews: [visibleUnallocatedFixture().review, visibleUnallocatedFixture().review]},
    {label: 'review for another attempt', reviews: [{...visibleUnallocatedFixture().review, runId: '48000001234-6'}]},
    {label: 'wrong proof kind', reviews: [{...visibleUnallocatedFixture().review, completionKind: 'github-hosted-job-decommission'}]},
    {label: 'a bare claimed absence record', reviews: [{runId: '48000001234-7', completionKind: 'unallocated-cancellation'}]},
  ])('keeps the predecessor blocked for $label', async ({reviews}) => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({reviews})).toMatchObject({failed: true});
  });

  it.each([
    ['nativeJobs.0.runnerId', 190123456], ['nativeJobs.0.runnerName', 'GitHub Actions 190123456'],
    ['nativeJobs.0.runnerGroupId', 190123456], ['nativeJobs.0.runnerGroupName', 'GitHub Actions'],
    ['guardianJobs.0.runnerId', 190123456], ['guardianJobs.0.runnerName', 'GitHub Actions 190123456'],
    ['guardianJobs.0.runnerGroupId', 190123456], ['guardianJobs.0.runnerGroupName', 'GitHub Actions'],
    ['nativeJobs.0.steps', [{name: 'Set up job', status: 'completed', conclusion: 'success'}]],
    ['guardianJobs.0.steps', [{name: 'Set up job', status: 'completed', conclusion: 'cancelled'}]],
    ['nativeJobs.0.labels', ['self-hosted']], ['guardianJobs.0.labels', []],
    ['nativeJobs.0.conclusion', 'failure'], ['guardianJobs.0.conclusion', 'skipped'],
    ['nativeJobs.0.runId', '48000001235'], ['guardianJobs.0.sourceSha', 'a'.repeat(limits.sourceShaLength)],
    ['nativeJobs', []], ['guardianJobs', []],
  ])('retains worker/recovery refusal for mixed provider evidence at %s', async (path, value) => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({pair: visibleUnallocatedReplace(path as string, value)})).toMatchObject({failed: true});
  });

  it('does not exempt a duplicate native job', async () => {
    requireVisibleUnallocatedVerifier();
    const pair = visibleUnallocatedFixture();
    pair.nativeJobs.push(visibleUnallocatedClone(pair.nativeJobs[0]));
    expect(await executeVisibleUnallocatedPreflight({pair})).toMatchObject({failed: true});
  });

  it('does not exempt a duplicate guardian job', async () => {
    requireVisibleUnallocatedVerifier();
    const pair = visibleUnallocatedFixture();
    pair.guardianJobs.push(visibleUnallocatedClone(pair.guardianJobs[0]));
    expect(await executeVisibleUnallocatedPreflight({pair})).toMatchObject({failed: true});
  });

  it.each([
    {head_sha: 'a'.repeat(limits.sourceShaLength)}, {head_branch: 'other'},
    {event: 'pull_request'}, {path: '.github/workflows/seed.yml'},
    {repository: {id: 190123456, full_name: 'OGUN01/other'}},
    {head_repository: {id: 190123457, full_name: limits.repository}},
    {head_repository: {id: 190123456, full_name: 'OGUN01/other'}},
    {status: 'in_progress'}, {conclusion: 'success'}, {run_attempt: 8}, {id: 48000001235},
  ])('refuses untrusted original selected-attempt run metadata %s', async (mutateRun) => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({mutateRun})).toMatchObject({failed: true});
  });

  it.each([
    'native-db-manifest', 'native-db-recovery', 'native-db-client-smoke', 'native-db-final',
    'native-db-private', 'native-db-private-custody', 'native-db-timing-boundary', 'native-db-ci-job',
  ])('keeps expired conflicting %s custody authoritative without downloading it', async (prefix) => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({artifactNames: [`${prefix}-48000001234-7`]})).toMatchObject({failed: true});
  });

  it.each(['native-db-restoration-48000001234-7', 'native-db-restoration-48000001234-7-1', 'native-db-restoration-48000001234-7-48000009999-1'])('retains refusal for restoration custody %s', async (name) => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({artifactNames: [name]})).toMatchObject({failed: true});
  });

  it('refuses an incomplete original artifact listing', async () => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({artifactTotal: 1})).toMatchObject({failed: true});
  });

  it('refuses an incomplete original job listing', async () => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({jobsTotal: ['native', 'guardian', 'unseen'].length})).toMatchObject({failed: true});
  });

  it('retains the allocated-worker gate for an earlier attempt of this same run', async () => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({olderAssigned: true})).toMatchObject({failed: true});
  });

  it('retains the older armed-recovery scan despite a reviewed later never-assigned pair', async () => {
    requireVisibleUnallocatedVerifier();
    expect(await executeVisibleUnallocatedPreflight({artifactNames: ['native-db-recovery-48000001234-6']})).toMatchObject({failed: true});
  });

  it('the inert fixture reaches the existing original-attempt observation without network or process execution', async () => {
    const result = await executeVisibleUnallocatedPreflight();
    expect(result.thrown, String(result.thrown)).toBeUndefined();
    expect(result.observedAttempts).toContainEqual({runId: Number(visibleUnallocatedFixture().run.id), attempt: Number(visibleUnallocatedFixture().run.attempt)});
    expect(result.forbiddenCalls).toEqual([]);
  });
});
