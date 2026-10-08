import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord, exactNativeDataArray, nativeEvidenceClock } from './data-record.mjs';

function unallocatedRun(value, review) {
  const run = exactNativeDataRecord(value, ['id', 'attempt', 'sourceSha', 'repositoryId', 'repository',
    'headRepositoryId', 'headRepository', 'event', 'path', 'branch', 'status', 'conclusion']);
  if (!run || typeof run.id !== 'string' || !/^[1-9]\d*$/.test(run.id)
    || typeof run.attempt !== 'string' || !/^[1-9]\d*$/.test(run.attempt)
    || `${run.id}-${run.attempt}` !== review.runId || run.sourceSha !== review.sourceSha
    || !Number.isSafeInteger(run.repositoryId) || run.repositoryId <= 0
    || run.headRepositoryId !== run.repositoryId
    || run.repository !== NATIVE_DB_VALIDATION.repository || run.headRepository !== run.repository
    || !['push', 'workflow_dispatch'].includes(run.event) || run.path !== '.github/workflows/db.yml'
    || run.branch !== 'main' || run.status !== 'completed' || run.conclusion !== 'cancelled') return null;
  return run;
}

function unallocatedJob(value, run, name, jobId, verifiedAt) {
  const job = exactNativeDataRecord(value, ['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion',
    'runnerId', 'runnerName', 'runnerGroupId', 'runnerGroupName', 'labels', 'steps', 'startedAt', 'completedAt']);
  if (!job || !Number.isSafeInteger(job.id) || job.id <= 0 || String(job.id) !== jobId
    || job.runId !== run.id || job.attempt !== run.attempt || job.sourceSha !== run.sourceSha
    || job.name !== name || job.status !== 'completed' || job.conclusion !== 'cancelled'
    || !['runnerId', 'runnerName', 'runnerGroupId', 'runnerGroupName'].every(field => job[field] === null)) return null;
  const labels = exactNativeDataArray(job.labels);
  const steps = exactNativeDataArray(job.steps);
  if (!labels || !steps || steps.length !== 0
    || !(labels.length === 1 && labels[0] === 'ubuntu-latest'
      || name === NATIVE_DB_VALIDATION.job && labels.length === 0)) return null;
  const startedAt = nativeEvidenceClock(job.startedAt, true);
  const completedAt = nativeEvidenceClock(job.completedAt, true);
  return startedAt !== null && completedAt !== null && startedAt === completedAt && verifiedAt > completedAt ? job : null;
}

/** Classify a reviewed original pair that never received a native or guardian worker. */
export function verifyUnallocatedNativeCancellation(input) {
  try {
    const record = exactNativeDataRecord(input, ['review', 'run', 'nativeJobs', 'guardianJobs', 'artifactNames',
      'jobListingComplete', 'artifactListingComplete']);
    if (!record || record.jobListingComplete !== true || record.artifactListingComplete !== true) return { verified: false };
    const review = exactNativeDataRecord(record.review, ['formatVersion', 'runId', 'sourceSha', 'jobId',
      'guardianJobId', 'completionKind', 'privateProofSha256', 'verifiedAt']);
    if (!review || review.formatVersion !== NATIVE_DB_VALIDATION.formatVersion
      || review.completionKind !== 'unallocated-cancellation'
      || typeof review.runId !== 'string' || !/^[1-9]\d*-[1-9]\d*$/.test(review.runId)
      || typeof review.sourceSha !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(review.sourceSha)
      || typeof review.privateProofSha256 !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(review.privateProofSha256)
      || ![review.jobId, review.guardianJobId].every(value => typeof value === 'string' && /^[1-9]\d*$/.test(value))
      || review.jobId === review.guardianJobId) return { verified: false };
    const verifiedAt = nativeEvidenceClock(review.verifiedAt);
    const run = unallocatedRun(record.run, review);
    const nativeJobs = exactNativeDataArray(record.nativeJobs);
    const guardianJobs = exactNativeDataArray(record.guardianJobs);
    const artifactNames = exactNativeDataArray(record.artifactNames);
    if (verifiedAt === null || !run || !nativeJobs || nativeJobs.length !== 1 || !guardianJobs || guardianJobs.length !== 1
      || !artifactNames || !artifactNames.every(value => typeof value === 'string' && value.length > 0)
      || !unallocatedJob(nativeJobs[0], run, NATIVE_DB_VALIDATION.job, review.jobId, verifiedAt)
      || !unallocatedJob(guardianJobs[0], run, 'timeout-guardian', review.guardianJobId, verifiedAt)) return { verified: false };
    const bound = `${run.id}-${run.attempt}`;
    if (artifactNames.some(name => ['native-db-manifest', 'native-db-recovery', 'native-db-client-smoke', 'native-db-final',
      'native-db-private', 'native-db-private-custody', 'native-db-timing-boundary', 'native-db-ci-job']
      .some(prefix => name === `${prefix}-${bound}`)
      || name === `native-db-restoration-${bound}` || name.startsWith(`native-db-restoration-${bound}-`))) return { verified: false };
    return { verified: true };
  } catch { return { verified: false }; }
}
