import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';
import { test as heldVitestTest } from 'vitest';

function registerHeldPs5EnvironmentTest(name: string, options: { skip: boolean | string }, body: () => void) {
  if (options.skip) {
    heldVitestTest.skip(name, body);
    return;
  }
  const sealedLimits = JSON.parse(readFileSync('C:/fr-sealed-20261007/watchdog-limits.json', 'utf8')) as {
    nativeCleanupReserveMs: number;
    processStopGraceMs: number;
  };
  heldVitestTest(name, { timeout: sealedLimits.nativeCleanupReserveMs + sealedLimits.processStopGraceMs + sealedLimits.processStopGraceMs }, body);
}

// Independent DBV-008 holdout. The candidate is consumed only by an opaque AST
// extraction in the private fixture; no production entry point is executed.
function executeHeldPs5Environment(scenario: string) {
  const candidate = 'C:/fr-sealed-20261007/register-start-trial8.ps1';
  const limitsPath = 'C:/fr-sealed-20261007/watchdog-limits.json';
  assert.ok(existsSync(candidate), 'The frozen Windows candidate must exist before native acceptance.');
  const limitsBytes = readFileSync(limitsPath);
  assert.equal(createHash('sha256').update(limitsBytes).digest('hex'), '5799d0354e2cf671851f3e6016ea37de9d98e1441559ec724b2db0805c003320');
  const limits = JSON.parse(limitsBytes.toString('utf8')) as {
    processStopGraceMs: number;
    nativeCleanupReserveMs: number;
    timeoutQueryMaxBytes: number;
    maxProcessBytes: number;
    millisecondsPerSecond: number;
    artifactRetentionDays: number;
  };
  const directory = mkdtempSync(join(tmpdir(), 'held-ps5-env-'));
  const fixture = join(directory, 'fixture.ps1');
  const payload = join(directory, 'payload.txt');
  const expectedArguments = ['', 'space separated', 'quote"inside', 'backslash\\', '\\"both', '-looks-like-a-switch', 'भारत 🏋', "single'quote"];
  const expectedInherited = 'C:\\held-environment-sentinel;C:\\held-second-sentinel';
  writeFileSync(payload, 'Independent held DBV-008 payload\r\n', 'utf8');
  writeFileSync(join(directory, 'native-probe.ps1'), `
$ErrorActionPreference = 'Stop'
$commands = @('Get-FileHash', 'ConvertTo-Json', 'ConvertFrom-Json', 'Get-Item', 'Get-ChildItem', 'Get-Acl')
$observed = @()
foreach ($commandName in $commands) {
  $command = Get-Command -Name $commandName -ErrorAction Stop
  $observed += @{ name = $command.Name; module = $command.ModuleName; path = $command.Module.Path }
}
$vendor = Get-Item -LiteralPath 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Modules' -ErrorAction Stop
$file = Get-Item -LiteralPath (Join-Path $PSScriptRoot 'payload.txt') -ErrorAction Stop
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $file.FullName -ErrorAction Stop
$acl = Get-Acl -LiteralPath $file.FullName -ErrorAction Stop
$roundTrip = (@{ marker = 'held-json-roundtrip' } | ConvertTo-Json -Compress) | ConvertFrom-Json -ErrorAction Stop
$nativeArgs = @([Environment]::GetCommandLineArgs())
$scriptIndex = [Array]::IndexOf($nativeArgs, $PSCommandPath)
if ($scriptIndex -lt 0) { throw 'Missing own script boundary' }
$transport = @()
for ($index = $scriptIndex + 1; $index -lt $nativeArgs.Length; $index++) { $transport += $nativeArgs[$index] }
@{ version = $PSVersionTable.PSVersion.ToString(); modulePath = $env:PSModulePath; commands = $observed; hash = $hash.Hash; fileName = $file.Name; aclPath = $acl.Path; roundTrip = $roundTrip.marker; arguments = $transport; reparse = (($vendor.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) } | ConvertTo-Json -Depth ([int]${limits.artifactRetentionDays}) -Compress
`, 'utf8');
  writeFileSync(join(directory, 'exit-probe.ps1'), `
[Console]::Out.Write('held-success-stream')
[Console]::Error.Write('held-error-stream')
exit ([int]${limits.artifactRetentionDays})
`, 'utf8');
  writeFileSync(join(directory, 'sleep-probe.ps1'), `
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'target.pid'), [string]$PID)
[Threading.Thread]::Sleep([int]${limits.processStopGraceMs + limits.nativeCleanupReserveMs})
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'target-finished.txt'), 'finished')
`, 'utf8');
  writeFileSync(join(directory, 'sentinel-probe.ps1'), `
[Threading.Thread]::Sleep([int]${limits.processStopGraceMs + limits.nativeCleanupReserveMs})
`, 'utf8');
  writeFileSync(join(directory, 'overflow-probe.ps1'), `
$chunk = New-Object string ([char]'x', [int]${limits.timeoutQueryMaxBytes})
$emitted = 0
while ($emitted -le [long]${limits.maxProcessBytes}) {
  if ($args[0] -eq 'stderr') { [Console]::Error.Write($chunk) } else { [Console]::Out.Write($chunk) }
  $emitted += $chunk.Length
}
`, 'utf8');
  writeFileSync(join(directory, 'input.json'), JSON.stringify({ candidate, limitsPath, scenario, expectedArguments, expectedInherited }), 'utf8');
  writeFileSync(fixture, `
$ErrorActionPreference = 'Stop'
$inputRecord = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'input.json')) | ConvertFrom-Json
$taskLimits = [IO.File]::ReadAllText($inputRecord.limitsPath) | ConvertFrom-Json
$taskUtf8 = [Text.UTF8Encoding]::new($false)
$taskNativePowerShell = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe'
$taskDeadline = $null
$parseTokens = $null
$parseErrors = $null
$candidateAst = [Management.Automation.Language.Parser]::ParseFile($inputRecord.candidate, [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count -ne 0) { throw 'Candidate cannot be parsed' }
foreach ($entryName in @('Windows-Argument', 'Invoke-Private')) {
  $entries = @($candidateAst.FindAll({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $entryName }, $true))
  if ($entries.Count -ne 1) { throw 'Frozen helper boundary unavailable' }
  . ([ScriptBlock]::Create($entries[0].Extent.Text))
}
$originalCaller = $env:PSModulePath
$originalUser = [Environment]::GetEnvironmentVariable('PSModulePath', [EnvironmentVariableTarget]::User)
$originalMachine = [Environment]::GetEnvironmentVariable('PSModulePath', [EnvironmentVariableTarget]::Machine)
$env:PSModulePath = [string]$inputRecord.expectedInherited + ';' + (Join-Path $PSHOME 'Modules')
$beforeCall = $env:PSModulePath
$result = $null
$reported = $null
$nativePrefix = @('-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File')
try {
  switch ($inputRecord.scenario) {
    'modules' {
      $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'native-probe.ps1')))
    }
    'upper-native' {
      $result = Invoke-Private -Executable $taskNativePowerShell.ToUpperInvariant() -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'native-probe.ps1')))
    }
    'arguments' {
      $childArguments = $nativePrefix + @((Join-Path $PSScriptRoot 'native-probe.ps1')) + @($inputRecord.expectedArguments)
      $result = Invoke-Private -Executable $taskNativePowerShell -Arguments $childArguments
    }
    'command-line' {
      $childArguments = $nativePrefix + @((Join-Path $PSScriptRoot 'native-probe.ps1')) + @($inputRecord.expectedArguments)
      $lineParts = @()
      foreach ($value in $childArguments) { $lineParts += Windows-Argument -Value ([string]$value) }
      $result = Invoke-Private -Executable $taskNativePowerShell -Arguments @() -CommandLine ($lineParts -join ' ')
    }
    'other-executable' {
      $result = Invoke-Private -Executable 'C:\\Windows\\System32\\cmd.exe' -Arguments @('/d', '/c', 'echo %PSModulePath%')
    }
    'nonzero' {
      $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'exit-probe.ps1')))
    }
    'missing-file' {
      $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'missing-file.ps1')))
    }
    'missing-executable' {
      $refused = $false
      try { $result = Invoke-Private -Executable (Join-Path $PSScriptRoot 'missing-executable.exe') -Arguments @() } catch { $refused = $true }
      $reported = @{ refused = $refused; returned = ($null -ne $result) }
    }
    'timeout' {
      $sentinelInfo = [Diagnostics.ProcessStartInfo]::new()
      $sentinelInfo.FileName = $taskNativePowerShell
      $sentinelInfo.UseShellExecute = $false
      $sentinelInfo.CreateNoWindow = $true
      foreach ($value in ($nativePrefix + @((Join-Path $PSScriptRoot 'sentinel-probe.ps1')))) { $sentinelInfo.ArgumentList.Add($value) }
      $sentinelInfo.Environment['PSModulePath'] = 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Modules'
      $sentinel = [Diagnostics.Process]::Start($sentinelInfo)
      try {
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $refused = $false
        try { $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'sleep-probe.ps1'))) -Budget ([int]$taskLimits.processStopGraceMs) } catch { $refused = $true }
        $clock.Stop()
        $pidFile = Join-Path $PSScriptRoot 'target.pid'
        $started = [IO.File]::Exists($pidFile)
        $stopped = $false
        if ($started) {
          $targetPid = [int][IO.File]::ReadAllText($pidFile)
          try { $target = [Diagnostics.Process]::GetProcessById($targetPid); $stopped = $target.HasExited; $target.Dispose() } catch [ArgumentException] { $stopped = $true }
        }
        $reported = @{ refused = $refused; returned = ($null -ne $result); started = $started; stopped = $stopped; sentinelAlive = (-not $sentinel.HasExited); finished = [IO.File]::Exists((Join-Path $PSScriptRoot 'target-finished.txt')); elapsedMs = $clock.ElapsedMilliseconds }
      } finally {
        if (-not $sentinel.HasExited) { $sentinel.Kill($true); [void]$sentinel.WaitForExit([int]$taskLimits.processStopGraceMs) }
        $sentinel.Dispose()
      }
    }
    'stdout-overflow' {
      $refused = $false
      try { $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'overflow-probe.ps1'), 'stdout')) } catch { $refused = $true }
      $reported = @{ refused = $refused; returned = ($null -ne $result) }
    }
    'stderr-overflow' {
      $refused = $false
      try { $result = Invoke-Private -Executable $taskNativePowerShell -Arguments ($nativePrefix + @((Join-Path $PSScriptRoot 'overflow-probe.ps1'), 'stderr')) } catch { $refused = $true }
      $reported = @{ refused = $refused; returned = ($null -ne $result) }
    }
    default { throw 'Unknown held probe' }
  }
  if ($null -eq $reported) {
    $resultNames = @()
    if ($result -is [Collections.IDictionary]) { $resultNames = @($result.Keys) } else { $resultNames = @($result.PSObject.Properties.Name) }
    $reported = @{ result = $result; keys = @($resultNames | Sort-Object) }
  }
  $reported.inherited = $beforeCall
  $reported.callerUnchanged = ($env:PSModulePath -ceq $beforeCall)
  $reported.userUnchanged = ([Environment]::GetEnvironmentVariable('PSModulePath', [EnvironmentVariableTarget]::User) -ceq $originalUser)
  $reported.machineUnchanged = ([Environment]::GetEnvironmentVariable('PSModulePath', [EnvironmentVariableTarget]::Machine) -ceq $originalMachine)
  $reported | ConvertTo-Json -Depth ([int]$taskLimits.artifactRetentionDays) -Compress
} finally { $env:PSModulePath = $originalCaller }
`, 'utf8');
  try {
    const completion = spawnSync('pwsh.exe', ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', fixture], {
      encoding: 'utf8',
      windowsHide: true,
      timeout: limits.nativeCleanupReserveMs + limits.processStopGraceMs + limits.processStopGraceMs,
      maxBuffer: limits.timeoutQueryMaxBytes,
    });
    assert.equal(completion.error, undefined, 'The private held fixture must finish within sealed process and output limits.');
    assert.equal(completion.status, 0, 'The private held fixture must complete without infrastructure failure.');
    assert.equal(completion.stderr, '', 'The controlled fixture must not emit unbounded diagnostics.');
    const observation = JSON.parse(completion.stdout) as {
      result?: { exitCode: number; stdout: string; stderr: string };
      keys?: string[];
      refused?: boolean;
      returned?: boolean;
      started?: boolean;
      stopped?: boolean;
      sentinelAlive?: boolean;
      finished?: boolean;
      elapsedMs?: number;
      inherited: string;
      callerUnchanged: boolean;
      userUnchanged: boolean;
      machineUnchanged: boolean;
    };
    assert.equal(observation.callerUnchanged, true);
    assert.equal(observation.userUnchanged, true);
    assert.equal(observation.machineUnchanged, true);
    if (observation.result) {
      assert.deepEqual(observation.keys, ['exitCode', 'stderr', 'stdout']);
      assert.equal(Number.isInteger(observation.result.exitCode), true);
      assert.equal(typeof observation.result.stdout, 'string');
      assert.equal(typeof observation.result.stderr, 'string');
    }
    return { observation, limits, expectedArguments, expectedInherited, expectedHash: createHash('sha256').update(readFileSync(payload)).digest('hex').toUpperCase() };
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

for (const scenario of ['modules', 'upper-native']) {
  registerHeldPs5EnvironmentTest(`DBV-008 native PS5 ${scenario} resolves vendor hash/JSON/filesystem/security commands`, { skip: process.platform !== 'win32' && 'Requires actual native Windows PowerShell 5 and vendor modules.' }, () => {
    const { observation, expectedHash } = executeHeldPs5Environment(scenario);
    assert.ok(observation.result);
    assert.equal(observation.result.exitCode, 0);
    assert.equal(observation.result.stderr, '');
    const probe = JSON.parse(observation.result.stdout) as { version: string; modulePath: string; commands: { name: string; module: string; path: string }[]; hash: string; fileName: string; aclPath: string; roundTrip: string; reparse: boolean };
    assert.ok(probe.version.startsWith('5.'));
    const nativeDirectories = probe.modulePath.toLowerCase().split(';');
    assert.ok(nativeDirectories.includes('c:\\windows\\system32\\windowspowershell\\v1.0\\modules'));
    for (const directory of nativeDirectories) assert.ok(['c:\\windows\\system32\\windowspowershell\\v1.0\\modules', 'c:\\program files\\windowspowershell\\modules'].includes(directory));
    assert.equal(probe.hash, expectedHash);
    assert.equal(probe.fileName, 'payload.txt');
    assert.ok(probe.aclPath.endsWith('payload.txt'));
    assert.equal(probe.roundTrip, 'held-json-roundtrip');
    assert.equal(probe.reparse, false);
    assert.deepEqual(probe.commands.map(({ name, module }) => [name, module]), [
      ['Get-FileHash', 'Microsoft.PowerShell.Utility'],
      ['ConvertTo-Json', 'Microsoft.PowerShell.Utility'],
      ['ConvertFrom-Json', 'Microsoft.PowerShell.Utility'],
      ['Get-Item', 'Microsoft.PowerShell.Management'],
      ['Get-ChildItem', 'Microsoft.PowerShell.Management'],
      ['Get-Acl', 'Microsoft.PowerShell.Security'],
    ]);
    for (const command of probe.commands) assert.equal(command.path.toLowerCase(), `c:\\windows\\system32\\windowspowershell\\v1.0\\modules\\${command.module.toLowerCase()}\\${command.module.toLowerCase()}.psd1`);
  });
}

for (const scenario of ['arguments', 'command-line']) {
  registerHeldPs5EnvironmentTest(`DBV-008 native PS5 ${scenario} preserves exact empty/quoted/Unicode argument values`, { skip: process.platform !== 'win32' && 'Requires actual native Windows PowerShell 5 argument transport.' }, () => {
    const { observation, expectedArguments } = executeHeldPs5Environment(scenario);
    assert.ok(observation.result);
    assert.equal(observation.result.exitCode, 0);
    assert.equal(observation.result.stderr, '');
    const probe = JSON.parse(observation.result.stdout) as { arguments: string[] };
    assert.deepEqual(probe.arguments, expectedArguments);
  });
}

registerHeldPs5EnvironmentTest('DBV-008 another executable retains its inherited module environment', { skip: process.platform !== 'win32' && 'Requires actual Windows native process environment.' }, () => {
  const { observation, expectedInherited } = executeHeldPs5Environment('other-executable');
  assert.ok(observation.result);
  assert.equal(observation.result.exitCode, 0);
  assert.equal(observation.result.stderr, '');
  assert.ok(observation.inherited.startsWith(`${expectedInherited};`));
  assert.equal(observation.result.stdout.trim(), observation.inherited);
});

registerHeldPs5EnvironmentTest('DBV-008 completed native child preserves its nonzero exit and separate output streams', { skip: process.platform !== 'win32' && 'Requires actual native Windows PowerShell 5 exit status.' }, () => {
  const { observation, limits } = executeHeldPs5Environment('nonzero');
  assert.ok(observation.result);
  assert.equal(observation.result.exitCode, limits.artifactRetentionDays);
  assert.equal(observation.result.stdout, 'held-success-stream');
  assert.equal(observation.result.stderr, 'held-error-stream');
});

registerHeldPs5EnvironmentTest('DBV-008 a missing native file cannot look like a successful probe', { skip: process.platform !== 'win32' && 'Requires actual native Windows PowerShell 5 file refusal.' }, () => {
  const { observation } = executeHeldPs5Environment('missing-file');
  assert.ok(observation.result);
  assert.notEqual(observation.result.exitCode, 0);
  assert.equal(observation.result.stdout.includes('held-json-roundtrip'), false);
});

for (const scenario of ['missing-executable', 'stdout-overflow', 'stderr-overflow']) {
  registerHeldPs5EnvironmentTest(`DBV-008 ${scenario} throws instead of returning a completed-child result`, { skip: process.platform !== 'win32' && 'Requires actual Windows process admission and bounded output.' }, () => {
    const { observation } = executeHeldPs5Environment(scenario);
    assert.equal(observation.refused, true);
    assert.equal(observation.returned, false);
  });
}

registerHeldPs5EnvironmentTest('DBV-008 deadline refusal terminates only its admitted child', { skip: process.platform !== 'win32' && 'Requires actual Windows process lifetime and exact termination.' }, () => {
  const { observation, limits } = executeHeldPs5Environment('timeout');
  assert.equal(observation.refused, true);
  assert.equal(observation.returned, false);
  assert.equal(observation.started, true);
  assert.equal(observation.stopped, true);
  assert.equal(observation.sentinelAlive, true);
  assert.equal(observation.finished, false);
  assert.ok(observation.elapsedMs !== undefined);
  assert.ok(observation.elapsedMs >= limits.processStopGraceMs);
  assert.ok(observation.elapsedMs < limits.processStopGraceMs + limits.nativeCleanupReserveMs);
});
