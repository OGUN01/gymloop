import { spawn, type ChildProcess } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Implementation-blind CLI tests for the frozen bounded hook launcher. Every
// child below is an author-owned synthetic guard; no real guard or runner runs.
type CliResult = { code: number | null; signal: NodeJS.Signals | null; stdout: string; stderr: string; elapsedMs: number };
const CLI = fileURLToPath(new URL('../native-runner-hook.mjs', import.meta.url));
const PREFIX = 'fitcruxx-native-hook-visible-';
const ACCEPTED = 'Native runner binding accepted.';
const REFUSED = 'Native runner binding refused: RUNNER_UNTRUSTED.';
const SECRET = 'synthetic-private-hook-output-sentinel';
const BOUND = NATIVE_DB_VALIDATION.processStopGraceMs;
const TEST_LIMIT = BOUND * 3;
const actors = new Set<ChildProcess>();
let fixtureRoot: string;

beforeAll(async () => {
  fixtureRoot = resolve(await mkdtemp(join(tmpdir(), PREFIX)));
});

afterAll(async () => {
  for (const child of actors) child.kill('SIGTERM');
  await Promise.all([...actors].map(waitForExit));
  // Recursive cleanup is confined to the exact new disposable directory.
  if (dirname(fixtureRoot) !== resolve(tmpdir()) || !basename(fixtureRoot).startsWith(PREFIX)) throw new Error('Synthetic fixture cleanup refused');
  await rm(fixtureRoot, { recursive: true, force: true });
});

function waitForExit(child: ChildProcess): Promise<void> {
  if (child.exitCode !== null || child.signalCode !== null) return Promise.resolve();
  return new Promise(done => { child.once('exit', () => done()); });
}

function tracked(child: ChildProcess): ChildProcess {
  actors.add(child);
  child.once('close', () => { actors.delete(child); });
  return child;
}

async function guard(name: string, body: string): Promise<string> {
  const path = join(fixtureRoot, `${name}.mjs`);
  await writeFile(path, body, { encoding: 'utf8', flag: 'wx' });
  return path;
}

async function binding(name: string): Promise<string> {
  const path = join(fixtureRoot, `${name}.json`);
  await writeFile(path, '{}\n', { encoding: 'utf8', flag: 'wx' });
  return path;
}

function launch(args: string[]): Promise<CliResult> {
  const began = performance.now();
  const child = tracked(spawn(process.execPath, [CLI, ...args], { cwd: fixtureRoot, windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }));
  let stdout = '';
  let stderr = '';
  child.stdout?.setEncoding('utf8');
  child.stderr?.setEncoding('utf8');
  child.stdout?.on('data', text => { stdout += String(text); });
  child.stderr?.on('data', text => { stderr += String(text); });
  return new Promise((done, reject) => {
    const watchdog = setTimeout(() => { child.kill('SIGTERM'); }, BOUND * 2);
    child.once('error', error => { clearTimeout(watchdog); reject(error); });
    child.once('close', (code, signal) => {
      clearTimeout(watchdog);
      done({ code, signal, stdout, stderr, elapsedMs: performance.now() - began });
    });
  });
}

function safeStatus(result: CliResult, accepted = false): void {
  const output = `${result.stdout}${result.stderr}`.replaceAll('\r\n', '\n').trim();
  expect(output).toBe(accepted ? ACCEPTED : REFUSED);
  expect(output).not.toContain(SECRET);
  expect(output).not.toContain(fixtureRoot);
  expect(result.signal).toBeNull();
  if (accepted) expect(result.code).toBe(0);
  else expect(result.code).not.toBe(0);
}

async function exists(path: string): Promise<boolean> {
  try { await readFile(path); return true; } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ENOENT') return false;
    throw error;
  }
}

function live(pid: number): boolean {
  try { process.kill(pid, 0); return true; } catch (error) {
    if ((error as NodeJS.ErrnoException).code === 'ESRCH') return false;
    throw error;
  }
}

async function recordedPid(path: string): Promise<number | null> {
  if (!await exists(path)) return null;
  const pid = Number((await readFile(path, 'utf8')).trim());
  if (!Number.isSafeInteger(pid) || pid <= 0) throw new Error('Synthetic fixture PID invalid');
  return pid;
}

async function awaitGone(pid: number): Promise<void> {
  const deadline = performance.now() + BOUND;
  while (live(pid) && performance.now() < deadline) await new Promise(done => setTimeout(done, 20));
  expect(live(pid)).toBe(false);
}

