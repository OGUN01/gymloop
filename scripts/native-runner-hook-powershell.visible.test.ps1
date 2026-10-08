param(
    [string]$CandidatePath = (Join-Path $PSScriptRoot 'native-runner-hook.ps1'),
    [string]$OpaqueHookPath = 'C:/fr-sealed-20261007/hook.mjs',
    [string]$LimitsPath = 'C:/fr-sealed-20261007/watchdog-limits.json',
    [string]$ReceiptRoot = (Join-Path ([IO.Path]::GetTempPath()) 'gymloop Windows prejob visible')
)

# Independent visible operational tests from the frozen PUBLIC Windows pre-job
# compatibility contract. Candidate and approved hook are copied as opaque bytes.
# No bridge body, held test, production binding, credential, DB or provider read.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
    Write-Output 'WINDOWS_PREJOB_VISIBLE_SKIP WINDOWS_ONLY'
    exit 0
}

$script:Checks = 0
$script:Failures = [Collections.Generic.List[object]]::new()
$script:Results = [Collections.Generic.List[object]]::new()
$script:Owned = [Collections.Generic.List[Diagnostics.Process]]::new()
$script:Utf8 = [Text.UTF8Encoding]::new($false)
$script:NativeNode = 'C:/Program Files/nodejs/node.exe'
$script:Limits = [IO.File]::ReadAllText($LimitsPath) | ConvertFrom-Json
$script:Acceptance = 'Native runner binding accepted.'
$script:Refusal = 'Native runner binding refused: RUNNER_UNTRUSTED.'
$script:ReceiptDirectory = Join-Path $ReceiptRoot ('run ' + [guid]::NewGuid().ToString('N'))
$script:CaseDirectory = Join-Path $script:ReceiptDirectory "sealed siblings with spaces and 'quotes'"
$script:CallerDirectory = Join-Path $script:ReceiptDirectory 'unrelated current directory'
$script:Secret = 'VISIBLE_PRIVATE_' + [guid]::NewGuid().ToString('N')
$script:OpaqueHookHash = (Get-FileHash -LiteralPath $OpaqueHookPath -Algorithm SHA256).Hash.ToLowerInvariant()
$script:CandidateExists = [IO.File]::Exists($CandidatePath)
$script:CandidateHash = if ($script:CandidateExists) { (Get-FileHash -LiteralPath $CandidatePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
$script:Hosts = @(
    [ordered]@{ name = 'WindowsPowerShell5'; path = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' },
    [ordered]@{ name = 'PowerShell7'; path = (Get-Command pwsh.exe -CommandType Application).Source }
)

function Assert-VisiblePrejob([bool]$Condition, [string]$Code) {
    $script:Checks++
    if (-not $Condition) { throw ('VISIBLE_ASSERTION_' + $Code) }
}

function Protect-VisiblePrejobDirectory([string]$Path) {
    [IO.Directory]::CreateDirectory($Path) | Out-Null
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $acl.SetOwner($owner)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($owner, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'), [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new($sid, [Security.AccessControl.FileSystemRights]::FullControl,
            ([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),
            [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    $directory = [IO.DirectoryInfo]::new($Path)
    if ($null -ne $directory.PSObject.Methods['SetAccessControl']) { $directory.SetAccessControl($acl) }
    else { [IO.FileSystemAclExtensions]::SetAccessControl($directory, $acl) }
    $sections = [Security.AccessControl.AccessControlSections]::Access -bor [Security.AccessControl.AccessControlSections]::Owner -bor [Security.AccessControl.AccessControlSections]::Group
    $observed = if ($null -ne $directory.PSObject.Methods['GetAccessControl']) { $directory.GetAccessControl($sections) }
                else { [IO.FileSystemAclExtensions]::GetAccessControl($directory, $sections) }
    Assert-VisiblePrejob $observed.AreAccessRulesProtected 'PRIVATE_ACL_PROTECTED'
    Assert-VisiblePrejob ($observed.GetOwner([Security.Principal.SecurityIdentifier]).Value -ceq $owner.Value) 'PRIVATE_ACL_OWNER'
    $allowed = @($owner.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($rule in $observed.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        Assert-VisiblePrejob (($allowed -ccontains $rule.IdentityReference.Value) -and
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $rule.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl) 'PRIVATE_ACL_TRUSTED_ONLY'
    }
}

function Write-VisiblePrejobFile([string]$Path, [string]$Text) {
    [IO.File]::WriteAllText($Path, $Text, $script:Utf8)
}

function Quote-VisiblePrejobArgument([string]$Value) {
    # Windows CRT quoting for actual ProcessStartInfo argv, including apostrophes
    # in the PowerShell command text and spaces in executable/script paths.
    return '"' + ([regex]::Replace(([regex]::Replace($Value, '(\\*)"', '$1$1\"')), '(\\+)$', '$1$1')) + '"'
}

function Stop-VisiblePrejobOwnedProcess([Diagnostics.Process]$Process) {
    if ($null -eq $Process) { return }
    try {
        if (-not $Process.HasExited) {
            $Process.Kill()
            Assert-VisiblePrejob ($Process.WaitForExit($script:Limits.processStopGraceMs)) 'EXACT_OWNED_CLEANUP'
        }
    } finally { $Process.Dispose() }
}

function Invoke-VisiblePrejobHost($HostRecord, [string]$BridgePath, [string]$GuardMarker, [bool]$ObserveStall = $false) {
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = $HostRecord.path
    # Exact documented pre-job execution form: -command ". '{pathtofile}'".
    $dotSource = ". '" + $BridgePath.Replace("'", "''") + "'"
    $start.Arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command ' + (Quote-VisiblePrejobArgument $dotSource)
    $start.WorkingDirectory = $script:CallerDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    # A caller PATH decoy must not replace the contract's fixed native Node.
    $start.EnvironmentVariables['PATH'] = $script:CallerDirectory
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $guard = $null
    $startedUtc = [DateTime]::UtcNow
    $clock = [Diagnostics.Stopwatch]::StartNew()
    try {
        Assert-VisiblePrejob ($process.Start()) 'HOST_STARTS'
        $script:Owned.Add($process)
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if ($ObserveStall) {
            while (-not [IO.File]::Exists($GuardMarker) -and -not $process.HasExited -and $clock.ElapsedMilliseconds -lt $script:Limits.processStopGraceMs) {
                [Threading.Thread]::Sleep($script:Limits.millisecondsPerSecond)
            }
            if ([IO.File]::Exists($GuardMarker)) {
                $identity = [IO.File]::ReadAllText($GuardMarker) | ConvertFrom-Json
                $guard = [Diagnostics.Process]::GetProcessById([int]$identity.pid)
                $script:Owned.Add($guard)
                Assert-VisiblePrejob (-not $guard.HasExited) 'STALL_GUARD_ACTUALLY_LIVE'
                Assert-VisiblePrejob ($guard.StartTime.ToUniversalTime() -ge $startedUtc) 'STALL_GUARD_CREATED_THIS_CALL'
                Assert-VisiblePrejob ([IO.Path]::GetFullPath($guard.MainModule.FileName) -ieq [IO.Path]::GetFullPath($script:NativeNode)) 'STALL_GUARD_NATIVE_NODE'
            }
        }
        $remaining = [Math]::Max(0, $script:Limits.nativeCleanupReserveMs - $clock.ElapsedMilliseconds)
        Assert-VisiblePrejob ($process.WaitForExit([int]$remaining)) 'HOST_FINITE_COMPLETION'
        $process.WaitForExit()
        Assert-VisiblePrejob ($stdoutTask.Wait($script:Limits.processStopGraceMs)) 'STDOUT_FINITE_COMPLETION'
        Assert-VisiblePrejob ($stderrTask.Wait($script:Limits.processStopGraceMs)) 'STDERR_FINITE_COMPLETION'
        $result = [ordered]@{
            exitCode = $process.ExitCode; stdout = $stdoutTask.Result; stderr = $stderrTask.Result
            elapsedMs = $clock.ElapsedMilliseconds; guardObserved = ($null -ne $guard)
            guardExited = $false; guardLifetimeMs = $null
        }
        if ($null -ne $guard) {
            Assert-VisiblePrejob ($guard.WaitForExit($script:Limits.processStopGraceMs)) 'STALL_GUARD_TERMINATED'
            $result.guardExited = $guard.HasExited
            $result.guardLifetimeMs = ($guard.ExitTime.ToUniversalTime() - $guard.StartTime.ToUniversalTime()).TotalMilliseconds
        }
        return $result
    } finally {
        # Only retained handles to this suite's exact created/observed processes.
        if ($null -ne $guard) { Stop-VisiblePrejobOwnedProcess $guard; $script:Owned.Remove($guard) | Out-Null }
        Stop-VisiblePrejobOwnedProcess $process
        $script:Owned.Remove($process) | Out-Null
    }
}

function New-VisiblePrejobCase([string]$Name, [string]$Mode) {
    $directory = Join-Path $script:CaseDirectory $Name
    Protect-VisiblePrejobDirectory $directory
    $bridge = Join-Path $directory 'hook.ps1'
    if ($script:CandidateExists) {
        [IO.File]::Copy($CandidatePath, $bridge, $false)
        Assert-VisiblePrejob ((Get-FileHash -LiteralPath $bridge -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $script:CandidateHash) 'CANDIDATE_COPY_IDENTITY'
    }
    $binding = Join-Path $directory 'binding.json'
    Write-VisiblePrejobFile $binding (([ordered]@{ sentinel = $script:Secret; mode = $Mode }) | ConvertTo-Json -Compress)
    $guard = Join-Path $directory 'guard.mjs'
    $marker = Join-Path $directory 'guard-observation.json'
    $guardSource = @'
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
const here = (name) => fileURLToPath(new URL(name, import.meta.url));
writeFileSync(here('guard-observation.json'), JSON.stringify({pid: process.pid, argv: process.argv, execPath: process.execPath}));
const binding = JSON.parse(readFileSync(process.argv[2], 'utf8'));
process.stdout.write(binding.sentinel + '\n');
process.stderr.write(binding.sentinel + '\n');
if (binding.mode === 'stall') {
  const limits = JSON.parse(readFileSync(here('limits.json'), 'utf8'));
  setInterval(() => {}, limits.processStopGraceMs);
} else {
  process.exit(binding.mode === 'reject' ? 1 : 0);
}
'@
    Write-VisiblePrejobFile $guard $guardSource
    [IO.File]::Copy($LimitsPath, (Join-Path $directory 'limits.json'), $false)
    $hook = Join-Path $directory 'hook.mjs'
    if ($Mode -eq 'argv') {
        $hookSource = @'
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
writeFileSync(fileURLToPath(new URL('argv-observation.json', import.meta.url)), JSON.stringify({argv: process.argv, execPath: process.execPath}));
process.stdout.write('Native runner binding accepted.\n');
process.exit(0);
'@
        Write-VisiblePrejobFile $hook $hookSource
    } else {
        [IO.File]::Copy($OpaqueHookPath, $hook, $false)
        Assert-VisiblePrejob ((Get-FileHash -LiteralPath $hook -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $script:OpaqueHookHash) 'OPAQUE_HOOK_COPY_IDENTITY'
    }
    if ($Mode -eq 'missing-guard') { [IO.File]::Delete($guard) }
    if ($Mode -eq 'missing-binding') { [IO.File]::Delete($binding) }
    if ($Mode -eq 'missing-hook') { [IO.File]::Delete($hook) }
    return [ordered]@{ directory = $directory; bridge = $bridge; hook = $hook; guard = $guard; binding = $binding; marker = $marker }
}

function Test-VisiblePrejobCase($HostRecord, [string]$Mode) {
    $name = $HostRecord.name + '-' + $Mode
    $before = $script:Checks
    $case = $null
    $result = $null
    $survivor = $null
    $failure = $null
    try {
        $case = New-VisiblePrejobCase $name $Mode
        if ($Mode -eq 'stall') {
            $survivorStart = [Diagnostics.ProcessStartInfo]::new()
            $survivorStart.FileName = $script:NativeNode
            $survivorStart.Arguments = (Quote-VisiblePrejobArgument $case.guard) + ' ' + (Quote-VisiblePrejobArgument $case.binding)
            $survivorStart.WorkingDirectory = $script:CallerDirectory
            $survivorStart.UseShellExecute = $false
            $survivorStart.CreateNoWindow = $true
            $survivorStart.RedirectStandardOutput = $true
            $survivorStart.RedirectStandardError = $true
            # An unrelated exact same-executable live fixture in a separate root.
            $survivorDirectory = Join-Path $script:CaseDirectory 'unrelated survivor'
            Protect-VisiblePrejobDirectory $survivorDirectory
            [IO.File]::Copy($case.guard, (Join-Path $survivorDirectory 'guard.mjs'), $false)
            [IO.File]::Copy($case.binding, (Join-Path $survivorDirectory 'binding.json'), $false)
            [IO.File]::Copy($LimitsPath, (Join-Path $survivorDirectory 'limits.json'), $false)
            $survivorStart.Arguments = (Quote-VisiblePrejobArgument (Join-Path $survivorDirectory 'guard.mjs')) + ' ' + (Quote-VisiblePrejobArgument (Join-Path $survivorDirectory 'binding.json'))
            $survivor = [Diagnostics.Process]::new()
            $survivor.StartInfo = $survivorStart
            Assert-VisiblePrejob ($survivor.Start()) 'UNRELATED_STARTS'
            $script:Owned.Add($survivor)
            $survivor.StandardOutput.ReadToEndAsync() | Out-Null
            $survivor.StandardError.ReadToEndAsync() | Out-Null
        }
        $result = Invoke-VisiblePrejobHost $HostRecord $case.bridge $case.marker ($Mode -eq 'stall')
        $successful = $Mode -in @('argv', 'success')
        if ($successful) {
            Assert-VisiblePrejob ($result.exitCode -eq 0) 'SUCCESS_EXIT_ZERO'
            Assert-VisiblePrejob ($result.stdout.TrimEnd("`r", "`n") -ceq $script:Acceptance) 'SUCCESS_ONLY_GENERIC_ACCEPTANCE'
            Assert-VisiblePrejob ([string]::IsNullOrEmpty($result.stderr)) 'SUCCESS_NO_RAW_STDERR'
        } else {
            Assert-VisiblePrejob ($result.exitCode -ne 0) 'REFUSAL_EXIT_NONZERO'
            Assert-VisiblePrejob ([string]::IsNullOrEmpty($result.stdout)) 'REFUSAL_NO_RAW_STDOUT'
            Assert-VisiblePrejob ($result.stderr.TrimEnd("`r", "`n") -ceq $script:Refusal) 'REFUSAL_ONLY_GENERIC_MESSAGE'
        }
        Assert-VisiblePrejob (-not ($result.stdout + $result.stderr).Contains($script:Secret)) 'NO_PRIVATE_SENTINEL'
        Assert-VisiblePrejob (-not ($result.stdout + $result.stderr).Contains($case.directory)) 'NO_PRIVATE_FIXTURE_PATH'
        Assert-VisiblePrejob (-not [IO.File]::Exists((Join-Path $script:CallerDirectory 'fallback-used.txt'))) 'NO_PATH_NODE_FALLBACK'
        if ($Mode -eq 'argv') {
            $observed = [IO.File]::ReadAllText((Join-Path $case.directory 'argv-observation.json')) | ConvertFrom-Json
            $expected = @([IO.Path]::GetFullPath($script:NativeNode), [IO.Path]::GetFullPath($case.hook), [IO.Path]::GetFullPath($case.guard), [IO.Path]::GetFullPath($case.binding))
            Assert-VisiblePrejob ($observed.argv.Count -eq $expected.Count) 'EXACT_HOOK_ARGV_COUNT'
            Assert-VisiblePrejob ([IO.Path]::GetFullPath($observed.execPath) -ieq $expected[0]) 'PINNED_NODE_EXECUTABLE'
            foreach ($index in 0..($expected.Count - 1)) {
                Assert-VisiblePrejob ([IO.Path]::IsPathRooted($observed.argv[$index])) 'ABSOLUTE_HOOK_ARGUMENT'
                Assert-VisiblePrejob ([IO.Path]::GetFullPath($observed.argv[$index]) -ceq $expected[$index]) 'EXACT_HOOK_ARGV_ORDER'
            }
        }
        if ($Mode -in @('success', 'reject', 'missing-binding', 'stall')) {
            $observed = [IO.File]::ReadAllText($case.marker) | ConvertFrom-Json
            $expected = @([IO.Path]::GetFullPath($script:NativeNode), [IO.Path]::GetFullPath($case.guard), [IO.Path]::GetFullPath($case.binding))
            Assert-VisiblePrejob ($observed.argv.Count -eq $expected.Count) 'EXACT_GUARD_ARGV_COUNT'
            foreach ($index in 0..($expected.Count - 1)) {
                Assert-VisiblePrejob ([IO.Path]::GetFullPath($observed.argv[$index]) -ceq $expected[$index]) 'EXACT_GUARD_ARGV_ORDER'
            }
        }
        if ($Mode -eq 'stall') {
            Assert-VisiblePrejob $result.guardObserved 'STALL_CHILD_MARKER_OBSERVED'
            Assert-VisiblePrejob $result.guardExited 'STALL_EXACT_CHILD_EXITED'
            Assert-VisiblePrejob ($result.guardLifetimeMs -gt 0 -and $result.guardLifetimeMs -le $script:Limits.processStopGraceMs) 'ORIGINAL_TEN_SECOND_CHILD_CAP'
            Assert-VisiblePrejob (-not $survivor.HasExited) 'UNRELATED_SAME_EXECUTABLE_SURVIVES'
            Assert-VisiblePrejob ([IO.File]::Exists((Join-Path $survivorDirectory 'guard-observation.json'))) 'UNRELATED_ACTUALLY_ENTERED'
        }
    } catch {
        $text = $_.Exception.Message
        $failure = if ($text.StartsWith('VISIBLE_ASSERTION_', [StringComparison]::Ordinal)) { $text } else { 'VISIBLE_FIXTURE_FAILURE' }
        $script:Failures.Add([ordered]@{ host = $HostRecord.name; case = $Mode; code = $failure })
    } finally {
        if ($null -ne $survivor) { Stop-VisiblePrejobOwnedProcess $survivor; $script:Owned.Remove($survivor) | Out-Null }
        $script:Results.Add([ordered]@{
            host = $HostRecord.name; case = $Mode; passed = ($null -eq $failure); checks = ($script:Checks - $before)
            exitCode = if ($null -ne $result) { $result.exitCode } else { $null }
            elapsedMs = if ($null -ne $result) { $result.elapsedMs } else { $null }
            genericOutput = if ($null -ne $result) {
                (($result.stdout.TrimEnd("`r", "`n") -ceq $script:Acceptance) -and [string]::IsNullOrEmpty($result.stderr)) -or
                ([string]::IsNullOrEmpty($result.stdout) -and ($result.stderr.TrimEnd("`r", "`n") -ceq $script:Refusal))
            } else { $false }
            guardLifetimeMs = if ($null -ne $result) { $result.guardLifetimeMs } else { $null }
        })
        Write-Output ('WINDOWS_PREJOB_VISIBLE_CASE ' + $name + ' ' + $(if ($null -eq $failure) { 'PASS' } else { $failure }))
    }
}

$suiteFailure = $null
try {
    Protect-VisiblePrejobDirectory $ReceiptRoot
    Protect-VisiblePrejobDirectory $script:ReceiptDirectory
    Protect-VisiblePrejobDirectory $script:CaseDirectory
    Protect-VisiblePrejobDirectory $script:CallerDirectory
    Write-VisiblePrejobFile (Join-Path $script:CallerDirectory 'node.cmd') '@echo off
echo PATH_FALLBACK>fallback-used.txt
exit /b 1
'
    Write-VisiblePrejobFile (Join-Path $script:CallerDirectory 'hook.mjs') 'throw new Error("CALLER_HOOK_MUST_NOT_RUN");'
    Write-VisiblePrejobFile (Join-Path $script:CallerDirectory 'guard.mjs') 'throw new Error("CALLER_GUARD_MUST_NOT_RUN");'
    Write-VisiblePrejobFile (Join-Path $script:CallerDirectory 'binding.json') '{}'
    foreach ($hostRecord in $script:Hosts) {
        Assert-VisiblePrejob ([IO.File]::Exists($hostRecord.path)) 'REQUIRED_NATIVE_POWERSHELL_HOST_EXISTS'
        foreach ($mode in @('argv', 'success', 'reject', 'missing-guard', 'missing-binding', 'missing-hook')) { Test-VisiblePrejobCase $hostRecord $mode }
    }
    # One real ten-second stall; both hosts already exercised success/refusal.
    Test-VisiblePrejobCase $script:Hosts[-1] 'stall'
} catch {
    $suiteFailure = 'VISIBLE_SETUP_FAILURE'
    $script:Failures.Add([ordered]@{ host = 'suite'; case = 'setup'; code = $suiteFailure })
} finally {
    foreach ($process in @($script:Owned.ToArray())) { Stop-VisiblePrejobOwnedProcess $process; $script:Owned.Remove($process) | Out-Null }
    $receipt = [ordered]@{
        suite = 'windows-prejob-powershell-visible'; candidatePresent = $script:CandidateExists; candidateSha256 = $script:CandidateHash
        opaqueHookSha256 = $script:OpaqueHookHash; originalChildCapMs = $script:Limits.processStopGraceMs
        checks = $script:Checks; groups = $script:Results.Count
        passed = @($script:Results | Where-Object { $_.passed }).Count; failed = $script:Failures.Count; skipped = 0
        exactOwnedSurvivors = $script:Owned.Count; results = $script:Results.ToArray(); failures = $script:Failures.ToArray()
        exitCode = if ($script:Failures.Count -eq 0) { 0 } else { 1 }
    }
    if ([IO.Directory]::Exists($script:ReceiptDirectory)) {
        Write-VisiblePrejobFile (Join-Path $script:ReceiptDirectory 'safe-receipt.json') ($receipt | ConvertTo-Json -Depth $script:Limits.digestHexLength -Compress)
    }
    Write-Output ('WINDOWS_PREJOB_VISIBLE_RESULT groups=' + $receipt.groups + ' passed=' + $receipt.passed + ' failed=' + $receipt.failed + ' checks=' + $receipt.checks + ' survivors=' + $receipt.exactOwnedSurvivors)
    Write-Output ('WINDOWS_PREJOB_VISIBLE_RECEIPT ' + (Join-Path $script:ReceiptDirectory 'safe-receipt.json'))
}
if ($script:Failures.Count -ne 0) { exit 1 }
exit 0
