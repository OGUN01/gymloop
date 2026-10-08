import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord, exactNativeDataArray } from './data-record.mjs';
import { verifyNativeWorkloadTeardown } from './workload-teardown.mjs';

const setupNativeSteps = [
  ['Set up job', 'success'],
  ['Set up runner', 'failure'],
  ['Record adapter setup start before checkout', 'skipped'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'skipped'],
  ['Run pnpm/action-setup@v6', 'skipped'],
  ['Run actions/setup-node@v7', 'skipped'],
  ['Install the frozen adapter dependencies', 'skipped'],
  ['Install the frozen hosted adapter dependencies', 'skipped'],
  ['Use the verified Git Bash executable for the pinned CLI installer', 'skipped'],
  ['Run supabase/setup-cli@v3', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Freeze full rollback-safe file and schema metadata', 'skipped'],
  ['Run actions/upload-artifact@v5', 'skipped'],
  ['Validate the full native suite with outside-worker recovery custody', 'skipped'],
  ['Retain sanitized native receipt', 'success'],
  ['Retain client-only smoke metadata', 'success'],
  ['Retain the explicit interim timing boundary', 'success'],
  ['Retain sanitized encrypted-artifact custody verification', 'success'],
  ['Complete job', 'success'],
];

const setupGuardianSteps = [
  ['Set up job', 'success'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Run pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts', 'success'],
  ['Run supabase/setup-cli@v3', 'success'],
  ['Find the exact armed receipt, including an earlier attempt of this run', 'failure'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run supabase link --project-ref "$PROJECT_REF" --yes', 'skipped'],
  ['Restore and freshly verify only the captured role-global timeout', 'skipped'],
  ['Retain independently hosted restoration evidence', 'skipped'],
  ['Post Run supabase/setup-cli@v3', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
];

const dependencyNativeSteps = [
  ['Set up job', 'success'],
  ['Set up runner', 'success'],
  ['Record adapter setup start before checkout', 'success'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Install the frozen adapter dependencies', 'failure'],
  ['Install the frozen hosted adapter dependencies', 'skipped'],
  ['Use the verified Git Bash executable for the pinned CLI installer', 'skipped'],
  ['Run supabase/setup-cli@v3', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Freeze full rollback-safe file and schema metadata', 'skipped'],
  ['Run actions/upload-artifact@v5', 'skipped'],
  ['Validate the full native suite with outside-worker recovery custody', 'skipped'],
  ['Retain sanitized native receipt', 'success'],
  ['Retain client-only smoke metadata', 'success'],
  ['Retain the explicit interim timing boundary', 'success'],
  ['Retain sanitized encrypted-artifact custody verification', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
];

/** Recognize only the reviewed pre-native/pre-link failure pairs, never armed work. */
export function verifyUnarmedNativeSetupFailure(input) {
  try {
    const data = exactNativeDataRecord(input, ['run', 'nativeJobs', 'guardianJobs', 'artifactNames',
      'jobListingComplete', 'artifactListingComplete', 'teardownReview']);
    if (!data || data.jobListingComplete !== true || data.artifactListingComplete !== true) return false;
    const run = exactNativeDataRecord(data.run, ['id', 'attempt', 'sourceSha', 'repositoryId', 'repository',
      'headRepositoryId', 'headRepository', 'event', 'path', 'branch', 'status', 'conclusion']);
    if (!run || typeof run.id !== 'string' || !/^[1-9][0-9]*$/.test(run.id)
      || !Number.isSafeInteger(Number(run.id)) || run.attempt !== '1'
      || typeof run.sourceSha !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(run.sourceSha)
      || !Number.isSafeInteger(run.repositoryId) || run.repositoryId <= 0
      || run.headRepositoryId !== run.repositoryId || run.repository !== 'OGUN01/gymloop'
      || run.headRepository !== 'OGUN01/gymloop' || !['push', 'workflow_dispatch'].includes(run.event)
      || run.path !== '.github/workflows/db.yml' || run.branch !== 'main'
      || run.status !== 'completed' || run.conclusion !== 'failure') return false;
    const nativeJobs = exactNativeDataArray(data.nativeJobs);
    const guardianJobs = exactNativeDataArray(data.guardianJobs);
    if (!nativeJobs || !guardianJobs || nativeJobs.length !== 1 || guardianJobs.length !== 1) return false;
    const jobs = [nativeJobs[0], guardianJobs[0]].map(job => exactNativeDataRecord(job, ['id', 'runId', 'attempt',
      'sourceSha', 'name', 'status', 'conclusion', 'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps']));
    if (!jobs.every(job => job && Number.isSafeInteger(job.id) && job.id > 0
      && Number.isSafeInteger(job.runnerId) && job.runnerId > 0 && job.runId === run.id
      && job.attempt === run.attempt && job.sourceSha === run.sourceSha && job.status === 'completed'
      && job.conclusion === 'failure' && typeof job.runnerName === 'string' && job.runnerName.length > 0)
      || jobs[0].id === jobs[1].id || jobs[0].runnerId === jobs[1].runnerId) return false;
    const [native, guardian] = jobs;
    if (native.name !== NATIVE_DB_VALIDATION.job || native.runnerGroupName !== 'Default'
      || guardian.name !== 'timeout-guardian' || guardian.runnerGroupName !== 'GitHub Actions'
      || guardian.runnerName !== `GitHub Actions ${guardian.runnerId}`) return false;
    const nativeLabels = exactNativeDataArray(native.labels);
    const guardianLabels = exactNativeDataArray(guardian.labels);
    const expectedLabels = ['self-hosted', 'Windows', 'X64',
      `${NATIVE_DB_VALIDATION.labelPrefix}-${run.id}-${run.attempt}-${run.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`];
    if (!nativeLabels || !guardianLabels || nativeLabels.length !== expectedLabels.length
      || new Set(nativeLabels).size !== expectedLabels.length
      || !expectedLabels.every(label => nativeLabels.includes(label))
      || guardianLabels.length !== 1 || guardianLabels[0] !== 'ubuntu-latest') return false;
    for (const [job, vectors] of [[native, [setupNativeSteps, dependencyNativeSteps]], [guardian, [setupGuardianSteps]]]) {
      const steps = exactNativeDataArray(job.steps);
      if (!steps || !vectors.some(vector => steps.length === vector.length && steps.every((value, index) => {
        const step = exactNativeDataRecord(value, ['name', 'status', 'conclusion']);
        return step && step.name === vector[index][0] && step.status === 'completed'
          && step.conclusion === vector[index][1];
      }))) return false;
    }
    const artifacts = exactNativeDataArray(data.artifactNames);
    const expectedArtifacts = [`native-db-schema-${run.id}-${run.attempt}`, `native-db-ci-job-${run.id}-${run.attempt}`];
    if (!artifacts || artifacts.length !== expectedArtifacts.length
      || new Set(artifacts).size !== expectedArtifacts.length
      || !expectedArtifacts.every(name => artifacts.includes(name))) return false;
    return verifyNativeWorkloadTeardown({runId: `${run.id}-${run.attempt}`, sourceSha: run.sourceSha,
      jobId: String(native.id), runnerId: native.runnerId, runnerEnvironment: 'self-hosted'}, data.teardownReview);
  } catch { return false; }
}
