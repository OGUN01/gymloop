param(
    [string]$ModulePath = 'C:/fr-sealed-20261007/registration-custodian-core.psm1',
    [string]$FixtureRoot = 'C:/fr-sealed-20261007/registration-lease-fixtures',
    [string]$LimitsPath = 'C:/fr-sealed-20261007/watchdog-limits.json'
)

# Independent Windows operational fixtures, derived from DBV-008's frozen
# registration-startup-custody declaration. No network, runner configuration,
# project database, Docker or project test-body access is performed.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = New-Object System.Text.UTF8Encoding($false)
$script:Checks = 0
$script:Groups = New-Object System.Collections.Generic.List[object]
$FixtureRoot = Join-Path $FixtureRoot ('run-' + [guid]::NewGuid().ToString('N'))
$script:ProbePath = Join-Path $FixtureRoot 'RegistrationProbe.exe'
$script:Serial = 0

function Assert-Fixture([bool]$Condition, [string]$Code) {
    $script:Checks++
    if (-not $Condition) { throw ('Fixture assertion: ' + $Code) }
}

function Get-FixtureHash([byte[]]$Bytes) {
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Convert-FixtureBytes($Record) {
    return ,$script:Utf8.GetBytes(($Record | ConvertTo-Json -Depth 20 -Compress))
}

function Write-FixtureBytes([string]$Path, [byte[]]$Bytes) {
    [IO.File]::WriteAllBytes($Path, $Bytes)
}

function Get-OriginalProcess([string]$PidText, [string]$CreationText) {
    try {
        $process = [Diagnostics.Process]::GetProcessById([int]::Parse($PidText))
        if ($process.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -cne $CreationText) { $process.Dispose(); return $null }
        return $process
    } catch { return $null }
}

function Wait-FixtureFile([string]$Path, [int]$BudgetMs = 3000) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($Path) -and $watch.ElapsedMilliseconds -lt $BudgetMs) { [Threading.Thread]::Sleep(20) }
    Assert-Fixture ([IO.File]::Exists($Path)) 'native-marker-present'
}

function Stop-FixtureProcess($Process) {
    if ($null -eq $Process) { return }
    try { if (-not $Process.HasExited) { $Process.Kill(); $Process.WaitForExit(3000) | Out-Null } } finally { $Process.Dispose() }
}

function New-FixtureRunner($State, [string]$Id = '901') {
    return [ordered]@{
        id = $Id; name = $State.Admission.runnerName; os = 'Windows'; status = 'offline'; busy = $false
        labels = @(
            [ordered]@{ name = 'self-hosted'; type = 'read-only' },
            [ordered]@{ name = 'Windows'; type = 'read-only' },
            [ordered]@{ name = 'X64'; type = 'read-only' },
            [ordered]@{ name = $State.Admission.runnerLabel; type = 'custom' }
        )
    }
}

function New-FixtureOwner($State) {
    $owner = [pscustomobject]@{ OwnerJobName = ('fixture-imported-owner-' + $State.Serial) }
    $owner | Add-Member ScriptMethod StartConfig ({ param($Arguments, $BudgetMs)
        $State.Events.Add('config:start')
        $State.StartArguments = @($Arguments)
        $State.StartBudget = $BudgetMs
        $State.ConfigStarted = $true
        if ($State.RowOnStart) { $State.Rows = @($State.RowOnStart) }
        return [ordered]@{ pid = '3001'; creationFileTimeUtc = '133700000000000001'; executablePath = $State.Admission.listenerExecutablePath; ownerJobName = $this.OwnerJobName; assignedBeforeResume = $true; killOnClose = $true }
    }.GetNewClosure())
    $owner | Add-Member ScriptMethod Snapshot ({
        $expired = $State.ConfigStarted -and $State.ConfigNeverExits -and $State.MonotonicMs -ge $State.StartBudget
        return [ordered]@{ activeProcessCount = $(if ($State.Stopped -or -not $State.ConfigNeverExits) { 0 } else { 1 }); processes = @(); configExited = ($State.Stopped -or -not $State.ConfigNeverExits); configExitCode = $(if ($State.ConfigNeverExits -and -not $State.Stopped) { $null } else { $State.ConfigExit }); budgetExpired = $expired }
    }.GetNewClosure())
    $owner | Add-Member ScriptMethod Stop ({ param($GraceMs)
        $State.Events.Add('config:stop'); $State.Stopped = $true
        return [ordered]@{ terminationRequested = $State.ConfigStarted; processesStopped = $true }
    }.GetNewClosure())
    $owner | Add-Member ScriptMethod Dispose ({ $State.Events.Add('config:dispose'); $State.Stopped = $true }.GetNewClosure())
    return $owner
}

