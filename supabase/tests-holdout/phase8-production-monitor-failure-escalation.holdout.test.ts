import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const WORKFLOW_PATH = resolve(process.cwd(), '.github/workflows/phase8-production-monitor.yml');
const REPOSITORY = 'OGUN01/gymloop';
const RUN_ID = '35859870821';

type Issue = {
  readonly body: string;
  readonly labels: readonly string[];
  readonly title: string;
};

type IssueStore = {
  readonly create: (issue: Issue) => Promise<unknown>;
  readonly findOpen: (labels: readonly string[]) => Promise<number | null>;
  readonly update: (number: number, issue: Issue) => Promise<unknown>;
};

type FailureModule = {
  readonly reconcileMonitorFailure: (options: {
    readonly issueStore: IssueStore;
    readonly mode: 'production' | 'test';
    readonly repository: string;
    readonly runId: string;
  }) => Promise<unknown>;
};

type StoreRecorder = {
  readonly created: Issue[];
  readonly findLabels: (readonly string[])[];
  readonly store: IssueStore;
  readonly updated: { issue: Issue; number: number }[];
};

function issueStore(openNumber: number | null = null): StoreRecorder {
  const created: Issue[] = [];
  const findLabels: (readonly string[])[] = [];
  const updated: { issue: Issue; number: number }[] = [];
  return {
    created,
    findLabels,
    store: {
      create: async (issue) => created.push(issue),
      findOpen: async (labels) => {
        findLabels.push(labels);
        return openNumber;
      },
      update: async (number, issue) => updated.push({ issue, number }),
    },
    updated,
  };
}

async function loadFailureModule(): Promise<FailureModule> {
  return await import('../../scripts/phase8-monitor-failure') as FailureModule;
}

function workflowSource(): string {
  return readFileSync(WORKFLOW_PATH, 'utf8');
}

function stepSources(source: string): readonly { offset: number; source: string }[] {
  const starts = [...source.matchAll(/^(\s*)- (?:name|uses|run):\s*.+$/gm)];
  return starts.map((start, index) => ({
    offset: start.index,
    source: source.slice(start.index, starts[index + 1]?.index ?? source.length),
  }));
}

