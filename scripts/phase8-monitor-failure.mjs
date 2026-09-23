import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { PHASE8_MONITOR_FAILURE } from '../packages/shared/src/config/constants.ts';

const REPOSITORY_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_.-]*\/[A-Za-z0-9][A-Za-z0-9_.-]*$/;
const RUN_ID_PATTERN = /^[1-9][0-9]*$/;
const PRIMARY_RESPONDER = 'OGUN01';

export async function reconcileMonitorFailure({ mode, repository, runId, issueStore }) {
  if (mode !== 'production' && mode !== 'test') {
    throw new Error('Invalid monitor failure mode');
  }
  if (typeof repository !== 'string' || !REPOSITORY_PATTERN.test(repository)) {
    throw new Error('Invalid monitor repository');
  }
  if (typeof runId !== 'string' || !RUN_ID_PATTERN.test(runId)) {
    throw new Error('Invalid monitor run ID');
  }
  if (!issueStore || typeof issueStore.findOpen !== 'function'
    || typeof issueStore.create !== 'function' || typeof issueStore.update !== 'function') {
    throw new Error('Invalid monitor issue store');
  }

  const testOnly = mode === 'test';
  const labels = testOnly
    ? ['phase8-monitor-failure-test', 'phase8-monitor-failure', 'phase8-monitor-test']
    : ['phase8-monitor-failure', 'production-alert', 'sev-2'];
  const runUrl = `https://github.com/${repository}/actions/runs/${runId}`;
  const issue = testOnly
    ? {
      title: '[TEST] Production monitor collection failure delivery',
      body: `TEST ONLY: a manual input intentionally stopped collection before provider contact.\n\nRun: ${runUrl}\n\nClose this receipt after verification. This does not represent a production incident.`,
      labels,
      assignees: [PRIMARY_RESPONDER],
    }
    : {
      title: '[SEV-2] Production monitor collection failed',
      body: `Production evidence collection or evaluation failed before thresholds could be assessed.\n\nRun: ${runUrl}\n\nTechnical Lead: acknowledge this SEV-2 within 30 minutes, investigate the failed run, and escalate to the Incident Commander if customer-impacting or ongoing. Stop new onboarding if unacknowledged after 30 minutes.`,
      labels,
      assignees: [PRIMARY_RESPONDER],
    };

  const identityLabels = testOnly ? [labels[0]] : [labels[0], labels[1]];
  const existing = await issueStore.findOpen(identityLabels);
  if (existing) {
    const number = typeof existing === 'number' ? existing : existing.number;
    if (!Number.isSafeInteger(number) || number < 1) {
      throw new Error('Invalid existing monitor issue');
    }
    await issueStore.update(number, issue);
    return { action: 'updated', number };
  }
  const created = await issueStore.create(issue);
  return { action: 'created', number: created?.number };
}

function gh(args) {
  return execFileSync('gh', args, { encoding: 'utf8' }).trim();
}

function parseCliArgs(args) {
  if (args.length !== PHASE8_MONITOR_FAILURE.cliArgCount) throw new Error('Invalid monitor failure arguments');
  const values = new Map();
  for (let index = 0; index < args.length; index += PHASE8_MONITOR_FAILURE.cliArgStride) {
    const key = args[index];
    if (!['--mode', '--repository', '--run-id'].includes(key) || values.has(key)) {
      throw new Error('Invalid monitor failure arguments');
    }
    values.set(key, args[index + 1]);
  }
  return {
    mode: values.get('--mode'),
    repository: values.get('--repository'),
    runId: values.get('--run-id'),
  };
}

function githubIssueStore(repository) {
  return {
    async findOpen(labels) {
      const result = gh(['issue', 'list', '--repo', repository, '--state', 'open',
        '--limit', String(PHASE8_MONITOR_FAILURE.issueListLimit), '--json', 'number',
        ...labels.flatMap((label) => ['--label', label])]);
      return JSON.parse(result)[0] ?? null;
    },
    async create(issue) {
      for (const label of issue.labels) {
        gh(['label', 'create', label, '--repo', repository,
          '--color', PHASE8_MONITOR_FAILURE.issueLabelColor, '--force']);
      }
      const url = gh(['issue', 'create', '--repo', repository, '--title', issue.title,
        '--body', issue.body, '--label', issue.labels.join(','), '--assignee', PRIMARY_RESPONDER]);
      const number = Number(url.split('/').at(-1));
      return { number };
    },
    async update(number, issue) {
      for (const label of issue.labels) {
        gh(['label', 'create', label, '--repo', repository,
          '--color', PHASE8_MONITOR_FAILURE.issueLabelColor, '--force']);
      }
      gh(['issue', 'edit', String(number), '--repo', repository, '--title', issue.title,
        '--body', issue.body, '--add-label', issue.labels.join(','), '--add-assignee', PRIMARY_RESPONDER]);
      return { number };
    },
  };
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) {
  try {
    const args = parseCliArgs(process.argv.slice(PHASE8_MONITOR_FAILURE.cliArgStride));
    await reconcileMonitorFailure({ ...args, issueStore: githubIssueStore(args.repository) });
  } catch {
    console.error('Monitor failure issue reconciliation failed');
    process.exitCode = 1;
  }
}