describe('DBV-008 bounded native runner hook CLI', () => {
  it('starts native Node with the exact binding argument and never reads the binding itself', async () => {
    const marker = join(fixtureRoot, 'accepted-argv.json');
    const guardPath = await guard('accepted', `import { writeFileSync } from 'node:fs';\nwriteFileSync(${JSON.stringify(marker)}, JSON.stringify({args:process.argv.slice(2),node:process.execPath}));\n`);
    // An absent binding proves the launcher delegates filesystem work to guard.
    const bindingPath = join(fixtureRoot, 'intentionally-absent-binding.json');
    const result = await launch([guardPath, bindingPath]);
    safeStatus(result, true);
    expect(JSON.parse(await readFile(marker, 'utf8'))).toEqual({ args: [bindingPath], node: process.execPath });
  });

  it('suppresses private child stdout and stderr even when guard succeeds', async () => {
    const guardPath = await guard('private-success', `process.stdout.write(${JSON.stringify(SECRET)});\nprocess.stderr.write(${JSON.stringify(SECRET)});\n`);
    safeStatus(await launch([guardPath, await binding('private-success')]), true);
  });

  it('keeps nonzero guard work red and suppresses both private streams', async () => {
    const guardPath = await guard('nonzero', `process.stdout.write(${JSON.stringify(SECRET)});\nprocess.stderr.write(${JSON.stringify(SECRET)});\nprocess.exit(7);\n`);
    safeStatus(await launch([guardPath, await binding('nonzero')]));
  });

  it('keeps signalled guard work red instead of treating null exit status as zero', async () => {
    const guardPath = await guard('signal', `process.stdout.write(${JSON.stringify(SECRET)});\nprocess.kill(process.pid,'SIGTERM');\n`);
    safeStatus(await launch([guardPath, await binding('signal')]));
  });

  it('refuses a missing guard executable without forwarding native diagnostics', async () => {
    const guardPath = join(fixtureRoot, 'absent-guard.mjs');
    safeStatus(await launch([guardPath, await binding('absent-guard')]));
  });

  it('refuses a guard syntax error without forwarding exception or path details', async () => {
    const guardPath = await guard('broken-syntax', `${SECRET}\nconst = ;\n`);
    safeStatus(await launch([guardPath, await binding('broken-syntax')]));
  });

  it('rejects absent, extra and relative arguments before any guard marker is created', async () => {
    const marker = join(fixtureRoot, 'invalid-arguments.marker');
    const guardPath = await guard('invalid-arguments', `import { writeFileSync } from 'node:fs';\nwriteFileSync(${JSON.stringify(marker)},'called');\n`);
    const bindingPath = await binding('invalid-arguments');
    const invalid = [
      [], [guardPath], [guardPath, bindingPath, SECRET],
      [basename(guardPath), bindingPath], [guardPath, basename(bindingPath)], ['', bindingPath],
    ];
    for (const args of invalid) {
      safeStatus(await launch(args));
      expect(await exists(marker)).toBe(false);
    }
  });

  it('kills only the recorded stalled guard at the real ten-second bound while an unrelated sentinel survives', async () => {
    const pidPath = join(fixtureRoot, 'stalled-guard.pid');
    const guardPath = await guard('stalled-guard', `import { writeFileSync } from 'node:fs';\nwriteFileSync(${JSON.stringify(pidPath)},String(process.pid));\nprocess.stdout.write(${JSON.stringify(SECRET)});\nsetInterval(()=>{},1000);\n`);
    const sentinelPath = await guard('unrelated-sentinel', 'setInterval(()=>{},1000);\n');
    const sentinel = tracked(spawn(process.execPath, [sentinelPath], { windowsHide: true, stdio: 'ignore' }));
    try {
      const result = await launch([guardPath, await binding('stalled-guard')]);
      safeStatus(result);
      expect(result.elapsedMs).toBeGreaterThanOrEqual(BOUND * 0.9);
      expect(result.elapsedMs).toBeLessThan(BOUND * 2);
      const guardPid = await recordedPid(pidPath);
      expect(guardPid).not.toBeNull();
      if (guardPid === null) throw new Error('Synthetic stalled guard never started');
      await awaitGone(guardPid);
      expect(sentinel.pid).toBeDefined();
      if (sentinel.pid === undefined) throw new Error('Synthetic sentinel never started');
      expect(live(sentinel.pid)).toBe(true);
    } finally {
      // Failed launchers still cannot strand this author-owned guard fixture.
      const guardPid = await recordedPid(pidPath);
      if (guardPid !== null && live(guardPid)) process.kill(guardPid, 'SIGTERM');
      sentinel.kill('SIGTERM');
      await waitForExit(sentinel);
    }
  }, TEST_LIMIT);
});
