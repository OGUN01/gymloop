import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';

const repository = 'OGUN01/gymloop';
const firstRunId = '35859870821';
const secondRunId = '35859870822';
const privateLog = 'Bearer private-provider-token member@example.com';
const workflowPath = new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url);

type Issue = { title: string; body: string; labels: string[] };
type ExistingIssue = Issue & { number: number };

function memoryStore() {
  const openIssues: ExistingIssue[] = [];
  const findOpen = vi.fn(async (labels: string[]) =>
    openIssues.find((issue) => labels.every((label) => issue.labels.includes(label))) ?? null);
  const create = vi.fn(async (issue: Issue) => {
    const saved = { ...issue, number: openIssues.length + 1 };
    openIssues.push(saved);
    return saved;
  });
  const update = vi.fn(async (number: number, issue: Issue) => {
    const index = openIssues.findIndex((item) => item.number === number);
    if (index < 0) throw new Error('test issue not found');
    openIssues[index] = { ...issue, number };
    return openIssues[index];
  });
  return { issueStore: { findOpen, create, update }, openIssues, findOpen, create, update };
}

const reconcile = async (mode: 'production' | 'test', runId: string, issueStore: ReturnType<typeof memoryStore>['issueStore']) => {
  const module = await import('../phase8-monitor-failure.mjs');
  expect(typeof module.reconcileMonitorFailure).toBe('function');
  return module.reconcileMonitorFailure({ mode, repository, runId, issueStore });
};

describe('HARD-005 monitor collection/evaluation failure escalation', () => {
  it('opens one generic production alert with a run link and the 30-minute SEV-2 acknowledgement path', async () => {
    const store = memoryStore();

    await reconcile('production', firstRunId, store.issueStore);

    expect(store.findOpen).toHaveBeenCalledTimes(1);
    expect(store.create).toHaveBeenCalledTimes(1);
    expect(store.update).not.toHaveBeenCalled();
    const issue = store.openIssues[0];
    expect(issue.labels).toEqual(expect.arrayContaining(['production-alert', 'phase8-monitor-failure']));
    expect(issue.title).toMatch(/monitor/i);
    expect(issue.body).toContain(`https://github.com/${repository}/actions/runs/${firstRunId}`);
    expect(issue.body).toMatch(/SEV-2/i);
    expect(issue.body).toMatch(/30.minute/i);
    expect(JSON.stringify(issue)).not.toContain(privateLog);
  });

  it('updates the same open production issue for a later failed run', async () => {
    const store = memoryStore();

    await reconcile('production', firstRunId, store.issueStore);
    await reconcile('production', secondRunId, store.issueStore);

    expect(store.create).toHaveBeenCalledTimes(1);
    expect(store.update).toHaveBeenCalledTimes(1);
    expect(store.update.mock.calls[0]?.[0]).toBe(store.openIssues[0]?.number);
    expect(store.openIssues).toHaveLength(1);
    expect(store.openIssues[0]?.body).toContain(`https://github.com/${repository}/actions/runs/${secondRunId}`);
    expect(store.findOpen.mock.calls[0]?.[0]).toContain('phase8-monitor-failure');
    expect(store.findOpen.mock.calls[1]?.[0]).toContain('phase8-monitor-failure');
  });

  it('creates a clearly marked TEST-only receipt in a separate issue identity', async () => {
    const store = memoryStore();
    await reconcile('production', firstRunId, store.issueStore);

    await reconcile('test', secondRunId, store.issueStore);

    expect(store.openIssues).toHaveLength(2);
    const productionIssue = store.openIssues.find((issue) => issue.labels.includes('production-alert'));
    const testIssue = store.openIssues.find((issue) => !issue.labels.includes('production-alert'));
    expect(testIssue).toBeDefined();
    expect(testIssue?.labels).toEqual(expect.arrayContaining([expect.stringMatching(/test/i)]));
    expect(testIssue?.labels).not.toContain('production-alert');
    expect(`${testIssue?.title} ${testIssue?.body}`).toMatch(/TEST/i);
    expect(testIssue?.body).toContain(`https://github.com/${repository}/actions/runs/${secondRunId}`);
    expect(testIssue?.number).not.toBe(productionIssue?.number);
  });

  it('builds fresh generic text instead of copying a previous issue body or extra caller fields', async () => {
    const store = memoryStore();
    store.openIssues.push({
      number: 7,
      title: privateLog,
      body: privateLog,
      labels: ['production-alert', 'phase8-monitor-failure'],
    });
    const module = await import('../phase8-monitor-failure.mjs');
    await module.reconcileMonitorFailure({
      mode: 'production', repository, runId: secondRunId,
      issueStore: store.issueStore,
      providerLog: privateLog,
      exception: new Error(privateLog),
    });

    expect(store.create).not.toHaveBeenCalled();
    expect(store.update).toHaveBeenCalledTimes(1);
    expect(JSON.stringify(store.openIssues[0])).not.toContain(privateLog);
    expect(store.openIssues[0]?.body).toContain(`https://github.com/${repository}/actions/runs/${secondRunId}`);
  });

  it.each([
    ['unknown mode', 'unknown', repository, firstRunId],
    ['foreign repository shape', 'production', `${repository}?token=${privateLog}`, firstRunId],
    ['zero run ID', 'production', repository, '0'],
    ['nondecimal run ID', 'production', repository, `${firstRunId}-${privateLog}`],
  ])('rejects %s before touching GitHub issue storage', async (_label, mode, candidateRepository, runId) => {
    const store = memoryStore();
    const module = await import('../phase8-monitor-failure.mjs');

    await expect(Promise.resolve().then(() => module.reconcileMonitorFailure({
      mode, repository: candidateRepository, runId, issueStore: store.issueStore,
    }))).rejects.toThrow();
    expect(store.findOpen).not.toHaveBeenCalled();
    expect(store.create).not.toHaveBeenCalled();
    expect(store.update).not.toHaveBeenCalled();
  });
});

