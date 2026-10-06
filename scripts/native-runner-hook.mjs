import { spawn } from 'node:child_process';
import { isAbsolute } from 'node:path';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../packages/shared/src/config/constants.ts';

const args = process.argv.slice(PHASE8_BACKUP_LIMITS.cliArgumentStart);
let child;
let timer;
let ended = false;
const finish = accepted => {
  if (ended) return;
  ended = true;
  if (timer) globalThis.clearTimeout(timer);
  if (accepted) process.stdout.write('Native runner binding accepted.\n');
  else process.stderr.write('Native runner binding refused: RUNNER_UNTRUSTED.\n');
  process.exitCode = accepted ? 0 : 1;
};
const terminate = () => {
  try { child?.kill('SIGKILL'); } catch { /* status remains a refusal */ }
  finish(false);
  process.exit(1);
};

if (args.length !== NATIVE_DB_VALIDATION.hookArgumentCount || !args.every(path => isAbsolute(path))) finish(false);
else {
  try {
    timer = globalThis.setTimeout(terminate, NATIVE_DB_VALIDATION.processStopGraceMs);
    child = spawn(process.execPath, args, { windowsHide: true, stdio: 'ignore', shell: false });
    child.once('error', () => finish(false));
    child.once('close', (code, signal) => finish(code === 0 && signal === null));
    process.once('SIGINT', terminate);
    process.once('SIGTERM', terminate);
  } catch { finish(false); }
}
