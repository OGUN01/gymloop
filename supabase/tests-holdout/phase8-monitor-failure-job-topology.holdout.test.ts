import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

import { describe, expect, it } from 'vitest';

const WORKFLOW_PATH = resolve(process.cwd(), '.github/workflows/phase8-production-monitor.yml');

type Job = {
  readonly name: string;
  readonly source: string;
};

function workflowSource(): string {
  return readFileSync(WORKFLOW_PATH, 'utf8');
}

function jobsIn(source: string): readonly Job[] {
  const jobsStart = /^jobs:\s*$/m.exec(source)?.index;
  if (jobsStart === undefined) return [];
  const jobsSource = source.slice(jobsStart);
  const starts = [...jobsSource.matchAll(/^ {2}([a-zA-Z][\w-]*):\s*$/gm)];
  return starts.map((start, index) => ({
    name: start[1] ?? '',
    source: jobsSource.slice(start.index, starts[index + 1]?.index ?? jobsSource.length),
  }));
}

function topology(): { escalation?: Job; monitor?: Job; source: string } {
  const source = workflowSource();
  const jobs = jobsIn(source);
  return {
    escalation: jobs.find((job) => /phase8-monitor-failure\.mjs/.test(job.source)),
    monitor: jobs.find((job) => job.name === 'monitor'),
    source,
  };
}

describe('independent HARD-005 dependent failure-job topology holdout', () => {
  it('runs the handler in a job separate from the monitor job', () => {
    const { escalation, monitor } = topology();

    expect(monitor).toEqual(expect.any(Object));
    expect(escalation).toEqual(expect.any(Object));
    expect(escalation?.name).not.toBe('monitor');
    expect(monitor?.source).not.toMatch(/phase8-monitor-failure\.mjs/);
  });

  it('depends on monitor and runs for every original non-success conclusion', () => {
    const { escalation } = topology();
    const beforeSteps = escalation?.source.split(/^\s{4}steps:\s*$/m)[0] ?? '';

    expect(/^\s{4}needs:\s*monitor\s*$/m.test(beforeSteps)).toBe(true);
    expect(/^\s{4}if:\s*.*always\(\)/m.test(beforeSteps)).toBe(true);
    expect(/needs\.monitor\.result\s*!=\s*['"]success['"]/.test(beforeSteps)).toBe(true);
  });

  it('owns checkout and Node setup before invoking the failure handler', () => {
    const { escalation } = topology();
    const source = escalation?.source ?? '';
    const checkout = source.search(/uses:\s*actions\/checkout@/i);
    const setupNode = source.search(/uses:\s*actions\/setup-node@/i);
    const handler = source.search(/phase8-monitor-failure\.mjs/);

    expect(checkout).toBeGreaterThan(0);
    expect(setupNode).toBeGreaterThan(checkout);
    expect(handler).toBeGreaterThan(setupNode);
    expect(/vercel\s+logs/i.test(source)).toBe(false);
    expect(/secrets\.VERCEL_TOKEN/.test(source)).toBe(false);
  });

  it('preserves monitor installation, execution, and timeout failures', () => {
    const { escalation, monitor } = topology();
    const monitorSource = monitor?.source ?? '';
    const escalationSource = escalation?.source ?? '';

    expect(/^\s{4}timeout-minutes:\s*[1-9]\d*\s*$/m.test(monitorSource)).toBe(true);
    expect(/continue-on-error:\s*true/i.test(monitorSource)).toBe(false);
    expect(/needs\.monitor\.result\s*!=\s*['"]success['"]/.test(escalationSource)).toBe(true);
  });

  it('does not swallow checkout, setup, handler, or issue API failures', () => {
    const { escalation } = topology();
    const source = escalation?.source ?? '';

    expect(/continue-on-error:\s*true/i.test(source)).toBe(false);
    expect(/\|\|\s*true\b/.test(source)).toBe(false);
    expect(/(?:phase8-monitor-failure\.mjs|gh\s+issue[^\n]*)[^\n]*\|\|\s*:/i.test(source)).toBe(false);
  });
});
