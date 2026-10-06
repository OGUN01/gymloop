import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataRecord as exactWorkloadData } from './data-record.mjs';
function validWorkloadBinding(value) {
  return typeof value.runId === 'string' && /^[1-9][0-9]*-[1-9][0-9]*$/.test(value.runId)
    && typeof value.sourceSha === 'string' && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(value.sourceSha)
    && typeof value.jobId === 'string' && /^[1-9][0-9]*$/.test(value.jobId)
    && Number.isSafeInteger(value.runnerId) && value.runnerId > 0
    && ['self-hosted', 'github-hosted'].includes(value.runnerEnvironment);
}

/** Validate owner-supplied physical proof metadata against the real failed job. */
export function verifyNativeWorkloadTeardown(expected, receipt) {
  try {
    const binding = ['runId', 'sourceSha', 'jobId', 'runnerId', 'runnerEnvironment'];
    expected = exactWorkloadData(expected, binding);
    receipt = exactWorkloadData(receipt, ['formatVersion', ...binding, 'privateProofSha256', 'nativeProcessesStopped',
      'ownedContainersStopped', 'runnerDeregistered', 'verifiedAt']);
    if (!expected || !validWorkloadBinding(expected) || !receipt || !validWorkloadBinding(receipt)
      || !binding.every(field => receipt[field] === expected[field])
      || receipt.formatVersion !== NATIVE_DB_VALIDATION.formatVersion
      || typeof receipt.privateProofSha256 !== 'string'
      || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(receipt.privateProofSha256)
      || receipt.nativeProcessesStopped !== true || receipt.ownedContainersStopped !== true || receipt.runnerDeregistered !== true
      || typeof receipt.verifiedAt !== 'string') return false;
    const clock = Date.parse(receipt.verifiedAt);
    return Number.isFinite(clock) && new Date(clock).toISOString() === receipt.verifiedAt;
  } catch { return false; }
}
