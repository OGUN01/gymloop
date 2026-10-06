import { beforeAll, describe, expect, it } from 'vitest';

// Independent source-blind tests from operational boundary frozen 0321784c.
// No runner is registered, no GitHub job dispatched and no paid resource exists.
type Boundary = {
  verifyNativeRunnerJob: (expected: unknown, observed: unknown) => { trusted: boolean; failureCodes: string[] };
  chooseNativeRunnerLabels: (input: unknown) => string[];
};
const SOURCE = 'a'.repeat(40);
const RUN_ID = '37486763608';
const RUN_ATTEMPT = '1';
const LABEL = `fitcruxx-db-win-x64-${RUN_ID}-${RUN_ATTEMPT}-${SOURCE.slice(0, 12)}`;
const EXPECTED = { sourceSha: SOURCE, runId: RUN_ID, runAttempt: RUN_ATTEMPT, label: LABEL };
const JOB = {
  repository: 'OGUN01/gymloop',
  eventName: 'push',
  ref: 'refs/heads/main',
  sourceSha: SOURCE,
  runId: RUN_ID,
  runAttempt: RUN_ATTEMPT,
  workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
};
const OBSERVED = { ...JOB, runnerOs: 'Windows', job: 'pgtap' };
const RUNNER = {
  id: 1,
  status: 'online',
  busy: false,
  ephemeral: true,
  guardVerified: true,
  label: LABEL,
  sourceSha: SOURCE,
  runId: RUN_ID,
  runAttempt: RUN_ATTEMPT,
};
const HOSTED = ['ubuntu-latest'];
const REGIONAL = ['self-hosted', 'Windows', 'X64', LABEL];
let boundary: Boundary;

beforeAll(async () => {
  const modulePath = '../pgtap/runner-job.mjs';
  boundary = await import(modulePath) as Boundary;
});

function untrusted(expected: unknown, observed: unknown): void {
  expect(boundary.verifyNativeRunnerJob(expected, observed)).toEqual({ trusted: false, failureCodes: ['RUNNER_UNTRUSTED'] });
}