describe('HARD-005 failed workflow receipt', () => {
  it('routes both collection/evaluation failure and forced TEST failure through the failure handler', () => {
    const workflow = readFileSync(workflowPath, 'utf8');

    expect(/force_test_collection_failure\s*:/.test(workflow)).toBe(true);
    expect(/phase8-monitor-failure\.mjs/.test(workflow)).toBe(true);
    expect(/if:\s*(?:\$\{\{\s*)?failure\(\)/.test(workflow)).toBe(true);
    expect(/continue-on-error:\s*true/.test(workflow)).toBe(false);
    const failureCommand = /node\s+scripts\/phase8-monitor-failure\.mjs[^\r\n]*/.exec(workflow)?.[0] ?? '';
    expect(failureCommand).toContain('--mode');
    expect(failureCommand).toContain('--repository');
    expect(failureCommand).toContain('--run-id');
    expect(/--(?:input|logs|exception|token)\b/.test(failureCommand)).toBe(false);
  });

  it('forces the manual TEST collection failure before any provider contact', () => {
    const workflow = readFileSync(workflowPath, 'utf8');
    const firstProviderCommand = workflow.search(/vercel\s+(?:inspect|logs)|curl\s+[^\r\n]*https:\/\/gymloop-phi\.vercel\.app/i);
    const forcedFailureBranch = workflow.search(/if[^\r\n]*(?:force_test_collection_failure|FORCE_TEST_COLLECTION_FAILURE)|(?:force_test_collection_failure|FORCE_TEST_COLLECTION_FAILURE)[^\r\n]*==[^\r\n]*true/i);

    expect(firstProviderCommand).toBeGreaterThanOrEqual(0);
    expect(forcedFailureBranch).toBeGreaterThanOrEqual(0);
    expect(forcedFailureBranch).toBeLessThan(firstProviderCommand);
    expect(/exit\s+1|throw\s+new\s+Error|\bfalse\b/.test(workflow.slice(forcedFailureBranch, firstProviderCommand))).toBe(true);
  });
});
