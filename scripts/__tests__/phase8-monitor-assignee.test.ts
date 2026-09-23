import { readFileSync } from 'node:fs';
import { describe, expect, it, vi } from 'vitest';

const repository = 'OGUN01/gymloop';
const responder = 'OGUN01';
const runId = '35859870821';
const workflowPaths = [
  new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url),
  new URL('../../.github/workflows/phase8-monitor-watchdog.yml', import.meta.url),
];

type Issue = { title: string; body: string; labels: string[]; assignees?: string[] };
type ExistingIssue = Issue & { number: number };

const issueStore = (existing?: ExistingIssue) => {
  const findOpen = vi.fn(async () => existing ?? null);
  const create = vi.fn(async (issue: Issue) => ({ ...issue, number: 1 }));
  const update = vi.fn(async (number: number, issue: Issue) => ({ ...issue, number }));
  return { findOpen, create, update };
};

const reconcile = async (mode: 'production' | 'test', store: ReturnType<typeof issueStore>) => {
  const module = await import('../phase8-monitor-failure.mjs');
  return module.reconcileMonitorFailure({ mode, repository, runId, issueStore: store });
};

describe('pilot issue routing to the owner', () => {
  it.each(workflowPaths)('assigns OGUN01 when %s creates or updates evaluator/watchdog issues', (path) => {
    const workflow = readFileSync(path, 'utf8');
    const create = workflow.match(/gh\s+issue\s+create\b[^\r\n]*/g) ?? [];
    const edit = workflow.match(/gh\s+issue\s+edit\b[^\r\n]*/g) ?? [];

    expect(create.length).toBeGreaterThan(0);
    expect(edit.length).toBeGreaterThan(0);
    for (const command of create) {
      expect(command).toMatch(/--assignee(?:=|\s+)["']?OGUN01["']?(?:\s|$)/);
      expect(command).not.toMatch(/\|\|\s*true\b/);
    }
    for (const command of edit) {
      expect(command).toMatch(/--add-assignee(?:=|\s+)["']?OGUN01["']?(?:\s|$)/);
      expect(command).not.toMatch(/\|\|\s*true\b/);
    }
    expect(workflow).not.toMatch(/continue-on-error:\s*true/);
    expect(workflow).toMatch(/needs\.[a-z][a-z0-9_-]*\.result\s*!=\s*['"]success['"]/);
    expect(workflow).toMatch(/phase8-monitor-failure\.mjs/);
  });

  it.each(['production', 'test'] as const)('assigns a newly created %s failure issue to exactly OGUN01', async (mode) => {
    const store = issueStore();

    await reconcile(mode, store);

    expect(store.create).toHaveBeenCalledTimes(1);
    const issue = store.create.mock.calls[0]?.[0];
    expect(issue?.assignees).toEqual([responder]);
    expect(issue?.labels.includes('production-alert')).toBe(mode === 'production');
  });

  it.each(['production', 'test'] as const)('reassigns an existing %s failure issue to exactly OGUN01', async (mode) => {
    const labels = mode === 'production'
      ? ['phase8-monitor-failure', 'production-alert']
      : ['phase8-monitor-failure', 'phase8-monitor-failure-test'];
    const store = issueStore({ number: 7, title: 'old', body: 'old', labels });

    await reconcile(mode, store);

    expect(store.create).not.toHaveBeenCalled();
    expect(store.update).toHaveBeenCalledTimes(1);
    expect(store.update.mock.calls[0]?.[0]).toBe(7);
    const issue = store.update.mock.calls[0]?.[1];
    expect(issue?.assignees).toEqual([responder]);
    expect(issue?.labels.includes('production-alert')).toBe(mode === 'production');
  });

  it.each(['create', 'update'] as const)('fails the dependent handler when %s cannot assign OGUN01', async (operation) => {
    const existing = operation === 'update'
      ? { number: 7, title: 'old', body: 'old', labels: ['phase8-monitor-failure', 'production-alert'] }
      : undefined;
    const store = issueStore(existing);
    store[operation].mockImplementation(async (...args: unknown[]) => {
      const issue = args.at(-1) as Issue;
      if (issue.assignees?.length === 1 && issue.assignees[0] === responder) {
        throw new Error('GitHub rejected issue assignment');
      }
      return { ...issue, number: 7 };
    });

    await expect(reconcile('production', store)).rejects.toThrow('GitHub rejected issue assignment');
    expect(store[operation]).toHaveBeenCalledTimes(1);
  });
});