describe('DBV-008 exact trusted main job guard', () => {
  it.each(['push', 'workflow_dispatch'])('accepts the exact protected binding for %s', eventName => {
    expect(boundary.verifyNativeRunnerJob(EXPECTED, { ...OBSERVED, eventName })).toEqual({ trusted: true, failureCodes: [] });
  });

  it('derives the OS-aware unique label from all three exact bound identities', () => {
    const sourceSha = '0123456789abcdef'.repeat(2) + '01234567';
    const runId = '2';
    const runAttempt = '12';
    const expected = { sourceSha, runId, runAttempt, label: `fitcruxx-db-win-x64-${runId}-${runAttempt}-${sourceSha.slice(0, 12)}` };
    expect(boundary.verifyNativeRunnerJob(expected, { ...OBSERVED, sourceSha, runId, runAttempt })).toEqual({ trusted: true, failureCodes: [] });
  });

  it.each([
    ['fork repository', { repository: 'outsider/gymloop' }],
    ['repository case mismatch', { repository: 'ogun01/gymloop' }],
    ['pull request', { eventName: 'pull_request' }],
    ['pull request target', { eventName: 'pull_request_target' }],
    ['scheduled event', { eventName: 'schedule' }],
    ['repository dispatch', { eventName: 'repository_dispatch' }],
    ['main lookalike ref', { ref: 'refs/heads/main-extra' }],
    ['feature branch', { ref: 'refs/heads/feature' }],
    ['PR merge ref', { ref: 'refs/pull/1/merge' }],
    ['tag ref', { ref: 'refs/tags/main' }],
    ['different source', { sourceSha: 'b'.repeat(40) }],
    ['different run', { runId: '37486763609' }],
    ['different attempt', { runAttempt: '2' }],
    ['different workflow', { workflowRef: 'OGUN01/gymloop/.github/workflows/other.yml@refs/heads/main' }],
    ['different workflow branch', { workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/feature' }],
    ['different workflow repository', { workflowRef: 'outsider/gymloop/.github/workflows/db.yml@refs/heads/main' }],
    ['Linux runner', { runnerOs: 'Linux' }],
    ['Windows case mismatch', { runnerOs: 'windows' }],
    ['different job', { job: 'migrate' }],
    ['unknown observation key', { token: 'synthetic-no-secret' }],
    ['numeric run', { runId: 37486763608 }],
    ['numeric attempt', { runAttempt: 1 }],
    ['zero run', { runId: '0' }],
    ['zero attempt', { runAttempt: '0' }],
    ['leading zero run', { runId: `0${RUN_ID}` }],
    ['leading zero attempt', { runAttempt: '01' }],
    ['signed run', { runId: `+${RUN_ID}` }],
    ['exponential run', { runId: '1e3' }],
    ['whitespace identity', { runAttempt: '1 ' }],
    ['uppercase source', { sourceSha: 'A'.repeat(40) }],
    ['nonhex source', { sourceSha: 'g'.repeat(40) }],
    ['short source', { sourceSha: 'a'.repeat(39) }],
  ])('rejects %s before trusted execution', (_name, change) => {
    untrusted(EXPECTED, { ...OBSERVED, ...change });
  });

  it.each(Object.keys(OBSERVED))('rejects missing observation field %s', key => {
    const observed: Record<string, unknown> = { ...OBSERVED };
    delete observed[key];
    untrusted(EXPECTED, observed);
  });

  it.each([
    ['generic self-hosted label', { label: 'self-hosted' }],
    ['wrong OS label', { label: LABEL.replace('win-x64', 'linux-x64') }],
    ['wrong source suffix', { label: LABEL.replace('a'.repeat(12), 'b'.repeat(12)) }],
    ['wrong run label', { label: LABEL.replace(RUN_ID, '37486763609') }],
    ['wrong attempt label', { label: `fitcruxx-db-win-x64-${RUN_ID}-2-${SOURCE.slice(0, 12)}` }],
    ['unbound full source', { sourceSha: `${'a'.repeat(12)}${'b'.repeat(28)}` }],
    ['unknown expected key', { approved: true }],
    ['expected run leading zero', { runId: `0${RUN_ID}` }],
    ['expected attempt zero', { runAttempt: '0' }],
    ['expected short source', { sourceSha: 'a'.repeat(39) }],
  ])('rejects malformed expected binding: %s', (_name, change) => {
    untrusted({ ...EXPECTED, ...change }, OBSERVED);
  });

  it.each(Object.keys(EXPECTED))('rejects missing expected field %s', key => {
    const expected: Record<string, unknown> = { ...EXPECTED };
    delete expected[key];
    untrusted(expected, OBSERVED);
  });

  it.each([null, undefined, [], 'trusted', true, 1])('returns an ordinary untrusted receipt for malformed %j', input => {
    untrusted(input, OBSERVED);
    untrusted(EXPECTED, input);
  });

  it('does not mutate the captured or observed identities', () => {
    const expected = Object.freeze({ ...EXPECTED });
    const observed = Object.freeze({ ...OBSERVED });
    expect(boundary.verifyNativeRunnerJob(expected, observed)).toEqual({ trusted: true, failureCodes: [] });
    expect(expected).toEqual(EXPECTED);
    expect(observed).toEqual(OBSERVED);
  });
});

describe('DBV-008/009 pre-selection readiness and hosted fallback', () => {
  it.each(['push', 'workflow_dispatch'])('selects the exact ready ephemeral runner for trusted %s', eventName => {
    expect(boundary.chooseNativeRunnerLabels({ job: { ...JOB, eventName }, runner: RUNNER })).toEqual(REGIONAL);
  });

  it('keeps an absent runner on the ordinary hosted native path', () => {
    expect(boundary.chooseNativeRunnerLabels({ job: JOB, runner: null })).toEqual(HOSTED);
  });

  it.each([
    ['offline runner', { status: 'offline' }],
    ['busy runner', { busy: true }],
    ['permanent runner', { ephemeral: false }],
    ['unproved pre-job guard', { guardVerified: false }],
    ['generic runner label', { label: 'self-hosted' }],
    ['wrong OS label', { label: LABEL.replace('win-x64', 'linux-x64') }],
    ['different source binding', { sourceSha: 'b'.repeat(40) }],
    ['different run binding', { runId: '2' }],
    ['different attempt binding', { runAttempt: '2' }],
    ['zero runner id', { id: 0 }],
    ['negative runner id', { id: -1 }],
    ['fractional runner id', { id: 1.5 }],
    ['unsafe runner id', { id: Number.MAX_SAFE_INTEGER + 1 }],
    ['coerced runner id', { id: '1' }],
    ['unknown runner status', { status: 'ready' }],
    ['coerced busy flag', { busy: 'false' }],
    ['coerced ephemeral flag', { ephemeral: 'true' }],
    ['coerced guard flag', { guardVerified: 1 }],
    ['unknown runner key', { lifetimeHours: 4 }],
    ['leading-zero attempt', { runAttempt: '01' }],
    ['leading-zero run', { runId: `0${RUN_ID}` }],
    ['source case mismatch', { sourceSha: 'A'.repeat(40) }],
  ])('selects hosted fallback for %s', (_name, change) => {
    expect(boundary.chooseNativeRunnerLabels({ job: JOB, runner: { ...RUNNER, ...change } })).toEqual(HOSTED);
  });

  it.each(Object.keys(RUNNER))('selects hosted fallback for missing runner %s', key => {
    const runner: Record<string, unknown> = { ...RUNNER };
    delete runner[key];
    expect(boundary.chooseNativeRunnerLabels({ job: JOB, runner })).toEqual(HOSTED);
  });

  it.each([
    ['fork repository', { repository: 'outsider/gymloop' }],
    ['pull request', { eventName: 'pull_request' }],
    ['pull request target', { eventName: 'pull_request_target' }],
    ['different branch', { ref: 'refs/heads/feature' }],
    ['different workflow', { workflowRef: 'OGUN01/gymloop/.github/workflows/not-db.yml@refs/heads/main' }],
    ['different source', { sourceSha: 'b'.repeat(40) }],
    ['different run', { runId: '2' }],
    ['different attempt', { runAttempt: '2' }],
    ['extra job field', { job: 'pgtap' }],
    ['extra OS field', { runnerOs: 'Windows' }],
    ['unknown job key', { trusted: true }],
  ])('keeps %s hosted even if a runner is available', (_name, change) => {
    expect(boundary.chooseNativeRunnerLabels({ job: { ...JOB, ...change }, runner: RUNNER })).toEqual(HOSTED);
  });

  it.each(Object.keys(JOB))('selects hosted fallback for missing job %s', key => {
    const job: Record<string, unknown> = { ...JOB };
    delete job[key];
    expect(boundary.chooseNativeRunnerLabels({ job, runner: RUNNER })).toEqual(HOSTED);
  });

  it.each([
    null, undefined, [], 'regional', true, 1,
    { runner: RUNNER }, { job: JOB }, { job: JOB, runner: RUNNER, override: true },
    { job: null, runner: RUNNER }, { job: JOB, runner: [] },
  ])('never throws or skips native validation for malformed readiness %j', input => {
    expect(boundary.chooseNativeRunnerLabels(input)).toEqual(HOSTED);
  });

  it('does not change an exact ready input or append generic labels', () => {
    const job = Object.freeze({ ...JOB });
    const runner = Object.freeze({ ...RUNNER });
    const input = Object.freeze({ job, runner });
    expect(boundary.chooseNativeRunnerLabels(input)).toEqual(REGIONAL);
    expect(input).toEqual({ job: JOB, runner: RUNNER });
  });
});
