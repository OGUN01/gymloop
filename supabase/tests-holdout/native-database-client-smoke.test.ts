import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmod, mkdir, mkdtemp, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { join, resolve, relative, isAbsolute } from 'node:path';
import { Script } from 'node:vm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.js';
import { nativeDatabaseProcessEnv } from '../../packages/shared/src/config/env.js';

// Independent DBV-002/003 fixture: source bytes are extracted and executed opaquely.
// Neither the concrete implementation nor any project SQL or counterpart is read.
type NativeResult = { completed: boolean; exitCode: number | null; signal: string | null; stdout: string; stderr: string; elapsedMs: number };
type Options = { cwd?: string; env?: NodeJS.ProcessEnv; timeoutMs?: number };
type CaseMetadata = { name: string; exitCode: number | null; completed: boolean; signal: string | null; stdoutSha256: string; stderrSha256: string; timerCount: number; rawTapPresent: boolean; checkPassed: boolean; inputsUnchanged: boolean; fileMetadata: { path: string; sha256: string; byteLength: number }[] };
type Receipt = { accepted: boolean; sourceSha: string; cases: CaseMetadata[]; firstDirectoryCwd: boolean; readOnlyBinds: boolean; network: string; clientDigest: string; reportingLines: string[] };
type SmokePort = (runtime: object, sourceSha: string, workdir: string, directory: string) => Promise<void>;

const parent = 'C:\\fr-sealed-20261007';
const sourceSha = 'c152a486314ccc061f9df38e57f87f3ffaa97a5c';
const approvedCli = 'C:\\Users\\Harsh\\AppData\\Roaming\\npm\\node_modules\\supabase\\node_modules\\@supabase\\cli-windows-x64\\bin\\supabase.exe';
const reportingText = `${NATIVE_DB_VALIDATION.reportingLines.join('\n')}\n`;
const hash = (bytes: Buffer | string) => createHash('sha256').update(bytes).digest('hex');
const inside = (root: string, path: string) => {
  const tail = relative(resolve(root), resolve(path));
  return tail === '' || (!tail.startsWith('..') && !isAbsolute(tail));
};

