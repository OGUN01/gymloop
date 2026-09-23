import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const workflows = [
  '.github/workflows/phase8-production-monitor.yml',
  '.github/workflows/phase8-monitor-watchdog.yml',
] as const;

type Job = { id: string; source: string };

function jobsIn(workflow: string): Job[] {
  const source = readFileSync(resolve(process.cwd(), workflow), 'utf8');
  const jobsHeading = /^jobs:\s*$/m.exec(source);
  const jobsSection = jobsHeading ? source.slice(jobsHeading.index + jobsHeading[0].length) : '';
  const starts = [...jobsSection.matchAll(/^  ([\w-]+):\s*(?:#.*)?$/gm)];

  return starts.map((start, index) => ({
    id: start[1],
    source: jobsSection.slice(start.index, starts[index + 1]?.index),
  }));
}

function issueCalls(source: string): Array<{ operation: string; body: string; kind: 'api' | 'cli' }> {
  const calls: Array<{ operation: string; body: string; kind: 'api' | 'cli' }> = [];
  const pattern = /\bissues\.(create|update)\s*\(/g;
  for (const match of source.matchAll(pattern)) {
    const start = match.index + match[0].length;
    let depth = 1;
    let quote = '';
    let escaped = false;
    for (let index = start; index < source.length; index += 1) {
      const char = source[index];
      if (quote) {
        if (escaped) escaped = false;
        else if (char === '\\') escaped = true;
        else if (char === quote) quote = '';
      } else if (char === '"' || char === "'" || char === '`') {
        quote = char;
      } else if (char === '(') {
        depth += 1;
      } else if (char === ')') {
        depth -= 1;
        if (depth === 0) {
          calls.push({ operation: match[1], body: source.slice(start, index), kind: 'api' });
          break;
        }
      }
    }
  }
  for (const match of source.matchAll(/\bgh\s+issue\s+(create|edit)\b/g)) {
    const lines = source.slice(match.index).split(/\r?\n/);
    const command = [lines[0]];
    for (let index = 1; index < lines.length && command.at(-1)?.trimEnd().endsWith('\\'); index += 1) {
      command.push(lines[index]);
    }
    calls.push({ operation: match[1], body: command.join('\n'), kind: 'cli' });
  }
  return calls;
}

function issueJobs(workflow: string) {
  return jobsIn(workflow).filter((job) => issueCalls(job.source).length > 0);
}

function dependentFailureJobs(workflow: string) {
  return jobsIn(workflow).filter((job) => /\bneeds\s*:|\bneeds\s*\r?\n/.test(job.source)
    && /\bfailure\b/i.test(job.source));
}

describe.each(workflows)('%s pilot issue routing', (workflow) => {
  it('has an issue-writing monitor job and a dependent failure handler', () => {
    expect(issueJobs(workflow).length).toBeGreaterThanOrEqual(1);
    expect(dependentFailureJobs(workflow).length).toBeGreaterThanOrEqual(1);
  });

  it('assigns the exact OGUN01 account on every issue create and update path', () => {
    const jobs = issueJobs(workflow);
    expect(jobs.length).toBeGreaterThanOrEqual(1);
    for (const job of jobs) {
      const calls = issueCalls(job.source);
      expect(calls.length, `${workflow}: ${job.id} has no issue write`).toBeGreaterThan(0);
      for (const call of calls) {
        const assignment = call.kind === 'api'
          ? /\bassignees\s*:\s*\[?\s*['"`]OGUN01['"`]/
          : /--(?:add-)?assignee(?:=|\s+)["']?OGUN01\b/;
        expect(call.body, `${workflow}: ${job.id} issue ${call.operation} must route to OGUN01`)
          .toMatch(assignment);
      }
    }
  });

  it('keeps TEST receipts out of the production-alert label route', () => {
    const jobs = issueJobs(workflow);
    for (const job of jobs) {
      expect(job.source, `${workflow}: ${job.id} needs a separate TEST label route`)
        .toMatch(/\bTEST\b/i);
      const operativeLines = job.source.split(/\r?\n/).filter((line) => !line.trimStart().startsWith('#'));
      for (const line of operativeLines) {
        expect(line, `${workflow}: ${job.id} combines TEST and production-alert labels`)
          .not.toMatch(/(?:\bTEST\b|phase8-[\w-]*test)[^\r\n]*production-alert|production-alert[^\r\n]*(?:\bTEST\b|phase8-[\w-]*test)/i);
      }
      for (const call of issueCalls(job.source)) {
        if (/\btest\b/i.test(call.body)) {
          expect(call.body, `${workflow}: ${job.id} puts production-alert on a TEST receipt`)
            .not.toMatch(/production-alert/);
        }
      }
    }
  });

  it('allows assignment errors to fail their job and trigger dependent escalation', () => {
    const jobs = issueJobs(workflow);
    expect(jobs.length).toBeGreaterThanOrEqual(1);
    for (const job of jobs) {
      expect(job.source, `${workflow}: ${job.id} must not mask assignment failure`)
        .not.toMatch(/continue-on-error\s*:\s*true/i);
      expect(job.source, `${workflow}: ${job.id} must not discard issue API rejections`)
        .not.toMatch(/\bissues\.(?:create|update)\s*\([\s\S]*?\)\s*\.catch\s*\(/);
      for (const call of issueCalls(job.source)) {
        const assignmentFlag = call.kind === 'api' ? /\bassignees\s*:/ : /--(?:add-)?assignee\b/;
        expect(call.body, `${workflow}: ${job.id} assignment belongs to the failing issue write`)
          .toMatch(assignmentFlag);
        expect(call.body, `${workflow}: ${job.id} must not suppress assignment errors`)
          .not.toMatch(/\|\|\s*true\b/);
      }
    }
    const failureHandlers = dependentFailureJobs(workflow);
    expect(failureHandlers.length).toBeGreaterThanOrEqual(1);
    for (const job of failureHandlers) {
      expect(job.source, `${workflow}: ${job.id} must assign its own issue to OGUN01`)
        .toMatch(/--(?:add-)?assignee(?:=|\s+)["']?OGUN01\b|\bassignees\s*:\s*\[?\s*['"`]OGUN01['"`]/);
      expect(job.source, `${workflow}: ${job.id} must fail when assignment fails`)
        .not.toMatch(/continue-on-error\s*:\s*true|\|\|\s*true\b/i);
    }
  });
});
