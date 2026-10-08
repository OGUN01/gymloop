import { spawn, type ChildProcessWithoutNullStreams } from 'node:child_process';
import { access, chmod, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { basename, isAbsolute, join, relative, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Independent CLI contract author: frozen operational paragraph and declared
// central fields only. No launcher/guard implementation or visible tests read.
const hookPath = fileURLToPath(new URL('../../scripts/native-runner-hook.mjs', import.meta.url));
const envModuleUrl = new URL('../../packages/shared/src/config/env.ts', import.meta.url).href;
const verifierModuleUrl = new URL('../../scripts/pgtap/runner-job.mjs', import.meta.url).href;
// Absence is a collection-red prerequisite; it must not become a green skip.
await access(hookPath);
const tempParent = resolve(tmpdir());
const prefix = 'gymloop-held-hook-';
const acceptedText = 'Native runner binding accepted.';
const refusedText = 'Native runner binding refused: RUNNER_UNTRUSTED.';
const canary = 'PRIVATE_HELD_CHILD_DIAGNOSTIC_738251';
const deadlineMs = NATIVE_DB_VALIDATION.processStopGraceMs;
const outerMs = deadlineMs + 7000;
const syntheticSha = '719805c6feac814320e97dcd383a7f049e821020';
const syntheticRun = '548293';
const syntheticAttempt = '2';
const expectedBinding = {
  sourceSha: syntheticSha, runId: syntheticRun, runAttempt: syntheticAttempt,
  label: `fitcruxx-db-win-x64-${syntheticRun}-${syntheticAttempt}-${syntheticSha.slice(0, 12)}`,
};
let ownTemp = '';
let fixtureSequence = 0;
const ownChildren = new Set<ChildProcessWithoutNullStreams>();
const ownGuardPids = new Set<number>();

type Capture = {
  code: number | null; signal: NodeJS.Signals | null; stdout: string; stderr: string;
  elapsedMs: number; outerTimedOut: boolean; launcherPid: number | undefined;
};
type Fixture = { guardPath: string; bindingPath: string; markerPath: string };
type ChildReceipt = { pid: number; ppid: number; execPath: string; args: string[] };

function controlledIdentity(): Record<string, string> {
  return {
    GITHUB_REPOSITORY: 'OGUN01/gymloop', GITHUB_EVENT_NAME: 'push',
    GITHUB_REF: 'refs/heads/main', GITHUB_SHA: syntheticSha,
    GITHUB_RUN_ID: syntheticRun, GITHUB_RUN_ATTEMPT: syntheticAttempt,
    GITHUB_WORKFLOW_REF: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
    GITHUB_JOB: 'pgtap', RUNNER_OS: 'Windows',
  };
}

function alive(pid: number) {
  try { process.kill(pid, 0); return true; } catch { return false; }
}

async function stopped(pid: number) {
  const until = performance.now() + 1500;
  while (alive(pid) && performance.now() < until) await new Promise(done => setTimeout(done, 25));
  return !alive(pid);
}

async function fixture(body: string): Promise<Fixture> {
  fixtureSequence += 1;
  const stem = `fixture ${fixtureSequence} β`;
  const guardPath = join(ownTemp, `${stem}.mjs`);
  const bindingPath = join(ownTemp, `${stem}.binding.json`);
  const markerPath = join(ownTemp, `${stem}.child.json`);
  const source = [
    "import { writeFileSync } from 'node:fs';",
    `writeFileSync(${JSON.stringify(markerPath)}, JSON.stringify({pid:process.pid,ppid:process.ppid,execPath:process.execPath,args:process.argv.slice(2)}), {mode:0o600});`,
    body,
    '',
  ].join('\n');
  await writeFile(guardPath, source, { mode: 0o600 });
  await writeFile(bindingPath, `${JSON.stringify(expectedBinding)}\n`, { mode: 0o600 });
  return { guardPath, bindingPath, markerPath };
}

async function captureHook(args: string[], environment: Record<string, string> = {}): Promise<Capture> {
  const started = performance.now();
  const child = spawn(process.execPath, [hookPath, ...args], {
    cwd: ownTemp, env: environment, windowsHide: true, stdio: 'pipe',
  });
  ownChildren.add(child);
  const stdout: Buffer[] = [];
  const stderr: Buffer[] = [];
  child.stdout.on('data', (chunk: Buffer) => stdout.push(Buffer.from(chunk)));
  child.stderr.on('data', (chunk: Buffer) => stderr.push(Buffer.from(chunk)));
  let outerTimedOut = false;
  const timer = setTimeout(() => { outerTimedOut = true; child.kill('SIGKILL'); }, outerMs);
  const result = await new Promise<Capture>((done, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => done({
      code, signal, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8'),
      elapsedMs: performance.now() - started, outerTimedOut, launcherPid: child.pid,
    }));
  }).finally(() => { clearTimeout(timer); ownChildren.delete(child); });
  // Captures stay in this private disposable fixture directory, never stdout.
  await writeFile(join(ownTemp, `capture-${fixtureSequence}-${performance.now().toFixed(3)}.json`), JSON.stringify(result), { mode: 0o600 });
  return result;
}

function genericFailure(result: Capture) {
  expect(result.code).not.toBe(0);
  expect(result.outerTimedOut).toBe(false);
  expect(`${result.stdout}${result.stderr}`.trim()).toBe(refusedText);
  expect(`${result.stdout}${result.stderr}`).not.toContain(canary);
  expect(`${result.stdout}${result.stderr}`).not.toContain(ownTemp);
  expect(`${result.stdout}${result.stderr}`).not.toContain('Error:');
}

async function childReceipt(created: Fixture, launcherPid: number | undefined) {
  const value = JSON.parse(await readFile(created.markerPath, 'utf8')) as ChildReceipt;
  expect(Number.isSafeInteger(value.pid) && value.pid > 0).toBe(true);
  ownGuardPids.add(value.pid);
  expect(value.ppid).toBe(launcherPid);
  expect(resolve(value.execPath)).toBe(resolve(process.execPath));
  return value;
}

beforeAll(async () => {
  ownTemp = await mkdtemp(join(tempParent, prefix));
  await chmod(ownTemp, 0o700);
});

afterAll(async () => {
  for (const child of ownChildren) if (child.pid !== undefined && alive(child.pid)) child.kill('SIGKILL');
  for (const pid of ownGuardPids) if (alive(pid)) process.kill(pid, 'SIGKILL');
  for (const pid of ownGuardPids) await stopped(pid);
  if (ownTemp !== '') {
    const actualParent = await realpath(tempParent);
    const actualTemp = await realpath(ownTemp);
    const within = relative(actualParent, actualTemp);
    if (within.startsWith('..') || isAbsolute(within) || basename(actualTemp).startsWith(prefix) === false || within === '') {
      throw new Error('Refusing fixture cleanup outside the verified own temporary directory.');
    }
    await rm(actualTemp, { recursive: true, force: false });
  }
});

describe('DBV-008 held exact bounded hook CLI', () => {
  it('starts the native Node executable with only guard/binding argv and ignores successful child streams', async () => {
    const created = await fixture(`process.stdout.write(${JSON.stringify(canary)}); process.stderr.write(${JSON.stringify(canary)}); process.exit(0);`);
    const result = await captureHook([created.guardPath, created.bindingPath]);
    expect(result.code).toBe(0);
    expect(result.signal).toBeNull();
    expect(result.outerTimedOut).toBe(false);
    expect(`${result.stdout}${result.stderr}`.trim()).toBe(acceptedText);
    expect(result.elapsedMs).toBeLessThan(deadlineMs / 2);
    expect((await childReceipt(created, result.launcherPid)).args).toEqual([created.bindingPath]);
  });

  it('leaves binding custody to the guard and does not read a missing binding path itself', async () => {
    const created = await fixture('process.exit(0);');
    const missingBinding = join(ownTemp, 'deliberately absent binding.json');
    const result = await captureHook([created.guardPath, missingBinding]);
    expect(result.code).toBe(0);
    expect(`${result.stdout}${result.stderr}`.trim()).toBe(acceptedText);
    expect((await childReceipt(created, result.launcherPid)).args).toEqual([missingBinding]);
  });

  it.each(['none', 'one', 'extra', 'relative guard', 'relative binding', 'empty guard', 'empty binding', 'file URL'])('rejects %s arguments before any fixture child can launch', async kind => {
    const created = await fixture('process.exit(0);');
    let args = [created.guardPath, created.bindingPath];
    if (kind === 'none') args = [];
    if (kind === 'one') args = [created.guardPath];
    if (kind === 'extra') args.push(canary);
    if (kind === 'relative guard') args[0] = basename(created.guardPath);
    if (kind === 'relative binding') args[1] = basename(created.bindingPath);
    if (kind === 'empty guard') args[0] = '';
    if (kind === 'empty binding') args[1] = '';
    if (kind === 'file URL') args[0] = new URL(`file:///${created.guardPath.replaceAll('\\', '/')}`).href;
    genericFailure(await captureHook(args));
    await expect(access(created.markerPath)).rejects.toMatchObject({ code: 'ENOENT' });
  });

  it.each([1, 7, 255])('refuses guard exit %i without forwarding either raw stream', async exitCode => {
    const created = await fixture(`process.stdout.write(${JSON.stringify(canary)}); process.stderr.write(${JSON.stringify(canary)}); process.exit(${exitCode});`);
    const result = await captureHook([created.guardPath, created.bindingPath]);
    genericFailure(result);
    expect((await childReceipt(created, result.launcherPid)).args).toEqual([created.bindingPath]);
  });

  it('refuses an uncaught guard exception without revealing the underlying message or stack', async () => {
    const created = await fixture(`throw new Error(${JSON.stringify(canary)});`);
    const result = await captureHook([created.guardPath, created.bindingPath]);
    genericFailure(result);
    await childReceipt(created, result.launcherPid);
  });

  it('refuses a guard terminated by signal rather than treating null exit as successful', async () => {
    const created = await fixture("process.kill(process.pid, 'SIGTERM');");
    genericFailure(await captureHook([created.guardPath, created.bindingPath]));
  });

  it('refuses a missing absolute guard without leaking the native loader error', async () => {
    const bindingPath = join(ownTemp, 'unused binding.json');
    genericFailure(await captureHook([join(ownTemp, 'missing guard.mjs'), bindingPath]));
  });

  it('enforces the actual ten-second child bound and kills only its exact guard', async () => {
    const sentinelFixture = await fixture('setInterval(() => {}, 1000);');
    const sentinel = spawn(process.execPath, [sentinelFixture.guardPath, sentinelFixture.bindingPath], {
      cwd: ownTemp, env: {}, windowsHide: true, stdio: 'pipe',
    });
    ownChildren.add(sentinel);
    try {
      expect(sentinel.pid).toBeDefined();
      const created = await fixture(`process.stdout.write(${JSON.stringify(canary)}); setInterval(() => {}, 1000);`);
      const result = await captureHook([created.guardPath, created.bindingPath]);
      const receipt = await childReceipt(created, result.launcherPid);
      genericFailure(result);
      expect(result.elapsedMs).toBeGreaterThanOrEqual(NATIVE_DB_VALIDATION.runnerHookActiveTimeoutMs - 250);
      expect(result.elapsedMs).toBeLessThan(deadlineMs + 5000);
      expect(await stopped(receipt.pid)).toBe(true);
      expect(alive(sentinel.pid!)).toBe(true);
    } finally {
      if (sentinel.pid !== undefined && alive(sentinel.pid)) sentinel.kill('SIGKILL');
      if (sentinel.pid !== undefined) await stopped(sentinel.pid);
      ownChildren.delete(sentinel);
    }
  }, outerMs + 5000);
});

describe('DBV-008 held child runtime identity propagation', () => {
  async function identityFixture() {
    return fixture([
      "import { readFileSync } from 'node:fs';",
      `import { nativeDatabaseValidationEnv } from ${JSON.stringify(envModuleUrl)};`,
      `import { verifyNativeRunnerJob } from ${JSON.stringify(verifierModuleUrl)};`,
      'const expected = JSON.parse(readFileSync(process.argv[2], "utf8"));',
      'const runtime = nativeDatabaseValidationEnv();',
      'const observed = {repository:runtime.GITHUB_REPOSITORY,eventName:runtime.GITHUB_EVENT_NAME,ref:runtime.GITHUB_REF,sourceSha:runtime.GITHUB_SHA,runId:runtime.GITHUB_RUN_ID,runAttempt:runtime.GITHUB_RUN_ATTEMPT,workflowRef:runtime.GITHUB_WORKFLOW_REF,runnerOs:runtime.RUNNER_OS,job:runtime.GITHUB_JOB};',
      'process.exit(verifyNativeRunnerJob(expected, observed).trusted ? 0 : 1);',
    ].join('\n'));
  }

  it.each(['push', 'workflow_dispatch'])('permits the exact controlled %s runtime through the separately executing guard fixture', async eventName => {
    const created = await identityFixture();
    const result = await captureHook([created.guardPath, created.bindingPath], { ...controlledIdentity(), GITHUB_EVENT_NAME: eventName });
    expect(result.code).toBe(0);
    expect(`${result.stdout}${result.stderr}`.trim()).toBe(acceptedText);
    await childReceipt(created, result.launcherPid);
  });

  it.each([
    ['GITHUB_REPOSITORY', 'attacker/gymloop'],
    ['GITHUB_EVENT_NAME', 'pull_request'],
    ['GITHUB_EVENT_NAME', 'pull_request_target'],
    ['GITHUB_REF', 'refs/pull/55/merge'],
    ['GITHUB_SHA', 'd'.repeat(40)],
    ['GITHUB_RUN_ID', '548294'],
    ['GITHUB_RUN_ATTEMPT', '3'],
    ['GITHUB_WORKFLOW_REF', 'OGUN01/gymloop/.github/workflows/other.yml@refs/heads/main'],
    ['GITHUB_JOB', 'migrate'], ['RUNNER_OS', 'Linux'],
  ])('refuses untrusted controlled runtime %s before any trusted-job acceptance', async (name, value) => {
    const created = await identityFixture();
    const result = await captureHook([created.guardPath, created.bindingPath], { ...controlledIdentity(), [name]: value });
    genericFailure(result);
    await childReceipt(created, result.launcherPid);
  });

  it('refuses missing runtime authority and a binding JSON parse failure privately', async () => {
    const created = await identityFixture();
    genericFailure(await captureHook([created.guardPath, created.bindingPath], {}));
    await writeFile(created.bindingPath, canary, { mode: 0o600 });
    genericFailure(await captureHook([created.guardPath, created.bindingPath], controlledIdentity()));
  });
});
