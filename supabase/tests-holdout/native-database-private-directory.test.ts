import { spawn } from 'node:child_process';
import { chmod, lstat, mkdir, mkdtemp, readFile, realpath, rm, stat } from 'node:fs/promises';
import { join, win32 } from 'node:path';
import { Script } from 'node:vm';
import { afterAll, beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.js';

// DBV-004/007: opaque extraction preserves implementation blindness while exercising
// the registered private process boundary. No SQL or counterpart test is read.
type ProcessOutcome = { completed: boolean; exitCode: number | null; signal: string | null; stdout: string; stderr: string; elapsedMs: number };
type CaptureOptions = { cwd?: string };
type CapturePort = (command: string, args: string[], options?: CaptureOptions) => Promise<ProcessOutcome>;
type DirectoryPort = (path: string, workdir: string) => Promise<unknown>;

const sourceUrl = new URL('../../scripts/native-database-validation.mjs', import.meta.url);
const scratchParent = 'C:\\fr-sealed-20261007';
const workdir = win32.resolve('C:\\Users\\Harsh\\Desktop\\gymloop');
const fixturePath = 'C:\\fr-sealed-20261007\\acl-holdout-process-fixture';
const blankOutcome: ProcessOutcome = { completed: true, exitCode: 0, signal: null, stdout: '', stderr: '', elapsedMs: 0 };
const protectedOutcome: ProcessOutcome = { ...blankOutcome, stdout: 'protected\n' };

async function directoryPort(capture: CapturePort, nativeFilesystem = false): Promise<DirectoryPort> {
  const bytes = await readFile(sourceUrl, 'utf8');
  const start = bytes.indexOf('async function privateDirectory(path, workdir) {');
  const end = bytes.indexOf('async function privateWrite(path, bytes) {', start);
  if (start < 0 || end <= start) throw new Error('Private directory boundary unavailable.');
  return new Script(`${bytes.slice(start, end)}\nprivateDirectory;`).runInNewContext({
    Buffer,
    resolve: win32.resolve,
    inside: (root: string, path: string) => {
      const relative = win32.relative(root, path);
      return relative === '' || (!relative.startsWith('..') && !win32.isAbsolute(relative));
    },
    mkdir: nativeFilesystem ? mkdir : async () => undefined,
    lstat: nativeFilesystem ? lstat : async () => ({ isSymbolicLink: () => false }),
    realpath: nativeFilesystem ? realpath : async (path: string) => path,
    chmod,
    stat,
    process: { platform: 'win32' },
    NATIVE_DB_VALIDATION,
    capture,
    refuse: (code: string) => { throw Object.assign(new Error('Protected directory refused.'), { code }); },
  }) as DirectoryPort;
}

async function nativeCapture(command: string, args: string[], options: CaptureOptions = {}): Promise<ProcessOutcome> {
  return new Promise((resolve, reject) => {
    const started = Date.now();
    const child = spawn(command, args, { ...options, windowsHide: true, shell: false });
    let stdout = '';
    let stderr = '';
    let timedOut = false;
    const timer = setTimeout(() => { timedOut = true; child.kill(); }, NATIVE_DB_VALIDATION.processStopGraceMs);
    child.stdout.on('data', (chunk: Buffer) => { stdout += chunk.toString('utf8'); });
    child.stderr.on('data', (chunk: Buffer) => { stderr += chunk.toString('utf8'); });
    child.on('error', error => { clearTimeout(timer); reject(error); });
    child.on('close', (exitCode, signal) => {
      clearTimeout(timer);
      resolve({ completed: !timedOut, exitCode, signal, stdout, stderr, elapsedMs: Math.max(0, Date.now() - started) });
    });
  });
}

async function sealOwnedDirectory(path: string, broad = false): Promise<void> {
  await mkdir(path);
  // Encoding supplies literal UTF-8 data even for PowerShell's straight/curly quotes.
  const pathData = Buffer.from(path, 'utf8').toString('base64');
  const script = `
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Import-Module (Join-Path $PSHOME 'Modules\\Microsoft.PowerShell.Security\\Microsoft.PowerShell.Security.psd1') -ErrorAction Stop
$path = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${pathData}'))
$owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
$ids = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544'${broad ? ", 'S-1-1-0'" : ''})
$acl = [Security.AccessControl.DirectorySecurity]::new()
$acl.SetAccessRuleProtection($true, $false)
$acl.SetOwner($owner)
foreach ($id in $ids) {
  $sid = [Security.Principal.SecurityIdentifier]::new($id)
  $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, [Security.AccessControl.FileSystemRights]::FullControl, [Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit', [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
  $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $path -AclObject $acl -ErrorAction Stop
$actual = Get-Acl -LiteralPath $path -ErrorAction Stop
if (!$actual.AreAccessRulesProtected -or $actual.Owner -eq $null) { throw 'Fixture ACL verification failed.' }
foreach ($entry in $actual.Access) {
  $sid = $entry.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
  if ($entry.AccessControlType -ne 'Allow' -or $sid -notin $ids) { throw 'Fixture ACL verification failed.' }
}
if (@($actual.Access).Count -ne @($ids | Select-Object -Unique).Count) { throw 'Fixture ACL verification failed.' }
`;
  const result = await nativeCapture('powershell.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')]);
  if (result.exitCode !== 0 || result.stderr !== '') throw new Error('Independent ACL fixture could not be sealed.');
}

