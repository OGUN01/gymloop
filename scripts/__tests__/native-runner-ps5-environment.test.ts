import { spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';

const visibleCandidate = 'C:/fr-sealed-20261007/register-start-trial8.ps1';
const visibleLimitsPath = 'C:/fr-sealed-20261007/watchdog-limits.json';
const visibleNativeModules = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Modules';
const visibleLimits = (process.platform === 'win32' ? JSON.parse(readFileSync(visibleLimitsPath, 'utf8')) : {}) as {
  processStopGraceMs: number;
  nativeCleanupReserveMs: number;
  maxProcessBytes: number;
  millisecondsPerSecond: number;
  hookArgumentCount: number;
};
const visibleArguments = [
  'ordinary', '', 'with spaces', 'quote"inside', 'end\\', 'slash\\\\"quote',
  'literal;$([sentinel])', 'caf\u00e9 \ud83d\udcaa', 'line\r\nvalue', 'tab\tvalue',
];
const visibleHashBytes = Buffer.from('DBV-008 independent visible native file probe\r\n', 'utf8');

// The frozen contract expressly permits opaque extraction of these two existing
// functions. Their source is never inspected, printed, or invoked as a wrapper.
function executeVisiblePs5Environment(
  scenario: 'native' | 'casefold' | 'other' | 'hash-refusal' | 'nonzero' | 'stdout-limit' | 'stderr-limit' | 'timeout',
) {
  if (!existsSync(visibleCandidate)) throw new Error('Frozen trial8 candidate is absent');
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-dbv008-visible-'));
  const hashFile = join(directory, 'harmless-hash.bin');
  writeFileSync(hashFile, visibleHashBytes);
  writeFileSync(join(directory, 'arguments.json'), JSON.stringify(visibleArguments), 'utf8');
  writeFileSync(join(directory, 'native-probe.ps1'), String.raw`
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$limits = ConvertFrom-Json ([IO.File]::ReadAllText([string]$args[1]))
$path = [string]$args[0]
$values = @($args | Select-Object -Skip $limits.hookArgumentCount)
$canonical = 'C:\Windows\System32\WindowsPowerShell\v1.0\Modules'
$commandNames = @('Get-FileHash', 'ConvertTo-Json', 'New-Item', 'Get-Acl')
$commandTrees = @($commandNames | ForEach-Object { (Get-Command -Name $_ -ErrorAction Stop).Module.Path })
$nativeDirectory = Get-Item -LiteralPath $canonical -Force
$createdPath = Join-Path (Split-Path -Parent $path) 'management-probe.txt'
$null = New-Item -ItemType File -Path $createdPath -ErrorAction Stop
$created = Test-Path -LiteralPath $createdPath -PathType Leaf
$acl = Get-Acl -LiteralPath $createdPath -ErrorAction Stop
Remove-Item -LiteralPath $createdPath -ErrorAction Stop
$removed = -not (Test-Path -LiteralPath $createdPath)
$hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
$receipt = [ordered]@{
  version = $PSVersionTable.PSVersion.ToString()
  modulePath = $env:PSModulePath
  arguments = $values
  hash = $hash
  commandTrees = $commandTrees
  directoryIsReparse = (($nativeDirectory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
  directoryFullName = $nativeDirectory.FullName
  aclPresent = ($null -ne $acl)
  created = $created
  removed = $removed
}
[Console]::Out.Write(($receipt | ConvertTo-Json -Compress))
`, 'utf8');
  writeFileSync(join(directory, 'other-probe.ps1'), String.raw`
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
[Console]::Out.Write((@{ modulePath = $env:PSModulePath; version = $PSVersionTable.PSVersion.ToString() } | ConvertTo-Json -Compress))
`, 'utf8');
  writeFileSync(join(directory, 'failure-probe.ps1'), String.raw`
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$limits = ConvertFrom-Json ([IO.File]::ReadAllText([string]$args[0]))
if ([string]$args[1] -eq 'hash-refusal') {
  try { $null = Get-FileHash -LiteralPath ([string]$args[2]) -Algorithm SHA256 -ErrorAction Stop }
  catch { [Console]::Error.Write('visible-file-hash-refusal'); exit $limits.hookArgumentCount }
  exit 0
}
[Console]::Out.Write('visible-before-nonzero')
[Console]::Error.Write('visible-nonzero')
exit $limits.hookArgumentCount
`, 'utf8');
  writeFileSync(join(directory, 'limit-probe.ps1'), String.raw`
$ErrorActionPreference = 'Stop'
$limits = ConvertFrom-Json ([IO.File]::ReadAllText([string]$args[0]))
$content = [string]::new([char]'v', $limits.maxProcessBytes + 1)
if ([string]$args[1] -eq 'stdout-limit') { [Console]::Out.Write($content) }
else { [Console]::Error.Write($content) }
`, 'utf8');
  writeFileSync(join(directory, 'timeout-probe.ps1'), String.raw`
$limits = ConvertFrom-Json ([IO.File]::ReadAllText([string]$args[0]))
[IO.File]::WriteAllText([string]$args[1], [string]$PID)
[Threading.Thread]::Sleep($limits.processStopGraceMs + $limits.millisecondsPerSecond)
[IO.File]::WriteAllText([string]$args[2], 'late-completion')
`, 'utf8');
  const fixturePath = join(directory, 'fixture.ps1');
  writeFileSync(fixturePath, String.raw`
param([string]$Candidate, [string]$LimitsPath, [string]$Directory, [string]$Scenario)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility, Microsoft.PowerShell.Management
$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($Candidate, [ref]$tokens, [ref]$parseErrors)
$names = @('Windows-Argument', 'Invoke-Private')
$functions = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $names }, $true))
if ($parseErrors.Count -ne 0 -or $functions.Count -ne $names.Count) { throw 'private-function-port-unavailable' }
. ([scriptblock]::Create(($functions | ForEach-Object { $_.Extent.Text }) -join [Environment]::NewLine))
$script:taskLimits = ConvertFrom-Json ([IO.File]::ReadAllText($LimitsPath))
$script:taskUtf8 = [Text.UTF8Encoding]::new($false)
$script:taskNativePowerShell = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
$script:taskDeadline = $null
$parentOriginal = $env:PSModulePath
$machineOriginal = [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine')
$userOriginal = [Environment]::GetEnvironmentVariable('PSModulePath', 'User')
$parentMarker = [IO.Path]::Combine($PSHOME, 'Modules') + ';C:\DBV008-visible-inherited-marker'
$env:PSModulePath = $parentMarker
$before = $env:PSModulePath
$executable = $taskNativePowerShell
$arguments = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File')
$budget = $taskLimits.processStopGraceMs
switch ($Scenario) {
  'native' {
    $arguments += @([IO.Path]::Combine($Directory, 'native-probe.ps1'), [IO.Path]::Combine($Directory, 'harmless-hash.bin'), $LimitsPath)
    $arguments += [string[]](ConvertFrom-Json ([IO.File]::ReadAllText([IO.Path]::Combine($Directory, 'arguments.json'))))
  }
  'casefold' {
    $executable = $taskNativePowerShell.ToUpperInvariant()
    $arguments += @([IO.Path]::Combine($Directory, 'native-probe.ps1'), [IO.Path]::Combine($Directory, 'harmless-hash.bin'), $LimitsPath)
    $arguments += [string[]](ConvertFrom-Json ([IO.File]::ReadAllText([IO.Path]::Combine($Directory, 'arguments.json'))))
  }
  'other' {
    $executable = [IO.Path]::Combine($PSHOME, 'pwsh.exe')
    $arguments += [IO.Path]::Combine($Directory, 'other-probe.ps1')
  }
  { $_ -in @('hash-refusal', 'nonzero') } {
    $arguments += @([IO.Path]::Combine($Directory, 'failure-probe.ps1'), $LimitsPath, $Scenario, [IO.Path]::Combine($Directory, 'absent-hash.bin'))
  }
  { $_ -in @('stdout-limit', 'stderr-limit') } {
    $arguments += @([IO.Path]::Combine($Directory, 'limit-probe.ps1'), $LimitsPath, $Scenario)
  }
  'timeout' {
    $budget = $taskLimits.millisecondsPerSecond
    $arguments += @([IO.Path]::Combine($Directory, 'timeout-probe.ps1'), $LimitsPath, [IO.Path]::Combine($Directory, 'child-pid.txt'), [IO.Path]::Combine($Directory, 'late.txt'))
  }
  default { throw 'unknown-private-scenario' }
}
$refused = $false
$result = $null
$watch = [Diagnostics.Stopwatch]::StartNew()
try { $result = Invoke-Private -Executable $executable -Arguments $arguments -Budget $budget -CommandLine $null }
catch { $refused = $true }
$watch.Stop()
$after = $env:PSModulePath
$machineUnchanged = [string]::Equals($machineOriginal, [Environment]::GetEnvironmentVariable('PSModulePath', 'Machine'), [StringComparison]::Ordinal)
$userUnchanged = [string]::Equals($userOriginal, [Environment]::GetEnvironmentVariable('PSModulePath', 'User'), [StringComparison]::Ordinal)
$env:PSModulePath = $parentOriginal
$restored = [string]::Equals($env:PSModulePath, $parentOriginal, [StringComparison]::Ordinal)
$pidPath = [IO.Path]::Combine($Directory, 'child-pid.txt')
$pidSeen = [IO.File]::Exists($pidPath)
$pidAlive = $false
if ($pidSeen) {
  try { $child = [Diagnostics.Process]::GetProcessById([int]([IO.File]::ReadAllText($pidPath))); $pidAlive = -not $child.HasExited; $child.Dispose() }
  catch { $pidAlive = $false }
}
$probe = $null
if ($null -ne $result -and $Scenario -in @('native', 'casefold', 'other') -and $result.exitCode -eq 0) {
  $probe = ConvertFrom-Json $result.stdout
}
$stdout = $null
$stderr = $null
if ($null -ne $result -and $Scenario -in @('hash-refusal', 'nonzero')) { $stdout = $result.stdout; $stderr = $result.stderr }
$receipt = [ordered]@{
  refused = $refused
  resultKeys = $(if ($null -eq $result) { @() } elseif ($result -is [Collections.IDictionary]) { @($result.Keys | Sort-Object) } else { @($result.PSObject.Properties.Name | Sort-Object) })
  exitCode = $(if ($null -eq $result) { $null } else { $result.exitCode })
  stdout = $stdout
  stderr = $stderr
  stdoutLength = $(if ($null -eq $result) { $null } else { $result.stdout.Length })
  stderrLength = $(if ($null -eq $result) { $null } else { $result.stderr.Length })
  probe = $probe
  parentBefore = $before
  parentAfter = $after
  machineUnchanged = $machineUnchanged
  userUnchanged = $userUnchanged
  restored = $restored
  pidSeen = $pidSeen
  pidAlive = $pidAlive
  lateCompleted = [IO.File]::Exists([IO.Path]::Combine($Directory, 'late.txt'))
  elapsedMs = $watch.ElapsedMilliseconds
}
$json = $receipt | ConvertTo-Json -Depth $taskLimits.hookArgumentCount -Compress
[IO.File]::WriteAllText([IO.Path]::Combine($Directory, 'receipt.json'), $json, $taskUtf8)
[Console]::Out.Write($json)
`, 'utf8');
  const result = spawnSync('pwsh.exe', [
    '-NoProfile', '-NonInteractive', '-File', fixturePath,
    '-Candidate', visibleCandidate, '-LimitsPath', visibleLimitsPath,
    '-Directory', directory, '-Scenario', scenario,
  ], {
    encoding: 'utf8', windowsHide: true,
    timeout: visibleLimits.nativeCleanupReserveMs,
    maxBuffer: visibleLimits.maxProcessBytes,
  });
  writeFileSync(join(directory, 'fixture.stdout.private.txt'), result.stdout ?? '', 'utf8');
  writeFileSync(join(directory, 'fixture.stderr.private.txt'), result.stderr ?? '', 'utf8');
  if (result.error || result.status !== 0) throw new Error('Private independent PowerShell fixture failed');
  return JSON.parse(result.stdout) as {
    refused: boolean;
    resultKeys: string[];
    exitCode: number | null;
    stdout: string | null;
    stderr: string | null;
    stdoutLength: number | null;
    stderrLength: number | null;
    probe: {
      version: string;
      modulePath: string;
      arguments: string[];
      hash: string;
      commandTrees: string[];
      directoryIsReparse: boolean;
      directoryFullName: string;
      aclPresent: boolean;
      created: boolean;
      removed: boolean;
    } | null;
    parentBefore: string;
    parentAfter: string;
    machineUnchanged: boolean;
    userUnchanged: boolean;
    restored: boolean;
    pidSeen: boolean;
    pidAlive: boolean;
    lateCompleted: boolean;
    elapsedMs: number;
  };
}

function registerVisiblePs5EnvironmentTest(name: string, callback: () => void) {
  if (process.platform === 'win32') it(name, callback, visibleLimits.nativeCleanupReserveMs);
  else it.skip(name, callback);
}

describe('DBV-008 frozen native PowerShell module environment', () => {
  registerVisiblePs5EnvironmentTest('discovers vendor hash, JSON, filesystem and security commands and preserves exact -File arguments', () => {
    const receipt = executeVisiblePs5Environment('native');
    expect(receipt.refused).toBe(false);
    expect(receipt.resultKeys).toEqual(['exitCode', 'stderr', 'stdout']);
    expect(receipt.exitCode).toBe(0);
    expect(receipt.probe?.version.startsWith('5.')).toBe(true);
    expect(receipt.probe?.modulePath.split(';')).toEqual(['C:\\Program Files\\WindowsPowerShell\\Modules', visibleNativeModules]);
    expect(receipt.probe?.arguments).toEqual(visibleArguments);
    expect(receipt.probe?.hash).toBe(createHash('sha256').update(visibleHashBytes).digest('hex'));
    expect(receipt.probe?.commandTrees.every(path => path.toLowerCase().startsWith(`${visibleNativeModules.toLowerCase()}\\`))).toBe(true);
    expect(receipt.probe?.directoryIsReparse).toBe(false);
    expect(receipt.probe?.directoryFullName).toBe(visibleNativeModules);
    expect(receipt.probe?.aclPresent).toBe(true);
    expect(receipt.probe?.created).toBe(true);
    expect(receipt.probe?.removed).toBe(true);
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
    expect(receipt.machineUnchanged).toBe(true);
    expect(receipt.userUnchanged).toBe(true);
    expect(receipt.restored).toBe(true);
  });

  registerVisiblePs5EnvironmentTest('recognizes only the fixed native executable with Windows case-insensitive path semantics', () => {
    const receipt = executeVisiblePs5Environment('casefold');
    expect(receipt.refused).toBe(false);
    expect(receipt.exitCode).toBe(0);
    expect(receipt.probe?.modulePath.split(';')).toEqual(['C:\\Program Files\\WindowsPowerShell\\Modules', visibleNativeModules]);
    expect(receipt.probe?.arguments).toEqual(visibleArguments);
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });

  registerVisiblePs5EnvironmentTest('preserves the caller environment for a different child executable', () => {
    const receipt = executeVisiblePs5Environment('other');
    expect(receipt.refused).toBe(false);
    expect(receipt.exitCode).toBe(0);
    expect(receipt.probe?.modulePath).toBe(receipt.parentBefore);
    expect(receipt.probe?.modulePath).not.toBe(visibleNativeModules);
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
    expect(receipt.machineUnchanged).toBe(true);
    expect(receipt.userUnchanged).toBe(true);
    expect(receipt.restored).toBe(true);
  });

  registerVisiblePs5EnvironmentTest('retains the actual failed-file Get-FileHash refusal and nonzero result', () => {
    const receipt = executeVisiblePs5Environment('hash-refusal');
    expect(receipt.refused).toBe(false);
    expect(receipt.resultKeys).toEqual(['exitCode', 'stderr', 'stdout']);
    expect(receipt.exitCode).toBe(visibleLimits.hookArgumentCount);
    expect(receipt.stdout).toBe('');
    expect(receipt.stderr).toBe('visible-file-hash-refusal');
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });

  registerVisiblePs5EnvironmentTest('preserves a native child nonzero exit and its bounded private streams', () => {
    const receipt = executeVisiblePs5Environment('nonzero');
    expect(receipt.refused).toBe(false);
    expect(receipt.exitCode).toBe(visibleLimits.hookArgumentCount);
    expect(receipt.stdout).toBe('visible-before-nonzero');
    expect(receipt.stderr).toBe('visible-nonzero');
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });

  registerVisiblePs5EnvironmentTest('refuses stdout beyond the unchanged sealed process output ceiling', () => {
    const receipt = executeVisiblePs5Environment('stdout-limit');
    expect(receipt.refused).toBe(true);
    expect(receipt.exitCode).toBeNull();
    expect(receipt.stdoutLength).toBeNull();
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });

  registerVisiblePs5EnvironmentTest('refuses stderr beyond the unchanged sealed process output ceiling', () => {
    const receipt = executeVisiblePs5Environment('stderr-limit');
    expect(receipt.refused).toBe(true);
    expect(receipt.exitCode).toBeNull();
    expect(receipt.stderrLength).toBeNull();
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });

  registerVisiblePs5EnvironmentTest('throws at the supplied sealed-derived budget and terminates the actual harmless child', () => {
    const receipt = executeVisiblePs5Environment('timeout');
    expect(receipt.refused).toBe(true);
    expect(receipt.exitCode).toBeNull();
    expect(receipt.pidSeen).toBe(true);
    expect(receipt.pidAlive).toBe(false);
    expect(receipt.lateCompleted).toBe(false);
    expect(receipt.elapsedMs).toBeLessThan(visibleLimits.processStopGraceMs);
    expect(receipt.parentAfter).toBe(receipt.parentBefore);
  });
});
