import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync } from 'node:fs';
import { chmod, lstat, mkdir, mkdtemp, readFile, realpath, rm, rmdir, stat, writeFile } from 'node:fs/promises';
import { basename, dirname, isAbsolute, join, relative, resolve, sep } from 'node:path';
import { Script } from 'node:vm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type NativeCapture = {
  completed: boolean;
  exitCode: number | null;
  signal: string | null;
  stdout: string;
  stderr: string;
  elapsedMs: number;
};

type ProcessOptions = { cwd?: string };
type ProcessPort = (command: string, args: string[], options?: ProcessOptions) => Promise<NativeCapture>;
type DirectoryBoundary = (path: string, workdir: string) => Promise<unknown>;

// DBV-004/007: this independent suite reads the private entry only as opaque
// executable bytes. It never displays, searches, or reasons from its body.
describe.skipIf(process.platform !== 'win32')('DBV-004/007 native Windows protected-directory boundary', () => {
  let retainedRoot = '';
  let fixturesRoot = '';
  let workdir = '';
  let ordinal = 0;
  let boundaryBytes = '';

  const inside = (parent: string, child: string) => {
    const remainder = relative(resolve(parent), resolve(child));
    return remainder === '' || (!remainder.startsWith(`..${sep}`) && remainder !== '..' && !isAbsolute(remainder));
  };

  const nativeProcess: ProcessPort = (command, args, options) => new Promise((fulfill) => {
    const started = Date.now();
    const child = spawn(command, args, {
      cwd: options?.cwd ?? workdir,
      windowsHide: true,
      shell: false,
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const stdout: Buffer[] = [];
    const stderr: Buffer[] = [];
    let completed = true;
    let settled = false;
    let byteLength = 0;
    const timer = setTimeout(() => {
      completed = false;
      child.kill();
    }, NATIVE_DB_VALIDATION.processStopGraceMs);
    const receive = (parts: Buffer[], bytes: Buffer) => {
      byteLength += bytes.byteLength;
      if (byteLength > NATIVE_DB_VALIDATION.maxProcessBytes) {
        completed = false;
        child.kill();
      } else {
        parts.push(bytes);
      }
    };
    const finish = (exitCode: number | null, signal: string | null) => {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      fulfill({ completed, exitCode, signal, stdout: Buffer.concat(stdout).toString('utf8'), stderr: Buffer.concat(stderr).toString('utf8'), elapsedMs: Date.now() - started });
    };
    child.stdout.on('data', (bytes: Buffer) => receive(stdout, bytes));
    child.stderr.on('data', (bytes: Buffer) => receive(stderr, bytes));
    child.on('error', () => {
      completed = false;
      finish(null, null);
    });
    child.on('close', finish);
  });

  const powershell = async (script: string) => {
    const encoded = Buffer.from(script, 'utf16le').toString('base64');
    return nativeProcess('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', encoded]);
  };

  const literalPath = (path: string) => `[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${Buffer.from(path, 'utf8').toString('base64')}'))`;

  const aclProof = (path: string, create: boolean, includeOtherPrincipal = false) => `
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSHOME 'Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$p = ${literalPath(path)}
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
${create ? `
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($owner)
$acl.SetAccessRuleProtection($true, $false)
foreach ($sidText in $allowed) {
  $sid = New-Object Security.Principal.SecurityIdentifier($sidText)
  $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid, 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
  $acl.AddAccessRule($rule)
}
${includeOtherPrincipal ? `
$foreign = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
$acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($foreign, 'ReadAndExecute', 'None', 'None', 'Allow')))
` : ''}
Set-Acl -LiteralPath $p -AclObject $acl -ErrorAction Stop
` : ''}
$observed = Get-Acl -LiteralPath $p -ErrorAction Stop
if ($observed.GetOwner([Security.Principal.SecurityIdentifier]).Value -ne $owner.Value) { throw 'Fixture owner mismatch.' }
$foreignAllows = @($observed.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object { $_.AccessControlType -eq 'Allow' -and $_.IdentityReference.Value -notin $allowed })
if (${includeOtherPrincipal ? '$foreignAllows.Count -eq 0' : '$foreignAllows.Count -ne 0'}) { throw 'Fixture access mismatch.' }
if ($PSVersionTable.PSVersion.Major -ne 5 -or $PSVersionTable.PSVersion.Minor -ne 1) { throw 'Fixture requires native PowerShell 5.1.' }
[Console]::Out.Write('NATIVE_FIXTURE_VERIFIED')
`;

  const retain = async (label: string, capture: NativeCapture) => {
    ordinal += 1;
    await writeFile(join(retainedRoot, `${ordinal}-${label}.json`), `${JSON.stringify(capture)}\n`, { flag: 'wx' });
  };

  const newFixture = async (name: string, includeOtherPrincipal = false) => {
    const path = join(fixturesRoot, name);
    await mkdir(path);
    const proof = await powershell(aclProof(path, true, includeOtherPrincipal));
    await retain('fixture-acl-proof', proof);
    if (!proof.completed || proof.exitCode !== 0 || proof.signal !== null || proof.stdout !== 'NATIVE_FIXTURE_VERIFIED' || proof.stderr !== '') {
      throw new Error('Owned native ACL fixture unavailable.');
    }
    return path;
  };

  const loadBoundary = (capture: ProcessPort): DirectoryBoundary => new Script(`${boundaryBytes}\nprivateDirectory;`).runInNewContext({
    resolve, relative, dirname, basename, isAbsolute, sep, inside, mkdir, lstat, realpath, chmod,
    statUnix: stat, stat, existsSync, Buffer, NATIVE_DB_VALIDATION,
    process: { platform: 'win32' }, capture,
    refuse: (code: string) => { throw Object.assign(new Error('Private boundary refused.'), { code }); },
  }) as DirectoryBoundary;

  const admission = async (path: string, capture: ProcessPort) => {
    try {
      await loadBoundary(capture)(path, workdir);
      return 'accepted';
    } catch {
      return 'refused';
    }
  };

  const realAdmission = async (path: string, beforeNative?: () => Promise<void>) => {
    const calls: string[] = [];
    const outcome = await admission(path, async (command, args, options) => {
      calls.push(basename(command).toLowerCase());
      await beforeNative?.();
      const result = await nativeProcess(command, args, options);
      await retain('adapter-native-acl', result);
      return result;
    });
    expect(calls.some(command => command === 'powershell' || command === 'powershell.exe')).toBe(true);
    return outcome;
  };

  beforeAll(async () => {
    const sealedParent = resolve('C:/fr-sealed-20261007');
    workdir = sealedParent;
    const parentProof = await powershell(aclProof(sealedParent, false));
    if (!parentProof.completed || parentProof.exitCode !== 0 || parentProof.signal !== null || parentProof.stdout !== 'NATIVE_FIXTURE_VERIFIED' || parentProof.stderr !== '') {
      throw new Error('Existing protected fixture parent unavailable.');
    }
    retainedRoot = await mkdtemp(join(sealedParent, 'visible-acl-'));
    const rootProof = await powershell(aclProof(retainedRoot, true));
    if (!rootProof.completed || rootProof.exitCode !== 0 || rootProof.signal !== null || rootProof.stdout !== 'NATIVE_FIXTURE_VERIFIED' || rootProof.stderr !== '') {
      throw new Error('Owned protected retention root unavailable.');
    }
    await retain('parent-acl-proof', parentProof);
    await retain('root-acl-proof', rootProof);
    fixturesRoot = join(retainedRoot, 'fixtures');
    await mkdir(fixturesRoot);
    workdir = await newFixture('owned-workdir');
    const opaque = await readFile(new URL('../native-database-validation.mjs', import.meta.url), 'utf8');
    const start = opaque.indexOf('async function privateDirectory(path, workdir) {');
    const end = opaque.indexOf('async function privateWrite(path, bytes) {', start);
    if (start < 0 || end <= start) throw new Error('Declared private boundary unavailable.');
    boundaryBytes = opaque.slice(start, end);
  }, NATIVE_DB_VALIDATION.nativeCleanupReserveMs);

  afterAll(async () => {
    if (!retainedRoot || !fixturesRoot || !existsSync(fixturesRoot)) return;
    const sealedParent = resolve('C:/fr-sealed-20261007');
    const canonicalRoot = await realpath(retainedRoot);
    const target = await realpath(fixturesRoot);
    if (!inside(sealedParent, canonicalRoot) || canonicalRoot === sealedParent || !basename(canonicalRoot).startsWith('visible-acl-') || target !== resolve(canonicalRoot, 'fixtures') || (await lstat(fixturesRoot)).isSymbolicLink()) {
      throw new Error('Owned fixture cleanup boundary refused.');
    }
    await rm(target, { recursive: true });
    await writeFile(join(retainedRoot, 'retention-metadata.json'), `${JSON.stringify({ fixtureCleanupVerified: !existsSync(target), nativeTranscriptCount: ordinal, opaqueBoundarySha256: createHash('sha256').update(boundaryBytes).digest('hex') })}\n`, { flag: 'wx' });
  });

  it.each([
    ['ordinary directory', 'ordinary'],
    ['spaces', 'private output with spaces'],
    ['ASCII apostrophe', "owner's private output"],
    ['curly apostrophe', 'owner’s private output'],
    ['quote and command text', "owner'; New-Item ACL-PATH-WAS-EXECUTED -ItemType File; #"],
    ['subexpression command text', 'literal $(New-Item ACL-PATH-WAS-EXECUTED -ItemType File)'],
  ])('accepts owner/System/Admin-only native ACLs with inert %s path data', async (_label, name) => {
    const path = await newFixture(name);
    const outcome = await realAdmission(path);
    expect(existsSync(join(workdir, 'ACL-PATH-WAS-EXECUTED'))).toBe(false);
    expect(existsSync(join(retainedRoot, 'ACL-PATH-WAS-EXECUTED'))).toBe(false);
    expect(outcome).toBe('accepted');
  });

  it('refuses a real native ACL allowing an additional principal', async () => {
    const path = await newFixture('foreign-allowed-principal', true);
    expect(await realAdmission(path)).toBe('refused');
  });

  it('refuses a native Get-Acl error when its exact owned directory disappears', async () => {
    const path = await newFixture('acl-unavailable-at-process-boundary');
    expect(await realAdmission(path, async () => {
      const target = await realpath(path);
      if (target !== resolve(path) || !inside(fixturesRoot, target) || (await lstat(target)).isSymbolicLink()) throw new Error('Owned empty fixture removal refused.');
      await rmdir(target);
    })).toBe('refused');
  });

  it.each([
    ['no ACL verdict', { completed: true, exitCode: 0, signal: null, stdout: '', stderr: '', elapsedMs: 0 }],
    ['incidental success-looking output', { completed: true, exitCode: 0, signal: null, stdout: 'Operation completed successfully.\n', stderr: '', elapsedMs: 0 }],
    ['nonterminating ACL error with a positive verdict', { completed: true, exitCode: 0, signal: null, stdout: 'protected\n', stderr: 'Get-Acl: ACL information unavailable.\n', elapsedMs: 0 }],
    ['command failure with a positive verdict', { completed: true, exitCode: 1, signal: null, stdout: 'protected\n', stderr: 'Native ACL command failed.\n', elapsedMs: 0 }],
    ['missing exit status with a positive verdict', { completed: true, exitCode: null, signal: null, stdout: 'protected\n', stderr: '', elapsedMs: 0 }],
    ['incomplete child process with a positive verdict', { completed: false, exitCode: 0, signal: null, stdout: 'protected\n', stderr: '', elapsedMs: 0 }],
    ['signaled child process with a positive verdict', { completed: true, exitCode: 0, signal: 'SIGTERM', stdout: 'protected\n', stderr: '', elapsedMs: 0 }],
  ] satisfies [string, NativeCapture][])('refuses %s even when the process port returns', async (_label, result) => {
    const path = await newFixture(`process-port-${ordinal}`);
    let calls = 0;
    const outcome = await admission(path, async () => {
      calls += 1;
      await retain('synthetic-process-result', result);
      return result;
    });
    expect(calls).toBeGreaterThan(0);
    expect(outcome).toBe('refused');
  });

  it('refuses a process startup exception without accepting filesystem existence', async () => {
    const path = await newFixture('process-startup-exception');
    let calls = 0;
    const outcome = await admission(path, async () => {
      calls += 1;
      throw new Error('Synthetic ACL process startup failed.');
    });
    expect(calls).toBeGreaterThan(0);
    expect(outcome).toBe('refused');
  });

});