describe('DBV-004/007 independent Windows protected directory boundary', () => {
  it('accepts a completed unsignalled process with the exact protected verdict', async () => {
    let reached = false;
    const check = await directoryPort(async () => { reached = true; return { ...protectedOutcome }; });
    await check(fixturePath, workdir);
    expect(reached).toBe(true);
  });

  it.each([
    { label: 'unavailable ACL with empty success output', outcome: { ...blankOutcome } },
    { label: 'incidental stdout', outcome: { ...blankOutcome, stdout: 'An unrelated command completed.\r\n' } },
    { label: 'process failure', outcome: { ...protectedOutcome, exitCode: 1 } },
    { label: 'missing process status', outcome: { ...protectedOutcome, exitCode: null } },
    { label: 'incomplete process', outcome: { ...protectedOutcome, completed: false } },
    { label: 'signalled process', outcome: { ...protectedOutcome, signal: 'SIGTERM' } },
    { label: 'non-terminating ACL error', outcome: { ...protectedOutcome, stderr: 'Get-Acl : Access is denied.\r\n' } },
  ])('refuses $label after reaching native capture', async ({ outcome }) => {
    const calls: { command: string; args: string[] }[] = [];
    const check = await directoryPort(async (command, args) => {
      calls.push({ command, args });
      return outcome;
    });
    await expect(check(fixturePath, workdir)).rejects.toThrow();
    expect(calls).toHaveLength(1);
    expect(calls[0]?.command).toMatch(/powershell(?:\.exe)?$/i);
    expect(calls[0]?.args.length).toBeGreaterThan(0);
  });

  it('refuses a failed process launch after reaching native capture', async () => {
    let reached = false;
    const check = await directoryPort(async () => { reached = true; throw new Error('Synthetic process launch refused.'); });
    await expect(check(fixturePath, workdir)).rejects.toThrow();
    expect(reached).toBe(true);
  });

  describe.skipIf(process.platform !== 'win32')('native Windows PowerShell 5.1 invocation', () => {
    let ownedRoot = '';

    beforeAll(async () => {
      ownedRoot = await mkdtemp(join(scratchParent, 'acl-holdout-'));
    });

    afterAll(async () => {
      if (!ownedRoot) return;
      const relative = win32.relative(win32.resolve(scratchParent), win32.resolve(ownedRoot));
      if (!relative.startsWith('acl-holdout-') || relative.includes('\\') || win32.isAbsolute(relative)) throw new Error('Scratch ownership refused.');
      await rm(ownedRoot, { recursive: true, force: true });
    });

    it.each([
      'ordinary private directory',
      "spaces and a straight apostrophe's directory",
      'curly apostrophes ‘quoted’ and ’ trailing',
      'command-like ; Write-Output injected ; $null directory',
    ])('accepts the exact protected literal directory: %s', async name => {
      const directory = join(ownedRoot, name);
      await sealOwnedDirectory(directory);
      let reached = false;
      const check = await directoryPort(async (command, args, options) => {
        reached = true;
        return nativeCapture(command, args, options);
      }, true);
      await check(directory, workdir);
      expect(reached).toBe(true);
    });

    it('refuses a real Everyone grant after reaching native capture', async () => {
      const directory = join(ownedRoot, 'broad principal');
      await sealOwnedDirectory(directory, true);
      let reached = false;
      const check = await directoryPort(async (command, args, options) => {
        reached = true;
        return nativeCapture(command, args, options);
      }, true);
      await expect(check(directory, workdir)).rejects.toThrow();
      expect(reached).toBe(true);
    });

    it('refuses non-terminating ACL stderr even alongside its native successful verdict', async () => {
      const directory = join(ownedRoot, 'error output beside native verdict');
      await sealOwnedDirectory(directory);
      let successfulCapture = false;
      const check = await directoryPort(async (command, args, options) => {
        const result = await nativeCapture(command, args, options);
        expect(result.exitCode).toBe(0);
        expect(result.stderr).toBe('');
        successfulCapture = true;
        return { ...result, stderr: 'Get-Acl : The requested ACL is unavailable.\r\n' };
      }, true);
      await expect(check(directory, workdir)).rejects.toThrow();
      expect(successfulCapture).toBe(true);
    });
  });
});
