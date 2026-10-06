import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { constants as vmConstants, runInThisContext } from 'node:vm';
import { beforeAll, describe, expect, it, vi } from 'vitest';

// Independent integration fixtures from the frozen DBV transport contract.
// The workflow is parsed and executed as the system under test; its script is
// never displayed or rewritten, apart from explicit GitHub expression inputs.
type Run = {
  id: number;
  run_attempt: number;
  head_sha: string;
  head_branch: string;
  event: string;
  status: string;
  conclusion: string | null;
};
type Job = {
  id: number;
  name: string;
  head_sha: string;
  status: string;
  conclusion: string;
  runner_id: number;
  runner_name: string;
  labels: string[];
  steps: { name: string; status: string; conclusion: string; number: number }[];
};
type Workflow = {
  jobs: Record<string, { steps?: { name?: string; with?: { script?: string } }[] }>;
};
type ApiParameters = { run_id?: number | string; attempt_number?: number; [key: string]: unknown };
type Fixture = {
  attempt?: number;
  pages?: unknown[];
  baseline?: Partial<Run>;
  baselineJobs?: Job[];
  jobs?: Record<string, unknown>;
  artifacts?: Record<string, unknown>;
};

const IDS = { baseline: 37519113387, current: 37520000000, recent: 37519999999, older: 37519113386 };
const BASELINE_SOURCE = '6802d201df51afc4adc77ade6fa8394dfea5f9f0';
const CURRENT_SOURCE = 'a'.repeat(40);
const localRequire = createRequire(import.meta.url);
const eslintRequire = createRequire(localRequire.resolve('eslint/package.json'));
const yaml = eslintRequire('js-yaml') as { load: (text: string) => unknown };
let preflightScript: string;

function run(id = IDS.baseline, overrides: Partial<Run> = {}): Run {
  return {
    id,
    run_attempt: 1,
    head_sha: id === IDS.baseline ? BASELINE_SOURCE : CURRENT_SOURCE,
    head_branch: 'main',
    event: 'push',
    status: 'completed',
    conclusion: 'success',
    ...overrides,
  };
}

function job(name: string, conclusion = 'success', overrides: Partial<Job> = {}): Job {
  return {
    id: 901,
    name,
    head_sha: CURRENT_SOURCE,
    status: 'completed',
    conclusion,
    runner_id: 41,
    runner_name: 'synthetic-hosted-worker',
    labels: ['ubuntu-latest'],
    steps: [],
    ...overrides,
  };
}

function baselineJobs(): Job[] {
  return ['migrate', 'pgtap', 'seed-dry-run'].map(name => job(name, 'success', { head_sha: BASELINE_SOURCE }));
}

function skippedJobs(): Job[] {
  return [job('preflight', 'failure'), job('pgtap', 'skipped'), job('timeout-guardian', 'skipped')];
}