describe('independent HARD-005 monitor-failure escalation holdout', () => {
  it('creates one generic production failure issue with the run and acknowledgement path', async () => {
    const module = await loadFailureModule();
    const recorder = issueStore();

    await module.reconcileMonitorFailure({
      issueStore: recorder.store,
      mode: 'production',
      repository: REPOSITORY,
      runId: RUN_ID,
    });

    expect(recorder.findLabels).toHaveLength(1);
    expect(recorder.created).toHaveLength(1);
    expect(recorder.updated).toHaveLength(0);
    const issue = recorder.created[0]!;
    expect(issue.labels).toEqual(expect.arrayContaining([
      'production-alert',
      'phase8-monitor-failure',
    ]));
    expect(issue.body).toContain(`https://github.com/${REPOSITORY}/actions/runs/${RUN_ID}`);
    expect(issue.body).toMatch(/30[- ]minute/i);
    expect(issue.body).toMatch(/SEV-2/i);
  });

  it('updates the matching open production failure instead of creating a duplicate', async () => {
    const module = await loadFailureModule();
    const recorder = issueStore(41);

    await module.reconcileMonitorFailure({
      issueStore: recorder.store,
      mode: 'production',
      repository: REPOSITORY,
      runId: RUN_ID,
    });

    expect(recorder.findLabels).toHaveLength(1);
    expect(recorder.created).toHaveLength(0);
    expect(recorder.updated).toHaveLength(1);
    expect(recorder.updated[0]?.number).toBe(41);
    expect(recorder.updated[0]?.issue.labels).toEqual(expect.arrayContaining([
      'production-alert',
      'phase8-monitor-failure',
    ]));
  });

  it('uses a separate TEST-only key and never gives the test receipt a production label', async () => {
    const module = await loadFailureModule();
    const production = issueStore();
    const test = issueStore();

    await module.reconcileMonitorFailure({
      issueStore: production.store,
      mode: 'production',
      repository: REPOSITORY,
      runId: RUN_ID,
    });
    await module.reconcileMonitorFailure({
      issueStore: test.store,
      mode: 'test',
      repository: REPOSITORY,
      runId: RUN_ID,
    });

    const productionIssue = production.created[0]!;
    const testIssue = test.created[0]!;
    expect(productionIssue.labels).toContain('production-alert');
    expect(testIssue.labels).toContain('phase8-monitor-failure');
    expect(testIssue.labels).not.toContain('production-alert');
    expect(`${testIssue.title}\n${testIssue.body}\n${testIssue.labels.join('\n')}`).toMatch(/TEST/i);
    expect(test.findLabels[0]).not.toEqual(production.findLabels[0]);
  });

  it.each([
    { repository: 'OGUN01/gymloop;member@example.com', runId: RUN_ID },
    { repository: REPOSITORY, runId: '35859870821\nBearer secret-value' },
    { repository: REPOSITORY, runId: '0' },
  ])('rejects malformed identifiers without calling the issue store or echoing them %#', async (input) => {
    const module = await loadFailureModule();
    const recorder = issueStore();
    let error: unknown;

    try {
      await module.reconcileMonitorFailure({
        issueStore: recorder.store,
        mode: 'production',
        repository: input.repository,
        runId: input.runId,
      });
    } catch (caught) {
      error = caught;
    }

    expect(error).toBeInstanceOf(Error);
    expect(String(error)).not.toContain(input.repository);
    expect(String(error)).not.toContain(input.runId);
    expect(recorder.findLabels).toHaveLength(0);
    expect(recorder.created).toHaveLength(0);
    expect(recorder.updated).toHaveLength(0);
  });

  it('builds fixed generic issue text without provider or credential detail fields', async () => {
    const module = await loadFailureModule();
    const recorder = issueStore();

    await module.reconcileMonitorFailure({
      issueStore: recorder.store,
      mode: 'production',
      repository: REPOSITORY,
      runId: RUN_ID,
    });

    const serialized = JSON.stringify(recorder.created[0]);
    expect(serialized).not.toMatch(/provider[_ -]?logs?|exception[_ -]?(?:text|message)|stderr|stack[_ -]?trace|response[_ -]?body/i);
    expect(serialized).not.toMatch(/authorization|cookie|password|secret|access[_ -]?token|refresh[_ -]?token|email|phone/i);
  });

  it('forces collection failure before provider contact and invokes the handler on failure', () => {
    const source = workflowSource();
    const steps = stepSources(source);
    const forced = steps.filter((step) =>
      /force_test_collection_failure/.test(step.source) && /exit\s+1/.test(step.source),
    );
    const handlers = steps.filter((step) => /phase8-monitor-failure\.mjs/.test(step.source));
    const dependentHandler = /needs:\s*monitor[\s\S]*?if:\s*.*always\(\).*needs\.monitor\.result\s*!=\s*['"]success['"][\s\S]*?phase8-monitor-failure\.mjs/i.test(source);
    const providerOffset = source.search(/vercel\s+logs/i);

    expect(/force_test_collection_failure:\s*\n(?:\s+.+\n)*?\s+type:\s*boolean\s*\n(?:\s+.+\n)*?\s+default:\s*false/m.test(source)).toBe(true);
    expect(forced.length).toBeGreaterThan(0);
    expect(forced.every((step) => step.offset < providerOffset)).toBe(true);
    expect(handlers.length).toBeGreaterThan(0);
    expect(handlers.some((step) => /if:\s*.*(?:failure\(\)|always\(\))/i.test(step.source)) || dependentHandler).toBe(true);
    expect(/continue-on-error:\s*true/i.test(source)).toBe(false);
  });

  it('passes only the frozen CLI identifiers and keeps provider credentials out of the handler', () => {
    const source = workflowSource();
    const handlers = stepSources(source)
      .filter((step) => /phase8-monitor-failure\.mjs/.test(step.source))
      .map((step) => step.source)
      .join('\n');

    expect(/--mode\s+[^\s]+/.test(handlers)).toBe(true);
    expect(/--repository\s+[^\s]+/.test(handlers)).toBe(true);
    expect(/--run-id\s+[^\s]+/.test(handlers)).toBe(true);
    expect(/secrets\.VERCEL_TOKEN/.test(handlers)).toBe(false);
    expect(/secrets\.[A-Z0-9_]*(?:PASSWORD|SECRET|SERVICE_ROLE|ACCESS_TOKEN)/i.test(handlers)).toBe(false);
  });
});
