import { createHash } from 'node:crypto';
import { NATIVE_DB_VALIDATION as limits, NATIVE_DB_OWNER_BASELINE as authority } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord as record, exactNativeDataArray as array, nativeEvidenceClock as clock } from './data-record.mjs';
import { verifyNativeWorkloadTeardown } from './workload-teardown.mjs';

const ownerBaselineSetSteps = ['Set up job', 'Run actions/checkout@v7', 'Run pnpm/action-setup@v6', 'Run actions/setup-node@v7',
  'Install the frozen owner-baseline adapter dependencies', 'Run supabase/setup-cli@v3', 'Stage the accepted original workload teardown',
  'Read the existing owner-baseline retention limit', 'Configure the owner-approved trial19 timeout baseline',
  'Retain owner baseline configuration evidence', 'Post Run supabase/setup-cli@v3', 'Post Run actions/setup-node@v7',
  'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job'];
const ownerBaselineVerifySteps = ownerBaselineSetSteps.map(name => name === 'Configure the owner-approved trial19 timeout baseline'
  ? 'Independently verify the owner-approved trial19 timeout baseline' : name === 'Retain owner baseline configuration evidence'
    ? 'Retain independent owner baseline verification evidence' : name);

/** Admit only the independently reviewed configured state of the owner-approved fixed attempt. */
export function verifyOwnerConfiguredTimeoutBaseline(context, envelope) {
  try {
    context = record(context, ['targetRun', 'targetNativeJob', 'targetGuardianJob', 'targetArtifactNames', 'maintenanceRun',
      'setterJob', 'verifierJob', 'jobListingComplete', 'artifactListingComplete']);
    envelope = record(envelope, ['review', 'setArchive', 'baselineArchive', 'setReceipt', 'baselineReceipt', 'teardownReview']);
    if (!context || !envelope || context.jobListingComplete !== true || context.artifactListingComplete !== true) return false;
    const positive = value => Number.isSafeInteger(value) && value > 0;
    const decimal = value => typeof value === 'string' && /^[1-9]\d*$/.test(value);
    const digest = value => typeof value === 'string' && new RegExp(`^[a-f0-9]{${limits.digestHexLength}}$`).test(value);
    const source = value => typeof value === 'string' && new RegExp(`^[a-f0-9]{${limits.sourceShaLength}}$`).test(value);
    const hash = value => createHash('sha256').update(`${JSON.stringify(value)}\n`, 'utf8').digest('hex');
    const setting = value => {
      const observed = record(value, ['originalPresent', 'originalValue']);
      return observed && typeof observed.originalPresent === 'boolean' && (observed.originalPresent
        ? typeof observed.originalValue === 'string' && observed.originalValue.length > 0 : observed.originalValue === null);
    };
    const configured = value => setting(value) && value.originalPresent === true && value.originalValue === authority.configured.originalValue;
    const target = value => {
      value = record(value, ['projectRef', 'role', 'parameter']);
      return value && ['projectRef', 'role', 'parameter'].every(field => value[field] === limits[field]);
    };
    const run = value => {
      value = record(value, ['id', 'attempt', 'sourceSha', 'repositoryId', 'repository', 'headRepositoryId', 'headRepository',
        'event', 'path', 'branch', 'status', 'conclusion', 'actorLogin', 'triggeringActorLogin', 'startedAt', 'updatedAt']);
      if (!value || !decimal(value.id) || !decimal(value.attempt) || !source(value.sourceSha) ||
          value.repositoryId !== authority.repositoryId || value.headRepositoryId !== authority.repositoryId ||
          value.repository !== limits.repository || value.headRepository !== limits.repository || value.branch !== 'main' ||
          value.status !== 'completed' || clock(value.startedAt, true) === null || clock(value.updatedAt, true) === null ||
          clock(value.startedAt, true) > clock(value.updatedAt, true)) return null;
      return value;
    };
    const job = value => {
      value = record(value, ['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion', 'runnerId', 'runnerName',
        'runnerGroupName', 'labels', 'steps', 'startedAt', 'completedAt']);
      if (!value || !positive(value.id) || !decimal(value.runId) || !decimal(value.attempt) || !source(value.sourceSha) ||
          !positive(value.runnerId) || value.status !== 'completed' || clock(value.startedAt, true) === null ||
          clock(value.completedAt, true) === null || clock(value.startedAt, true) > clock(value.completedAt, true)) return null;
      value.labels = array(value.labels); value.steps = array(value.steps)?.map(step => record(step, ['name', 'status', 'conclusion']));
      if (!value.labels || !value.labels.every(label => typeof label === 'string') || !value.steps ||
          value.steps.some(step => !step || typeof step.name !== 'string' || step.status !== 'completed' ||
            !['success', 'failure', 'skipped'].includes(step.conclusion))) return null;
      return value;
    };
    const review = record(envelope.review, ['formatVersion', 'authorityKind', 'targetRunId', 'targetRunAttempt', 'targetSourceSha',
      'targetNativeJobId', 'targetRunnerId', 'maintenanceRunId', 'maintenanceRunAttempt', 'maintenanceSourceSha', 'setterJobId',
      'verifierJobId', 'setArtifactId', 'setArchiveSha256', 'baselineArtifactId', 'baselineArchiveSha256',
      'teardownPrivateProofSha256', 'privateProofSha256', 'reviewedAt']);
    const commonFields = ['formatVersion', 'authorityKind', 'targetRunId', 'targetRunAttempt', 'targetSourceSha', 'targetNativeJobId',
      'targetRunnerId', 'maintenanceRunId', 'maintenanceRunAttempt', 'maintenanceSourceSha', 'target', 'configured'];
    const setReceipt = record(envelope.setReceipt, [...commonFields, 'setterJobId', 'before', 'beforeCapturedAt', 'requestedAt']);
    const baselineReceipt = record(envelope.baselineReceipt, [...commonFields, 'setterJobId', 'verifierJobId', 'setReceiptSha256',
      'observed', 'verified', 'verifiedAt']);
    if (!review || !setReceipt || !baselineReceipt || ![review, setReceipt, baselineReceipt].every(value =>
      value.formatVersion === limits.formatVersion && value.authorityKind === authority.authorityKind &&
      ['targetRunId', 'targetRunAttempt', 'targetSourceSha', 'targetNativeJobId', 'targetRunnerId'].every(field => value[field] === authority[field]) &&
      decimal(value.maintenanceRunId) && value.maintenanceRunAttempt === authority.targetRunAttempt && source(value.maintenanceSourceSha) &&
      value.maintenanceRunId === review.maintenanceRunId && value.maintenanceSourceSha === review.maintenanceSourceSha)) return false;
    if (!positive(review.setterJobId) || !positive(review.verifierJobId) || review.setterJobId === review.verifierJobId ||
        !positive(review.setArtifactId) || !positive(review.baselineArtifactId) || review.setArtifactId === review.baselineArtifactId ||
        !digest(review.setArchiveSha256) || !digest(review.baselineArchiveSha256) || !digest(review.privateProofSha256) ||
        review.teardownPrivateProofSha256 !== authority.teardownPrivateProofSha256 || clock(review.reviewedAt) === null ||
        ![setReceipt, baselineReceipt].every(value => target(value.target) && configured(value.configured)) ||
        setReceipt.setterJobId !== review.setterJobId || baselineReceipt.setterJobId !== review.setterJobId ||
        baselineReceipt.verifierJobId !== review.verifierJobId || !setting(setReceipt.before) ||
        baselineReceipt.verified !== true || !configured(baselineReceipt.observed) ||
        baselineReceipt.setReceiptSha256 !== hash(setReceipt)) return false;
    const original = run(context.targetRun); const maintenance = run(context.maintenanceRun);
    const native = job(context.targetNativeJob); const guardian = job(context.targetGuardianJob);
    const setter = job(context.setterJob); const verifier = job(context.verifierJob);
    if (!original || !maintenance || !native || !guardian || !setter || !verifier ||
        original.id !== authority.targetRunId || original.attempt !== authority.targetRunAttempt || original.sourceSha !== authority.targetSourceSha ||
        original.event !== 'push' || original.path !== limits.workflowRef.slice(`${limits.repository}/`.length).split('@')[0] || original.conclusion !== 'failure' ||
        maintenance.id !== review.maintenanceRunId || maintenance.attempt !== review.maintenanceRunAttempt ||
        maintenance.sourceSha !== review.maintenanceSourceSha || maintenance.event !== 'workflow_dispatch' ||
        maintenance.path !== authority.workflowPath || maintenance.conclusion !== 'success' ||
        maintenance.actorLogin !== authority.ownerLogin || maintenance.triggeringActorLogin !== authority.ownerLogin) return false;
    const binding = (value, expected) => value.runId === expected.id && value.attempt === expected.attempt && value.sourceSha === expected.sourceSha &&
      clock(value.startedAt, true) >= clock(expected.startedAt, true) && clock(value.completedAt, true) <= clock(expected.updatedAt, true);
    const failedStep = (value, name, conclusion) => value.steps.filter(step => step.name === name).length === 1 &&
      value.steps.some(step => step.name === name && step.conclusion === conclusion);
    if (!binding(native, original) || !binding(guardian, original) || String(native.id) !== authority.targetNativeJobId ||
        native.name !== limits.job || native.runnerId !== authority.targetRunnerId || native.runnerName !== authority.targetRunnerName ||
        native.runnerGroupName !== 'Default' || JSON.stringify(native.labels) !== JSON.stringify(authority.targetLabels) ||
        native.conclusion !== 'failure' || !failedStep(native, authority.nativeStep, 'failure') ||
        guardian.id !== authority.targetGuardianJobId || guardian.name !== 'timeout-guardian' || guardian.conclusion !== 'failure' ||
        !failedStep(guardian, authority.guardianFindStep, 'failure') || !failedStep(guardian, authority.guardianLinkStep, 'skipped') ||
        !failedStep(guardian, authority.guardianRestoreStep, 'skipped')) return false;
    const hosted = (value, id, name, steps) => binding(value, maintenance) && value.id === id && value.name === name && value.conclusion === 'success' &&
      value.runnerName === `GitHub Actions ${value.runnerId}` && value.runnerGroupName === 'GitHub Actions' &&
      JSON.stringify(value.labels) === JSON.stringify(['ubuntu-latest']) && value.steps.length === steps.length &&
      value.steps.every((step, index) => step.name === steps[index] && (step.conclusion === 'success' ||
        step.name === 'Post Run actions/setup-node@v7' && step.conclusion === 'skipped'));
    if (!hosted(setter, review.setterJobId, authority.setJob, ownerBaselineSetSteps) ||
        !hosted(verifier, review.verifierJobId, authority.verifyJob, ownerBaselineVerifySteps) || setter.runnerId === verifier.runnerId ||
        clock(verifier.startedAt, true) < clock(setter.completedAt, true)) return false;
    const names = array(context.targetArtifactNames);
    if (!names || names.length !== authority.targetArtifactNames.length || new Set(names).size !== names.length ||
        !authority.targetArtifactNames.every(name => names.includes(name))) return false;
    const archive = (value, id, prefix, expectedHash, receipt) => {
      value = record(value, ['id', 'name', 'runId', 'sourceSha', 'repositoryId', 'headRepositoryId', 'sizeBytes', 'apiSha256',
        'archiveSha256', 'bodySha256', 'expired']);
      return value && value.id === id && value.name === `${prefix}${maintenance.id}-${maintenance.attempt}` &&
        value.runId === maintenance.id && value.sourceSha === maintenance.sourceSha && value.repositoryId === authority.repositoryId &&
        value.headRepositoryId === authority.repositoryId && positive(value.sizeBytes) && value.sizeBytes <= limits.timeoutQueryMaxBytes &&
        value.expired === false && digest(value.apiSha256) && value.apiSha256 === expectedHash && value.archiveSha256 === expectedHash &&
        digest(value.bodySha256) && value.bodySha256 === hash(receipt);
    };
    if (!archive(envelope.setArchive, review.setArtifactId, authority.setArtifactPrefix, review.setArchiveSha256, setReceipt) ||
        !archive(envelope.baselineArchive, review.baselineArtifactId, authority.verifiedArtifactPrefix, review.baselineArchiveSha256, baselineReceipt)) return false;
    const teardown = envelope.teardownReview;
    const expected = { runId: `${authority.targetRunId}-${authority.targetRunAttempt}`, sourceSha: authority.targetSourceSha,
      jobId: authority.targetNativeJobId, runnerId: authority.targetRunnerId, runnerEnvironment: 'self-hosted' };
    if (!verifyNativeWorkloadTeardown(expected, teardown) || teardown.privateProofSha256 !== authority.teardownPrivateProofSha256 ||
        teardown.verifiedAt !== authority.teardownVerifiedAt) return false;
    const beforeAt = clock(setReceipt.beforeCapturedAt); const requestedAt = clock(setReceipt.requestedAt);
    const verifiedAt = clock(baselineReceipt.verifiedAt); const reviewedAt = clock(review.reviewedAt);
    return beforeAt !== null && requestedAt !== null && verifiedAt !== null &&
      beforeAt >= clock(setter.startedAt, true) && requestedAt >= beforeAt && requestedAt <= clock(setter.completedAt, true) &&
      verifiedAt > clock(setter.completedAt, true) && verifiedAt >= clock(verifier.startedAt, true) && verifiedAt <= clock(verifier.completedAt, true) &&
      reviewedAt >= clock(maintenance.updatedAt, true) && reviewedAt >= clock(verifier.completedAt, true) &&
      clock(maintenance.startedAt, true) >= clock(teardown.verifiedAt);
  } catch { return false; }
}
