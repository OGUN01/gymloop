import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock as hostedCompletionClock } from './data-record.mjs';

/** Verify provider-guaranteed hosted completion without inventing deletion observations. */
export function verifyHostedNativeWorkloadCompletion(expected, job, receipt) {
  try {
    if (![expected, job, receipt].every(value => value !== null && typeof value === 'object'
      && Object.getPrototypeOf(value) === Object.prototype)) return false;
    const binding = ['runId', 'sourceSha', 'jobId', 'runnerId', 'runnerEnvironment'];
    expected = exactNativeDataRecord(expected, binding);
    receipt = exactNativeDataRecord(receipt, ['formatVersion', ...binding, 'privateProofSha256', 'completionKind', 'verifiedAt']);
    job = exactNativeDataRecord(job, ['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion',
      'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps', 'completedAt']);
    if (!expected || !receipt || !job || expected.runnerEnvironment !== 'github-hosted'
      || typeof expected.runId !== 'string' || !/^[1-9]\d*-[1-9]\d*$/.test(expected.runId)
      || typeof expected.jobId !== 'string' || !/^[1-9]\d*$/.test(expected.jobId)
      || typeof expected.sourceSha !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(expected.sourceSha)
      || !Number.isSafeInteger(expected.runnerId) || expected.runnerId <= 0
      || !binding.every(field => expected[field] === receipt[field])
      || receipt.formatVersion !== NATIVE_DB_VALIDATION.formatVersion
      || receipt.completionKind !== 'github-hosted-job-decommission'
      || typeof receipt.privateProofSha256 !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(receipt.privateProofSha256)
      || !Number.isSafeInteger(job.id) || job.id <= 0 || String(job.id) !== expected.jobId
      || job.sourceSha !== expected.sourceSha || job.runnerId !== expected.runnerId
      || job.name !== NATIVE_DB_VALIDATION.job || job.status !== 'completed'
      || !['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure'].includes(job.conclusion)
      || job.runnerName !== `GitHub Actions ${expected.runnerId}` || job.runnerGroupName !== 'GitHub Actions') return false;
    const [runId, attempt] = expected.runId.split('-');
    if (job.runId !== runId || job.attempt !== attempt) return false;
    const labels = exactNativeDataArray(job.labels);
    const rawSteps = exactNativeDataArray(job.steps);
    if (!labels || labels.length !== 1 || labels[0] !== 'ubuntu-latest' || !rawSteps || rawSteps.length === 0) return false;
    const steps = rawSteps.map(step => step !== null && typeof step === 'object' && Object.getPrototypeOf(step) === Object.prototype
      ? exactNativeDataRecord(step, ['name', 'status', 'conclusion']) : null);
    if (!steps.every(step => step && typeof step.name === 'string' && step.name.length > 0 && step.status === 'completed'
      && ['success', 'failure', 'skipped', 'cancelled', 'timed_out'].includes(step.conclusion))) return false;
    if (!['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job']
      .every(name => {
        const matches = steps.filter(step => step.name === name);
        return matches.length === 1 && matches[0].conclusion === 'success';
      })) return false;
    const completedAt = hostedCompletionClock(job.completedAt, true);
    const verifiedAt = hostedCompletionClock(receipt.verifiedAt);
    return completedAt !== null && verifiedAt !== null && verifiedAt > completedAt;
  } catch { return false; }
}