beforeAll(() => {
  const workflow = yaml.load(readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8')) as Workflow;
  const steps = Object.values(workflow.jobs).flatMap(value => value.steps ?? []);
  const matches = steps.filter(step => step.name === "Require the previous armed attempt's verified restoration");
  expect(matches).toHaveLength(1);
  const extracted = matches[0]?.with?.script;
  expect(typeof extracted).toBe('string');
  preflightScript = extracted as string;
});

async function executePreflight(fixture: Fixture = {}) {
  const attempt = fixture.attempt ?? 1;
  const baseline = run(IDS.baseline, fixture.baseline);
  const current = run(IDS.current, { run_attempt: attempt });
  const pages = fixture.pages ?? [[baseline]];
  const jobsByAttempt: Record<string, unknown> = {
    [`${IDS.baseline}-1`]: fixture.baselineJobs ?? baselineJobs(),
    ...fixture.jobs,
  };
  const artifactsByRun = fixture.artifacts ?? {};
  const failed = vi.fn();
  const downloadArtifact = vi.fn(async () => {
    throw new Error('Synthetic fixture forbids artifact transport.');
  });
  const listWorkflowRuns = vi.fn();
  const listJobsForWorkflowRunAttempt = vi.fn();
  const listWorkflowRunArtifacts = vi.fn();
  const getWorkflowRun = vi.fn(async (parameters: ApiParameters) => ({
    data: Number(parameters.run_id) === IDS.current ? current : baseline,
  }));
  const visitedPages: unknown[] = [];
  const iterator = vi.fn(async function* (endpoint: unknown) {
    if (endpoint !== listWorkflowRuns) throw new Error('Unexpected paginated iterator endpoint.');
    for (const page of pages) {
      visitedPages.push(page);
      yield { data: page };
    }
  });
  const paginate = Object.assign(vi.fn(async (endpoint: unknown, parameters: ApiParameters) => {
    if (endpoint === listJobsForWorkflowRunAttempt) {
      const key = `${parameters.run_id}-${parameters.attempt_number}`;
      if (!(key in jobsByAttempt)) throw new Error(`Missing synthetic job fixture ${key}.`);
      return jobsByAttempt[key];
    }
    if (endpoint === listWorkflowRunArtifacts) return artifactsByRun[String(parameters.run_id)] ?? [];
    throw new Error('Unexpected direct pagination endpoint.');
  }), { iterator });
  const github = { rest: { actions: {
    getWorkflowRun,
    listWorkflowRuns,
    listJobsForWorkflowRunAttempt,
    listWorkflowRunArtifacts,
    downloadArtifact,
  } }, paginate };
  const context = {
    repo: { owner: 'OGUN01', repo: 'gymloop' },
    runId: IDS.current,
    sha: CURRENT_SOURCE,
    ref: 'refs/heads/main',
    eventName: 'push',
    payload: { repository: { full_name: 'OGUN01/gymloop' } },
  };
  const core = {
    setFailed: failed,
    info: vi.fn(),
    warning: vi.fn(),
    error: vi.fn(),
    notice: vi.fn(),
    setOutput: vi.fn(),
  };
  const substituted = preflightScript
    .replace(/\$\{\{\s*github\.run_attempt\s*\}\}/g, String(attempt))
    .replace(/\$\{\{\s*toJSON\(vars\.NATIVE_DB_WORKLOAD_TEARDOWN_RECEIPTS\s*\|\|\s*'\[\]'\)\s*\}\}/g, JSON.stringify('[]'))
    .replace(/\$\{\{\s*vars\.NATIVE_DB_WORKLOAD_TEARDOWN_RECEIPTS\s*\}\}/g, '[]');
  if (/\$\{\{/.test(substituted)) throw new Error('Fixture must explicitly control each GitHub expression.');
  const fetch = vi.fn(async () => { throw new Error('Synthetic fixture forbids network transport.'); });
  // Hosted absolute import paths are POSIX paths. On this Windows authoring
  // host, the controlled workspace fixture uses its equivalent file URL.
  const processFixture = { cwd: () => new URL('../../', import.meta.url).href.replace(/\/$/, '') };
  let error: string | null = null;
  try {
    // Node's main loader is required for the real step's dynamic imports.
    // The returned value is an AsyncFunction, with unchanged step body bytes.
    const execute = runInThisContext(`(async function (github, context, core, require, fetch, process) {\n${substituted}\n})`, {
      importModuleDynamically: vmConstants.USE_MAIN_CONTEXT_DEFAULT_LOADER,
    }) as (...arguments_: unknown[]) => Promise<unknown>;
    await execute(github, context, core, localRequire, fetch, processFixture);
  } catch (reason) {
    error = reason instanceof Error ? reason.message : 'Non-error rejection';
  }
  return { refused: failed.mock.calls.length > 0 || error !== null, error, failed,
    paginate, iterator, getWorkflowRun, visitedPages, downloadArtifact, fetch };
}

function expectNoExternalAction(result: Awaited<ReturnType<typeof executePreflight>>) {
  expect(result.downloadArtifact).not.toHaveBeenCalled();
  expect(result.fetch).not.toHaveBeenCalled();
}

describe('DBV-005/007/008/012 hosted predecessor preflight under normalized Octokit pagination', () => {
  it('accepts the exact successful adoption baseline from a normalized collection array', async () => {
    const result = await executePreflight();
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    expect(result.getWorkflowRun.mock.calls.some(([parameters]) =>
      String(parameters.run_id) === String(IDS.baseline),
    )).toBe(true);
    expect(result.paginate.mock.calls.some(([, parameters]) =>
      String(parameters.run_id) === String(IDS.baseline) && parameters.attempt_number === 1,
    )).toBe(true);
    expectNoExternalAction(result);
  });

  it('traverses a normalized empty page to the exact baseline on the following page', async () => {
    const pages = [[], [run()]];
    const result = await executePreflight({ pages });
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    expect(result.visitedPages).toEqual(pages);
    expectNoExternalAction(result);
  });

  it('traverses newer skipped failures across pages and stops at the exact baseline', async () => {
    const recent = run(IDS.recent, { conclusion: 'failure' });
    const pages = [[], [recent], [run(), run(IDS.older, { conclusion: 'cancelled' })], [null]];
    const result = await executePreflight({ pages, jobs: { [`${IDS.recent}-1`]: skippedJobs() } });
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    expect(result.visitedPages).toEqual(pages.slice(0, 3));
    const scannedRunIds = result.paginate.mock.calls.map(([, parameters]) => parameters.run_id);
    expect(scannedRunIds).toContain(IDS.recent);
    expect(scannedRunIds).not.toContain(IDS.older);
    expectNoExternalAction(result);
  });

  it.each(['failure', 'cancelled', 'timed_out'])('does not invent recovery for a newer %s whose native and guardian jobs were skipped', async conclusion => {
    const result = await executePreflight({
      pages: [[run(IDS.recent, { conclusion }), run()]],
      jobs: { [`${IDS.recent}-1`]: skippedJobs() },
    });
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    expectNoExternalAction(result);
  });

  it.each(['migrate', 'pgtap', 'seed-dry-run'])('refuses adoption when the baseline %s job did not successfully finish', async name => {
    const result = await executePreflight({
      baselineJobs: baselineJobs().map(value => value.name === name ? { ...value, conclusion: 'failure' } : value),
    });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it.each([
    ['unfinished run', { status: 'in_progress', conclusion: null }],
    ['different baseline source', { head_sha: 'b'.repeat(40) }],
    ['untrusted event', { event: 'pull_request' }],
    ['different branch', { head_branch: 'feature' }],
  ] satisfies [string, Partial<Run>][])('refuses the %s baseline before any external action', async (_, baseline) => {
    const result = await executePreflight({ baseline });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it('permits the known old type-drift baseline failure when migrate, native and serial seed jobs succeeded', async () => {
    // The frozen cutover deliberately reconciles this old run's type drift
    // through the newly generated snapshot and the adopting run's drift gate.
    const result = await executePreflight({ baseline: { conclusion: 'failure' }, baselineJobs: baselineJobs() });
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    expectNoExternalAction(result);
  });

  it.each(['failure', 'cancelled', 'timed_out'])('blocks a newer executed %s native worker with no verified recovery or teardown receipt', async conclusion => {
    const result = await executePreflight({
      pages: [[run(IDS.recent, { conclusion }), run()]],
      jobs: { [`${IDS.recent}-1`]: [job('pgtap', conclusion), job('timeout-guardian', 'skipped')] },
    });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it('requires recovery for an executed guardian even when its native worker was skipped', async () => {
    const result = await executePreflight({
      pages: [[run(IDS.recent, { conclusion: 'failure' }), run()]],
      jobs: { [`${IDS.recent}-1`]: [job('pgtap', 'skipped'), job('timeout-guardian')] },
    });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it('allows skipped earlier same-run attempts after checking the complete attempt history', async () => {
    const result = await executePreflight({
      attempt: 3,
      pages: [[run(IDS.current, { run_attempt: 3, status: 'in_progress', conclusion: null }), run()]],
      jobs: { [`${IDS.current}-1`]: skippedJobs(), [`${IDS.current}-2`]: skippedJobs() },
    });
    expect({ refused: result.refused, error: result.error }).toEqual({ refused: false, error: null });
    for (const attempt_number of [1, 2]) expect(result.paginate.mock.calls.some(([, parameters]) =>
      String(parameters.run_id) === String(IDS.current) && parameters.attempt_number === attempt_number,
    )).toBe(true);
    expectNoExternalAction(result);
  });

  it('blocks an unresolved earlier same-run worker without requiring further scanning after refusal', async () => {
    const result = await executePreflight({
      attempt: 3,
      pages: [[run(IDS.current, { run_attempt: 3, status: 'in_progress', conclusion: null }), run()]],
      jobs: {
        [`${IDS.current}-2`]: skippedJobs(),
        [`${IDS.current}-1`]: [job('pgtap', 'cancelled'), job('timeout-guardian', 'skipped')],
      },
    });
    expect(result.refused).toBe(true);
    expect(result.paginate.mock.calls.some(([, parameters]) =>
      String(parameters.run_id) === String(IDS.current) && parameters.attempt_number === 1,
    )).toBe(true);
    expectNoExternalAction(result);
  });

  it.each([null, {}, { workflow_runs: [] }, 'unknown'])('fails closed for an unknown iterator collection shape %j', async page => {
    const result = await executePreflight({ pages: [page, [run()]] });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it('fails closed when normalized jobs are replaced with a raw REST envelope', async () => {
    const result = await executePreflight({
      pages: [[run(IDS.recent, { conclusion: 'failure' }), run()]],
      jobs: { [`${IDS.recent}-1`]: { jobs: skippedJobs() } },
    });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });

  it('fails closed when normalized artifacts are replaced with a raw REST envelope', async () => {
    const result = await executePreflight({
      pages: [[run(IDS.recent, { conclusion: 'failure' }), run()]],
      jobs: { [`${IDS.recent}-1`]: [job('pgtap', 'failure'), job('timeout-guardian', 'skipped')] },
      artifacts: { [IDS.recent]: { artifacts: [] } },
    });
    expect(result.refused).toBe(true);
    expectNoExternalAction(result);
  });
});
