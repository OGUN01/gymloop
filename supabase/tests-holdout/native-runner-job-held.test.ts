import { describe, expect, it } from 'vitest';

// Implementation-blind contract authoring: only the frozen DBV design and EARS
// were consulted. This suite deliberately exercises no runner or infrastructure.
const modulePath = new URL('../../scripts/pgtap/runner-job.mjs', import.meta.url).href;
type TrustReceipt = { trusted: boolean; failureCodes: string[] };
type RunnerJobModule = {
  verifyNativeRunnerJob: (expected: unknown, observed: unknown) => TrustReceipt;
  chooseNativeRunnerLabels: (input: unknown) => string[];
};
const runnerJob = await import(modulePath) as RunnerJobModule;
const sourceSha = 'a417e2c36f805e9b31d77094ac262fab83050d12';
const runId = '70192';
const runAttempt = '3';
const label = `fitcruxx-db-win-x64-${runId}-${runAttempt}-${sourceSha.slice(0, 12)}`;
const hosted = ['ubuntu-latest'];

function binding() {
  return { sourceSha, runId, runAttempt, label };
}

function observedJob() {
  return {
    repository: 'OGUN01/gymloop',
    eventName: 'push',
    ref: 'refs/heads/main',
    sourceSha,
    runId,
    runAttempt,
    workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
    runnerOs: 'Windows',
    job: 'pgtap',
  };
}

function selectionJob() {
  const { repository, eventName, ref, workflowRef } = observedJob();
  return { repository, eventName, ref, sourceSha, runId, runAttempt, workflowRef };
}

function availableRunner() {
  return {
    id: 912,
    status: 'online',
    busy: false,
    ephemeral: true,
    guardVerified: true,
    label,
    sourceSha,
    runId,
    runAttempt,
  };
}

function rejected(expected: unknown, observed: unknown) {
  expect(() => runnerJob.verifyNativeRunnerJob(expected, observed)).not.toThrow();
  expect(runnerJob.verifyNativeRunnerJob(expected, observed)).toEqual({
    trusted: false,
    failureCodes: ['RUNNER_UNTRUSTED'],
  });
}

describe('DBV-008 held trusted setup identity boundary', () => {
  it('offers exactly the two frozen public pure entries', () => {
    expect(Object.keys(runnerJob).sort()).toEqual([
      'chooseNativeRunnerLabels', 'verifyNativeRunnerJob',
    ]);
  });

  it.each(['push', 'workflow_dispatch'])('accepts the exact approved %s job', eventName => {
    expect(runnerJob.verifyNativeRunnerJob(binding(), {
      ...observedJob(), eventName,
    })).toEqual({ trusted: true, failureCodes: [] });
  });

  it.each([
    ['repository', 'attacker/gymloop'],
    ['repository', 'ogun01/gymloop'],
    ['repository', 'OGUN01/Gymloop'],
    ['eventName', 'pull_request'],
    ['eventName', 'pull_request_target'],
    ['eventName', 'workflow_run'],
    ['eventName', 'Push'],
    ['ref', 'refs/pull/70192/merge'],
    ['ref', 'refs/heads/Main'],
    ['ref', 'refs/heads/main\n'],
    ['sourceSha', 'b'.repeat(40)],
    ['sourceSha', sourceSha.toUpperCase()],
    ['runId', '70193'],
    ['runId', '070192'],
    ['runAttempt', '4'],
    ['runAttempt', '03'],
    ['workflowRef', 'OGUN01/gymloop/.github/workflows/db.yml@refs/pull/1/merge'],
    ['workflowRef', 'OGUN01/gymloop/.github/workflows/ci.yml@refs/heads/main'],
    ['runnerOs', 'Linux'],
    ['runnerOs', 'windows'],
    ['job', 'migrate'],
    ['job', 'pgtap '],
  ])('rejects mismatched observed %s', (key, value) => {
    rejected(binding(), { ...observedJob(), [key]: value });
  });

  it.each([
    ['sourceSha', 'z'.repeat(40)],
    ['sourceSha', sourceSha.slice(1)],
    ['sourceSha', `${sourceSha}\n`],
    ['runId', '0'],
    ['runId', '-1'],
    ['runId', '1e3'],
    ['runId', '70192 '],
    ['runAttempt', '0'],
    ['runAttempt', '+3'],
    ['runAttempt', '3.0'],
    ['label', 'self-hosted'],
    ['label', label.toUpperCase()],
    ['label', label.replace('win-x64', 'linux-x64')],
    ['label', `${label}-extra`],
    ['label', label.replace(sourceSha.slice(0, 12), sourceSha.slice(0, 11))],
  ])('rejects malformed expected %s even with a matching observed job', (key, value) => {
    rejected({ ...binding(), [key]: value }, observedJob());
  });

  it.each(['sourceSha', 'runId', 'runAttempt', 'label'])('rejects missing expected %s', key => {
    const incomplete: Record<string, unknown> = binding();
    delete incomplete[key];
    rejected(incomplete, observedJob());
  });

  it.each(Object.keys(observedJob()))('rejects missing observed %s', key => {
    const incomplete: Record<string, unknown> = observedJob();
    delete incomplete[key];
    rejected(binding(), incomplete);
  });

  it.each([null, undefined, [], true, 3, 'job', new Date()])('does not coerce a malformed top-level record %s', value => {
    rejected(value, observedJob());
    rejected(binding(), value);
  });

  it.each([null, false, 70192, [], {}, ''])('does not coerce identity field values %s', value => {
    for (const key of Object.keys(binding())) rejected({ ...binding(), [key]: value }, observedJob());
    for (const key of Object.keys(observedJob())) rejected(binding(), { ...observedJob(), [key]: value });
  });

  it('rejects extra authority fields and inherited non-plain records', () => {
    rejected({ ...binding(), approved: true }, observedJob());
    rejected(binding(), { ...observedJob(), pullRequest: false });
    rejected(binding(), Object.assign(Object.create({ trusted: true }), observedJob()));
    rejected(Object.assign(Object.create({ authorized: true }), binding()), observedJob());
  });

  it('does not modify either caller-supplied job record', () => {
    const expected = Object.freeze(binding());
    const observed = Object.freeze(observedJob());
    const before = JSON.stringify({ expected, observed });
    expect(runnerJob.verifyNativeRunnerJob(expected, observed).trusted).toBe(true);
    expect(JSON.stringify({ expected, observed })).toBe(before);
  });
});

