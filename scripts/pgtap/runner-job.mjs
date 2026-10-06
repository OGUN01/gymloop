import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';

function exactRunnerRecord(value, keys) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) return null;
  const prototype = Object.getPrototypeOf(value);
  if (prototype !== Object.prototype && prototype !== null) return null;
  const descriptors = Object.getOwnPropertyDescriptors(value);
  const actual = Reflect.ownKeys(descriptors);
  if (actual.length !== keys.length || !actual.every(key => keys.includes(key)
    && descriptors[key].enumerable && Object.hasOwn(descriptors[key], 'value'))) return null;
  return Object.fromEntries(keys.map(key => [key, descriptors[key].value]));
}
function runnerLabel(identity) {
  return `${NATIVE_DB_VALIDATION.labelPrefix}-${identity.runId}-${identity.runAttempt}-${identity.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`;
}
function trustedMainIdentity(job) {
  return job.repository === NATIVE_DB_VALIDATION.repository
    && ['push', 'workflow_dispatch'].includes(job.eventName)
    && job.ref === NATIVE_DB_VALIDATION.mainRef && job.workflowRef === NATIVE_DB_VALIDATION.workflowRef
    && typeof job.sourceSha === 'string' && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(job.sourceSha)
    && typeof job.runId === 'string' && /^[1-9][0-9]*$/.test(job.runId)
    && typeof job.runAttempt === 'string' && /^[1-9][0-9]*$/.test(job.runAttempt);
}

/** Protect the exact authorized main job before checkout or a workflow step. */
export function verifyNativeRunnerJob(expected, observed) {
  let trusted;
  try {
    expected = exactRunnerRecord(expected, ['sourceSha', 'runId', 'runAttempt', 'label']);
    observed = exactRunnerRecord(observed, ['repository', 'eventName', 'ref', 'sourceSha', 'runId', 'runAttempt', 'workflowRef', 'runnerOs', 'job']);
    trusted = Boolean(expected && observed
      && trustedMainIdentity(observed)
      && observed.runnerOs === NATIVE_DB_VALIDATION.runnerOs && observed.job === NATIVE_DB_VALIDATION.job
      && expected.sourceSha === observed.sourceSha && expected.runId === observed.runId && expected.runAttempt === observed.runAttempt
      && expected.label === runnerLabel(observed));
  } catch { trusted = false; }
  return { trusted, failureCodes: trusted ? [] : ['RUNNER_UNTRUSTED'] };
}

/** Availability is decided on the hosted selector; trust is checked again locally. */
export function chooseNativeRunnerLabels(input) {
  const hosted = ['ubuntu-latest'];
  try {
    input = exactRunnerRecord(input, ['job', 'runner']);
    if (!input) return hosted;
    const job = exactRunnerRecord(input.job, ['repository', 'eventName', 'ref', 'sourceSha', 'runId', 'runAttempt', 'workflowRef']);
    const runner = exactRunnerRecord(input.runner, ['id', 'status', 'busy', 'ephemeral', 'guardVerified', 'label', 'sourceSha', 'runId', 'runAttempt']);
    if (!job || !trustedMainIdentity(job) || !runner) return hosted;
    if (!Number.isSafeInteger(runner.id) || runner.id <= 0 || runner.status !== 'online'
      || runner.busy !== false || runner.ephemeral !== true || runner.guardVerified !== true) return hosted;
    const expected = { sourceSha: runner.sourceSha, runId: runner.runId, runAttempt: runner.runAttempt, label: runner.label };
    const observed = { ...job, runnerOs: NATIVE_DB_VALIDATION.runnerOs, job: NATIVE_DB_VALIDATION.job };
    return verifyNativeRunnerJob(expected, observed).trusted ? ['self-hosted', NATIVE_DB_VALIDATION.runnerOs, 'X64', runner.label] : hosted;
  } catch { return hosted; }
}
