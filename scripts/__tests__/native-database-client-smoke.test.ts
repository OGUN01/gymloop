import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { chmod, lstat, mkdir, mkdtemp, readFile, readdir, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { basename, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { Script } from 'node:vm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';
import { nativeDatabaseProcessEnv } from '../../packages/shared/src/config/env';

type NativeCapture = { completed: boolean; exitCode: number | null; signal: string | null; stdout: string; stderr: string; elapsedMs: number };
type ProcessOptions = { cwd?: string; timeoutMs?: number; maxBytes?: number; env?: Record<string, string | undefined> };
type ProcessPort = (command: string, args: string[], options?: ProcessOptions) => Promise<NativeCapture>;
type SmokeRuntime = { GITHUB_RUN_ID: string; GITHUB_RUN_ATTEMPT: string; RUNNER_OS: string };
type SmokeBoundary = (runtime: SmokeRuntime, sourceSha: string, workdir: string, directory: string) => Promise<unknown>;
type FileMetadata = { path: string; sha256: string; byteLength: number };
type SmokeCase = { name: string; exitCode: number | null; completed: boolean; signal: string | null; nativeMs: number; stdoutSha256: string; stderrSha256: string; timerCount: number; rawTapPresent: boolean; inputsUnchanged: boolean; fileMetadata: FileMetadata[]; checkPassed: boolean };
type SmokeReceipt = { formatVersion: number; sourceSha: string; cliVersion: string; clientDigest: string; runnerOs: string; network: string; firstDirectoryCwd: boolean; readOnlyBinds: boolean; reportingLines: string[]; stubSha256: string; cases: SmokeCase[]; accepted: boolean };

describe('DBV-002/003 concrete native client-only stub boundary', () => {
  let retainedRoot = '';
  let workdir = '';
  let directory = '';
  let directRoot = '';
  let opaqueBoundary = '';
  let opaqueStub = Buffer.alloc(0);
  let logOrdinal = 0;
  const sourceSha = 'c152a486314ccc061f9df38e57f87f3ffaa97a5c';
  const runtime = { GITHUB_RUN_ID: '1', GITHUB_RUN_ATTEMPT: '1', RUNNER_OS: 'Windows' };
  const caseRoot = () => join(workdir, '.dbv', `client-smoke-${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}`);
  const hash = (bytes: string | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
  const jsonBytes = (value: unknown) => Buffer.from(`${JSON.stringify(value)}\n`);
  const inside = (parent: string, child: string) => {
    const rest = relative(resolve(parent), resolve(child));
    return rest === '' || (!rest.startsWith(`..${sep}`) && rest !== '..' && !isAbsolute(rest));
  };
  const refuse = (code: string): never => { throw Object.assign(new Error('Client-only smoke refused.'), { code }); };
  const retain = async (label: string, value: unknown) => {
    logOrdinal += 1;
    await writeFile(join(directory, `${logOrdinal}-${label}.json`), jsonBytes(value), { flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode });
  };
  const privateWrite = async (path: string, bytes: Uint8Array) => {
    if (!inside(retainedRoot, path) || inside(workdir, path) || inside(directRoot, path)) refuse('REPORTING_UNVERIFIED');
    await writeFile(path, bytes, { flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode });
    const observed = await readFile(path);
    if (!observed.equals(Buffer.from(bytes))) refuse('REPORTING_UNVERIFIED');
    return { path, sha256: hash(observed), byteLength: observed.byteLength };
  };
  const removeSmokeFiles = async (parent: string, path: string) => {
    const target = await realpath(path);
    if (target !== resolve(path) || target === resolve(parent) || !inside(parent, target) || (await lstat(path)).isSymbolicLink()) refuse('REPORTING_UNVERIFIED');
    await rm(target, { recursive: true });
  };
  const snapshots = async (path: string): Promise<FileMetadata[]> => {
    const files: FileMetadata[] = [];
    for (const entry of await readdir(path, { withFileTypes: true })) {
      const child = join(path, entry.name);
      if (entry.isSymbolicLink()) refuse('REPORTING_UNVERIFIED');
      if (entry.isDirectory()) files.push(...await snapshots(child));
      else if (entry.isFile()) {
        const bytes = await readFile(child);
        files.push({ path: relative(caseRoot(), child).replaceAll('\\', '/'), sha256: hash(bytes), byteLength: bytes.byteLength });
      }
    }
    return files.sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
  };
  const nativeProcess: ProcessPort = (command, args, options) => new Promise((fulfill) => {
    const started = Date.now();
    const child = spawn(command, args, { cwd: options?.cwd ?? workdir, env: options?.env ?? nativeDatabaseProcessEnv(), windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let completed = true;
    let settled = false;
    let totalBytes = 0;
    const timer = setTimeout(() => { completed = false; child.kill(); }, options?.timeoutMs ?? NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
    const receive = (parts: Buffer[], bytes: Buffer) => {
      totalBytes += bytes.byteLength;
      if (totalBytes > (options?.maxBytes ?? NATIVE_DB_VALIDATION.maxProcessBytes)) { completed = false; child.kill(); }
      else parts.push(bytes);
    };
    const finish = (exitCode: number | null, signal: string | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fulfill({ completed, exitCode, signal, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8'), elapsedMs: Date.now() - started });
    };
    child.stdout.on('data', (bytes: Buffer) => receive(stdout, bytes));
    child.stderr.on('data', (bytes: Buffer) => receive(stderr, bytes));
    child.on('error', () => { completed = false; finish(null, null); });
    child.on('close', finish);
  });
  const checked = async (command: string, args: string[], options?: ProcessOptions) => {
    let executable = command;
    if (command === 'supabase') {
      if (args.length !== 1 || args[0] !== '--version') refuse('REPORTING_UNVERIFIED');
      executable = 'C:/Users/Harsh/AppData/Roaming/npm/node_modules/supabase/node_modules/@supabase/cli-windows-x64/bin/supabase.exe';
    } else if (basename(command).toLowerCase() !== 'docker' && basename(command).toLowerCase() !== 'docker.exe') refuse('REPORTING_UNVERIFIED');
    const result = await nativeProcess(executable, args, options);
    await retain('approved-version-or-image-process', result);
    if (!result.completed || result.exitCode !== 0 || result.signal !== null) refuse('REPORTING_UNVERIFIED');
    return result.stdout;
  };
  const loadBoundary = (capture: ProcessPort, toolPort = checked, inheritedEnvironment = nativeDatabaseProcessEnv): SmokeBoundary => new Script(`${opaqueBoundary}\nensureClientSmoke;`).runInNewContext({
    nativeDatabaseProcessEnv: inheritedEnvironment, NATIVE_DB_VALIDATION, resolve, relative, join, inside, mkdir, chmod, readFile,
    process: { platform: process.platform }, Buffer, hash, hashBytes: hash, jsonBytes, refuse, reportingText: `${NATIVE_DB_VALIDATION.reportingLines.join('\n')}\n`,
    writeFile: async (path: string, bytes: string | Uint8Array, options: Parameters<typeof writeFile>[2]) => {
      if (basename(path) === 'psql') opaqueStub = Buffer.from(bytes);
      await writeFile(path, bytes, options);
    }, checked: toolPort, capture, privateWrite, removeSmokeFiles,
  }) as SmokeBoundary;

  beforeAll(async () => {
    const parent = process.platform === 'win32' ? 'C:/fr-sealed-20261007' : tmpdir();
    retainedRoot = await mkdtemp(join(parent, 'visible-client-smoke-'));
    await chmod(retainedRoot, NATIVE_DB_VALIDATION.privateDirectoryMode);
    workdir = join(retainedRoot, 'workdir');
    directory = join(retainedRoot, 'private-output');
    directRoot = join(retainedRoot, 'literal-stub-fixtures');
    await Promise.all([mkdir(join(workdir, '.dbv'), { recursive: true, mode: NATIVE_DB_VALIDATION.privateDirectoryMode }), mkdir(directory, { mode: NATIVE_DB_VALIDATION.privateDirectoryMode }), mkdir(directRoot, { mode: NATIVE_DB_VALIDATION.privateDirectoryMode })]);
    const bytes = await readFile(new URL('../native-database-validation.mjs', import.meta.url), 'utf8');
    const start = bytes.indexOf('async function ensureClientSmoke(runtime, sourceSha, workdir, directory) {');
    const end = bytes.indexOf('async function removeSmokeFiles(parent, path) {', start);
    if (start < 0 || end <= start) throw new Error('Declared opaque client boundary unavailable.');
    opaqueBoundary = bytes.slice(start, end);
    // Harvest the generated executable as opaque bytes. These deliberately red
    // process fixtures are setup only and never stand in for native equivalence.
    const fakeCapture: ProcessPort = async () => ({ completed: true, exitCode: 1, signal: null, stdout: '', stderr: '', elapsedMs: 0 });
    const fakeChecked = async (command: string, args: string[]) => command === 'supabase' ? `${NATIVE_DB_VALIDATION.cliVersion}\n` : args.includes('--version') ? `pg_prove ${NATIVE_DB_VALIDATION.clientImage.split(':').at(-1)}\n` : `${NATIVE_DB_VALIDATION.clientDigest}\n`;
    const harvestDirectory = join(retainedRoot, 'private-harvest-output');
    await mkdir(harvestDirectory, { mode: NATIVE_DB_VALIDATION.privateDirectoryMode });
    try { await loadBoundary(fakeCapture, fakeChecked, () => ({}))(runtime, sourceSha, workdir, harvestDirectory); } catch (error) {
      await retain('synthetic-harvest-status', { name: (error as Error).name, message: (error as Error).message, code: (error as NodeJS.ErrnoException).code });
    }
    if (opaqueStub.byteLength === 0) throw new Error('Opaque native stub fixture unavailable.');
    await writeFile(join(directRoot, 'psql'), opaqueStub, { flag: 'wx', mode: NATIVE_DB_VALIDATION.smokeExecutableMode });
    await writeFile(join(directRoot, "literal file's $(text).tap"), '1..1\nok 1 - inert literal fixture\n', { flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode });
  }, NATIVE_DB_VALIDATION.nativeCleanupReserveMs);

  afterAll(async () => {
    if (!retainedRoot) return;
    const canonicalRoot = await realpath(retainedRoot);
    for (const target of [workdir, directRoot]) {
      const canonicalTarget = await realpath(target);
      if (!inside(canonicalRoot, canonicalTarget) || canonicalTarget === canonicalRoot || canonicalTarget !== resolve(target) || (await lstat(target)).isSymbolicLink()) refuse('REPORTING_UNVERIFIED');
      await rm(canonicalTarget, { recursive: true });
    }
    await retain('retention-metadata', { opaqueBoundarySha256: hash(opaqueBoundary), opaqueStubSha256: hash(opaqueStub), ownedFixtureCleanupVerified: true });
  });

  it.each(['-f', '--file'])('opaque psql stub reads the exact literal fixture for %s', async (fileOption) => {
    const file = "literal file's $(text).tap";
    const beforeStub = await readFile(join(directRoot, 'psql'));
    const beforeFile = await readFile(join(directRoot, file));
    const result = process.platform === 'win32'
      ? await nativeProcess('docker', ['run', '--rm', '--network', 'none', '--mount', `type=bind,source=${directRoot},target=/opaque,readonly`, '--entrypoint', '/bin/sh', NATIVE_DB_VALIDATION.clientImage, '/opaque/psql', fileOption, `/opaque/${file}`])
      : await nativeProcess('/bin/sh', [join(directRoot, 'psql'), fileOption, join(directRoot, file)]);
    await retain('literal-stub-process', result);
    expect(result.completed).toBe(true);
    expect(result.exitCode).toBe(0);
    expect(result.signal).toBeNull();
    expect(result.stdout === beforeFile.toString('utf8')).toBe(true);
    expect(result.stderr === '').toBe(true);
    expect((await readFile(join(directRoot, 'psql'))).equals(beforeStub)).toBe(true);
    expect((await readFile(join(directRoot, file))).equals(beforeFile)).toBe(true);
  }, NATIVE_DB_VALIDATION.nativeCleanupReserveMs);

  it.skipIf(process.platform !== 'win32')('accepts one genuinely green pinned native case and all eight genuinely red damaged cases', async () => {
    const nativeCases: { result: NativeCapture; unchanged: boolean; hostNetwork: boolean; pinnedImage: boolean; readOnlyBind: boolean }[] = [];
    let outcome = 'accepted';
    try {
      await loadBoundary(async (command, args, options) => {
        if (basename(command).toLowerCase() !== 'docker' && basename(command).toLowerCase() !== 'docker.exe') refuse('REPORTING_UNVERIFIED');
        const before = await snapshots(caseRoot());
        const result = await nativeProcess(command, args, options);
        const after = await snapshots(caseRoot());
        await retain('actual-native-client', result);
        nativeCases.push({ result, unchanged: JSON.stringify(before) === JSON.stringify(after), hostNetwork: args[args.indexOf('--network') + 1] === 'host', pinnedImage: args.includes(`supabase/pg_prove@${NATIVE_DB_VALIDATION.clientDigest}`), readOnlyBind: args.some(argument => argument.endsWith(':ro') || argument.includes('readonly')) });
        return result;
      })(runtime, sourceSha, workdir, directory);
    } catch (error) {
      outcome = 'refused';
      await retain('native-boundary-refusal', { name: (error as Error).name, message: (error as Error).message, code: (error as NodeJS.ErrnoException).code });
    }
    const receipt = JSON.parse(await readFile(join(directory, 'client-smoke.json'), 'utf8')) as SmokeReceipt;
    const names = ['success', 'assertion-failure', 'missing-plan', 'extra-plan', 'broken-plan', 'malformed', 'truncated', 'client-error', 'connection-loss'];
    expect(nativeCases.length === names.length).toBe(true);
    expect(receipt.cases.map(item => item.name)).toEqual(names);
    const successful = nativeCases[0];
    const positive = receipt.cases[0];
    expect(successful !== undefined && positive !== undefined).toBe(true);
    if (!successful || !positive) throw new Error('Positive native smoke evidence absent.');
    expect(successful.result.completed && successful.result.exitCode === 0 && successful.result.signal === null).toBe(true);
    expect(/^1\.\.2\r?$/m.test(successful.result.stdout) && /^1\.\.1\r?$/m.test(successful.result.stdout) && /^ok 2\b/m.test(successful.result.stdout) && /Result: PASS/.test(successful.result.stdout)).toBe(true);
    const expectedTimerFiles = ['supabase/tests/visible.sql', 'supabase/tests-holdout/independent.pg'];
    const nativeTimerRecords: { path: string; milliseconds: number }[] = [];
    let currentTimerFile = '';
    // Grammar observed with the pinned client's green synthetic control: each
    // timestamped filename block ends in its own integer-ms CPU timer record.
    for (const line of successful.result.stdout.split(/\r?\n/)) {
      if (/^\[[0-9]{2}:[0-9]{2}:[0-9]{2}\]/.test(line)) {
        const normalized = line.replaceAll('\\', '/');
        const matchingFiles = expectedTimerFiles.filter(path => normalized.includes(`/${path} `));
        currentTimerFile = matchingFiles.length === 1 ? matchingFiles[0] ?? '' : '';
      }
      const timer = /^ok\s+([0-9]+)\s+ms\s+\([^)]*\busr\b[^)]*\bsys\b[^)]*\bCPU\)\s*$/.exec(line);
      if (timer) nativeTimerRecords.push({ path: currentTimerFile, milliseconds: Number(timer[1]) });
    }
    expect(nativeTimerRecords.map(record => record.path).sort()).toEqual([...expectedTimerFiles].sort());
    expect(nativeTimerRecords.every(record => Number.isSafeInteger(record.milliseconds) && record.milliseconds >= 0)).toBe(true);
    expect(positive.rawTapPresent && positive.timerCount === 2 && positive.checkPassed).toBe(true);
    expect(positive.fileMetadata.map(file => Object.keys(file).sort())).toEqual(positive.fileMetadata.map(() => ['byteLength', 'path', 'sha256']));
    for (const [index, item] of nativeCases.entries()) {
      expect(item.unchanged && item.hostNetwork && item.pinnedImage && item.readOnlyBind).toBe(true);
      expect(item.result.completed && item.result.signal === null).toBe(true);
      expect(item.result.exitCode).toBe(index === 0 ? 0 : 1);
      const metadata = receipt.cases[index];
      if (!metadata) throw new Error('Native case metadata absent.');
      expect(metadata.inputsUnchanged && metadata.checkPassed).toBe(true);
      expect(metadata.stdoutSha256 === hash(item.result.stdout) && metadata.stderrSha256 === hash(item.result.stderr)).toBe(true);
    }
    expect(receipt.sourceSha === sourceSha && receipt.cliVersion === NATIVE_DB_VALIDATION.cliVersion && receipt.clientDigest === NATIVE_DB_VALIDATION.clientDigest).toBe(true);
    expect(receipt.network === 'host' && receipt.firstDirectoryCwd && receipt.readOnlyBinds).toBe(true);
    expect(receipt.reportingLines).toEqual(NATIVE_DB_VALIDATION.reportingLines);
    expect(receipt.stubSha256).toBe(hash(opaqueStub));
    expect(receipt.accepted).toBe(true);
    expect(outcome).toBe('accepted');
    expect(await lstat(caseRoot()).then(() => false, error => (error as NodeJS.ErrnoException).code === 'ENOENT')).toBe(true);
  }, NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
});