function New-FixtureScenario {
    $script:Serial++
    $directory = Join-Path $FixtureRoot ('case-' + $script:Serial)
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    foreach ($name in @('runner', 'work', 'proof', 'ownership')) { New-Item -ItemType Directory -Path (Join-Path $directory $name) -Force | Out-Null }
    $limits = Get-Content -LiteralPath $LimitsPath -Raw | ConvertFrom-Json
    $limits.maxRunnerLifetimeMs = 4000
    $limits.nativeCleanupReserveMs = 1000
    $limits.processStopGraceMs = 200
    $limitsBytes = Convert-FixtureBytes $limits
    $localLimits = Join-Path $directory 'limits.json'
    Write-FixtureBytes $localLimits $limitsBytes
    $launcher = Join-Path $directory 'launcher.ps1'
    $watchdog = Join-Path $directory 'watchdog.ps1'
    Write-FixtureBytes $launcher $script:Utf8.GetBytes('# fixture launcher metadata')
    Write-FixtureBytes $watchdog $script:Utf8.GetBytes('# fixture watchdog metadata')
    $current = [Diagnostics.Process]::GetCurrentProcess()
    $source = '1234567890abcdef1234567890abcdef12345678'
    $admission = [ordered]@{
        formatVersion = 1; sourceSha = $source; runId = '88442'; runAttempt = '1'; repository = 'OGUN01/gymloop'
        runnerName = ('fitcruxx-fixture-' + $script:Serial); runnerLabel = ('fitcruxx-db-win-x64-88442-1-' + $source.Substring(0, 12))
        registrationUtc = '2026-10-07T00:00:00.000Z'; limitsPath = $localLimits; limitsSha256 = (Get-FixtureHash $limitsBytes)
        runnerDirectory = (Join-Path $directory 'runner'); workDirectory = (Join-Path $directory 'work'); proofDirectory = (Join-Path $directory 'proof')
        listenerExecutablePath = $script:ProbePath; listenerExecutableSha256 = (Get-FixtureHash ([IO.File]::ReadAllBytes($script:ProbePath)))
        wrapperProcessId = $current.Id.ToString(); wrapperCreationFileTimeUtc = $current.StartTime.ToUniversalTime().ToFileTimeUtc().ToString()
        launcherPath = $launcher; launcherSha256 = (Get-FixtureHash ([IO.File]::ReadAllBytes($launcher)))
        watchdogPath = $watchdog; watchdogSha256 = (Get-FixtureHash ([IO.File]::ReadAllBytes($watchdog)))
        launchBindingPath = (Join-Path $directory 'launch.json'); ownershipProofDirectory = (Join-Path $directory 'ownership')
    }
    $current.Dispose()
    $admissionBytes = Convert-FixtureBytes $admission
    $state = @{
        Serial = $script:Serial; Directory = $directory; Admission = $admission; AdmissionSha = (Get-FixtureHash $admissionBytes)
        Utc = [datetime]::ParseExact($admission.registrationUtc, 'yyyy-MM-ddTHH:mm:ss.fffZ', [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal).ToUniversalTime()
        MonotonicMs = 0L; Events = (New-Object System.Collections.Generic.List[string]); Receipts = @{}; BaselinePages = @(@()); BaselineTotal = 0
        Rows = @(); Deleted = (New-Object System.Collections.Generic.List[string]); Ready = $false; WrapperAlive = $true; WrapperLossAt = $null
        ConfigStarted = $false; ConfigNeverExits = $false; ConfigExit = 0; RowOnStart = $null; Stopped = $false; StartBudget = 0; StartArguments = @()
        RequestMutation = $null; NoRequest = $false; ListError = $false; GetError = $false; DeleteStatus = 204; DeleteLeavesRow = $false
        LateRowAt = $null; LateRow = $null; ReboundOnGet = $false; Readiness = 'matching-removed'; Handoff = $null; HandoffObserver = $null
        RealOwner = $false; Owner = $null; RealWait = $false; WaitHook = $null; ListenerStopped = $false
    }
    $request = [ordered]@{ formatVersion = 1; admissionSha256 = $state.AdmissionSha; sourceSha = $source; runId = '88442'; runAttempt = '1'; runnerName = $admission.runnerName; runnerLabel = $admission.runnerLabel; registrationToken = 'fixture-token_safe+/='; registrationTokenExpiresAt = '2026-10-07T01:00:00.000Z' }
    $state.Request = $request
    $ports = @{
        Clock = { return [ordered]@{ utc = $state.Utc.ToString('yyyy-MM-ddTHH:mm:ss.fffZ'); monotonicMs = $state.MonotonicMs } }.GetNewClosure()
        Wait = { param($Milliseconds)
            Assert-Fixture ($Milliseconds -is [int] -or $Milliseconds -is [long]) 'wait-integer'
            Assert-Fixture ($Milliseconds -ge 0 -and $Milliseconds -le 4000) 'wait-bounded'
            if ($state.RealWait) { [Threading.Thread]::Sleep([int]$Milliseconds) }
            $state.MonotonicMs += $Milliseconds; $state.Utc = $state.Utc.AddMilliseconds($Milliseconds)
            if ($null -ne $state.WaitHook) { & $state.WaitHook $state }
            if ($state.MonotonicMs -gt 20000) { throw 'Fixture bounded-loop stop.' }
        }.GetNewClosure()
        WrapperAlive = { param($PidText, $CreationText)
            Assert-Fixture ($PidText -ceq $state.Admission.wrapperProcessId -and $CreationText -ceq $state.Admission.wrapperCreationFileTimeUtc) 'original-wrapper-bound'
            if ($null -ne $state.WrapperLossAt -and $state.MonotonicMs -ge $state.WrapperLossAt) { return $false }
            return $state.WrapperAlive
        }.GetNewClosure()
        ListRunners = { param($Page)
            $state.Events.Add('list:' + $Page)
            if ($state.ListError) { throw 'Fixture provider listing error.' }
            if (-not $state.Ready) {
                $items = @(); if ($Page -le $state.BaselinePages.Count) { $items = @($state.BaselinePages[$Page - 1]) }
                return [ordered]@{ totalCount = $state.BaselineTotal; runners = $items }
            }
            if ($null -ne $state.LateRowAt -and $state.MonotonicMs -ge $state.LateRowAt -and $null -ne $state.LateRow) { $state.Rows = @($state.Rows) + @($state.LateRow); $state.LateRow = $null }
            return [ordered]@{ totalCount = $state.Rows.Count; runners = $(if ($Page -eq 1) { @($state.Rows) } else { @() }) }
        }.GetNewClosure()
        GetRunner = { param($Id)
            $state.Events.Add('get:' + $Id)
            if ($state.GetError) { throw 'Fixture provider read error.' }
            $found = @($state.Rows | Where-Object { $_.id -ceq $Id })
            if ($found.Count -eq 0) { return [ordered]@{ status = 404; runner = $null } }
            if ($state.ReboundOnGet) { $found[0].name = 'unrelated-rebound'; $found[0].labels = @([ordered]@{ name = 'Linux'; type = 'read-only' }) }
            return [ordered]@{ status = 200; runner = $found[0] }
        }.GetNewClosure()
        DeleteRunner = { param($Id)
            $state.Events.Add('delete:' + $Id); $state.Deleted.Add($Id)
            if (-not $state.DeleteLeavesRow -and $state.DeleteStatus -eq 204) { $state.Rows = @($state.Rows | Where-Object { $_.id -cne $Id }) }
            return $state.DeleteStatus
        }.GetNewClosure()
        ReadConfigurationRequest = {
            if ($state.NoRequest) { return $null }
            if ($null -ne $state.RequestMutation) { & $state.RequestMutation $state.Request; $state.RequestMutation = $null }
            return ,(Convert-FixtureBytes $state.Request)
        }.GetNewClosure()
        ObserveHandoff = { if ($null -ne $state.HandoffObserver) { return (& $state.HandoffObserver $state) }; return $state.Handoff }.GetNewClosure()
        StopAdmittedListener = { $state.Events.Add('listener:stop'); $state.ListenerStopped = $true; return [ordered]@{ terminationRequested = ($null -ne $state.Handoff -or $null -ne $state.HandoffObserver) } }.GetNewClosure()
        RemoveOwnReadiness = { param($Id, $Sha, $Run, $Attempt)
            $state.Events.Add('readiness:' + $Id)
            Assert-Fixture ($Sha -ceq $state.Admission.sourceSha -and $Run -ceq $state.Admission.runId -and $Attempt -ceq '1') 'readiness-exact-binding'
            return $state.Readiness
        }.GetNewClosure()
        WriteReceipt = { param($Name, $Record)
            Assert-Fixture ($Name -cin @('admission-ready.json', 'admission-final.json')) 'receipt-fixed-name'
            Assert-Fixture (-not $state.Receipts.ContainsKey($Name)) 'receipt-create-new'
            $state.Events.Add('receipt:' + $Name); $state.Receipts[$Name] = $Record
            if ($Name -ceq 'admission-ready.json') { $state.Ready = $true }
        }.GetNewClosure()
        NewOwner = { param($ObservedAdmission)
            Assert-Fixture ($ObservedAdmission.sourceSha -ceq $state.Admission.sourceSha) 'owner-admission-bound'
            if ($state.RealOwner) {
                $owner = New-NativeRegistrationOwner -ExecutablePath $state.Admission.listenerExecutablePath -ExecutableSha256 $state.Admission.listenerExecutableSha256 -WorkingDirectory $state.Admission.workDirectory
                [IO.File]::WriteAllText((Join-Path $state.Admission.workDirectory 'owner-job-name.txt'), $owner.OwnerJobName)
                [IO.File]::WriteAllText((Join-Path $state.Admission.workDirectory 'behavior.txt'), $(if ($state.ConfigExit -ne 0) { 'fail' } else { 'hang' }))
                $state.Owner = $owner; return $owner
            }
            $state.Owner = New-FixtureOwner $state; return $state.Owner
        }.GetNewClosure()
    }
    $state.Ports = $ports
    return $state
}

function Invoke-Fixture($State) {
    $result = Invoke-NativeRegistrationCustodian -Admission $State.Admission -AdmissionSha256 $State.AdmissionSha -Ports $State.Ports
    Assert-Fixture ($State.Receipts.ContainsKey('admission-final.json')) 'final-receipt-present'
    $final = $State.Receipts['admission-final.json']
    Assert-Fixture ((Convert-FixtureBytes $result).Length -eq (Convert-FixtureBytes $final).Length) 'returned-final-shape'
    Assert-Fixture ((Get-FixtureHash (Convert-FixtureBytes $result)) -ceq (Get-FixtureHash (Convert-FixtureBytes $final))) 'returned-exact-final'
    Assert-Fixture ($final.physicalTeardownVerified -ceq $false) 'no-invented-physical-proof'
    $public = $final | ConvertTo-Json -Depth 20 -Compress
    Assert-Fixture (-not $public.Contains('fixture-token')) 'no-token-in-final'
    return $final
}

function Assert-Retired($State, $Final, [string]$Reason) {
    Assert-Fixture ($Final.status -ceq 'RETIRED') 'retired-verdict'
    Assert-Fixture ($Final.stopReason -ceq $Reason) 'retirement-cause'
    Assert-Fixture ($Final.configProcessesStopped -ceq $true -and $Final.runnerDeregistered -ceq $true) 'verified-local-and-remote-retirement'
    Assert-Fixture ($Final.deadlineUtc -ceq '2026-10-07T00:00:04.000Z') 'original-deadline-preserved'
    Assert-Fixture ($State.MonotonicMs -ge 4000) 'late-registration-backstop-retained'
}

function New-HandoffRequest($State, [string]$Id = '901') {
    return [ordered]@{ formatVersion = 1; admissionSha256 = $State.AdmissionSha; sourceSha = $State.Admission.sourceSha; runId = $State.Admission.runId; runAttempt = '1'; runnerId = $Id; runnerName = $State.Admission.runnerName; runnerLabel = $State.Admission.runnerLabel; configSha256 = ('a' * 64); launchBindingPath = $State.Admission.launchBindingPath; launchBindingSha256 = ('b' * 64); ownershipProofDirectory = $State.Admission.ownershipProofDirectory }
}

$probeSource = @'
using System;
using System.IO;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
public static class RegistrationFixtureProbe {
    [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenJobObject(uint access, bool inherit, string name);
    [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool member);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
    public static bool ExactMember(int pid, string name) {
        IntPtr job = OpenJobObject(4, false, name);
        if (job == IntPtr.Zero) return false;
        try { using (Process p = Process.GetProcessById(pid)) { bool member; return IsProcessInJob(p.Handle, job, out member) && member; } }
        catch { return false; } finally { CloseHandle(job); }
    }
    static string Work(string[] args) { for(int i=0;i<args.Length-1;i++) if(args[i]=="--work") return args[i+1]; throw new Exception("Missing fixture work path."); }
    public static int Main(string[] args) {
        string work = Work(args);
        if(Array.IndexOf(args, "--sentinel") >= 0) { File.WriteAllText(Path.Combine(work,"sentinel.txt"),Process.GetCurrentProcess().Id.ToString()); Thread.Sleep(Timeout.Infinite); return 0; }
        bool member = ExactMember(Process.GetCurrentProcess().Id, File.ReadAllText(Path.Combine(work,"owner-job-name.txt")));
        bool child = Array.IndexOf(args,"--child") >= 0;
        using(Process current = Process.GetCurrentProcess()) File.WriteAllText(Path.Combine(work, child?"child-membership.txt":"membership.txt"), member.ToString().ToLowerInvariant()+"|"+current.Id+"|"+current.StartTime.ToUniversalTime().ToFileTimeUtc());
        if(!member) return 73;
        string behavior=File.ReadAllText(Path.Combine(work,"behavior.txt"));
        if(behavior=="fail") return 1;
        if(!child && behavior=="tree") Process.Start(new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--child --work \""+work+"\"") { UseShellExecute=false,CreateNoWindow=true });
        Thread.Sleep(Timeout.Infinite); return 0;
    }
}
'@

function Initialize-NativeProbe {
    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Windows native fixtures required.' }
    if ($PSVersionTable.PSVersion.Major -ne 5) { throw 'Run this manual suite with Windows PowerShell 5.1.' }
    if (-not [IO.File]::Exists($script:ProbePath)) { Add-Type -TypeDefinition $probeSource -OutputAssembly $script:ProbePath -OutputType ConsoleApplication }
    if ($null -eq ('RegistrationFixtureProbe' -as [type])) { Add-Type -Path $script:ProbePath }
}

function New-ProbeOwner([string]$Directory, [string]$Behavior = 'tree') {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $owner = New-NativeRegistrationOwner -ExecutablePath $script:ProbePath -ExecutableSha256 (Get-FixtureHash ([IO.File]::ReadAllBytes($script:ProbePath))) -WorkingDirectory $Directory
    Assert-Fixture (-not [string]::IsNullOrWhiteSpace($owner.OwnerJobName)) 'owner-name-before-first-start'
    [IO.File]::WriteAllText((Join-Path $Directory 'owner-job-name.txt'), $owner.OwnerJobName)
    [IO.File]::WriteAllText((Join-Path $Directory 'behavior.txt'), $Behavior)
    return $owner
}

function Start-Sentinel([string]$Directory) {
    New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $script:ProbePath; $info.Arguments = ('--sentinel --work "' + $Directory + '"'); $info.UseShellExecute = $false; $info.CreateNoWindow = $true
    $sentinel = [Diagnostics.Process]::Start($info)
    Wait-FixtureFile (Join-Path $Directory 'sentinel.txt')
    return $sentinel
}

$testGroups = [ordered]@{
    'startup-refusal-and-complete-pagination' = {
        foreach ($conflict in @('name', 'label')) {
            $s = New-FixtureScenario; $row = New-FixtureRunner $s '100'
            if ($conflict -ceq 'name') { $row.labels = @([ordered]@{ name = 'unrelated'; type = 'custom' }) } else { $row.name = 'unrelated-name' }
            $unrelated = New-FixtureRunner $s '99'; $unrelated.name = 'another-runner'; $unrelated.labels = @([ordered]@{ name = 'Linux'; type = 'read-only' }); $unrelated.os = 'Linux'
            $s.BaselinePages = @(@($unrelated), @($row), @()); $s.BaselineTotal = 2
            $f = Invoke-Fixture $s
            Assert-Fixture ($f.status -ceq 'ADMISSION_REFUSED' -and $f.stopReason -ceq 'BASELINE_CONFLICT') 'name-or-label-baseline-conflict'
            Assert-Fixture (-not $s.ConfigStarted -and $s.Deleted.Count -eq 0 -and -not $s.Ready) 'conflict-before-ready-and-config'
        }
        foreach ($damage in @('count', 'duplicate', 'error')) {
            $s = New-FixtureScenario; $row = New-FixtureRunner $s '99'; $row.name = 'other'; $row.labels = @([ordered]@{ name = 'Linux'; type = 'read-only' })
            $s.BaselinePages = @(@($row), @()); $s.BaselineTotal = 1
            if ($damage -ceq 'count') { $s.BaselineTotal = 2 }; if ($damage -ceq 'duplicate') { $s.BaselinePages = @(@($row), @($row), @()); $s.BaselineTotal = 2 }; if ($damage -ceq 'error') { $s.ListError = $true }
            $f = Invoke-Fixture $s
            Assert-Fixture ($f.stopReason -ceq 'BASELINE_UNVERIFIED' -and -not $s.ConfigStarted -and $s.Deleted.Count -eq 0) 'uncertain-baseline-fails-before-effects'
            Assert-Fixture ($f.runnerDeregistered -ceq $false) 'uncertain-baseline-does-not-prove-absence'
        }
        foreach ($damage in @('expired-token', 'wrong-run', 'token-newline', 'unknown-field')) {
            $s = New-FixtureScenario
            switch ($damage) { 'expired-token' { $s.Request.registrationTokenExpiresAt = $s.Admission.registrationUtc }; 'wrong-run' { $s.Request.runId = '9' }; 'token-newline' { $s.Request.registrationToken = "fixture`ntoken" }; 'unknown-field' { $s.Request.extra = $true } }
            $f = Invoke-Fixture $s
            Assert-Fixture (-not $s.ConfigStarted -and $f.stopReason -ceq 'REQUEST_INVALID') 'invalid-request-cannot-configure'
        }
        $s = New-FixtureScenario; $s.NoRequest = $true; $f = Invoke-Fixture $s
        Assert-Fixture (-not $s.ConfigStarted -and $f.stopReason -ceq 'REQUEST_TIMEOUT') 'request-bounded-without-config'
    }
    'native-first-instruction-tree-timer-and-root-loss' = {
        $directory = Join-Path $FixtureRoot 'native-tree'; $sentinel = Start-Sentinel (Join-Path $FixtureRoot 'sentinel-tree'); $owner = New-ProbeOwner $directory
        try {
            $identity = $owner.StartConfig(@('configure', '--work', $directory), 3000)
            Wait-FixtureFile (Join-Path $directory 'membership.txt'); Wait-FixtureFile (Join-Path $directory 'child-membership.txt')
            Assert-Fixture (([IO.File]::ReadAllText((Join-Path $directory 'membership.txt'))).StartsWith('true|')) 'first-instruction-exact-job-membership'
            Assert-Fixture (([IO.File]::ReadAllText((Join-Path $directory 'child-membership.txt'))).StartsWith('true|')) 'descendant-exact-job-membership'
            Assert-Fixture ($identity.ownerJobName -ceq $owner.OwnerJobName -and $identity.assignedBeforeResume -ceq $true -and $identity.killOnClose -ceq $true) 'native-retained-identity'
            Assert-Fixture (-not [RegistrationFixtureProbe]::ExactMember($sentinel.Id, $owner.OwnerJobName)) 'unrelated-sentinel-outside-exact-job'
            $stop = $owner.Stop(1000); Assert-Fixture ($stop.processesStopped -ceq $true -and $owner.Snapshot().activeProcessCount -eq 0) 'owned-tree-stopped'
            Assert-Fixture (-not $sentinel.HasExited) 'sentinel-preserved-after-stop'
        } finally { $owner.Dispose(); Stop-FixtureProcess $sentinel }
        $timerDir = Join-Path $FixtureRoot 'native-timer'; $owner = New-ProbeOwner $timerDir 'hang'
        try {
            $identity = $owner.StartConfig(@('configure', '--work', $timerDir), 1000)
            Wait-FixtureFile (Join-Path $timerDir 'membership.txt')
            [Threading.Thread]::Sleep(1500)
            $snapshot = $owner.Snapshot()
            Assert-Fixture ($snapshot.budgetExpired -ceq $true -and $snapshot.activeProcessCount -eq 0) 'timer-independent-of-blocked-orchestration'
            Assert-Fixture ($null -eq (Get-OriginalProcess $identity.pid $identity.creationFileTimeUtc)) 'timed-out-original-process-stopped'
        } finally { $owner.Dispose() }
        $rootDir = Join-Path $FixtureRoot 'native-root-loss'; New-Item -ItemType Directory -Path $rootDir -Force | Out-Null
        $helperPath = Join-Path $FixtureRoot 'owned-root-helper.ps1'
        $helper = @'
param($ModulePath,$ProbePath,$WorkDirectory)
$ErrorActionPreference='Stop'
Import-Module -Name $ModulePath -Force
$sha=([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash([IO.File]::ReadAllBytes($ProbePath)))).Replace('-','').ToLowerInvariant()
$owner=New-NativeRegistrationOwner -ExecutablePath $ProbePath -ExecutableSha256 $sha -WorkingDirectory $WorkDirectory
[IO.File]::WriteAllText((Join-Path $WorkDirectory 'owner-job-name.txt'),$owner.OwnerJobName)
[IO.File]::WriteAllText((Join-Path $WorkDirectory 'behavior.txt'),'tree')
$identity=$owner.StartConfig(@('configure','--work',$WorkDirectory),10000)
[IO.File]::WriteAllText((Join-Path $WorkDirectory 'started.json'),($identity|ConvertTo-Json -Compress))
while($true){[Threading.Thread]::Sleep(100)}
'@
        Write-FixtureBytes $helperPath $script:Utf8.GetBytes($helper)
        $info = New-Object Diagnostics.ProcessStartInfo; $info.FileName = 'C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'; $info.UseShellExecute = $false; $info.CreateNoWindow = $true
        $info.Arguments = ('-NoProfile -NonInteractive -File "' + $helperPath + '" -ModulePath "' + $ModulePath + '" -ProbePath "' + $script:ProbePath + '" -WorkDirectory "' + $rootDir + '"')
        $root = [Diagnostics.Process]::Start($info)
        try {
            Wait-FixtureFile (Join-Path $rootDir 'started.json'); Wait-FixtureFile (Join-Path $rootDir 'child-membership.txt')
            $config = [IO.File]::ReadAllText((Join-Path $rootDir 'started.json')) | ConvertFrom-Json
            $child = ([IO.File]::ReadAllText((Join-Path $rootDir 'child-membership.txt'))).Split('|')
            $root.Kill(); $root.WaitForExit(3000) | Out-Null; [Threading.Thread]::Sleep(200)
            Assert-Fixture ($null -eq (Get-OriginalProcess $config.pid $config.creationFileTimeUtc)) 'kernel-kills-config-on-owning-root-loss'
            Assert-Fixture ($null -eq (Get-OriginalProcess $child[1] $child[2])) 'kernel-kills-child-on-owning-root-loss'
        } finally { Stop-FixtureProcess $root }
    }
    'partial-and-late-row-without-local-runner-file' = {
        $s = New-FixtureScenario; $s.ConfigExit = 1; $s.RowOnStart = New-FixtureRunner $s; $f = Invoke-Fixture $s
        Assert-Retired $s $f 'CONFIG_REFUSED'
        Assert-Fixture ($f.learnedRunnerId -ceq '901' -and $s.Deleted.Contains('901')) 'failed-config-api-id-learned-and-removed'
        Assert-Fixture (-not [IO.File]::Exists((Join-Path $s.Admission.runnerDirectory '.runner'))) 'no-local-runner-needed'
        $s = New-FixtureScenario; $s.ConfigNeverExits = $true; $s.LateRowAt = 1800; $s.LateRow = New-FixtureRunner $s '902'; $f = Invoke-Fixture $s
        Assert-Retired $s $f 'CONFIG_TIMEOUT'; Assert-Fixture ($s.Deleted.Contains('902')) 'late-row-after-first-absence-retired'
        Assert-Fixture ($s.StartBudget -eq 1000) 'same-config-budget-path'
        $s = New-FixtureScenario; $s.WrapperLossAt = 100; $s.RowOnStart = New-FixtureRunner $s; $f = Invoke-Fixture $s
        Assert-Retired $s $f 'WRAPPER_LOST'; Assert-Fixture ($s.ListenerStopped) 'wrapper-loss-stops-admitted-listener-capability'
    }
    'exact-discovery-default-labels-and-ambiguity' = {
        foreach ($damage in @('missing-default', 'custom-default', 'new-id-conflict', 'unknown-online', 'unknown-busy', 'ambiguous')) {
            $s = New-FixtureScenario; $s.ConfigExit = 1; $row = New-FixtureRunner $s
            switch ($damage) {
                'missing-default' { $row.labels = @($row.labels | Where-Object { $_.name -cne 'X64' }) }
                'custom-default' { $row.labels[0].type = 'custom' }
                'new-id-conflict' { $row.name = 'somebody-else' }
                'unknown-online' { $row.os = 'unknown'; $row.status = 'online' }
                'unknown-busy' { $row.os = 'unknown'; $row.busy = $true }
                'ambiguous' { $s.Rows = @($row, (New-FixtureRunner $s '902')) }
            }
            if ($damage -cne 'ambiguous') { $s.RowOnStart = $row }
            $f = Invoke-Fixture $s
            Assert-Fixture ($f.status -cne 'RETIRED') 'nonexact-discovery-fails-closed'
            Assert-Fixture ($s.Deleted.Count -eq 0) 'nonexact-or-ambiguous-row-preserved'
        }
        $s = New-FixtureScenario; $s.ConfigExit = 1; $row = New-FixtureRunner $s; $row.os = 'unknown'; $s.RowOnStart = $row
        $f = Invoke-Fixture $s; Assert-Retired $s $f 'CONFIG_REFUSED'; Assert-Fixture ($s.Deleted.Contains('901')) 'unknown-offline-idle-exact-row-retired'
    }
    'live-owned-handoff-wrapper-exit-watchdog-loss-and-deadline' = {
        foreach ($mode in @('valid', 'watchdog-lost', 'dead-listener', 'malformed', 'extended-deadline')) {
            $s = New-FixtureScenario; $s.RowOnStart = New-FixtureRunner $s
            $listenerDir = Join-Path $s.Directory 'listener'; $listener = New-ProbeOwner $listenerDir 'hang'
            $listenerIdentity = $listener.StartConfig(@('run', '--once', '--work', $listenerDir), 10000)
            Wait-FixtureFile (Join-Path $listenerDir 'membership.txt')
            $watchdog = Start-Sentinel (Join-Path $s.Directory 'live-watchdog')
            $request = New-HandoffRequest $s
            $binding = [ordered]@{ sourceSha = $s.Admission.sourceSha; runId = $s.Admission.runId; runAttempt = '1'; runnerId = '901'; configSha256 = $request.configSha256; deadlineUtc = '2026-10-07T00:00:04.000Z'; listenerPid = $listenerIdentity.pid; listenerCreation = $listenerIdentity.creationFileTimeUtc; ownerJobName = $listener.OwnerJobName; watchdogPid = $watchdog.Id.ToString(); watchdogCreation = $watchdog.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() }
            if ($mode -ceq 'extended-deadline') { $binding.deadlineUtc = '2026-10-07T00:00:05.000Z' }
            if ($mode -ceq 'malformed') { $request.extra = $true }
            if ($mode -ceq 'dead-listener') { $listener.Stop(1000) | Out-Null }
            $requestBytes = Convert-FixtureBytes $request
            $s.WrapperLossAt = 500
            $s.HandoffObserver = { param($State)
                if (-not $State.ConfigStarted -or $State.MonotonicMs -lt 100) { return $null }
                $liveListener = Get-OriginalProcess $binding.listenerPid $binding.listenerCreation
                $liveWatchdog = Get-OriginalProcess $binding.watchdogPid $binding.watchdogCreation
                $watchdogAlive = $null -ne $liveWatchdog
                if ($mode -ceq 'watchdog-lost' -and $State.MonotonicMs -ge 700) { $watchdogAlive = $false }
                $verified = $null -ne $liveListener -and [RegistrationFixtureProbe]::ExactMember([int]$binding.listenerPid, $binding.ownerJobName) -and $binding.deadlineUtc -cle '2026-10-07T00:00:04.000Z' -and $watchdogAlive
                if ($null -ne $liveListener) { $liveListener.Dispose() }; if ($null -ne $liveWatchdog) { $liveWatchdog.Dispose() }
                return [ordered]@{ request = $requestBytes; verified = $verified; watchdogAlive = $watchdogAlive; fullJobFinalVerified = $false }
            }.GetNewClosure()
            $s.Ports.StopAdmittedListener = { $s.Events.Add('listener:stop'); $s.ListenerStopped = $true; $result = $listener.Stop(1000); return [ordered]@{ terminationRequested = $result.terminationRequested } }.GetNewClosure()
            try {
                $f = Invoke-Fixture $s
                if ($mode -cin @('valid', 'watchdog-lost')) {
                    Assert-Fixture ($f.handoffAccepted -ceq $true) 'actual-live-owned-handoff-accepted'
                    Assert-Retired $s $f $(if ($mode -ceq 'valid') { 'DEADLINE' } else { 'WATCHDOG_LOST' })
                } else { Assert-Fixture ($f.handoffAccepted -ceq $false) 'invalid-or-dead-handoff-refused' }
                Assert-Fixture ($f.deadlineUtc -ceq '2026-10-07T00:00:04.000Z') 'handoff-cannot-reset-lease'
                Assert-Fixture ($listener.Snapshot().activeProcessCount -eq 0) 'retained-listener-capability-stopped'
            } finally { $listener.Dispose(); Stop-FixtureProcess $watchdog }
        }
    }
    'narrow-stop-delete-absence-readiness-and-api-uncertainty' = {
        $s = New-FixtureScenario; $s.ConfigExit = 1; $s.RowOnStart = New-FixtureRunner $s; $s.Readiness = 'unrelated-preserved'; $f = Invoke-Fixture $s
        Assert-Retired $s $f 'CONFIG_REFUSED'; Assert-Fixture ($f.readinessState -ceq 'unrelated-preserved') 'unrelated-readiness-preserved'
        $events = $s.Events.ToArray()
        $delete = [Array]::IndexOf($events, 'delete:901'); $stop = [Array]::IndexOf($events, 'config:stop')
        Assert-Fixture ($stop -ge 0 -and $delete -gt $stop) 'owned-config-stopped-before-remote-delete'
        Assert-Fixture ($events[$delete - 1] -ceq 'get:901' -and $events[$delete + 1] -ceq 'get:901') 'fresh-identity-before-delete-and-fresh-absence-after'
        foreach ($damage in @('read-error', 'delete-error', 'delete-no-absence', 'rebound')) {
            $s = New-FixtureScenario; $s.ConfigExit = 1; $s.RowOnStart = New-FixtureRunner $s
            switch ($damage) { 'read-error' { $s.GetError = $true }; 'delete-error' { $s.DeleteStatus = 500 }; 'delete-no-absence' { $s.DeleteLeavesRow = $true }; 'rebound' { $s.ReboundOnGet = $true } }
            $f = Invoke-Fixture $s
            Assert-Fixture ($f.status -ceq 'RETIREMENT_UNVERIFIED' -and $f.runnerDeregistered -ceq $false) 'remote-uncertainty-keeps-retirement-failed'
            if ($damage -ceq 'rebound') { Assert-Fixture ($s.Deleted.Count -eq 0) 'rebound-id-never-deleted' }
        }
    }
}

New-Item -ItemType Directory -Path $FixtureRoot -Force | Out-Null
$moduleError = $null
try { Import-Module -Name $ModulePath -Force; Initialize-NativeProbe } catch { $moduleError = $_.Exception.Message }
foreach ($entry in $testGroups.GetEnumerator()) {
    $before = $script:Checks
    try {
        if ($null -ne $moduleError) { throw $moduleError }
        & $entry.Value
        $script:Groups.Add([ordered]@{ group = $entry.Key; passed = $true; assertions = ($script:Checks - $before); diagnostic = $null })
    } catch { $script:Groups.Add([ordered]@{ group = $entry.Key; passed = $false; assertions = ($script:Checks - $before); diagnostic = $_.Exception.Message }) }
}
$report = [ordered]@{ formatVersion = 1; groups = $script:Groups.ToArray(); assertions = $script:Checks }
$reportPath = Join-Path $FixtureRoot 'visible-fixture-private-results.json'
$reportBytes = Convert-FixtureBytes $report
Write-FixtureBytes $reportPath $reportBytes
$passed = @($script:Groups | Where-Object { $_.passed }).Count
$failed = $script:Groups.Count - $passed
$summary = [ordered]@{ groups = $script:Groups.Count; passed = $passed; failed = $failed; assertions = $script:Checks; testSha256 = (Get-FixtureHash ([IO.File]::ReadAllBytes($PSCommandPath))); privateLogSha256 = (Get-FixtureHash $reportBytes) }
$summary | ConvertTo-Json -Compress
if ($failed -gt 0) { exit 1 }
exit 0
