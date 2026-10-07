param([string]$ModulePath = 'C:/fr-sealed-20261007/registration-custodian-core.psm1')
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$heldRoot = 'C:/fr-sealed-20261007/registration-lease-held'
$executionRoot = Join-Path $heldRoot ([guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $executionRoot | Out-Null
$logPath = Join-Path $executionRoot 'held-result.log'
$checks = [System.Collections.Generic.List[object]]::new()
$children = [System.Collections.Generic.List[System.Diagnostics.Process]]::new()
$owners = [System.Collections.Generic.List[object]]::new()
function Check([string]$name,[scriptblock]$body) {
    try { & $body; $checks.Add(@{name=$name;passed=$true}) }
    catch { $checks.Add(@{name=$name;passed=$false}); [IO.File]::AppendAllText($logPath,($name + ': ' + $_.Exception.Message + [Environment]::NewLine)) }
}
function Require($condition,[string]$message) { if ($condition -ne $true) { throw $message } }
function Sha([string]$path) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Bytes($record) { [Text.Encoding]::UTF8.GetBytes(($record | ConvertTo-Json -Depth 20 -Compress)) }
function CanonicalUtc([datetime]$value) { $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') }
function WaitFile([string]$path,[int]$limit=3000) {
    $watch=[Diagnostics.Stopwatch]::StartNew()
    while (-not [IO.File]::Exists($path)) { if ($watch.ElapsedMilliseconds -gt $limit) { throw 'Controlled probe did not reach its observation.' }; Start-Sleep -Milliseconds 10 }
}
function IsOriginalAlive([string]$pidText,[string]$createdText) {
    try { $p=[Diagnostics.Process]::GetProcessById([int]$pidText); $same=($p.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -ceq $createdText); $p.Dispose(); return $same } catch { return $false }
}
function ReadProbe([string]$path) {
    $probeWait=[Diagnostics.Stopwatch]::StartNew(); WaitFile $path
    while($true){
        try { return ([IO.File]::ReadAllText($path)).Split('|') }
        catch [IO.IOException] { if($probeWait.ElapsedMilliseconds -ge 3000){throw}; Start-Sleep -Milliseconds 10 }
    }
}
function StopOwner($owner) { if ($null -ne $owner) { try { $null=$owner.Stop(1000) } catch {}; try { $owner.Dispose() } catch {} } }
$probeSource=@'
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
public static class LeaseHeldProbe {
 [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr OpenJobObject(uint access,bool inherit,string name);
 [DllImport("kernel32.dll", SetLastError=true)] static extern bool IsProcessInJob(IntPtr process,IntPtr job,out bool value);
 [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr value);
 static string Quote(string value) { return "\"" + value.Replace("\"","\\\"") + "\""; }
 public static int Main(string[] args) {
  string dir=Environment.CurrentDirectory;
  if(args.Length>0 && args[0]=="--sentinel") { File.WriteAllText(args[1],Process.GetCurrentProcess().Id.ToString()); Thread.Sleep(60000); return 0; }
  bool direct=args.Length>0 && args[0]=="--probe";
  string job=direct?args[1]:File.ReadAllText(Path.Combine(dir,"job-name.txt"));
  string marker=direct?args[2]:Path.Combine(dir,"config.marker");
  string mode=direct?args[3]:File.ReadAllText(Path.Combine(dir,"mode.txt"));
  IntPtr handle=OpenJobObject(4,false,job); bool member=false;
  bool query=handle!=IntPtr.Zero && IsProcessInJob(Process.GetCurrentProcess().Handle,handle,out member);
  if(handle!=IntPtr.Zero) CloseHandle(handle);
  File.WriteAllText(marker,Process.GetCurrentProcess().Id+"|"+Process.GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc()+"|"+(query&&member?"owned":"unowned")+"|"+job);
  if(!direct) File.WriteAllLines(Path.Combine(dir,"config.args"),args);
  if(mode=="parent" || mode=="hang") {
   string child=marker+".child";
   var psi=new ProcessStartInfo(Process.GetCurrentProcess().MainModule.FileName,"--probe "+Quote(job)+" "+Quote(child)+" child");
   psi.UseShellExecute=false; psi.CreateNoWindow=true; psi.WorkingDirectory=dir;
   using(var process=Process.Start(psi)) { }
  }
  if(mode=="exit-error") return 19;
  if(mode=="exit-ok") return 0;
  Thread.Sleep(60000); return 0;
 }
}
'@
$probePath=Join-Path $executionRoot 'held-probe.exe'
Add-Type -TypeDefinition $probeSource -OutputAssembly $probePath -OutputType ConsoleApplication
$probeHash=Sha $probePath
$moduleReady=$false
try { Import-Module -Name $ModulePath -Force -ErrorAction Stop; $moduleReady=$true } catch { [IO.File]::AppendAllText($logPath,'MODULE_UNAVAILABLE'+[Environment]::NewLine) }
function FreshNative([string]$name) {
    Require $moduleReady 'Frozen core unavailable.'
    $dir=Join-Path $executionRoot $name; New-Item -ItemType Directory -Path $dir | Out-Null
    $owner=New-NativeRegistrationOwner -ExecutablePath $probePath -ExecutableSha256 $probeHash -WorkingDirectory $dir
    $owners.Add($owner)
    return @{dir=$dir;owner=$owner;marker=(Join-Path $dir 'probe.marker')}
}
Check 'named ownership and descendant stop preserve unrelated sentinel' {
    $native=FreshNative 'first-instruction'
    $sentinelPath=Join-Path $executionRoot 'sentinel.marker'
    $start=[Diagnostics.ProcessStartInfo]::new($probePath,('--sentinel "'+$sentinelPath+'"')); $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $sentinel=[Diagnostics.Process]::Start($start); $children.Add($sentinel); WaitFile $sentinelPath
    $job=$native.owner.OwnerJobName
    Require (-not [string]::IsNullOrWhiteSpace($job)) 'Named custody unavailable before start.'
    $startResult=$native.owner.StartConfig(@('--probe',$job,$native.marker,'parent'),4000)
    $p=ReadProbe $native.marker; $child=ReadProbe ($native.marker+'.child')
    Require ($p[2] -ceq 'owned' -and $child[2] -ceq 'owned' -and $p[3] -ceq $job) 'First instruction escaped exact named job.'
    Require ($startResult.assignedBeforeResume -ceq $true -and $startResult.killOnClose -ceq $true -and $startResult.pid.ToString() -ceq $p[0]) 'Original launch evidence disagrees.'
    Require ($native.owner.Snapshot().activeProcessCount -ge 2) 'Descendant omitted from native custody.'
    $stop=$native.owner.Stop(1000)
    Require ($stop.terminationRequested -ceq $true -and $stop.processesStopped -ceq $true) 'Owned tree stop unverified.'
    Require (-not (IsOriginalAlive $p[0] $p[1]) -and -not (IsOriginalAlive $child[0] $child[1])) 'Owned process survived stop.'
    Require (-not $sentinel.HasExited) 'Unrelated sentinel was terminated.'
}
Check 'real native timer survives a blocked caller' {
    $native=FreshNative 'independent-timer'; $null=$native.owner.StartConfig(@('--probe',$native.owner.OwnerJobName,$native.marker,'parent'),350)
    $p=ReadProbe $native.marker; $child=ReadProbe ($native.marker+'.child')
    Start-Sleep -Milliseconds 850
    $snapshot=$native.owner.Snapshot()
    Require ($snapshot.budgetExpired -ceq $true -and $snapshot.activeProcessCount -eq 0 -and $snapshot.configExited -ceq $true -and $null -ne $snapshot.configExitCode) 'Native independent budget did not stop the tree.'
    Require (-not (IsOriginalAlive $p[0] $p[1]) -and -not (IsOriginalAlive $child[0] $child[1])) 'Blocked caller left configuration running.'
}
Check 'disposal closes exact kill-on-close job' {
    $native=FreshNative 'dispose'; $null=$native.owner.StartConfig(@('--probe',$native.owner.OwnerJobName,$native.marker,'parent'),4000)
    $p=ReadProbe $native.marker; $child=ReadProbe ($native.marker+'.child'); $native.owner.Dispose(); Start-Sleep -Milliseconds 100
    Require (-not (IsOriginalAlive $p[0] $p[1]) -and -not (IsOriginalAlive $child[0] $child[1])) 'Job close failed to terminate original tree.'
}
Check 'owner root loss closes original kernel job' {
    Require $moduleReady 'Frozen core unavailable.'
    $dir=Join-Path $executionRoot 'root-loss'; New-Item -ItemType Directory -Path $dir | Out-Null
    $driver=Join-Path $dir 'driver.ps1'; $marker=Join-Path $dir 'root.marker'
    $driverBody=@'
param($module,$exe,$hash,$directory,$marker)
$ErrorActionPreference='Stop'
Import-Module -Name $module -Force
$owner=New-NativeRegistrationOwner -ExecutablePath $exe -ExecutableSha256 $hash -WorkingDirectory $directory
$null=$owner.StartConfig(@('--probe',$owner.OwnerJobName,$marker,'parent'),5000)
while($true){Start-Sleep -Milliseconds 100}
'@
    [IO.File]::WriteAllText($driver,$driverBody)
    $quoted=@($driver,$ModulePath,$probePath,$probeHash,$dir,$marker) | ForEach-Object {'"'+$_+'"'}
    $start=[Diagnostics.ProcessStartInfo]::new('C:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe',('-NoProfile -ExecutionPolicy Bypass -File '+($quoted -join ' '))); $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $root=[Diagnostics.Process]::Start($start); $children.Add($root); $p=ReadProbe $marker; $child=ReadProbe ($marker+'.child')
    $root.Kill(); $root.WaitForExit(1000) | Out-Null; Start-Sleep -Milliseconds 150
    Require (-not (IsOriginalAlive $p[0] $p[1]) -and -not (IsOriginalAlive $child[0] $child[1])) 'Owner loss left owned configuration descendants alive.'
}
function Runner([string]$id,[string]$name,[string]$label,[string]$os='Windows',[string]$status='offline',$busy=$false) {
    return @{id=$id;name=$name;os=$os;status=$status;busy=$busy;labels=@(@{name='self-hosted';type='read-only'},@{name='Windows';type='read-only'},@{name='X64';type='read-only'},@{name=$label;type='custom'})}
}
function NewCase([string]$name) {
    Require $moduleReady 'Frozen core unavailable.'
    $dir=Join-Path $executionRoot ('case-'+$name); New-Item -ItemType Directory -Path $dir | Out-Null
    $runnerDir=Join-Path $dir 'runner'; $workDir=Join-Path $runnerDir 'work'; $proof=Join-Path $dir 'proof'; $ownership=Join-Path $dir 'ownership'
    @($runnerDir,$workDir,$proof,$ownership) | ForEach-Object { New-Item -ItemType Directory -Path $_ | Out-Null }
    $limits=([IO.File]::ReadAllText('C:/fr-sealed-20261007/watchdog-limits.json') | ConvertFrom-Json)
    $limits.maxRunnerLifetimeMs=2000; $limits.nativeCleanupReserveMs=500; $limits.processStopGraceMs=100
    $limitsPath=Join-Path $dir 'limits.json'; [IO.File]::WriteAllBytes($limitsPath,(Bytes $limits))
    $launcher=Join-Path $dir 'launcher.ps1'; $watchdog=Join-Path $dir 'watchdog.ps1'; $launchBinding=Join-Path $dir 'launch.json'
    [IO.File]::WriteAllText($launcher,'held sealed launcher'); [IO.File]::WriteAllText($watchdog,'held sealed watchdog'); [IO.File]::WriteAllText($launchBinding,'{}')
    $startUtc=[datetime]::UtcNow; $startUtc=$startUtc.AddTicks(-($startUtc.Ticks % [TimeSpan]::TicksPerMillisecond))
    $source='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; $run='883'; $attempt='1'; $nameValue='held-registration-'+$name
    $label='fitcruxx-db-win-x64-'+$run+'-'+$attempt+'-aaaaaaaaaaaa'
    $admission=@{formatVersion=1;sourceSha=$source;runId=$run;runAttempt=$attempt;repository='OGUN01/gymloop';runnerName=$nameValue;runnerLabel=$label;registrationUtc=(CanonicalUtc $startUtc);limitsPath=$limitsPath;limitsSha256=(Sha $limitsPath);runnerDirectory=$runnerDir;workDirectory=$workDir;proofDirectory=$proof;listenerExecutablePath=$probePath;listenerExecutableSha256=$probeHash;wrapperProcessId=$PID.ToString();wrapperCreationFileTimeUtc=([Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().ToFileTimeUtc().ToString());launcherPath=$launcher;launcherSha256=(Sha $launcher);watchdogPath=$watchdog;watchdogSha256=(Sha $watchdog);launchBindingPath=$launchBinding;ownershipProofDirectory=$ownership}
    $admissionPath=Join-Path $dir 'admission.json'; [IO.File]::WriteAllBytes($admissionPath,(Bytes $admission))
    $state=@{dir=$dir;runnerDir=$runnerDir;admission=$admission;admissionSha=(Sha $admissionPath);startUtc=$startUtc;ms=0;step=100;realWait=15;ready=$false;owner=$null;baselinePages=@(@());baselineCounts=$null;events=[Collections.Generic.List[string]]::new();receipts=@{};rows=@();scan=0;pageRows=@();deleted=@{};deleteIds=[Collections.Generic.List[string]]::new();getIds=[Collections.Generic.List[string]]::new();getCounts=@{};request=$true;requestOverride=$null;mode='hang';rowAt=0;wrapperLostAt=[int]::MaxValue;getFailure=$false;deleteStatus=204;fresh404=$true;rebound=$null;readiness='matching-removed';handoff=$null;listenerOwner=$null;sentinel=$null}
    [IO.File]::WriteAllText((Join-Path $runnerDir 'mode.txt'),$state.mode)
    $clock={ @{utc=(CanonicalUtc $state.startUtc.AddMilliseconds($state.ms));monotonicMs=$state.ms} }.GetNewClosure()
    $wait={ param($milliseconds)
        if($state.ContainsKey('configStarted') -and $state.configStarted -and -not $state.ContainsKey('probePhaseEnded') -and -not $state.ContainsKey('retiring')){
            if([IO.File]::Exists((Join-Path $state.runnerDir 'config.marker'))){$state.probePhaseEnded=$true}else{
                $snapshot=$state.owner.Snapshot()
                if($snapshot.activeProcessCount -gt 0 -and -not $snapshot.configExited -and -not $snapshot.budgetExpired){
                    if(-not $state.ContainsKey('probeStartupWait')){$state.probeStartupWait=[Diagnostics.Stopwatch]::StartNew()}
                    if($state.probeStartupWait.ElapsedMilliseconds -ge 3000){throw 'Controlled native probe startup exceeded existing probe bound.'}
                    Start-Sleep -Milliseconds $state.realWait; return
                }
                $state.probePhaseEnded=$true
            }
        }
        $state.ms += $state.step; Start-Sleep -Milliseconds $state.realWait
    }.GetNewClosure()
    $wrapper={ param($pidText,$creation) Require ($pidText -ceq $state.admission.wrapperProcessId -and $creation -ceq $state.admission.wrapperCreationFileTimeUtc) 'Wrapper query lost identity binding.'; return ($state.ms -lt $state.wrapperLostAt) }.GetNewClosure()
    $list={ param($page)
        $state.events.Add(('list:'+ $page + ':'+$state.ms))
        if (-not $state.ready) {
            $all=@($state.baselinePages | ForEach-Object { @($_) }); $total=$all.Count
            if ($null -ne $state.baselineCounts) { $total=$state.baselineCounts[[Math]::Min($page-1,$state.baselineCounts.Count-1)] }
            $rows=@(); if ($page -le $state.baselinePages.Count) { $rows=@($state.baselinePages[$page-1]) }
            return @{totalCount=$total;runners=$rows}
        }
        if ($page -eq 1) {
            $state.scan += 1
            $visible=@(); if ($state.ms -ge $state.rowAt -and [IO.File]::Exists((Join-Path $state.runnerDir 'config.marker'))) { $visible=@($state.rows | Where-Object { -not $state.deleted.ContainsKey($_.id) }) }
            $state.pageRows=$visible
        }
        return @{totalCount=$state.pageRows.Count;runners=@(if($page -eq 1){$state.pageRows}else{@()})}
    }.GetNewClosure()
    $get={ param($id)
        $state.getIds.Add($id); $state.events.Add(('get:'+ $id + ':'+$state.ms))
        if ($state.getFailure) { throw 'Controlled provider uncertainty.' }
        if (-not $state.getCounts.ContainsKey($id)) {$state.getCounts[$id]=0}; $state.getCounts[$id]++
        if ($state.deleted.ContainsKey($id) -and $state.fresh404) { return @{status=404;runner=$null} }
        $rows=@($state.rows | Where-Object {$_.id -ceq $id})
        if ($state.ms -lt $state.rowAt -or $rows.Count -eq 0) { return @{status=404;runner=$null} }
        if ($null -ne $state.rebound) { return @{status=200;runner=$state.rebound} }
        return @{status=200;runner=$rows[0]}
    }.GetNewClosure()
    $delete={ param($id)
        $state.events.Add(('delete:'+ $id + ':'+$state.ms)); $state.deleteIds.Add($id)
        Require ($null -ne $state.owner -and $state.owner.Snapshot().activeProcessCount -eq 0) 'DELETE preceded actual config-tree stop.'
        if ($null -ne $state.listenerOwner) { Require ($state.listenerOwner.Snapshot().activeProcessCount -eq 0) 'DELETE preceded owned listener stop.' }
        Require ($state.getIds.Count -gt 0 -and $state.getIds[$state.getIds.Count-1] -ceq $id) 'DELETE lacked fresh bound GET.'
        if ($state.deleteStatus -eq 204) { $state.deleted[$id]=$true }; return $state.deleteStatus
    }.GetNewClosure()
    $request={
        if(-not $state.request){return $null}; if($null -ne $state.requestOverride){return ,(Bytes $state.requestOverride)}
        return ,(Bytes @{formatVersion=1;admissionSha256=$state.admissionSha;sourceSha=$state.admission.sourceSha;runId=$state.admission.runId;runAttempt='1';runnerName=$state.admission.runnerName;runnerLabel=$state.admission.runnerLabel;registrationToken='held-safe_./+=-token';registrationTokenExpiresAt=(CanonicalUtc $state.startUtc.AddHours(1))})
    }.GetNewClosure()
    $observe={
        if($null -eq $state.handoff){return $null}
        if(-not [IO.File]::Exists((Join-Path $state.runnerDir 'config.marker'))){return $null}
        if($state.ms -ge $state.handoff.watchdogLostAt -and -not $state.handoff.watchdog.HasExited){$state.handoff.watchdog.Kill();$state.handoff.watchdog.WaitForExit(1000)|Out-Null}
        $watchdogAlive=(-not $state.handoff.watchdog.HasExited)
        $nativeAlive=($state.listenerOwner.Snapshot().activeProcessCount -gt 0)
        $sealedConfig=((Sha (Join-Path $state.runnerDir '.runner')) -ceq $state.handoff.request.configSha256)
        return @{request=(Bytes $state.handoff.request);verified=($state.handoff.verified -and $nativeAlive -and $sealedConfig);watchdogAlive=$watchdogAlive;fullJobFinalVerified=$state.handoff.fullJobFinalVerified}
    }.GetNewClosure()
    $stopListener={
        $state.retiring=$true
        $state.events.Add(('listener-stop:'+$state.ms)); if($null -eq $state.listenerOwner){return @{terminationRequested=$false}}
        $stopped=$state.listenerOwner.Stop(100); Require ($stopped.processesStopped -ceq $true) 'Retained listener stop failed.'; return @{terminationRequested=$stopped.terminationRequested}
    }.GetNewClosure()
    $remove={ param($id,$source,$run,$attempt)
        Require ($id -ceq '971' -and $source -ceq $state.admission.sourceSha -and $run -ceq $state.admission.runId -and $attempt -ceq '1') 'Readiness cleanup expanded its identity.'
        $state.events.Add(('readiness:'+ $id + ':'+$state.ms)); return $state.readiness
    }.GetNewClosure()
    $write={ param($name,$record)
        Require (@('admission-ready.json','configuration-result.json','handoff-accepted.json','admission-final.json') -contains $name) 'Unapproved receipt name.'
        Require (-not $state.receipts.ContainsKey($name)) 'Receipt overwrite.'
        $state.receipts[$name]=$record; $state.events.Add(('receipt:'+ $name + ':'+$state.ms))
        if($name -ceq 'admission-ready.json'){
            Require ($null -ne $state.owner -and $record.configOwnerJobName -ceq $state.owner.OwnerJobName) 'READY did not bind actual named kernel owner.'
            Require (-not [IO.File]::Exists((Join-Path $state.runnerDir 'config.marker'))) 'Configuration ran before READY.'
            [IO.File]::WriteAllText((Join-Path $state.runnerDir 'job-name.txt'),$record.configOwnerJobName); $state.ready=$true
        }
    }.GetNewClosure()
    $newOwner={ param($admissionRecord)
        $state.events.Add('owner-new'); $state.owner=New-NativeRegistrationOwner -ExecutablePath $admissionRecord.listenerExecutablePath -ExecutableSha256 $admissionRecord.listenerExecutableSha256 -WorkingDirectory $admissionRecord.runnerDirectory
        $nativeStart=$state.owner.GetType().GetMethod('StartConfig')
        $state.owner | Add-Member -MemberType NoteProperty -Name HeldFixtureState -Value $state
        $state.owner | Add-Member -MemberType NoteProperty -Name HeldFixtureStartMethod -Value $nativeStart
        $state.owner | Add-Member -MemberType ScriptMethod -Name StartConfig -Force -Value {
            param($arguments,$budgetMs)
            $nativeBudget=[Convert]::ChangeType($budgetMs,$this.HeldFixtureStartMethod.GetParameters()[1].ParameterType,[Globalization.CultureInfo]::InvariantCulture)
            $actual=$this.HeldFixtureStartMethod.Invoke($this,[object[]]@([string[]]$arguments,$nativeBudget))
            $this.HeldFixtureState.configStarted=$true
            return $actual
        }
        $owners.Add($state.owner); return $state.owner
    }.GetNewClosure()
    $state.ports=@{Clock=$clock;Wait=$wait;WrapperAlive=$wrapper;ListRunners=$list;GetRunner=$get;DeleteRunner=$delete;ReadConfigurationRequest=$request;ObserveHandoff=$observe;StopAdmittedListener=$stopListener;RemoveOwnReadiness=$remove;WriteReceipt=$write;NewOwner=$newOwner}
    return $state
}
function RunCase($state) {
    [IO.File]::WriteAllText((Join-Path $state.runnerDir 'mode.txt'),$state.mode)
    $final=Invoke-NativeRegistrationCustodian -Admission $state.admission -AdmissionSha256 $state.admissionSha -Ports $state.ports
    Require ($state.receipts.ContainsKey('admission-final.json')) 'Final custody record missing.'
    Require (($final | ConvertTo-Json -Depth 20 -Compress) -ceq ($state.receipts['admission-final.json'] | ConvertTo-Json -Depth 20 -Compress)) 'Returned final differs from written final.'
    Require ($final.physicalTeardownVerified -ceq $false) 'Configuration evidence claimed workload teardown.'
    Require (-not (($final | ConvertTo-Json -Depth 20 -Compress).Contains('held-safe'))) 'Private token escaped to receipt.'
    return $final
}
function OwnRow($state,[string]$os='Windows',[string]$status='offline',$busy=$false) { Runner '971' $state.admission.runnerName $state.admission.runnerLabel $os $status $busy }
function RequireRetired($state,$final) {
    Require ($final.learnedRunnerId -ceq '971' -and $final.runnerDeregistered -ceq $true -and $final.configProcessesStopped -ceq $true -and $final.status -ceq 'RETIRED') 'Exact learned registration did not retire.'
    Require ($state.deleteIds.Count -gt 0 -and @($state.deleteIds | Where-Object {$_ -cne '971'}).Count -eq 0) 'Cleanup touched a different registration.'
    Require ($state.getIds.Count -gt $state.deleteIds.Count) 'No fresh post-delete absence observation.'
}
Check 'later baseline page exact-name conflict refuses before config' {
    $s=NewCase 'baseline-name'; $s.baselinePages=@(@((Runner '21' 'unrelated' 'other')), @((Runner '22' $s.admission.runnerName 'other' 'unknown')), @())
    $f=RunCase $s
    Require ($f.stopReason -ceq 'BASELINE_CONFLICT' -and -not $s.ready -and $s.deleteIds.Count -eq 0 -and -not [IO.File]::Exists((Join-Path $s.runnerDir 'config.marker'))) 'Later name collision was admitted.'
}
Check 'baseline unique-label collision with other name refuses' {
    $s=NewCase 'baseline-label'; $s.baselinePages=@(@((Runner '21' 'different-name' $s.admission.runnerLabel 'unknown')), @())
    $f=RunCase $s; Require ($f.stopReason -ceq 'BASELINE_CONFLICT' -and -not $s.ready -and $s.deleteIds.Count -eq 0) 'Label collision was treated as absent.'
}
Check 'contradictory pagination cannot certify absence' {
    $s=NewCase 'pagination-count'; $s.baselinePages=@(@((Runner '21' 'unrelated' 'other')), @()); $s.baselineCounts=@(1,0)
    $f=RunCase $s; Require ($f.stopReason -ceq 'BASELINE_UNVERIFIED' -and $f.runnerDeregistered -ceq $false -and -not $s.ready -and $s.deleteIds.Count -eq 0) 'Changing count became absence.'
}
Check 'duplicate baseline identities cannot certify absence' {
    $s=NewCase 'pagination-duplicate'; $row=Runner '21' 'unrelated' 'other'; $s.baselinePages=@(@($row),@($row),@())
    $f=RunCase $s; Require ($f.stopReason -ceq 'BASELINE_UNVERIFIED' -and -not $s.ready -and $s.deleteIds.Count -eq 0) 'Duplicate baseline ID was admitted.'
}
Check 'complete pages authorize exact config but never a service' {
    $s=NewCase 'config-command'; $s.baselinePages=@(@((Runner '21' 'other-one' 'other-one')), @((Runner '22' 'other-two' 'other-two' 'Linux')), @()); $s.rows=@((OwnRow $s)); $s.wrapperLostAt=600
    $f=RunCase $s; RequireRetired $s $f
    $args=[IO.File]::ReadAllLines((Join-Path $s.runnerDir 'config.args'))
    $expected=@('configure','--unattended','--url','https://github.com/OGUN01/gymloop','--token','held-safe_./+=-token','--name',$s.admission.runnerName,'--labels',$s.admission.runnerLabel,'--work',$s.admission.workDirectory,'--ephemeral','--disableupdate')
    Require (($args -join '|') -ceq ($expected -join '|')) 'Native configuration arguments violate frozen contract.'
    Require ($s.receipts['admission-ready.json'].baselineExhausted -ceq $true -and @($s.receipts['admission-ready.json'].baselineRunnerIds).Count -eq 2) 'READY lacks complete baseline.'
}
Check 'unknown offline idle API registration learned without local config' {
    $s=NewCase 'unknown-idle'; $s.rows=@((OwnRow $s 'unknown')); $s.wrapperLostAt=500
    $f=RunCase $s; RequireRetired $s $f
    Require (-not [IO.File]::Exists((Join-Path $s.runnerDir '.runner'))) 'Fixture unexpectedly needed local .runner.'
    Require ($s.ms -ge 2000 -and $f.physicalTeardownVerified -ceq $false) 'Failure backstop ended early or overstated teardown.'
}
Check 'unknown online or busy registration cannot be adopted' {
    foreach($variation in @('online','busy')){
        $s=NewCase ('unknown-'+$variation); $s.rows=@((OwnRow $s 'unknown' $(if($variation -ceq 'online'){'online'}else{'offline'}) ($variation -ceq 'busy'))); $s.wrapperLostAt=500
        $f=RunCase $s; Require ($f.learnedRunnerId -eq $null -and $s.deleteIds.Count -eq 0 -and $f.runnerDeregistered -ceq $false) 'Unsafe unknown OS registration adopted.'
    }
}
Check 'custom default label cannot impersonate Windows membership' {
    $s=NewCase 'label-type'; $row=OwnRow $s; $row.labels[1].type='custom'; $s.rows=@($row); $s.wrapperLostAt=500
    $f=RunCase $s; Require ($f.learnedRunnerId -eq $null -and $s.deleteIds.Count -eq 0) 'Custom default label supplied platform proof.'
}
Check 'configuration nonzero still retires partial remote creation' {
    $s=NewCase 'config-nonzero'; $s.mode='exit-error'; $s.rows=@((OwnRow $s)); $s.rowAt=200
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.stopReason -ceq 'CONFIG_REFUSED' -and -not $f.handoffAccepted -and $s.ms -ge 2000) 'Nonzero configuration was green or ended late monitoring.'
}
Check 'expired independent config budget stops descendants before deletion' {
    $s=NewCase 'config-budget'; $s.rows=@((OwnRow $s)); $s.step=20; $s.realWait=30
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.stopReason -ceq 'CONFIG_TIMEOUT') 'Native timeout evidence was ignored.'
    $p=ReadProbe (Join-Path $s.runnerDir 'config.marker'); $child=ReadProbe (Join-Path $s.runnerDir 'config.marker.child')
    Require (-not (IsOriginalAlive $p[0] $p[1]) -and -not (IsOriginalAlive $child[0] $child[1])) 'Config timeout failed descendant teardown.'
}
Check 'early absent observation does not abandon later creation' {
    $s=NewCase 'late-row'; $s.rows=@((OwnRow $s)); $s.rowAt=1200; $s.wrapperLostAt=300
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.stopReason -ceq 'WRAPPER_LOST' -and $s.ms -ge 2000 -and $s.scan -gt 3) 'Early absence ended conservative backstop.'
}
Check 'rebound registration ID is preserved after fresh identity check' {
    $s=NewCase 'id-rebound'; $s.rows=@((OwnRow $s)); $s.rebound=Runner '971' 'reused-unrelated-name' 'unrelated-label'; $s.wrapperLostAt=500
    $f=RunCase $s; Require ($s.deleteIds.Count -eq 0 -and $f.runnerDeregistered -ceq $false -and $f.status -ceq 'RETIREMENT_UNVERIFIED') 'Rebound ID was deleted or certified absent.'
}
Check 'ambiguous exact rows neither broaden nor choose an ID' {
    $s=NewCase 'ambiguous'; $s.rows=@((OwnRow $s),(Runner '972' $s.admission.runnerName $s.admission.runnerLabel)); $s.wrapperLostAt=500
    $f=RunCase $s; Require ($s.deleteIds.Count -eq 0 -and $f.learnedRunnerId -eq $null -and $f.stopReason -ceq 'BOUND_ROW_AMBIGUOUS') 'Ambiguity silently selected one registration.'
}
Check 'provider failure cannot become retirement or absence' {
    $s=NewCase 'provider-error'; $s.rows=@((OwnRow $s)); $s.getFailure=$true; $s.wrapperLostAt=500
    $f=RunCase $s; Require ($f.runnerDeregistered -ceq $false -and $f.status -ceq 'RETIREMENT_UNVERIFIED' -and $s.deleteIds.Count -eq 0 -and $f.readinessState -cne 'absent') 'Provider uncertainty was converted to absence.'
}
Check 'successful DELETE without fresh404 is unverified' {
    $s=NewCase 'delete-without-404'; $s.rows=@((OwnRow $s)); $s.fresh404=$false; $s.wrapperLostAt=500
    $f=RunCase $s; Require ($s.deleteIds.Count -gt 0 -and $f.runnerDeregistered -ceq $false -and $f.status -ceq 'RETIREMENT_UNVERIFIED') 'DELETE response substituted for observed absence.'
}
function InstallHandoff($state,$verified=$true,[int]$watchdogLostAt=[int]::MaxValue) {
    $native=FreshNative ('listener-'+([guid]::NewGuid().ToString('N')))
    $null=$native.owner.StartConfig(@('--probe',$native.owner.OwnerJobName,$native.marker,'parent'),5000)
    $p=ReadProbe $native.marker; $child=ReadProbe ($native.marker+'.child'); Require ($p[2] -ceq 'owned' -and $child[2] -ceq 'owned') 'Handoff fixture lacks actual named kernel ownership.'
    $state.listenerOwner=$native.owner
    $watchdogMarker=Join-Path $state.dir 'watchdog-live.marker'
    $start=[Diagnostics.ProcessStartInfo]::new($probePath,('--sentinel "'+$watchdogMarker+'"')); $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $watchdogProcess=[Diagnostics.Process]::Start($start); $children.Add($watchdogProcess); WaitFile $watchdogMarker
    $configPath=Join-Path $state.runnerDir '.runner'; [IO.File]::WriteAllText($configPath,'{"agentId":971,"agentName":"'+$state.admission.runnerName+'"}')
    $request=@{formatVersion=1;admissionSha256=$state.admissionSha;sourceSha=$state.admission.sourceSha;runId=$state.admission.runId;runAttempt='1';runnerId='971';runnerName=$state.admission.runnerName;runnerLabel=$state.admission.runnerLabel;configSha256=(Sha $configPath);launchBindingPath=$state.admission.launchBindingPath;launchBindingSha256=(Sha $state.admission.launchBindingPath);ownershipProofDirectory=$state.admission.ownershipProofDirectory}
    $state.handoff=@{request=$request;verified=$verified;watchdogLostAt=$watchdogLostAt;watchdog=$watchdogProcess;fullJobFinalVerified=$false}
}
Check 'bound handoff tolerates normal wrapper loss but retains deadline backstop' {
    $s=NewCase 'handoff-live'; $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); InstallHandoff $s; $s.wrapperLostAt=700
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.handoffAccepted -ceq $true -and $f.stopReason -ceq 'DEADLINE' -and $s.ms -ge 2000) 'Bound handoff was lost or extended lifetime.'
}
Check 'watchdog loss after genuine handoff leaves retirement armed' {
    $s=NewCase 'handoff-watchdog-loss'; $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); InstallHandoff $s $true 900; $s.wrapperLostAt=700
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.handoffAccepted -ceq $true -and $f.stopReason -ceq 'WATCHDOG_LOST' -and $s.ms -ge 2000) 'Watchdog loss escaped remote retirement.'
}
Check 'forged handoff cannot transfer registration custody' {
    foreach($variation in @('unverified','id','path','extra')){
        $s=NewCase ('handoff-forged-'+$variation); $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); InstallHandoff $s ($variation -cne 'unverified')
        if($variation -ceq 'id'){$s.handoff.request.runnerId='972'}
        if($variation -ceq 'path'){$s.handoff.request.ownershipProofDirectory=$s.dir}
        if($variation -ceq 'extra'){$s.handoff.request.extendedDeadline=(CanonicalUtc $s.startUtc.AddHours(5))}
        $s.wrapperLostAt=700; $f=RunCase $s
        Require ($f.handoffAccepted -ceq $false -and $s.ms -ge 2000) 'Forged handoff transferred or extended custody.'
    }
}
Check 'unrelated readiness authority survives exact registration cleanup' {
    $s=NewCase 'readiness-unrelated'; $s.rows=@((OwnRow $s)); $s.readiness='unrelated-preserved'; $s.wrapperLostAt=500
    $f=RunCase $s; RequireRetired $s $f
    Require ($f.readinessState -ceq 'unrelated-preserved') 'Unrelated readiness authority was claimed absent.'
}
function RawSha([byte[]]$raw) {
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($raw))).Replace('-','').ToLowerInvariant() } finally {$algorithm.Dispose()}
}
function ExactReceiptKeys($record,[string[]]$expected) {
    $keys=@(); if($record -is [Collections.IDictionary]){$keys=@($record.Keys)}else{$keys=@($record.PSObject.Properties | ForEach-Object {$_.Name})}
    Require ($keys.Count -eq $expected.Count -and (@($keys | Sort-Object) -join '|') -ceq (@($expected | Sort-Object) -join '|')) 'Acknowledgment receipt schema differs from declaration.'
}
function NewAckCase([string]$name) {
    $state=NewCase ('ack-'+$name)
    $state.requestRaw=$null; $state.handoffRaw=$null; $state.rejectAck=$false; $state.ackAttempts=0
    $state.actualConfigKernelStopped=$false; $state.actualConfigOriginalExited=$false; $state.actualListenerKernelStopped=$false
    $priorOwner=$state.ports.NewOwner
    $state.ports.NewOwner={ param($admissionRecord)
        $owner=& $priorOwner $admissionRecord
        $owner | Add-Member -MemberType NoteProperty -Name HeldAckState -Value $state
        $owner | Add-Member -MemberType NoteProperty -Name HeldAckStopMethod -Value ($owner.GetType().GetMethod('Stop'))
        $owner | Add-Member -MemberType ScriptMethod -Name StartConfig -Force -Value {
            param($arguments,$budgetMs)
            $nativeBudget=[Convert]::ChangeType($budgetMs,$this.HeldFixtureStartMethod.GetParameters()[1].ParameterType,[Globalization.CultureInfo]::InvariantCulture)
            $actual=$this.HeldFixtureStartMethod.Invoke($this,[object[]]@([string[]]$arguments,$nativeBudget))
            $this.HeldFixtureState.configStarted=$true
            $original=[Diagnostics.Process]::GetProcessById([int]$actual.pid); $null=$original.Handle
            Require ($original.StartTime.ToUniversalTime().ToFileTimeUtc().ToString() -ceq $actual.creationFileTimeUtc.ToString()) 'Original configuration handle identity changed.'
            $this.HeldAckState.actualConfigProcess=$original; $children.Add($original)
            return $actual
        }
        $owner | Add-Member -MemberType ScriptMethod -Name Stop -Force -Value {
            param($stopGraceMs)
            $nativeGrace=[Convert]::ChangeType($stopGraceMs,$this.HeldAckStopMethod.GetParameters()[0].ParameterType,[Globalization.CultureInfo]::InvariantCulture)
            $actual=$this.HeldAckStopMethod.Invoke($this,[object[]]@($nativeGrace))
            $this.HeldAckState.actualConfigKernelStopped=($actual.processesStopped -ceq $true)
            $this.HeldAckState.actualConfigOriginalExited=$this.HeldAckState.actualConfigProcess.HasExited
            return $actual
        }
        return $owner
    }.GetNewClosure()
    $priorListenerStop=$state.ports.StopAdmittedListener
    $state.ports.StopAdmittedListener={
        if($null -ne $state.listenerOwner -and -not $state.ContainsKey('ackListenerInstrumented')){
            $state.listenerOwner | Add-Member -MemberType NoteProperty -Name HeldAckState -Value $state
            $state.listenerOwner | Add-Member -MemberType NoteProperty -Name HeldAckStopMethod -Value ($state.listenerOwner.GetType().GetMethod('Stop'))
            $state.listenerOwner | Add-Member -MemberType ScriptMethod -Name Stop -Force -Value {
                param($stopGraceMs)
                $nativeGrace=[Convert]::ChangeType($stopGraceMs,$this.HeldAckStopMethod.GetParameters()[0].ParameterType,[Globalization.CultureInfo]::InvariantCulture)
                $actual=$this.HeldAckStopMethod.Invoke($this,[object[]]@($nativeGrace))
                $this.HeldAckState.actualListenerKernelStopped=($actual.processesStopped -ceq $true)
                return $actual
            }
            $state.ackListenerInstrumented=$true
        }
        & $priorListenerStop
    }.GetNewClosure()
    $priorRead=$state.ports.ReadConfigurationRequest
    $state.ports.ReadConfigurationRequest={
        $original=[byte[]](& $priorRead); $raw=[byte[]]($original + [Text.Encoding]::UTF8.GetBytes("`n  "))
        $state.requestRaw=$raw; return ,$raw
    }.GetNewClosure()
    $priorObserve=$state.ports.ObserveHandoff
    $state.ports.ObserveHandoff={
        $observation=& $priorObserve; if($null -eq $observation){return $null}
        $raw=[byte[]](([byte[]]$observation.request) + [Text.Encoding]::UTF8.GetBytes("`n  ")); $state.handoffRaw=$raw
        return @{request=$raw;verified=$observation.verified;watchdogAlive=$observation.watchdogAlive;fullJobFinalVerified=$observation.fullJobFinalVerified}
    }.GetNewClosure()
    $priorWrite=$state.ports.WriteReceipt
    $state.ports.WriteReceipt={ param($name,$record)
        if($name -ceq 'configuration-result.json'){
            ExactReceiptKeys $record @('formatVersion','admissionSha256','configurationRequestSha256','sourceSha','runId','runAttempt','runnerName','runnerLabel','configProcessId','configCreationFileTimeUtc','configExecutablePath','configOwnerJobName','assignedBeforeResume','configKillOnClose','configExited','configExitCode','budgetExpired','configProcessesStopped','verifiedAt')
            $snapshot=$state.owner.Snapshot(); $probe=ReadProbe (Join-Path $state.runnerDir 'config.marker')
            Require ($snapshot.configExited -ceq $true -and $snapshot.activeProcessCount -eq 0 -and $record.configExited -ceq $true -and $record.configProcessesStopped -ceq $true) 'Configuration acknowledgment preceded actual exit/tree observation.'
            Require ($record.configExitCode -is [int] -and $record.configExitCode -eq $snapshot.configExitCode -and $record.budgetExpired -ceq $snapshot.budgetExpired) 'Configuration acknowledgment invented exit/timer facts.'
            Require ($record.configurationRequestSha256 -ceq (RawSha $state.requestRaw) -and $record.admissionSha256 -ceq $state.admissionSha -and $record.sourceSha -ceq $state.admission.sourceSha -and $record.runId -ceq $state.admission.runId -and $record.runAttempt -ceq '1') 'Configuration acknowledgment lost raw request/source/run binding.'
            Require ($record.configProcessId -ceq $probe[0] -and $record.configCreationFileTimeUtc -ceq $probe[1] -and $record.configOwnerJobName -ceq $state.owner.OwnerJobName -and [IO.Path]::GetFullPath($record.configExecutablePath) -ceq [IO.Path]::GetFullPath($probePath)) 'Configuration acknowledgment lost actual original process/job identity.'
            Require ($record.assignedBeforeResume -ceq $true -and $record.configKillOnClose -ceq $true -and $record.runnerName -ceq $state.admission.runnerName -and $record.runnerLabel -ceq $state.admission.runnerLabel) 'Configuration acknowledgment lost kernel/runner binding.'
        }
        if($name -ceq 'handoff-accepted.json'){
            $state.ackAttempts++
            ExactReceiptKeys $record @('formatVersion','admissionSha256','handoffRequestSha256','sourceSha','runId','runAttempt','runnerId','runnerName','runnerLabel','configSha256','launchBindingSha256','deadlineUtc','handoffAccepted','verifiedAt')
            Require ($state.receipts.ContainsKey('configuration-result.json') -and $state.receipts['configuration-result.json'].configExitCode -eq 0 -and -not $state.receipts['configuration-result.json'].budgetExpired) 'Handoff acknowledgment preceded successful configuration result.'
            Require ($record.handoffAccepted -ceq $true -and $record.handoffRequestSha256 -ceq (RawSha $state.handoffRaw) -and $record.admissionSha256 -ceq $state.admissionSha -and $record.sourceSha -ceq $state.admission.sourceSha -and $record.runId -ceq $state.admission.runId -and $record.runAttempt -ceq '1' -and $record.runnerId -ceq '971') 'Handoff acknowledgment lost exact request/identity binding.'
            Require ($record.configSha256 -ceq $state.handoff.request.configSha256 -and $record.launchBindingSha256 -ceq $state.handoff.request.launchBindingSha256 -and $record.deadlineUtc -ceq $state.receipts['admission-ready.json'].deadlineUtc -and $record.runnerName -ceq $state.admission.runnerName -and $record.runnerLabel -ceq $state.admission.runnerLabel) 'Handoff acknowledgment extended or substituted admitted identity.'
            if($state.rejectAck){throw 'Controlled protected acknowledgment write refusal.'}
        }
        & $priorWrite $name $record
    }.GetNewClosure()
    return $state
}
Check 'configuration result binds original exit and exact raw private request' {
    $s=NewAckCase 'config-success'; $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); $s.wrapperLostAt=700
    $f=RunCase $s; RequireRetired $s $f
    Require ($s.receipts.ContainsKey('configuration-result.json') -and $s.receipts['configuration-result.json'].configExitCode -eq 0 -and -not $s.receipts['configuration-result.json'].budgetExpired -and -not $s.receipts.ContainsKey('handoff-accepted.json')) 'Successful configuration acknowledgment missing or handoff invented.'
}
Check 'nonzero and timed config results never authorize handoff' {
    foreach($variation in @('error','timer')){
        $s=NewAckCase ('config-'+$variation); $s.rows=@((OwnRow $s))
        if($variation -ceq 'error'){$s.mode='exit-error'}else{$s.step=20;$s.realWait=30}
        $f=RunCase $s; RequireRetired $s $f
        Require ($s.receipts.ContainsKey('configuration-result.json') -and -not $s.receipts.ContainsKey('handoff-accepted.json') -and -not $f.handoffAccepted) 'Refused configuration result was omitted or released custody.'
        if($variation -ceq 'error'){Require ($s.receipts['configuration-result.json'].configExitCode -eq 19 -and -not $s.receipts['configuration-result.json'].budgetExpired) 'Actual config nonzero lost.'}else{Require ($s.receipts['configuration-result.json'].budgetExpired -ceq $true) 'Actual native timer expiry lost.'}
    }
}
Check 'handoff acknowledgment binds raw request after zero exit without deadline reset' {
    $s=NewAckCase 'handoff-success'; $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); InstallHandoff $s; $s.wrapperLostAt=700
    $f=RunCase $s; RequireRetired $s $f
    Require ($s.receipts.ContainsKey('configuration-result.json') -and $s.receipts.ContainsKey('handoff-accepted.json') -and $s.ackAttempts -eq 1 -and $f.handoffAccepted -ceq $true -and $s.ms -ge 2000) 'Genuine handoff lacked singular bound acknowledgment/backstop.'
}
Check 'unwritten handoff acknowledgment never releases failure custody' {
    $s=NewAckCase 'handoff-write-refusal'; $s.mode='exit-ok'; $s.rows=@((OwnRow $s)); InstallHandoff $s; $s.rejectAck=$true; $s.wrapperLostAt=700
    $f=RunCase $s
    Require ($s.ackAttempts -gt 0 -and -not $s.receipts.ContainsKey('handoff-accepted.json') -and $f.handoffAccepted -ceq $false -and $f.stopReason -ceq 'ACKNOWLEDGMENT_UNVERIFIED') 'Failed acknowledgment write released or hid failed custody.'
    Require ($s.actualConfigKernelStopped -ceq $true -and $s.actualConfigOriginalExited -ceq $true -and $s.actualListenerKernelStopped -ceq $true -and $s.ms -ge 2000 -and $f.physicalTeardownVerified -ceq $false) 'Failed acknowledgment left owned execution or ended conservative backstop.'
}

foreach($owner in $owners){StopOwner $owner}
foreach($child in $children){try{if(-not $child.HasExited){$child.Kill();$child.WaitForExit(1000)|Out-Null}}catch{};try{$child.Dispose()}catch{}}
if(-not [IO.File]::Exists($logPath)){[IO.File]::WriteAllText($logPath,'HELD_PASS'+[Environment]::NewLine)}
$total=$checks.Count; $passed=@($checks | Where-Object {$_.passed}).Count; $failed=$total-$passed
[pscustomobject]@{suite='registration-startup-held';total=$total;passed=$passed;failed=$failed;verdict=$(if($failed -eq 0){'PASS'}else{'FAIL'});frozenFileSha256=(Sha $PSCommandPath);privateLogSha256=(Sha $logPath)} | ConvertTo-Json -Compress
if($failed -gt 0){exit 1};exit 0
