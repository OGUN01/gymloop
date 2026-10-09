import { readFileSync } from 'node:fs';
import { createRequire, registerHooks } from 'node:module';
import { isAbsolute, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { compileFunction, constants as vmConstants } from 'node:vm';
import { describe, expect, it, vi } from 'vitest';

// DBV-005/007/008/012: independently execute the deployed Actions boundary.
// The workflow script is loaded only as opaque executable SUT, never a fixture.
const workflowPath = resolve('.github/workflows/db.yml');
const stepName = "Require the previous armed attempt's verified restoration";
const baselineId = 37519113387;
const baselineSha = '6802d201df51afc4adc77ade6fa8394dfea5f9f0';
const currentId = 37519113491;
const currentSha = 'd'.repeat(40);
const previousId = 37519113439;
const workerStep = 'Validate the full native suite with outside-worker recovery custody';
const requireFromRoot = createRequire(resolve('package.json'));

type Run = {
  id: number;
  head_sha: string;
  run_attempt: number;
  status: string;
  conclusion: string | null;
  event: string;
  head_branch: string;
  created_at: string;
  updated_at: string;
  path: string;
  repository: { full_name: string };
  head_repository: { full_name: string };
};

type Job = {
  id: number;
  name: string;
  status: string;
  conclusion: string | null;
  head_sha: string;
  run_attempt: number;
  runner_id: number;
  runner_name: string;
  runner_group_name: string;
  labels: string[];
  started_at: string | null;
  completed_at: string | null;
  steps: { name: string; number: number; status: string; conclusion: string | null }[];
};

type Scenario = {
  pages?: unknown[];
  baseline?: Partial<Run>;
  currentMetadata?: Partial<Run> | null;
  currentAttempt?: number;
  baselineJobs?: Job[];
  jobs?: Map<string, Job[]>;
  runRecords?: Map<number, Run>;
};

function run(id: number, overrides: Partial<Run> = {}): Run {
  return {
    id,
    head_sha: id === baselineId ? baselineSha : currentSha,
    run_attempt: 1,
    status: 'completed',
    conclusion: id === baselineId ? 'success' : 'failure',
    event: 'push',
    head_branch: 'main',
    created_at: '2026-10-07T03:10:00Z',
    updated_at: '2026-10-07T03:15:00Z',
    path: '.github/workflows/db.yml',
    repository: { full_name: 'OGUN01/gymloop' },
    head_repository: { full_name: 'OGUN01/gymloop' },
    ...overrides,
  };
}

function job(name: string, overrides: Partial<Job> = {}): Job {
  return {
    id: name === 'pgtap' ? 71001 : name === 'timeout-guardian' ? 71002 : 71003,
    name,
    status: 'completed',
    conclusion: 'success',
    head_sha: baselineSha,
    run_attempt: 1,
    runner_id: 901,
    runner_name: 'GitHub Actions 901',
    runner_group_name: 'GitHub Actions',
    labels: ['ubuntu-latest'],
    started_at: '2026-10-07T02:10:00Z',
    completed_at: '2026-10-07T03:00:00Z',
    steps: [{ name: workerStep, number: 1, status: 'completed', conclusion: 'success' }],
    ...overrides,
  };
}

function skippedJobs(): Job[] {
  return ['pgtap', 'timeout-guardian'].map(name => job(name, {
    head_sha: currentSha,
    conclusion: 'skipped',
    started_at: null,
    completed_at: null,
    steps: [],
  }));
}

function successfulBaselineJobs(): Job[] {
  return ['migrate', 'pgtap', 'seed-dry-run'].map(name => job(name));
}

function opaqueScript(): string {
  const lines = readFileSync(workflowPath, 'utf8').split(/\r?\n/);
  const jobIndex = lines.findIndex(line => line.trim() === 'database-recovery-preflight:');
  if (jobIndex === -1) throw new Error('Required Actions job is absent.');
  const jobIndent = lines[jobIndex].search(/\S/);
  let jobEnd = lines.length;
  for (let index = jobIndex + 1; index < lines.length; index += 1) {
    if (lines[index].trim() && lines[index].search(/\S/) <= jobIndent) {
      jobEnd = index;
      break;
    }
  }
  const stepIndex = lines.findIndex((line, index) => index > jobIndex && index < jobEnd
    && /^\s*(?:-\s*)?name:/.test(line)
    && line.trim().replace(/^(?:-\s*)?name:\s*/, '').replace(/^(['"])(.*)\1$/, '$2') === stepName);
  if (stepIndex === -1) throw new Error('Required Actions boundary is absent.');
  const stepIndent = lines[stepIndex].search(/\S/) - (lines[stepIndex].trim().startsWith('-') ? 0 : 2);
  let scriptIndex = -1;
  for (let index = stepIndex + 1; index < lines.length; index += 1) {
    if (lines[index].trim() && lines[index].search(/\S/) <= stepIndent) break;
    if (/^\s*script:\s*\|\s*$/.test(lines[index])) {
      scriptIndex = index;
      break;
    }
  }
  if (scriptIndex === -1) throw new Error('Required Actions script is absent.');
  const scriptIndent = lines[scriptIndex].search(/\S/);
  const body: string[] = [];
  for (let index = scriptIndex + 1; index < lines.length; index += 1) {
    if (lines[index].trim() && lines[index].search(/\S/) <= scriptIndent) break;
    body.push(lines[index]);
  }
  const firstCode = body.find(line => line.trim());
  if (!firstCode) throw new Error('Required Actions script is empty.');
  const bodyIndent = firstCode.search(/\S/);
  const script = body.map(line => line.slice(bodyIndent)).join('\n');
  if ((script.match(/^[ \t]*const[ \t]+\{[ \t]*readFile[ \t]*\}[ \t]*=[ \t]*await[ \t]+import\('node:fs\/promises'\);[ \t]*$/gm) ?? []).length !== 1) throw new Error('Declared readFile fixture import differs.');
  if (/\$\{\{/.test(script)) throw new Error('Unspecified Actions expression in fixture boundary.');
  return script.replace(/^[ \t]*const[ \t]+\{[ \t]*readFile[ \t]*\}[ \t]*=[ \t]*await[ \t]+import\('node:fs\/promises'\);[ \t]*$/gm, '');
}

async function execute(scenario: Scenario = {}) {
  const attempt = scenario.currentAttempt ?? 1;
  const baseline = run(baselineId, {
    head_sha: baselineSha,
    conclusion: 'success',
    created_at: '2026-10-07T01:00:00Z',
    updated_at: '2026-10-07T03:00:00Z',
    ...scenario.baseline,
  });
  const current = run(currentId, {
    status: 'in_progress', conclusion: null, run_attempt: attempt, ...(scenario.currentMetadata ?? {}),
  });
  const records = new Map([[baselineId, baseline], [currentId, current], ...(scenario.runRecords ?? [])]);
  for (const page of scenario.pages ?? []) {
    if (!Array.isArray(page)) continue;
    for (const record of page) {
      if (record && typeof record === 'object' && typeof record.id === 'number'
        && record.id !== baselineId && record.id !== currentId && !records.has(record.id)) {
        records.set(record.id, record as Run);
      }
    }
  }
  const failures: string[] = [];
  const logs: string[] = [];
  const artifactsRequested: number[] = [];
  const jobsRequested: { runId: number; attempt: number }[] = [];
  let pagesVisited = 0;
  let downloads = 0;
  let fixturePortErrors = 0;
  const listWorkflowRuns = vi.fn();
  const listJobsForWorkflowRunAttempt = vi.fn();
  const listJobsForWorkflowRun = vi.fn();
  const listWorkflowRunArtifacts = vi.fn();
  const getWorkflowRun = vi.fn(async ({ run_id }: { run_id: number }) => {
    if (Number(run_id) === currentId && scenario.currentMetadata === null) {
      throw Object.assign(new Error('Current workflow metadata is unavailable.'), { status: 404 });
    }
    const record = records.get(Number(run_id));
    if (!record) {
      fixturePortErrors += 1;
      throw new Error('Fixture workflow metadata is absent.');
    }
    return { data: record };
  });
  const paginate = Object.assign(vi.fn(async (route: unknown, parameters: {
    run_id: number; attempt_number?: number; filter?: string;
  }) => {
    if (route === listWorkflowRunArtifacts) {
      artifactsRequested.push(Number(parameters.run_id));
      return [];
    }
    if (route === listJobsForWorkflowRunAttempt || route === listJobsForWorkflowRun) {
      const requestedId = Number(parameters.run_id);
      const requestedAttempt = Number(parameters.attempt_number ?? records.get(requestedId)?.run_attempt ?? 1);
      jobsRequested.push({ runId: requestedId, attempt: requestedAttempt });
      if (requestedId === baselineId) return scenario.baselineJobs ?? successfulBaselineJobs();
      return scenario.jobs?.get(`${requestedId}-${requestedAttempt}`) ?? skippedJobs();
    }
    fixturePortErrors += 1;
    throw new Error('Undeclared direct pagination route.');
  }), {
    iterator: vi.fn(async function* (route: unknown) {
      if (route !== listWorkflowRuns) {
        fixturePortErrors += 1;
        throw new Error('Undeclared iterator route.');
      }
      for (const data of scenario.pages ?? [[current, baseline]]) {
        pagesVisited += 1;
        yield { data, status: 200, headers: {}, url: 'https://api.github.invalid/workflow-runs' };
      }
    }),
  });
  const github = {
    paginate,
    rest: {
      actions: {
        listWorkflowRuns,
        listJobsForWorkflowRunAttempt,
        listJobsForWorkflowRun,
        listWorkflowRunArtifacts,
        getWorkflowRun,
        downloadArtifact: vi.fn(async () => { downloads += 1; throw new Error('Artifact transport is forbidden in fixtures.'); }),
      },
    },
  };
  const core = {
    setFailed: (message: unknown) => failures.push(String(message)),
    info: (message: unknown) => logs.push(String(message)),
    warning: (message: unknown) => logs.push(String(message)),
    notice: (message: unknown) => logs.push(String(message)),
    debug: (message: unknown) => logs.push(String(message)),
    setOutput: vi.fn(),
  };
  const context = {
    repo: { owner: 'OGUN01', repo: 'gymloop' },
    runId: currentId,
    sha: currentSha,
    eventName: 'push',
    ref: 'refs/heads/main',
    payload: { repository: { full_name: 'OGUN01/gymloop' } },
  };
  let threw = false;
  let runtimeTypeError = false;
  const preflight = compileFunction(`return (async () => {\n${opaqueScript()}\n})();`,
    ['github', 'context', 'core', 'require', 'readFile'], {
      importModuleDynamically: vmConstants.USE_MAIN_CONTEXT_DEFAULT_LOADER,
    });
  // Adapt native module resolution and the declared readFile import only.
  // Verifier behavior and all existing filesystem reads remain unchanged.
  const loader = registerHooks({
    resolve(specifier, context, nextResolve) {
      return nextResolve(isAbsolute(specifier) ? pathToFileURL(specifier).href : specifier, context);
    },
  });
  try {
    await preflight(github, context, core, requireFromRoot, async (path: string, encoding?: string) => {
      if ((encoding === 'utf8' || encoding === undefined) && path === '.dbv/current-attempt.txt') return encoding === undefined ? Buffer.from(`${attempt}\n`, 'utf8') : `${attempt}\n`;
      if ((encoding === 'utf8' || encoding === undefined) && path === '.dbv/operator-workload-teardowns.json') return encoding === undefined ? Buffer.from('[]\n', 'utf8') : '[]\n';
      if ((encoding === 'utf8' || encoding === undefined) && path === '.dbv/operator-owner-baselines.json') return encoding === undefined ? Buffer.from('[]\n', 'utf8') : '[]\n';
      return requireFromRoot('node:fs/promises').readFile(path, encoding);
    });
  } catch (caught) {
    const code = caught && typeof caught === 'object' && 'code' in caught ? String(caught.code) : '';
    if (code.startsWith('ERR_')) throw new Error(`Holdout execution setup port failed: ${code}.`, { cause: caught });
    runtimeTypeError = caught instanceof TypeError
      || Boolean(caught && typeof caught === 'object' && 'name' in caught && caught.name === 'TypeError');
    threw = true;
  } finally {
    loader.deregister();
  }
  if (fixturePortErrors) throw new Error('Holdout metadata fixture port failed.');
  return { refused: threw || failures.length > 0, runtimeTypeError, pagesVisited, downloads, jobsRequested, artifactsRequested, getWorkflowRun };
}

describe('DBV-005/007/008/012 held Actions preflight pagination contract', () => {
  it('accepts successful serial adoption with normalized empty pages', async () => {
    const result = await execute({ pages: [[], [], [run(baselineId, { head_sha: baselineSha, conclusion: 'success' })]] });
    expect(result.refused).toBe(false);
    expect(result.pagesVisited).toBe(3);
    expect(result.downloads).toBe(0);
  });

  it('accepts several unarmed skipped workflows across an empty middle page', async () => {
    const result = await execute({ pages: [[run(previousId)], [], [run(previousId - 1)], [run(baselineId)]] });
    expect(result.refused).toBe(false);
    expect(result.pagesVisited).toBe(4);
    expect(result.downloads).toBe(0);
  });

  it('does not require fabricated recovery artifacts for skipped native and guardian jobs', async () => {
    const result = await execute({ pages: [[run(previousId)], [run(baselineId)]] });
    expect(result.refused).toBe(false);
    expect(result.downloads).toBe(0);
  });

  it('stops historical adoption at the exact baseline boundary', async () => {
    const older = run(baselineId - 9, { run_attempt: 3 });
    const result = await execute({ pages: [[run(baselineId), older]], jobs: new Map([
      [`${older.id}-3`, [job('pgtap', { conclusion: 'failure', head_sha: currentSha })]],
    ]) });
    expect(result.refused).toBe(false);
    expect(result.jobsRequested.some(request => request.runId === older.id)).toBe(false);
  });

  it.each(['migrate', 'pgtap', 'seed-dry-run'])('rejects adoption when baseline %s was skipped', async name => {
    const result = await execute({ baselineJobs: successfulBaselineJobs().map(record => record.name === name
      ? { ...record, conclusion: 'skipped', steps: [], started_at: null, completed_at: null } : record) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested).toContainEqual({ runId: baselineId, attempt: 1 });
  });

  it.each(['migrate', 'pgtap', 'seed-dry-run'])('rejects adoption when baseline %s has no actual job', async name => {
    const result = await execute({ baselineJobs: successfulBaselineJobs().filter(record => record.name !== name) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested).toContainEqual({ runId: baselineId, attempt: 1 });
  });

  it('rejects a successful-looking baseline whose source differs', async () => {
    const result = await execute({ baseline: { head_sha: currentSha } });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.getWorkflowRun.mock.calls.some(([parameters]) => Number(parameters.run_id) === baselineId)).toBe(true);
  });

  it('rejects adoption before baseline completion', async () => {
    const result = await execute({ baseline: { status: 'in_progress', conclusion: null } });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.getWorkflowRun.mock.calls.some(([parameters]) => Number(parameters.run_id) === baselineId)).toBe(true);
  });

  it('accepts the exact completed cutover baseline with unrelated drift failure and successful required jobs', async () => {
    const result = await execute({ baseline: { conclusion: 'failure' } });
    expect(result.refused).toBe(false);
    expect(result.jobsRequested).toContainEqual({ runId: baselineId, attempt: 1 });
  });

  it('accepts verified cutover metadata and fully exhausted newer history without baseline listing membership', async () => {
    const result = await execute({ pages: [[run(previousId)], []] });
    expect(result.refused).toBe(false);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.pagesVisited).toBe(2);
  });

  it.each([null, { workflow_runs: [] }, 'unavailable'])('fails closed for malformed normalized page %j', async page => {
    const result = await execute({ pages: [page, [run(baselineId)]] });
    expect(result.refused).toBe(true);
    expect(result.pagesVisited).toBeGreaterThan(0);
  });

  it('finds an unresolved executed worker on a later page before baseline', async () => {
    const result = await execute({ pages: [[], [run(previousId)], [], [run(baselineId)]], jobs: new Map([
      [`${previousId}-1`, [job('pgtap', { head_sha: currentSha, conclusion: 'cancelled',
        steps: [{ name: workerStep, number: 1, status: 'completed', conclusion: 'cancelled' }] }), job('timeout-guardian', { head_sha: currentSha, conclusion: 'skipped', steps: [] })]],
    ]) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested.some(request => request.runId === previousId)).toBe(true);
    expect(result.downloads).toBe(0);
  });

  it('refuses an executed guardian without restoration evidence even when native was skipped', async () => {
    const result = await execute({ pages: [[run(previousId)], [run(baselineId)]], jobs: new Map([
      [`${previousId}-1`, [skippedJobs()[0], job('timeout-guardian', { head_sha: currentSha })]],
    ]) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested.some(request => request.runId === previousId)).toBe(true);
    expect(result.downloads).toBe(0);
  });

  it('scans earlier attempts of the current workflow before permitting retry', async () => {
    const result = await execute({ currentAttempt: 2, pages: [[run(currentId, { run_attempt: 2 })], [run(baselineId)]], jobs: new Map([
      [`${currentId}-1`, [job('pgtap', { head_sha: currentSha, conclusion: 'timed_out' }), job('timeout-guardian', { head_sha: currentSha, conclusion: 'skipped', steps: [] })]],
    ]) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested).toContainEqual({ runId: currentId, attempt: 1 });
    expect(result.downloads).toBe(0);
  });

  it('permits an unarmed earlier current attempt without operator teardown declarations', async () => {
    const result = await execute({ currentAttempt: 2, pages: [[], [run(baselineId)]] });
    expect(result.refused).toBe(false);
    expect(result.getWorkflowRun.mock.calls.some(([parameters]) => Number(parameters.run_id) === currentId)).toBe(true);
    expect(result.jobsRequested).toContainEqual({ runId: currentId, attempt: 1 });
    expect(result.downloads).toBe(0);

    const unavailableOrMismatched: (Partial<Run> | null)[] = [
      null,
      { id: previousId },
      { head_sha: baselineSha },
      { event: 'pull_request' },
      { head_branch: 'release' },
      { run_attempt: 1 },
    ];
    for (const currentMetadata of unavailableOrMismatched) {
      const invalid = await execute({ currentAttempt: 2, currentMetadata, pages: [[], [run(baselineId)]] });
      expect(invalid.refused).toBe(true);
      expect(invalid.runtimeTypeError).toBe(false);
      expect(invalid.getWorkflowRun.mock.calls.some(([parameters]) => Number(parameters.run_id) === currentId)).toBe(true);
      expect(invalid.jobsRequested.some(request => request.runId === currentId)).toBe(false);
      expect(invalid.downloads).toBe(0);
    }

    const unresolved = await execute({ currentAttempt: 2, pages: [[], [run(baselineId)]], jobs: new Map([
      [`${currentId}-1`, [job('pgtap', { head_sha: currentSha, conclusion: 'cancelled' }),
        job('timeout-guardian', { head_sha: currentSha, conclusion: 'skipped', steps: [] })]],
    ]) });
    expect(unresolved.refused).toBe(true);
    expect(unresolved.runtimeTypeError).toBe(false);
    expect(unresolved.getWorkflowRun.mock.calls.some(([parameters]) => Number(parameters.run_id) === currentId)).toBe(true);
    expect(unresolved.jobsRequested).toContainEqual({ runId: currentId, attempt: 1 });
    expect(unresolved.downloads).toBe(0);
  });

  it('inspects prior attempts of a newer skipped workflow', async () => {
    const result = await execute({ pages: [[run(previousId, { run_attempt: 2 })], [run(baselineId)]],
      runRecords: new Map([[previousId, run(previousId, { run_attempt: 2 })]]), jobs: new Map([
        [`${previousId}-1`, [job('pgtap', { head_sha: currentSha, conclusion: 'failure' }), job('timeout-guardian', { head_sha: currentSha, conclusion: 'skipped', steps: [] })]],
        [`${previousId}-2`, skippedJobs()],
    ]) });
    expect(result.refused).toBe(true);
    expect(result.runtimeTypeError).toBe(false);
    expect(result.jobsRequested).toContainEqual({ runId: previousId, attempt: 1 });
    expect(result.downloads).toBe(0);
  });
});