describe.skipIf(process.platform !== 'win32')('DBV-002/003 independent concrete native client smoke', () => {
  let ownedRoot = '';
  let workdir = '';
  let directory = '';
  let stub: Buffer | undefined;
  let receipt: Receipt | undefined;
  let boundaryError: unknown;
  const nativeRuns: NativeResult[] = [];

  async function capture(command: string, args: string[], options: Options = {}): Promise<NativeResult> {
    if (/supabase(?:\.exe)?$/i.test(command)) {
      if (args.length !== 1 || args[0] !== '--version') throw new Error('Database execution is forbidden in this fixture.');
      command = approvedCli;
    } else if (!/docker(?:\.exe)?$/i.test(command)) throw new Error('Unexpected fixture process.');
    const started = Date.now();
    const result = await new Promise<NativeResult>((accept, reject) => {
      const child = spawn(command, args, { ...(options.cwd ? { cwd: options.cwd } : {}), env: options.env ?? nativeDatabaseProcessEnv(), windowsHide: true, shell: false });
      let stdout = '';
      let stderr = '';
      let timedOut = false;
      const timer = setTimeout(() => { timedOut = true; child.kill(); }, options.timeoutMs ?? NATIVE_DB_VALIDATION.processStopGraceMs);
      child.stdout.on('data', (bytes: Buffer) => { stdout += bytes.toString('utf8'); });
      child.stderr.on('data', (bytes: Buffer) => { stderr += bytes.toString('utf8'); });
      child.on('error', error => { clearTimeout(timer); reject(error); });
      child.on('close', (exitCode, signal) => {
        clearTimeout(timer);
        accept({ completed: !timedOut, exitCode, signal, stdout, stderr, elapsedMs: Math.max(0, Date.now() - started) });
      });
    });
    if (/docker(?:\.exe)?$/i.test(command) && args[0] === 'run') nativeRuns.push(result);
    return result;
  }

  beforeAll(async () => {
    ownedRoot = await mkdtemp(join(parent, 'client-smoke-holdout-'));
    workdir = join(ownedRoot, 'checkout');
    directory = join(ownedRoot, 'private');
    await mkdir(workdir);
    await mkdir(join(workdir, '.dbv'));
    await mkdir(directory);
    const opaque = await readFile(new URL('../../scripts/native-database-validation.mjs', import.meta.url), 'utf8');
    const start = opaque.indexOf('async function ensureClientSmoke(runtime, sourceSha, workdir, directory) {');
    const end = opaque.indexOf('async function removeSmokeFiles(parent, path) {', start);
    if (start < 0 || end <= start) throw new Error('Concrete smoke boundary unavailable.');
    const smoke = new Script(`${opaque.slice(start, end)}\nensureClientSmoke;`).runInNewContext({
      Buffer, Date, process: { platform: 'win32' }, NATIVE_DB_VALIDATION,
      nativeDatabaseProcessEnv, resolve, join, relative, isAbsolute, inside, mkdir, chmod, hash, reportingText, readFile,
      jsonBytes: (value: unknown) => Buffer.from(`${JSON.stringify(value)}\n`, 'utf8'),
      writeFile: async (path: string, bytes: string | Buffer, options?: object) => {
        if (path === join(workdir, '.dbv', 'client-smoke-11-1', 'psql')) stub = Buffer.from(bytes);
        return writeFile(path, bytes, options);
      },
      capture,
      checked: async (command: string, args: string[], options?: Options) => {
        const result = await capture(command, args, options);
        if (!result.completed || result.exitCode !== 0 || result.signal !== null) throw new Error('Fixture process refused.');
        return result.stdout;
      },
      privateWrite: async (path: string, bytes: Buffer) => {
        if (!inside(directory, path)) throw new Error('Fixture output custody refused.');
        await writeFile(path, bytes, { flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode });
        const retained = await readFile(path);
        if (!retained.equals(bytes)) throw new Error('Fixture output readback refused.');
        return { path, sha256: hash(retained), byteLength: retained.length };
      },
      removeSmokeFiles: async (root: string, path: string) => {
        if (!inside(workdir, root) || path !== join(workdir, '.dbv', 'client-smoke-11-1') || !inside(root, path) || resolve(await realpath(path)) !== resolve(path)) throw new Error('Fixture cleanup ownership refused.');
        await rm(path, { recursive: true, force: true });
      },
      refuse: (code: string) => { throw Object.assign(new Error('Native smoke refused.'), { code }); },
    }) as SmokePort;
    try { await smoke({ GITHUB_RUN_ID: '11', GITHUB_RUN_ATTEMPT: '1', RUNNER_OS: 'Windows' }, sourceSha, workdir, directory); }
    catch (error) { boundaryError = error; }
    try { receipt = JSON.parse(await readFile(join(directory, 'client-smoke.json'), 'utf8')) as Receipt; }
    catch { receipt = undefined; }
  }, NATIVE_DB_VALIDATION.nativeCleanupReserveMs);

  afterAll(async () => {
    if (!ownedRoot) return;
    const tail = relative(resolve(parent), resolve(ownedRoot));
    if (!tail.startsWith('client-smoke-holdout-') || tail.includes('\\') || isAbsolute(tail)) throw new Error('Fixture cleanup ownership refused.');
    await rm(ownedRoot, { recursive: true, force: true });
  });

  it('passes its genuine native positive and discriminates all eight damaged fixtures', async () => {
    expect(receipt?.cases).toHaveLength(9);
    expect(boundaryError).toBeUndefined();
    expect(receipt?.accepted).toBe(true);
    expect(receipt?.sourceSha).toBe(sourceSha);
    expect(receipt?.firstDirectoryCwd).toBe(true);
    expect(receipt?.readOnlyBinds).toBe(true);
    expect(receipt?.network).toBe('host');
    expect(receipt?.clientDigest).toBe(NATIVE_DB_VALIDATION.clientDigest);
    expect(receipt?.reportingLines).toEqual([...NATIVE_DB_VALIDATION.reportingLines]);
    const results = receipt?.cases ?? [];
    expect(results.map(result => result.name)).toEqual(['success', 'assertion-failure', 'missing-plan', 'extra-plan', 'broken-plan', 'malformed', 'truncated', 'client-error', 'connection-loss']);
    for (const result of results) {
      const actual = nativeRuns.find(run => hash(run.stdout) === result.stdoutSha256 && hash(run.stderr) === result.stderrSha256);
      expect(actual).toBeDefined();
      expect(actual?.completed).toBe(true);
      expect(actual?.signal).toBeNull();
      expect(actual?.exitCode).toBe(result.name === 'success' ? 0 : 1);
      expect(result.inputsUnchanged).toBe(true);
      expect(result.checkPassed).toBe(true);
      expect(actual?.stdout).toMatch(/Result:\s+(?:PASS|FAIL)/);
    }
    const positive = results[0];
    expect(positive?.timerCount).toBe(2);
    expect(positive?.rawTapPresent).toBe(true);
    const expectedFiles = positive?.fileMetadata.filter(file => /\.(?:sql|pg)$/.test(file.path)) ?? [];
    expect(expectedFiles).toHaveLength(2);
    const output = nativeRuns.find(run => hash(run.stdout) === positive?.stdoutSha256)?.stdout ?? '';
    expect(output).toMatch(/^1\.\.2\s*$/m);
    expect(output).toMatch(/^1\.\.1\s*$/m);
    expect(output).toMatch(/^ok 2\b/m);
    expect(output).toMatch(/Files=2,\s*Tests=3/);
    expect(output).toMatch(/Result:\s+PASS/);
    const lines = output.split(/\r?\n/);
    const fileStarts = expectedFiles.map(file => lines.findIndex(line => line.includes(file.path) && /\.\.\s*$/.test(line)));
    expect(fileStarts.every(start => start >= 0)).toBe(true);
    expect(new Set(fileStarts).size).toBe(expectedFiles.length);
    const orderedStarts = fileStarts.sort((first, second) => first - second);
    for (const [index, start] of orderedStarts.entries()) {
      const fileBlock = lines.slice(start, orderedStarts[index + 1] ?? lines.length);
      expect(fileBlock.filter(line => /^\s*ok\s+\d+\s+ms\s+\([^)]*\bCPU\)\s*$/.test(line))).toHaveLength(1);
    }
    expect(results.slice(1).some(result => result.stdoutSha256 !== positive?.stdoutSha256)).toBe(true);
    await expect(readFile(join(workdir, '.dbv', 'client-smoke-11-1', 'psql'))).rejects.toThrow();
  });

  it.each(['-f', '--file'])('the generated stub consumes the literal %s file offline', async flag => {
    expect(stub).toBeDefined();
    const probe = await mkdtemp(join(ownedRoot, 'literal-probe-'));
    const path = join(probe, "literal space's ‘curly’ ; $() input.sql");
    const payload = '1..1\nok 1 - independent literal file\n';
    await writeFile(path, payload);
    await writeFile(join(probe, 'psql'), stub ?? Buffer.alloc(0), { mode: NATIVE_DB_VALIDATION.smokeExecutableMode });
    const result = await capture('docker', ['run', '--rm', '--network', 'host', '--volume', `${probe}:/probe:ro`, '--entrypoint', '/bin/sh', NATIVE_DB_VALIDATION.nativeClientImage, '/probe/psql', flag, `/probe/${path.slice(probe.length + 1)}`]);
    expect(result.completed).toBe(true);
    expect(result.signal).toBeNull();
    expect(result.exitCode).toBe(0);
    expect(result.stdout).toBe(payload);
    expect(result.stderr).toBe('');
    expect(await readFile(path, 'utf8')).toBe(payload);
  });
});
