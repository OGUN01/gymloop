import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord as exactUnarmedData, exactNativeDataArray as unarmedArray } from './data-record.mjs';

function unarmedHex(value, length = NATIVE_DB_VALIDATION.digestHexLength) {
  return typeof value === 'string' && new RegExp(`^[a-f0-9]{${length}}$`).test(value);
}

function unarmedUtc(value) {
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) return false;
  const timestamp = Date.parse(value);
  return unarmedCount(timestamp) && new Date(timestamp).toISOString() === value;
}

function unarmedCount(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function unarmedJob(value, run, name) {
  const job = exactUnarmedData(value, ['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion',
    'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps']);
  if (!job || !unarmedCount(job.id) || job.id === 0 || !unarmedCount(job.runnerId) || job.runnerId === 0
    || job.runId !== run.id || job.attempt !== run.attempt || job.sourceSha !== run.sourceSha
    || job.name !== name || job.status !== 'completed' || job.conclusion !== 'failure'
    || job.runnerGroupName !== 'GitHub Actions' || job.runnerName !== `GitHub Actions ${job.runnerId}`) return null;
  const labels = unarmedArray(job.labels);
  const rawSteps = unarmedArray(job.steps);
  if (!labels || labels.length !== 1 || labels[0] !== 'ubuntu-latest' || !rawSteps) return null;
  const steps = rawSteps.map(step => exactUnarmedData(step, ['name', 'status', 'conclusion']));
  const failedStep = name === NATIVE_DB_VALIDATION.job
    ? 'Validate the full native suite with outside-worker recovery custody'
    : 'Find the exact armed receipt, including an earlier attempt of this run';
  if (!steps.every(step => step && typeof step.name === 'string' && step.name.length > 0
    && step.status === 'completed' && (step.name === failedStep ? step.conclusion === 'failure'
      : ['success', 'skipped'].includes(step.conclusion)))) return null;
  const mandatory = [
    ['Post Run supabase/setup-cli@v3', 'success'],
    ['Post Run pnpm/action-setup@v6', 'success'],
    ['Post Run actions/checkout@v7', 'success'],
    ['Complete job', 'success'],
    [failedStep, 'failure'],
    ...(name === NATIVE_DB_VALIDATION.job ? [['Retain client-only smoke metadata', 'success']]
      : [['Run supabase link --project-ref "$PROJECT_REF" --yes', 'skipped'],
        ['Restore and freshly verify only the captured role-global timeout', 'skipped']]),
  ];
  if (!mandatory.every(([stepName, conclusion]) => {
    const matches = steps.filter(step => step.name === stepName);
    return matches.length === 1 && matches[0].conclusion === conclusion;
  })) return null;
  return job;
}

function unarmedSmoke(value, sourceSha) {
  const smoke = exactUnarmedData(value, ['formatVersion', 'sourceSha', 'cliVersion', 'clientDigest', 'runnerOs', 'network',
    'nativeClientImage', 'nativeClientImageId', 'imageSelectionSource', 'firstDirectoryCwd', 'readOnlyBinds',
    'reportingLines', 'stubSha256', 'capturedAt', 'cases', 'accepted']);
  if (!smoke || smoke.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || smoke.sourceSha !== sourceSha
    || smoke.cliVersion !== NATIVE_DB_VALIDATION.cliVersion || smoke.clientDigest !== NATIVE_DB_VALIDATION.clientDigest
    || smoke.nativeClientImage !== NATIVE_DB_VALIDATION.nativeClientImage || smoke.runnerOs !== 'Linux'
    || smoke.network !== 'host' || smoke.firstDirectoryCwd !== true || smoke.readOnlyBinds !== true
    || typeof smoke.nativeClientImageId !== 'string' || !smoke.nativeClientImageId.startsWith('sha256:')
    || !unarmedHex(smoke.nativeClientImageId.slice('sha256:'.length))
    || smoke.imageSelectionSource !== 'https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/shared/legacy-docker-registry.ts'
    || !unarmedHex(smoke.stubSha256) || !unarmedUtc(smoke.capturedAt) || smoke.accepted !== false) return false;
  const reporting = unarmedArray(smoke.reportingLines);
  const rawCases = unarmedArray(smoke.cases);
  const names = ['success', 'assertion-failure', 'missing-plan', 'extra-plan', 'broken-plan', 'malformed',
    'truncated', 'client-error', 'connection-loss'];
  if (!reporting || reporting.length !== NATIVE_DB_VALIDATION.reportingLines.length
    || !reporting.every((line, index) => line === NATIVE_DB_VALIDATION.reportingLines[index])
    || !rawCases || rawCases.length !== names.length) return false;
  const cases = rawCases.map(item => exactUnarmedData(item, ['name', 'exitCode', 'completed', 'signal', 'nativeMs',
    'stdoutSha256', 'stderrSha256', 'timerCount', 'rawTapPresent', 'inputsUnchanged', 'fileMetadata', 'checkPassed']));
  if (!cases.every((item, index) => {
    if (!item || item.name !== names[index] || ![0, 1].includes(item.exitCode) || item.completed !== true
      || item.signal !== null || !unarmedCount(item.nativeMs) || !unarmedCount(item.timerCount)
      || !unarmedHex(item.stdoutSha256) || !unarmedHex(item.stderrSha256) || item.inputsUnchanged !== true
      || typeof item.rawTapPresent !== 'boolean' || typeof item.checkPassed !== 'boolean') return false;
    const rawFiles = unarmedArray(item.fileMetadata);
    const paths = ['supabase/tests/.proverc', 'supabase/tests-holdout/independent.pg',
      `supabase/tests/${['client-error', 'connection-loss'].includes(item.name) ? item.name : 'visible'}.sql`];
    if (!rawFiles || rawFiles.length !== paths.length) return false;
    const files = rawFiles.map(file => exactUnarmedData(file, ['path', 'sha256', 'byteLength']));
    return files.every(file => file && paths.includes(file.path) && unarmedHex(file.sha256)
      && unarmedCount(file.byteLength) && file.byteLength > 0)
      && new Set(files.map(file => file.path)).size === paths.length;
  })) return false;
  return cases[0].checkPassed === false && smoke.accepted === cases.every(item => item.checkPassed);
}

/** Classify exact independently reviewed hosted client-only refusal; never restoration or native success. */
export function verifyUnarmedNativePrecheck(input) {
  try {
    const record = exactUnarmedData(input, ['review', 'run', 'nativeJob', 'guardianJob', 'smokeArchive', 'smoke',
      'sourceHashes', 'recoveryArtifactPresent', 'artifactListingComplete']);
    if (!record || record.recoveryArtifactPresent !== false || record.artifactListingComplete !== true) return { verified: false };
    const review = exactUnarmedData(record.review, ['formatVersion', 'runId', 'runAttempt', 'sourceSha', 'nativeJobId',
      'guardianJobId', 'runnerId', 'adapterSha256', 'workflowSha256', 'smokeArtifactId', 'smokeArchiveSha256',
      'privateProofSha256', 'reviewedAt']);
    const run = exactUnarmedData(record.run, ['id', 'attempt', 'sourceSha', 'event', 'branch', 'status', 'conclusion']);
    const archive = exactUnarmedData(record.smokeArchive, ['id', 'name', 'runId', 'sourceSha', 'apiSha256', 'archiveSha256', 'expired']);
    const sources = exactUnarmedData(record.sourceHashes, ['adapterSha256', 'workflowSha256']);
    if (!review || !run || !archive || !sources || typeof run.id !== 'string' || !/^[1-9][0-9]*$/.test(run.id)
      || typeof run.attempt !== 'string' || !/^[1-9][0-9]*$/.test(run.attempt)
      || !unarmedHex(run.sourceSha, NATIVE_DB_VALIDATION.sourceShaLength)
      || !['push', 'workflow_dispatch'].includes(run.event) || run.branch !== 'main'
      || run.status !== 'completed' || run.conclusion !== 'failure'
      || review.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || review.runId !== run.id
      || review.runAttempt !== run.attempt || review.sourceSha !== run.sourceSha
      || !unarmedHex(review.privateProofSha256) || !unarmedUtc(review.reviewedAt)
      || !unarmedHex(sources.adapterSha256) || !unarmedHex(sources.workflowSha256)
      || review.adapterSha256 !== sources.adapterSha256 || review.workflowSha256 !== sources.workflowSha256
      || !unarmedCount(archive.id) || archive.id === 0 || review.smokeArtifactId !== archive.id
      || archive.name !== `native-db-client-smoke-${run.id}-${run.attempt}`
      || archive.runId !== run.id || archive.sourceSha !== run.sourceSha || archive.expired !== false
      || !unarmedHex(archive.apiSha256) || !unarmedHex(archive.archiveSha256)
      || archive.apiSha256 !== archive.archiveSha256 || review.smokeArchiveSha256 !== archive.archiveSha256) return { verified: false };
    const native = unarmedJob(record.nativeJob, run, NATIVE_DB_VALIDATION.job);
    const guardian = unarmedJob(record.guardianJob, run, 'timeout-guardian');
    const verified = native !== null && guardian !== null && review.nativeJobId === native.id
      && review.guardianJobId === guardian.id && review.runnerId === native.runnerId
      && unarmedSmoke(record.smoke, run.sourceSha);
    return { verified };
  } catch { return { verified: false }; }
}