describe('DBV-008/009/013 held hosted selector fail-closed boundary', () => {
  it.each(['push', 'workflow_dispatch'])('selects the exact bound ephemeral Windows %s job', eventName => {
    expect(runnerJob.chooseNativeRunnerLabels({
      job: { ...selectionJob(), eventName }, runner: availableRunner(),
    })).toEqual(['self-hosted', 'Windows', 'X64', label]);
  });

  it('selects hosted when regional capacity is absent', () => {
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: null })).toEqual(hosted);
  });

  it.each([
    ['status', 'offline'], ['status', 'Online'], ['busy', true],
    ['ephemeral', false], ['guardVerified', false],
    ['label', 'fitcruxx-db'], ['label', `${label}-other`],
    ['sourceSha', 'f'.repeat(40)], ['runId', '70191'], ['runAttempt', '2'],
    ['id', 0], ['id', -1], ['id', 0.5], ['id', Number.MAX_SAFE_INTEGER + 1],
    ['id', '912'], ['busy', 'false'], ['ephemeral', 'true'], ['guardVerified', 1],
  ])('falls back for unavailable or malformed runner %s', (key, value) => {
    expect(runnerJob.chooseNativeRunnerLabels({
      job: selectionJob(), runner: { ...availableRunner(), [key]: value },
    })).toEqual(hosted);
  });

  it.each(Object.keys(availableRunner()))('falls back when runner %s is missing', key => {
    const incomplete: Record<string, unknown> = availableRunner();
    delete incomplete[key];
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: incomplete })).toEqual(hosted);
  });

  it.each([
    ['repository', 'attacker/gymloop'], ['repository', 'ogun01/gymloop'],
    ['eventName', 'pull_request'], ['eventName', 'pull_request_target'],
    ['eventName', 'workflow_run'], ['ref', 'refs/pull/2/head'],
    ['ref', 'refs/heads/other'], ['sourceSha', sourceSha.toUpperCase()],
    ['runId', '070192'], ['runAttempt', '0'],
    ['workflowRef', 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/other'],
  ])('never allocates a regional runner to untrusted job %s', (key, value) => {
    expect(runnerJob.chooseNativeRunnerLabels({
      job: { ...selectionJob(), [key]: value }, runner: availableRunner(),
    })).toEqual(hosted);
  });

  it.each(Object.keys(selectionJob()))('falls back when job %s is missing', key => {
    const incomplete: Record<string, unknown> = selectionJob();
    delete incomplete[key];
    expect(runnerJob.chooseNativeRunnerLabels({ job: incomplete, runner: availableRunner() })).toEqual(hosted);
  });

  it.each([null, undefined, [], false, 'ready', new Date()])('falls back without throwing for invalid selector shape %s', value => {
    expect(() => runnerJob.chooseNativeRunnerLabels(value)).not.toThrow();
    expect(runnerJob.chooseNativeRunnerLabels(value)).toEqual(hosted);
    expect(runnerJob.chooseNativeRunnerLabels({ job: value, runner: availableRunner() })).toEqual(hosted);
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: value })).toEqual(hosted);
  });

  it('rejects unknown selector, job and runner keys instead of accepting alternate authority', () => {
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: availableRunner(), paidApproved: true })).toEqual(hosted);
    expect(runnerJob.chooseNativeRunnerLabels({ job: { ...selectionJob(), runnerOs: 'Windows' }, runner: availableRunner() })).toEqual(hosted);
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: { ...availableRunner(), serviceInstalled: false } })).toEqual(hosted);
    expect(runnerJob.chooseNativeRunnerLabels({ job: selectionJob(), runner: Object.assign(Object.create({ online: true }), availableRunner()) })).toEqual(hosted);
  });

  it('does not mutate readiness records or publish registration credentials', () => {
    const job = Object.freeze(selectionJob());
    const runner = Object.freeze(availableRunner());
    const before = JSON.stringify({ job, runner });
    expect(runnerJob.chooseNativeRunnerLabels(Object.freeze({ job, runner }))).toEqual(['self-hosted', 'Windows', 'X64', label]);
    expect(JSON.stringify({ job, runner })).toBe(before);
  });
});
