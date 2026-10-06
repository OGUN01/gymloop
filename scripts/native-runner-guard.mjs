import { readFileSync, lstatSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { nativeDatabaseValidationEnv } from '../packages/shared/src/config/env.ts';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../packages/shared/src/config/constants.ts';
import { verifyNativeRunnerJob } from './pgtap/runner-job.mjs';

// The operator seals this entry and its imports outside every runner checkout.
try {
  const args = process.argv.slice(PHASE8_BACKUP_LIMITS.cliArgumentStart);
  if (args.length !== 1 || !isAbsolute(args[0])) throw new Error('RUNNER_UNTRUSTED');
  const metadata = lstatSync(args[0]);
  if (!metadata.isFile() || metadata.isSymbolicLink() || metadata.size > NATIVE_DB_VALIDATION.timeoutQueryMaxBytes) throw new Error('RUNNER_UNTRUSTED');
  const expected = JSON.parse(readFileSync(args[0], 'utf8'));
  const runtime = nativeDatabaseValidationEnv();
  const observed = {
    repository: runtime.GITHUB_REPOSITORY, eventName: runtime.GITHUB_EVENT_NAME,
    ref: runtime.GITHUB_REF, sourceSha: runtime.GITHUB_SHA,
    runId: runtime.GITHUB_RUN_ID, runAttempt: runtime.GITHUB_RUN_ATTEMPT,
    workflowRef: runtime.GITHUB_WORKFLOW_REF, runnerOs: runtime.RUNNER_OS,
    job: runtime.GITHUB_JOB,
  };
  if (!verifyNativeRunnerJob(expected, observed).trusted) throw new Error('RUNNER_UNTRUSTED');
  process.stdout.write('Native runner binding accepted.\n');
} catch {
  process.stderr.write('Native runner binding refused: RUNNER_UNTRUSTED.\n');
  process.exitCode = 1;
}
