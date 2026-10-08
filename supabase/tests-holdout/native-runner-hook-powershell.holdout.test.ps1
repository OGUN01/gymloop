param([string] $ReceiptPath = '')

$ErrorActionPreference = 'Stop'

function Invoke-HeldPowerShellHookContract {
    $suitePath = $PSCommandPath
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
    $bridgePath = Join-Path $repositoryRoot 'scripts\native-runner-hook.ps1'
    $constantsPath = Join-Path $repositoryRoot 'packages\shared\src\config\constants.ts'
    $approvedHookPath = 'C:\fr-sealed-20261007\hook-headroom-fixture-20261009\hook.mjs'
    $nodePath = 'C:\Program Files\nodejs\node.exe'
    $approvedHookHash = '8C278352E810D39ACA6D4ED2940117D3EFA7F6149CDCB3EA60F86AB1F7671A2B'
    $constants = [IO.File]::ReadAllText($constantsPath)
    $boundMatch = [regex]::Match($constants, 'processStopGraceMs:\s*([\d_]+)')
    $secondMatch = [regex]::Match($constants, 'millisecondsPerSecond:\s*([\d_]+)')
    if (-not $boundMatch.Success -or $boundMatch.Groups[1].Value -cne '10_000' -or -not $secondMatch.Success) {
        throw 'frozen-bound-unavailable'
    }
    $bound = [int] $boundMatch.Groups[1].Value.Replace('_', '')
    $second = [int] $secondMatch.Groups[1].Value.Replace('_', '')
    $tempBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $ownedRoot = Join-Path $tempBase ('gymloop-held-hook-' + [guid]::NewGuid().ToString('N'))
    $ownedMarker = [guid]::NewGuid().ToString('N')
    $null = [IO.Directory]::CreateDirectory($ownedRoot)
    [IO.File]::WriteAllText((Join-Path $ownedRoot 'owned.marker'), $ownedMarker)
    $utf8 = New-Object Text.UTF8Encoding($false)
    $ownedProcesses = New-Object Collections.ArrayList
    $results = New-Object Collections.ArrayList
    $hostResults = New-Object Collections.ArrayList
    $cleanupOkay = $true
    $startedAt = [DateTime]::UtcNow.ToString('o')
    $present = [IO.File]::Exists($bridgePath)
    $bridgeHash = $null
    if ($present) { $bridgeHash = (Get-FileHash -LiteralPath $bridgePath -Algorithm SHA256).Hash }

    $require = {
        param([bool] $Condition, [string] $Code)
        if (-not $Condition) { throw $Code }
    }
    $quoteNative = {
        param([string] $Value)
        '"' + $Value.Replace('"', '\"') + '"'
    }
    $quotePowerShell = {
        param([string] $Value)
        "'" + $Value.Replace("'", "''") + "'"
    }
    $samePath = {
        param([string] $Left, [string] $Right)
        [IO.Path]::IsPathRooted($Left) -and
        [IO.Path]::GetFullPath($Left).Equals([IO.Path]::GetFullPath($Right), [StringComparison]::OrdinalIgnoreCase)
    }
    $startChild = {
        param([string] $Executable, [string] $Arguments, [string] $WorkingDirectory)
        $info = New-Object Diagnostics.ProcessStartInfo
        $info.FileName = $Executable
        $info.Arguments = $Arguments
        $info.WorkingDirectory = $WorkingDirectory
        $info.UseShellExecute = $false
        $info.CreateNoWindow = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $info.EnvironmentVariables['PATH'] = ''
        $process = New-Object Diagnostics.Process
        $process.StartInfo = $info
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $null = $process.Start()
        $null = $process.Handle
        $null = $ownedProcesses.Add($process)
        [pscustomobject]@{
            Process = $process
            OutTask = $process.StandardOutput.ReadToEndAsync()
            ErrorTask = $process.StandardError.ReadToEndAsync()
            Watch = $watch
            LaunchTime = [DateTime]::UtcNow
        }
    }
    $finishChild = {
        param($Child, $Fixture)
        $guardProcess = $null
        $parentObservation = $null
        if ($null -ne $Fixture) {
            while (-not $Child.Process.HasExited -and -not [IO.File]::Exists($Fixture.Record) -and $Child.Watch.ElapsedMilliseconds -lt $bound) {
                $null = $Child.Process.WaitForExit($second)
            }
            if ([IO.File]::Exists($Fixture.Record)) {
                $record = [IO.File]::ReadAllText($Fixture.Record) | ConvertFrom-Json
                & $require ($record.nonce -ceq $Fixture.Nonce) 'controlled-child-custody'
                & $require (& $samePath $record.script $Fixture.Guard) 'controlled-child-custody'
                try {
                    $guardProcess = [Diagnostics.Process]::GetProcessById([int] $record.pid)
                    $null = $guardProcess.Handle
                    & $require (& $samePath $guardProcess.MainModule.FileName $nodePath) 'controlled-child-custody'
                    & $require ($guardProcess.StartTime.ToUniversalTime() -ge $Child.LaunchTime.AddMilliseconds(-$second)) 'controlled-child-custody'
                    $null = $ownedProcesses.Add($guardProcess)
                } catch {
                    if ($Fixture.Mode -eq 'stall') { throw 'owned-guard-observation' }
                    $guardProcess = $null
                }
                if ($Fixture.Mode -eq 'accept') {
                    $parent = Get-CimInstance -ClassName Win32_Process -Filter ('ProcessId=' + [int] $record.parentPid)
                    $parentObservation = [pscustomobject]@{
                        Executable = $parent.ExecutablePath
                        Arguments = @([regex]::Matches($parent.CommandLine, '"[^"]*"|[^\s"]+') | ForEach-Object { $_.Value.Trim('"') })
                    }
                    [IO.File]::WriteAllText($Fixture.Acknowledgment, $Fixture.Nonce, $utf8)
                }
            }
        }
        $remaining = [Math]::Max(1, $bound + $bound - $Child.Watch.ElapsedMilliseconds)
        $timedOut = -not $Child.Process.WaitForExit([int] $remaining)
        if ($timedOut -and -not $Child.Process.HasExited) { $Child.Process.Kill() }
        $null = $Child.Process.WaitForExit($bound)
        $Child.Watch.Stop()
        [pscustomobject]@{
            ExitCode = $Child.Process.ExitCode
            Output = $Child.OutTask.Result + $Child.ErrorTask.Result
            ElapsedMs = $Child.Watch.ElapsedMilliseconds
            FinishTime = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
            TimedOut = $timedOut
            Guard = $guardProcess
            Parent = $parentObservation
        }
    }
    $guardBody = @'
import { appendFileSync, existsSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const bindingPath = process.argv[2];
const fixture = JSON.parse(readFileSync(bindingPath, 'utf8'));
appendFileSync(fixture.invocations, fixture.nonce + '\n');
writeFileSync(fixture.record, JSON.stringify({
  nonce: fixture.nonce, executable: process.execPath,
  script: fileURLToPath(import.meta.url), bindingPath,
  argumentCount: process.argv.length - 2,
  pid: process.pid, parentPid: process.ppid, startedAtMs: Date.now()
}), { flag: 'wx' });
console.log(fixture.privateMarker);
console.error(fixture.privateMarker);
if (fixture.mode === 'accept') {
  const clock = setInterval(() => {
    if (existsSync(fixture.acknowledgment)) {
      clearInterval(clock);
      process.exit(0);
    }
  }, fixture.pollMs);
} else if (fixture.mode === 'stall') {
  setInterval(() => {}, fixture.cap);
} else {
  process.exit(1);
}
'@
    $prepareFixture = {
        param([string] $Directory, [string] $Mode, [bool] $CopyBridge)
        $null = [IO.Directory]::CreateDirectory($Directory)
        $fixture = [pscustomobject]@{
            Directory = $Directory
            Hook = Join-Path $Directory 'hook.mjs'
            Guard = Join-Path $Directory 'guard.mjs'
            Binding = Join-Path $Directory 'binding.json'
            Bridge = Join-Path $Directory 'native-runner-hook.ps1'
            Record = Join-Path $Directory 'guard.record.json'
            Invocations = Join-Path $Directory 'guard.invocations.txt'
            Acknowledgment = Join-Path $Directory 'guard.ack'
            Nonce = [guid]::NewGuid().ToString('N')
            PrivateMarker = 'held-private-' + [guid]::NewGuid().ToString('N')
            Mode = $Mode
        }
        Copy-Item -LiteralPath $approvedHookPath -Destination $fixture.Hook
        & $require ((Get-FileHash -LiteralPath $fixture.Hook -Algorithm SHA256).Hash -ceq $approvedHookHash) 'opaque-fixture-drift'
        if ($CopyBridge) { Copy-Item -LiteralPath $bridgePath -Destination $fixture.Bridge }
        [IO.File]::WriteAllText($fixture.Guard, $guardBody, $utf8)
        [IO.File]::WriteAllText($fixture.Binding, ([ordered]@{
            mode = $Mode
            cap = $bound
            pollMs = $second
            record = $fixture.Record
            invocations = $fixture.Invocations
            acknowledgment = $fixture.Acknowledgment
            nonce = $fixture.Nonce
            privateMarker = $fixture.PrivateMarker
        } | ConvertTo-Json -Compress), $utf8)
        $fixture
    }
    $checkRecord = {
        param($Fixture, $Run, [bool] $ObserveParent)
        & $require ([IO.File]::Exists($Fixture.Record)) 'sibling-argument-custody'
        $record = [IO.File]::ReadAllText($Fixture.Record) | ConvertFrom-Json
        & $require ($record.nonce -ceq $Fixture.Nonce) 'sibling-argument-custody'
        & $require (& $samePath $record.executable $nodePath) 'pinned-node-executable'
        & $require (& $samePath $record.script $Fixture.Guard) 'sibling-argument-custody'
        & $require (& $samePath $record.bindingPath $Fixture.Binding) 'sibling-argument-custody'
        & $require ($record.argumentCount -eq 1) 'sibling-argument-custody'
        & $require (@([IO.File]::ReadAllLines($Fixture.Invocations)).Count -eq 1) 'child-retry-denied'
        if ($ObserveParent) {
            & $require ($null -ne $Run.Parent) 'hook-argument-custody'
            & $require (& $samePath $Run.Parent.Executable $nodePath) 'pinned-node-executable'
            $arguments = $Run.Parent.Arguments
            & $require ($arguments.Count -eq $record.argumentCount + $record.argumentCount + $record.argumentCount + $record.argumentCount) 'hook-argument-custody'
            & $require (& $samePath $arguments[0] $nodePath) 'pinned-node-executable'
            & $require (& $samePath $arguments[1] $Fixture.Hook) 'hook-argument-custody'
            & $require (& $samePath $arguments[2] $Fixture.Guard) 'hook-argument-custody'
            & $require (& $samePath $arguments[3] $Fixture.Binding) 'hook-argument-custody'
        }
        $record
    }
    $invokeHook = {
        param($Fixture, [string] $Executable, [string] $WorkingDirectory, [bool] $NativeReference, [string] $Continuation)
        if ($NativeReference) {
            $arguments = (& $quoteNative $Fixture.Hook) + ' ' + (& $quoteNative $Fixture.Guard) + ' ' + (& $quoteNative $Fixture.Binding)
        } else {
            $command = '. ' + (& $quotePowerShell $Fixture.Bridge)
            if ($Continuation) {
                $command += '; [IO.File]::WriteAllText(' + (& $quotePowerShell $Continuation) + ", 'continued')"
            }
            $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + (& $quoteNative $command)
        }
        $child = & $startChild $Executable $arguments $WorkingDirectory
        & $finishChild $child $Fixture
    }

    try {
        & $require ([IO.File]::Exists($nodePath)) 'pinned-node-unavailable'
        & $require ((Get-FileHash -LiteralPath $approvedHookPath -Algorithm SHA256).Hash -ceq $approvedHookHash) 'approved-hook-drift'
        $hosts = @(
            [pscustomobject]@{ Major = '5'; Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' },
            [pscustomobject]@{ Major = '7'; Path = (Get-Command pwsh.exe -ErrorAction Stop).Source }
        )
        $referenceAccept = & $prepareFixture (Join-Path $ownedRoot 'reference-accept') 'accept' $false
        $referenceAccepted = & $invokeHook $referenceAccept $nodePath $ownedRoot $true ''
        & $require (-not $referenceAccepted.TimedOut -and $referenceAccepted.ExitCode -eq 0) 'opaque-control-refused'
        & $require (-not $referenceAccepted.Output.Contains($referenceAccept.PrivateMarker)) 'opaque-control-output-leak'
        $null = & $checkRecord $referenceAccept $referenceAccepted $true
        $referenceReject = & $prepareFixture (Join-Path $ownedRoot 'reference-reject') 'reject' $false
        $referenceRejected = & $invokeHook $referenceReject $nodePath $ownedRoot $true ''
        & $require (-not $referenceRejected.TimedOut -and $referenceRejected.ExitCode -ne 0) 'opaque-control-accepted-rejection'
        & $require (-not $referenceRejected.Output.Contains($referenceReject.PrivateMarker)) 'opaque-control-output-leak'

        foreach ($hostItem in $hosts) {
            & $require ([IO.File]::Exists($hostItem.Path)) 'powershell-host-unavailable'
            $hostResult = [ordered]@{ major = $hostItem.Major; executed = 0; passed = 0; failed = 0; causes = @(); ownedGuardExitObserved = $false; ownedGuardObservedDurationMs = $null }
            $probe = & $startChild $hostItem.Path '-NoLogo -NoProfile -NonInteractive -Command "$PSVersionTable.PSVersion.Major"' $ownedRoot
            $probeResult = & $finishChild $probe $null
            & $require ($probeResult.ExitCode -eq 0 -and $probeResult.Output.Trim() -ceq $hostItem.Major) 'powershell-host-version'
            if (-not $present) {
                $command = '. ' + (& $quotePowerShell $bridgePath)
                $missing = & $startChild $hostItem.Path ('-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + (& $quoteNative $command)) $ownedRoot
                $missingResult = & $finishChild $missing $null
                $hostResult.executed = 1
                $hostResult.failed = 1
                $hostResult.causes = @('bridge-absent')
                $null = $results.Add([pscustomobject]@{ major = $hostItem.Major; passed = $false; cause = 'bridge-absent'; observedNonzero = $missingResult.ExitCode -ne 0 })
                $null = $hostResults.Add([pscustomobject] $hostResult)
                continue
            }
            foreach ($scenario in @('accept-local', 'accept-foreign-spaces', 'reject', 'missing-binding', 'missing-guard', 'missing-hook', 'stall')) {
                $hostResult.executed++
                $caseDirectory = Join-Path $ownedRoot ($hostItem.Major + '-' + $scenario)
                if ($scenario -eq 'accept-foreign-spaces') { $caseDirectory = Join-Path $caseDirectory "sealed & owner's siblings" }
                $mode = 'reject'
                if ($scenario.StartsWith('accept')) { $mode = 'accept' }
                if ($scenario -eq 'stall') { $mode = 'stall' }
                $fixture = & $prepareFixture $caseDirectory $mode $true
                $currentDirectory = $fixture.Directory
                $continuation = ''
                $sentinel = $null
                try {
                    if ($scenario -eq 'accept-foreign-spaces') {
                        $foreign = & $prepareFixture (Join-Path $ownedRoot ('foreign caller & spaces-' + $hostItem.Major)) 'reject' $false
                        $currentDirectory = $foreign.Directory
                    }
                    if ($mode -ne 'accept') { $continuation = Join-Path $fixture.Directory 'checkout-must-not-continue' }
                    if ($scenario -eq 'missing-binding') { Remove-Item -LiteralPath $fixture.Binding -Force }
                    if ($scenario -eq 'missing-guard') { Remove-Item -LiteralPath $fixture.Guard -Force }
                    if ($scenario -eq 'missing-hook') { Remove-Item -LiteralPath $fixture.Hook -Force }
                    if ($scenario -eq 'stall') {
                        $sentinel = & $startChild $nodePath ('-e "setInterval(() => {}, Number(process.argv[1]))" ' + $bound) $ownedRoot
                    }
                    $run = & $invokeHook $fixture $hostItem.Path $currentDirectory $false $continuation
                    & $require (-not $run.TimedOut) 'bridge-process-bound'
                    & $require (-not $run.Output.Contains($fixture.PrivateMarker)) 'private-output-denial'
                    if ($mode -eq 'accept') {
                        & $require ($run.ExitCode -eq $referenceAccepted.ExitCode) 'acceptance-exit-preservation'
                        & $require ($run.Output -ceq $referenceAccepted.Output) 'generic-acceptance-preservation'
                        $null = & $checkRecord $fixture $run $true
                    } else {
                        & $require ($run.ExitCode -ne 0) 'rejection-exit-preservation'
                        & $require (-not [IO.File]::Exists($continuation)) 'checkout-blocked'
                    }
                    if ($scenario -eq 'accept-foreign-spaces') {
                        & $require (-not [IO.File]::Exists($foreign.Record)) 'caller-directory-isolation'
                    }
                    if ($scenario -eq 'reject' -or $scenario -eq 'stall') {
                        & $require ($run.ExitCode -eq $referenceRejected.ExitCode) 'rejection-exit-preservation'
                        & $require ($run.Output -ceq $referenceRejected.Output) 'generic-rejection-preservation'
                        $record = & $checkRecord $fixture $run $false
                    }
                    if ($scenario -eq 'stall') {
                        & $require ($null -ne $run.Guard -and $run.Guard.HasExited) 'exact-owned-guard-cleanup'
                        & $require (-not $sentinel.Process.HasExited) 'unrelated-child-preserved'
                        $guardExitTimeMs = ([DateTimeOffset] $run.Guard.ExitTime.ToUniversalTime()).ToUnixTimeMilliseconds()
                        $hostResult.ownedGuardExitObserved = $true
                        $hostResult.ownedGuardObservedDurationMs = $guardExitTimeMs - $record.startedAtMs
                        & $require ($guardExitTimeMs - $record.startedAtMs -le $bound + $second) 'original-child-bound'
                    }
                    $hostResult.passed++
                    $null = $results.Add([pscustomobject]@{ major = $hostItem.Major; passed = $true; cause = $null })
                } catch {
                    $cause = $_.Exception.Message
                    if ($cause -notmatch '^[a-z]+(?:-[a-z]+)*$') { $cause = 'controlled-runtime-failure' }
                    $hostResult.failed++
                    $hostResult.causes += $cause
                    $null = $results.Add([pscustomobject]@{ major = $hostItem.Major; passed = $false; cause = $cause })
                } finally {
                    if ($null -ne $sentinel -and -not $sentinel.Process.HasExited) {
                        $sentinel.Process.Kill()
                        $null = $sentinel.Process.WaitForExit($bound)
                    }
                }
            }
            $null = $hostResults.Add([pscustomobject] $hostResult)
        }
    } catch {
        $cause = $_.Exception.Message
        if ($cause -notmatch '^[a-z]+(?:-[a-z]+)*$') { $cause = 'controlled-runtime-failure' }
        $null = $results.Add([pscustomobject]@{ major = 'control'; passed = $false; cause = $cause })
    } finally {
        foreach ($process in $ownedProcesses) {
            try {
                if (-not $process.HasExited) {
                    $process.Kill()
                    $null = $process.WaitForExit($bound)
                }
                if (-not $process.HasExited) { $cleanupOkay = $false }
                $process.Dispose()
            } catch { $cleanupOkay = $false }
        }
        try {
            $resolvedRoot = [IO.Path]::GetFullPath($ownedRoot)
            $prefix = $tempBase.TrimEnd('\') + '\'
            if (-not $resolvedRoot.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                [IO.File]::ReadAllText((Join-Path $resolvedRoot 'owned.marker')) -cne $ownedMarker) {
                throw 'scratch-ownership'
            }
            Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
        } catch { $cleanupOkay = $false }
    }
    $failed = @($results | Where-Object { -not $_.passed }).Count
    $passed = @($results | Where-Object { $_.passed }).Count
    if (-not $cleanupOkay) { $failed++ }
    [ordered]@{
        schema = 'gymloop-held-powershell-hook-receipt-v1'
        suiteSha256 = (Get-FileHash -LiteralPath $suitePath -Algorithm SHA256).Hash
        approvedOpaqueHookSha256 = $approvedHookHash
        bridgePresent = $present
        bridgeSha256 = $bridgeHash
        constantsSha256 = (Get-FileHash -LiteralPath $constantsPath -Algorithm SHA256).Hash
        originalChildBoundMs = $bound
        timingBoundary = 'controlled-guard-start-to-kernel-exit'
        planned = @('accept-local', 'accept-foreign-spaces', 'reject', 'missing-binding', 'missing-guard', 'missing-hook', 'stall').Count * @('5', '7').Count
        executed = $results.Count
        passed = $passed
        failed = $failed
        hosts = @($hostResults)
        causes = @($results | Where-Object { -not $_.passed } | ForEach-Object { $_.cause } | Select-Object -Unique)
        ownedCleanup = $cleanupOkay
        beganUtc = $startedAt
        finishedUtc = [DateTime]::UtcNow.ToString('o')
    }
}

try {
    $receipt = Invoke-HeldPowerShellHookContract
    if (-not $ReceiptPath) { $ReceiptPath = Join-Path ([IO.Path]::GetTempPath()) ('gymloop-held-hook-receipt-' + [guid]::NewGuid().ToString('N') + '.json') }
    $receiptJson = $receipt | ConvertTo-Json -Depth 10 -Compress
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ReceiptPath), $receiptJson, (New-Object Text.UTF8Encoding($false)))
    Write-Output $receiptJson
    Write-Output ('receipt=' + [IO.Path]::GetFullPath($ReceiptPath))
    if ($receipt.failed -ne 0) { exit 1 }
    exit 0
} catch {
    Write-Output '{"failed":1,"causes":["held-control-startup-failure"]}'
    exit 1
}
