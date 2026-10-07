import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { readFileSync, writeFileSync } from 'node:fs';
import { platform } from 'node:os';
import { beforeAll, expect, test } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type VisibleWatchdogRecord = {
  error?: string;
  directExited?: boolean;
  bothEofBeforeRelease?: boolean;
  stdout?: string;
  stderr?: string;
  childAlive?: boolean;
  child?: { arguments: string[]; marker: string; cwd: string; hidden: boolean; nulInput: boolean; aliasesAbsent: boolean; sentinelAbsent: boolean; stdinType: number; stdoutType: number; stderrType: number };
  launcher?: { id: number; originalId: number; initiallyExited: boolean; refreshedExited: boolean; disposedMs: number; refused: boolean; unchanged: boolean; exitObserved: boolean; exitId: number };
  survivorCount?: number;
  logReadWhileAlive?: boolean;
  logWriteRefusedWhileAlive?: boolean;
};

const visibleWatchdogMetadata = {
  ps7: 'C:\\Users\\Harsh\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\native\\powershell\\pwsh.exe',
  ps5: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
  modules: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Modules',
  candidate: 'C:\\fr-sealed-20261007\\start-listener-suspended-trial9.ps1',
  root: 'C:\\fr-sealed-20261007\\watchdog-handle-visible-20261008',
  limits: 'C:\\fr-sealed-20261007\\watchdog-limits.json',
  limitsHash: '5799d0354e2cf671851f3e6016ea37de9d98e1441559ec724b2db0805c003320',
  expectedArguments: ['नमस्ते 🏋️', 'a b', '', 'a"b', 'tail\\', 'double\\\\"quote'],
  marker: 'visible-only: नमस्ते "quoted" \\ tail',
};
let visibleWatchdogHostFile = '';

const visibleWatchdogNativeScript = String.raw`
param([string]$TaskRoot,[string]$CaseId,[string]$Mode,[string]$Candidate,[string]$NativePowerShell,[string]$CanonicalModules,[string]$LimitsPath)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
$taskLimits=Get-Content -LiteralPath $LimitsPath -Raw | ConvertFrom-Json
$taskCase=Join-Path $TaskRoot $CaseId
function New-VisibleProtectedDirectory([string]$Path) {
  [IO.Directory]::CreateDirectory($Path) | Out-Null
  $acl=[IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($Path),[Security.AccessControl.AccessControlSections]::Access)
  $acl.SetAccessRuleProtection($true,$false)
  $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
  foreach($rule in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){$acl.RemoveAccessRuleAll($rule)}
  foreach($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))) {
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))
  }
  [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path),$acl)
}
function Quote-VisibleNative([string]$Value) {
  if($Value.Length -gt 0 -and $Value -notmatch '[\s"]'){return $Value}
  return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Write-VisibleRecord([string]$Path,$Record) {
  [IO.File]::WriteAllText($Path,($Record | ConvertTo-Json -Depth 8 -Compress),[Text.UTF8Encoding]::new($false))
}
function Get-VisibleOwnedProbe([string]$Executable,[datetime]$Since) {
  foreach($p in [Diagnostics.Process]::GetProcesses()) {
    try {
      if($p.StartTime.ToUniversalTime() -ge $Since -and [string]::Equals($p.MainModule.FileName,$Executable,[StringComparison]::OrdinalIgnoreCase)) {
        $null=$p.Handle
        $p
      } else {$p.Dispose()}
    } catch {$p.Dispose()}
  }
}
function Stop-VisibleOwnedProbes([string]$Executable,[datetime]$Since,[int]$Budget) {
  $owned=@(Get-VisibleOwnedProbe $Executable $Since)
  foreach($p in $owned) {
    try {if(-not $p.HasExited){$p.Kill();if(-not $p.WaitForExit($Budget)){throw 'OWNED_PROBE_STOP_UNVERIFIED'}}} finally {$p.Dispose()}
  }
}

$taskProbeSource=@'
using System;
using System.IO;
using System.Diagnostics;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
using System.Web.Script.Serialization;
public static class VisibleProbe {
  [DllImport("kernel32.dll")] private static extern IntPtr GetStdHandle(int n);
  [DllImport("kernel32.dll")] private static extern uint GetFileType(IntPtr h);
  [DllImport("kernel32.dll")] private static extern bool GetHandleInformation(IntPtr h,out uint flags);
  [DllImport("kernel32.dll")] private static extern IntPtr GetConsoleWindow();
  public static int Main(string[] args) {
    Console.OutputEncoding=new UTF8Encoding(false);
    string mode=args[0], receipt=args[1], release=args[2];
    IntPtr aliasOut=new IntPtr(long.Parse(args[3])), aliasErr=new IntPtr(long.Parse(args[4])), sentinel=new IntPtr(long.Parse(args[5]));
    uint ignored;
    string input=mode=="control-leak" ? "" : Console.In.ReadToEnd();
    string[] values=new string[args.Length-7];Array.Copy(args,7,values,0,values.Length);
    var facts=new {arguments=values,marker=Environment.GetEnvironmentVariable("VISIBLE_HANDLE_MARKER"),cwd=Environment.CurrentDirectory,
      hidden=GetConsoleWindow()==IntPtr.Zero,nulInput=input.Length==0,aliasesAbsent=GetFileType(aliasOut)!=3&&GetFileType(aliasErr)!=3,
      sentinelAbsent=!GetHandleInformation(sentinel,out ignored),stdinType=GetFileType(GetStdHandle(-10)),stdoutType=GetFileType(GetStdHandle(-11)),stderrType=GetFileType(GetStdHandle(-12)),
      pid=Process.GetCurrentProcess().Id,creation=Process.GetCurrentProcess().StartTime.ToUniversalTime().Ticks};
    Console.WriteLine("visible stdout नमस्ते \"quoted\"");Console.Out.Flush();
    Console.Error.WriteLine("visible stderr अलग 🏋️");Console.Error.Flush();
    File.WriteAllText(receipt,new JavaScriptSerializer().Serialize(facts),new UTF8Encoding(false));
    if(mode!="observe-exit")using(var signal=EventWaitHandle.OpenExisting(release)){signal.WaitOne(int.Parse(args[6]));}
    return 0;
  }
}
'@
$taskLauncher=@'
param([string]$TaskCase,[string]$Mode,[string]$Candidate,[string]$Probe,[string]$Release,[int]$Grace,[int]$Lifetime)
$ErrorActionPreference='Stop'
function Quote-VisibleNative([string]$Value) {
  if($Value.Length -gt 0 -and $Value -notmatch '[\s"]'){return $Value}
  return '"'+[regex]::Replace([regex]::Replace($Value,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'
}
function Write-VisibleRecord([string]$Path,$Record) {[IO.File]::WriteAllText($Path,($Record | ConvertTo-Json -Depth 8 -Compress),[Text.UTF8Encoding]::new($false))}
$taskHandleSource=@"
using System;
using System.Runtime.InteropServices;
public static class VisibleFixtureHandles {
  [DllImport("kernel32.dll")] public static extern IntPtr GetStdHandle(int n);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll",SetLastError=true)] public static extern bool DuplicateHandle(IntPtr source,IntPtr handle,IntPtr target,out IntPtr copy,uint access,bool inherit,uint options);
  [DllImport("kernel32.dll",SetLastError=true)] public static extern bool SetHandleInformation(IntPtr h,uint mask,uint flags);
  [DllImport("kernel32.dll")] public static extern bool CloseHandle(IntPtr h);
}
"@
$taskHandleType=Add-Type -TypeDefinition $taskHandleSource -PassThru
$taskSelf=[VisibleFixtureHandles]::GetCurrentProcess()
$taskAliases=[Collections.Generic.List[IntPtr]]::new()
$taskSentinel=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,'Local\visible-sentinel-'+[Guid]::NewGuid().ToString('N'))
$taskSentinelHandle=$taskSentinel.SafeWaitHandle.DangerousGetHandle()
if(-not [VisibleFixtureHandles]::SetHandleInformation($taskSentinelHandle,1,1)){throw 'SENTINEL_SEED_REFUSED'}
foreach($standard in @(-11,-12)) {
  $copy=[IntPtr]::Zero
  if(-not [VisibleFixtureHandles]::DuplicateHandle($taskSelf,[VisibleFixtureHandles]::GetStdHandle($standard),$taskSelf,[ref]$copy,0,$true,2)){throw 'ALIAS_SEED_REFUSED'}
  $taskAliases.Add($copy)
}
$taskProof=Join-Path $TaskCase 'proof'
$taskWork=Join-Path $TaskCase 'work'
$taskStdout=Join-Path $taskProof 'watchdog.stdout.log'
$taskStderr=Join-Path $taskProof 'watchdog.stderr.log'
$taskValues=@('नमस्ते 🏋️','a b','','a"b','tail\','double\\"quote')
$taskArgs=@($Mode,(Join-Path $TaskCase 'child.json'),$Release,$taskAliases[0].ToInt64().ToString(),$taskAliases[1].ToInt64().ToString(),$taskSentinelHandle.ToInt64().ToString(),$Lifetime.ToString())+$taskValues
$taskCommand=($taskArgs | ForEach-Object {Quote-VisibleNative $_}) -join ' '
$taskOwner=$null
$taskResult=@{refused=$false;unchanged=$false;id=0;originalId=0;initiallyExited=$true;refreshedExited=$true;disposedMs=0;exitObserved=$false;exitId=0}
$taskBefore=@{}
try {
  if($Mode -eq 'control-leak') {
    $taskProcess=Start-Process -FilePath $Probe -ArgumentList $taskCommand -WorkingDirectory $taskWork -WindowStyle Hidden -RedirectStandardOutput $taskStdout -RedirectStandardError $taskStderr -PassThru
    $taskResult.id=$taskProcess.Id;$taskResult.originalId=$taskProcess.Id
    $taskProcess.Dispose()
  } else {
    $taskExecutable=$Probe
    switch($Mode) {
      'stdout-existing' {[IO.File]::WriteAllBytes($taskStdout,[byte[]]@(0,255,32,127,10))}
      'stderr-existing' {[IO.File]::WriteAllBytes($taskStderr,[byte[]]@(255,0,13,10,42))}
      'stdout-directory' {[IO.Directory]::CreateDirectory($taskStdout) | Out-Null}
      'stderr-directory' {[IO.Directory]::CreateDirectory($taskStderr) | Out-Null}
      'proof-relative' {$taskProof='proof'}
      'work-relative' {$taskWork='work'}
      'executable-relative' {$taskExecutable='probe.exe'}
      'proof-missing' {$taskProof=Join-Path $TaskCase 'absent-proof'}
      'work-missing' {$taskWork=Join-Path $TaskCase 'absent-work'}
      'executable-missing' {$taskExecutable=Join-Path $TaskCase 'absent.exe'}
      'invalid-image' {$taskExecutable=Join-Path $TaskCase 'invalid.exe';[IO.File]::WriteAllText($taskExecutable,'harmless non executable')}
      'proof-broad-explicit' {
        $acl=[IO.DirectoryInfo]::new($taskProof).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
        [IO.DirectoryInfo]::new($taskProof).SetAccessControl($acl)
      }
      'proof-broad-inherited' {
        $acl=[IO.DirectoryInfo]::new($TaskCase).GetAccessControl([Security.AccessControl.AccessControlSections]::Access)
        $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'ReadAndExecute','ContainerInherit,ObjectInherit','None','Allow'))
        [IO.DirectoryInfo]::new($TaskCase).SetAccessControl($acl)
        $acl=[IO.DirectoryInfo]::new($taskProof).GetAccessControl([Security.AccessControl.AccessControlSections]::Access);$acl.SetAccessRuleProtection($false,$true);[IO.DirectoryInfo]::new($taskProof).SetAccessControl($acl)
      }
      'proof-reparse' {
        $taskLink=Join-Path $TaskCase 'proof-link';New-Item -ItemType Junction -Path $taskLink -Target $taskProof | Out-Null;$taskProof=$taskLink
      }
      'ancestor-reparse' {
        $taskLink=Join-Path $TaskCase 'ancestor-link';New-Item -ItemType Junction -Path $taskLink -Target $taskWork | Out-Null
        $taskProof=Join-Path $taskLink 'inner';[IO.Directory]::CreateDirectory($taskProof) | Out-Null
        $acl=[IO.DirectoryInfo]::new((Join-Path $TaskCase 'proof')).GetAccessControl([Security.AccessControl.AccessControlSections]::Access);[IO.DirectoryInfo]::new($taskProof).SetAccessControl($acl)
      }
      'log-reparse' {
        $taskTarget=Join-Path $TaskCase 'kept.log';[IO.Directory]::CreateDirectory($taskTarget)|Out-Null;[IO.File]::WriteAllText((Join-Path $taskTarget 'preserved.bin'),'keep these bytes')
        New-Item -ItemType Junction -Path $taskStdout -Target $taskTarget | Out-Null
      }
      'proof-escaped' {$taskProof=Join-Path $taskProof '..\proof'}
      'proof-unc' {$taskProof='\\localhost\C$\fr-sealed-20261007\watchdog-handle-visible-20261008'}
    }
    foreach($path in @($taskStdout,$taskStderr,(Join-Path $TaskCase 'kept.log\preserved.bin'))) {if([IO.File]::Exists($path)){$taskBefore[$path]=[Convert]::ToBase64String([IO.File]::ReadAllBytes($path))}}
    if(-not [IO.File]::Exists($Candidate)){throw 'MISSING_VISIBLE_WATCHDOG_CANDIDATE'}
    $taskOpaque=[IO.File]::ReadAllText($Candidate)
    $taskExtent=[regex]::Match($taskOpaque,'(?ms)^\s*\$launcherType\s*=\s*@([''"])\r?\n(?<code>.*?)\r?\n\1@')
    if(-not $taskExtent.Success){throw 'MISSING_VISIBLE_WATCHDOG_CLASS'}
    try {Add-Type -TypeDefinition $taskExtent.Groups['code'].Value -ErrorAction Stop | Out-Null} catch {throw 'OPAQUE_VISIBLE_WATCHDOG_COMPILE_REFUSED'}
    $taskOpaque=$null;$taskExtent=$null
    try {$taskOwner=[NativeDbPrivateSuspended.Watchdog]::new($taskExecutable,$taskCommand,$taskWork,$taskProof,$Grace)} catch {
      $taskResult.refused=$true
      $taskResult.unchanged=$true
      foreach($path in $taskBefore.Keys) {if(-not [IO.File]::Exists($path) -or [Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne $taskBefore[$path]){$taskResult.unchanged=$false}}
      if($Mode -in @('basic','pipes','dispose','observe-exit')){throw 'VISIBLE_CONSTRUCTOR_REFUSED'}
    }
    if($null -ne $taskOwner) {
      $taskResult.id=$taskOwner.Id;$taskResult.originalId=$taskOwner.Id
      $taskResult.initiallyExited=$taskOwner.HasExited;$taskOwner.Refresh();$taskResult.refreshedExited=$taskOwner.HasExited
      if($Mode -eq 'observe-exit') {
        $timer=[Diagnostics.Stopwatch]::StartNew()
        while(-not $taskOwner.HasExited -and $timer.ElapsedMilliseconds -lt $Grace){$taskOwner.Refresh();[Threading.Thread]::Yield() | Out-Null}
        $taskResult.exitObserved=$taskOwner.HasExited;$taskResult.exitId=$taskOwner.Id
      }
      $timer=[Diagnostics.Stopwatch]::StartNew();$taskOwner.Dispose();$timer.Stop();$taskResult.disposedMs=$timer.ElapsedMilliseconds;$taskOwner=$null
    }
  }
  Write-VisibleRecord (Join-Path $TaskCase 'launcher.json') $taskResult
  [Console]::Out.Write('direct-visible-stdout');[Console]::Error.Write('direct-visible-stderr')
} catch {
  Write-VisibleRecord (Join-Path $TaskCase 'launcher-error.json') @{error=$_.Exception.Message}
  exit 23
} finally {
  if($null -ne $taskOwner){$taskOwner.Dispose()}
  foreach($h in $taskAliases){[VisibleFixtureHandles]::CloseHandle($h) | Out-Null}
  $taskSentinel.Dispose()
}
'@

$taskHostProcess=$null;$taskRelease=$null;$taskStarted=[datetime]::UtcNow
try {
  if(-not [IO.Directory]::Exists($TaskRoot)){New-VisibleProtectedDirectory $TaskRoot}
  New-VisibleProtectedDirectory $taskCase
  New-VisibleProtectedDirectory (Join-Path $taskCase 'proof')
  New-VisibleProtectedDirectory (Join-Path $taskCase 'work')
  $taskProbe=Join-Path $taskCase 'probe.exe'
  $taskCompiler=Join-Path $taskCase 'compile.ps1'
  $taskProbeFile=Join-Path $taskCase 'probe.cs'
  [IO.File]::WriteAllText($taskProbeFile,$taskProbeSource,[Text.UTF8Encoding]::new($true))
  [IO.File]::WriteAllText($taskCompiler,'param([string]$Source,[string]$Output);$ErrorActionPreference="Stop";Add-Type -TypeDefinition ([IO.File]::ReadAllText($Source)) -OutputAssembly $Output -OutputType ConsoleApplication -ReferencedAssemblies System.dll,System.Core.dll,System.Web.Extensions.dll',[Text.UTF8Encoding]::new($true))
  $taskCompileInfo=[Diagnostics.ProcessStartInfo]::new($NativePowerShell)
  $taskCompileInfo.UseShellExecute=$false;$taskCompileInfo.CreateNoWindow=$true;$taskCompileInfo.RedirectStandardOutput=$true;$taskCompileInfo.RedirectStandardError=$true
  $taskCompileInfo.Environment['PSModulePath']=$CanonicalModules
  $taskCompileInfo.Arguments=(@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$taskCompiler,'-Source',$taskProbeFile,'-Output',$taskProbe) | ForEach-Object {Quote-VisibleNative $_}) -join ' '
  $taskCompilerProcess=[Diagnostics.Process]::Start($taskCompileInfo)
  try {
    $compileOut=$taskCompilerProcess.StandardOutput.ReadToEndAsync();$compileErr=$taskCompilerProcess.StandardError.ReadToEndAsync()
    if(-not $taskCompilerProcess.WaitForExit($taskLimits.processStopGraceMs)){$taskCompilerProcess.Kill();throw 'VISIBLE_FIXTURE_COMPILER_TIMEOUT'}
    if($taskCompilerProcess.ExitCode -ne 0){throw 'VISIBLE_FIXTURE_COMPILER_FAILED'}
    $null=$compileOut.GetAwaiter().GetResult();$null=$compileErr.GetAwaiter().GetResult()
  } finally {$taskCompilerProcess.Dispose()}
  $taskLauncherPath=Join-Path $taskCase 'launcher.ps1';[IO.File]::WriteAllText($taskLauncherPath,$taskLauncher,[Text.UTF8Encoding]::new($true))
  $taskReleaseName='Local\visible-release-'+$CaseId
  $taskRelease=[Threading.EventWaitHandle]::new($false,[Threading.EventResetMode]::ManualReset,$taskReleaseName)
  $taskStartInfo=[Diagnostics.ProcessStartInfo]::new($NativePowerShell)
  $taskStartInfo.UseShellExecute=$false;$taskStartInfo.CreateNoWindow=$true;$taskStartInfo.RedirectStandardOutput=$true;$taskStartInfo.RedirectStandardError=$true
  $taskStartInfo.StandardOutputEncoding=[Text.UTF8Encoding]::new($false);$taskStartInfo.StandardErrorEncoding=[Text.UTF8Encoding]::new($false)
  $taskStartInfo.Environment['PSModulePath']=$CanonicalModules;$taskStartInfo.Environment['VISIBLE_HANDLE_MARKER']='visible-only: नमस्ते "quoted" \ tail'
  $taskStartInfo.Arguments=(@('-NoLogo','-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$taskLauncherPath,'-TaskCase',$taskCase,'-Mode',$Mode,'-Candidate',$Candidate,'-Probe',$taskProbe,'-Release',$taskReleaseName,'-Grace',$taskLimits.processStopGraceMs.ToString(),'-Lifetime',$taskLimits.nativeCleanupReserveMs.ToString()) | ForEach-Object {Quote-VisibleNative $_}) -join ' '
  $taskHostProcess=[Diagnostics.Process]::Start($taskStartInfo)
  $taskOut=$taskHostProcess.StandardOutput.ReadToEndAsync();$taskErr=$taskHostProcess.StandardError.ReadToEndAsync()
  $taskDirectExited=$taskHostProcess.WaitForExit($taskLimits.processStopGraceMs)
  if(-not $taskDirectExited){$taskHostProcess.Kill();throw 'VISIBLE_DIRECT_LAUNCHER_TIMEOUT'}
  $taskErrorFile=Join-Path $taskCase 'launcher-error.json'
  if([IO.File]::Exists($taskErrorFile)) {
    $taskLaunchError=[IO.File]::ReadAllText($taskErrorFile) | ConvertFrom-Json
    throw $taskLaunchError.error
  }
  if($taskHostProcess.ExitCode -ne 0){throw 'VISIBLE_DIRECT_LAUNCHER_FAILED'}
  $taskEofTimer=[Diagnostics.Stopwatch]::StartNew()
  if($Mode -ne 'control-leak') {
    while((-not $taskOut.IsCompleted -or -not $taskErr.IsCompleted) -and $taskEofTimer.ElapsedMilliseconds -lt $taskLimits.processStopGraceMs){[Threading.Thread]::Yield() | Out-Null}
  }
  $taskBothEof=$taskOut.IsCompleted -and $taskErr.IsCompleted
  $taskLive=@(Get-VisibleOwnedProbe $taskProbe $taskStarted)
  $taskAlive=$taskLive.Count -eq 1 -and -not $taskLive[0].HasExited
  foreach($p in $taskLive){$p.Dispose()}
  $taskChildFile=Join-Path $taskCase 'child.json'
  $taskChildTimer=[Diagnostics.Stopwatch]::StartNew()
  while(-not [IO.File]::Exists($taskChildFile) -and $taskAlive -and $taskChildTimer.ElapsedMilliseconds -lt $taskLimits.processStopGraceMs){[Threading.Thread]::Yield() | Out-Null}
  $taskChild=$null;if([IO.File]::Exists($taskChildFile)){$taskChild=[IO.File]::ReadAllText($taskChildFile) | ConvertFrom-Json}
  $taskLauncherFacts=[IO.File]::ReadAllText((Join-Path $taskCase 'launcher.json')) | ConvertFrom-Json
  $taskLogOut='';$taskLogErr='';$taskLogReadWhileAlive=$false;$taskLogWriteRefusedWhileAlive=$false
  if($null -ne $taskChild -and $Mode -ne 'control-leak') {
    $taskLiveRead=[IO.File]::Open((Join-Path $taskCase 'proof\watchdog.stdout.log'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
      $taskLiveReader=[IO.StreamReader]::new($taskLiveRead)
      try {$taskLogOut=$taskLiveReader.ReadToEnd()} finally {$taskLiveReader.Dispose()}
    } finally {$taskLiveRead.Dispose()}
    $taskLiveRead=[IO.File]::Open((Join-Path $taskCase 'proof\watchdog.stderr.log'),[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
    try {
      $taskLiveReader=[IO.StreamReader]::new($taskLiveRead)
      try {$taskLogErr=$taskLiveReader.ReadToEnd()} finally {$taskLiveReader.Dispose()}
    } finally {$taskLiveRead.Dispose()}
    $taskLogReadWhileAlive=$taskAlive
    $taskWriteDenials=0
    foreach($taskLog in @((Join-Path $taskCase 'proof\watchdog.stdout.log'),(Join-Path $taskCase 'proof\watchdog.stderr.log'))) {
      $taskWriteHandle=$null
      try {$taskWriteHandle=[IO.File]::Open($taskLog,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite)} catch {$taskWriteDenials++} finally {if($null -ne $taskWriteHandle){$taskWriteHandle.Dispose()}}
    }
    $taskLogWriteRefusedWhileAlive=$taskAlive -and $taskWriteDenials -eq 2
  }
  $taskRelease.Set() | Out-Null
  if(-not $taskOut.Wait($taskLimits.processStopGraceMs) -or -not $taskErr.Wait($taskLimits.processStopGraceMs)){throw 'VISIBLE_RELEASED_PIPE_TIMEOUT'}
  $taskRawOut=$taskOut.GetAwaiter().GetResult();$taskRawErr=$taskErr.GetAwaiter().GetResult()
  $taskSurvivors=0
  if($taskLauncherFacts.refused){$taskUnexpected=@(Get-VisibleOwnedProbe $taskProbe $taskStarted);$taskSurvivors=$taskUnexpected.Count;foreach($p in $taskUnexpected){$p.Dispose()}}
  Write-VisibleRecord (Join-Path $taskCase 'result.json') @{directExited=$taskDirectExited;bothEofBeforeRelease=$taskBothEof;stdout=$taskRawOut;stderr=$taskRawErr;childAlive=$taskAlive;child=$taskChild;launcher=$taskLauncherFacts;survivorCount=$taskSurvivors;logOut=$taskLogOut;logErr=$taskLogErr;logReadWhileAlive=$taskLogReadWhileAlive;logWriteRefusedWhileAlive=$taskLogWriteRefusedWhileAlive}
  [Console]::Out.Write([IO.File]::ReadAllText((Join-Path $taskCase 'result.json')))
} catch {
  Write-VisibleRecord (Join-Path $taskCase 'result-error.json') @{error=$_.Exception.Message}
  [Console]::Out.Write([IO.File]::ReadAllText((Join-Path $taskCase 'result-error.json')))
  exit 1
} finally {
  if($null -ne $taskRelease){$taskRelease.Set() | Out-Null;$taskRelease.Dispose()}
  if($null -ne $taskHostProcess){try {if(-not $taskHostProcess.HasExited){$taskHostProcess.Kill();$null=$taskHostProcess.WaitForExit($taskLimits.processStopGraceMs)}} finally {$taskHostProcess.Dispose()}}
  if($null -ne $taskProbe){Stop-VisibleOwnedProbes $taskProbe $taskStarted $taskLimits.processStopGraceMs}
}
`;

function visibleWatchdogFixture(mode: string): VisibleWatchdogRecord & { logOut?: string; logErr?: string } {
  const metadata = visibleWatchdogMetadata;
  const result = spawnSync(metadata.ps7, ['-NoLogo', '-NoProfile', '-NonInteractive', '-File', visibleWatchdogHostFile, '-TaskRoot', metadata.root, '-CaseId', randomUUID(), '-Mode', mode, '-Candidate', metadata.candidate, '-NativePowerShell', metadata.ps5, '-CanonicalModules', metadata.modules, '-LimitsPath', metadata.limits], {
    windowsHide: true,
    timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs,
    maxBuffer: NATIVE_DB_VALIDATION.maxProcessBytes,
    encoding: 'utf8',
  });
  if (result.error) throw new Error(`VISIBLE_FIXTURE_HOST_FAILED:${result.error.name}`);
  let record: VisibleWatchdogRecord;
  try { record = JSON.parse(result.stdout.trim()) as VisibleWatchdogRecord; } catch { throw new Error('VISIBLE_FIXTURE_INVALID_REPORT'); }
  if (record.error) throw new Error(record.error);
  expect(result.status).toBe(0);
  return record;
}

function registerVisibleWatchdogHandleCase(name: string, run: () => void): void {
  test(name, { skip: platform() !== 'win32', timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs }, run);
}

beforeAll(() => {
  if (platform() !== 'win32') return;
  expect(createHash('sha256').update(readFileSync(visibleWatchdogMetadata.limits)).digest('hex')).toBe(visibleWatchdogMetadata.limitsHash);
  const setup = `$ErrorActionPreference='Stop';foreach($target in @('${visibleWatchdogMetadata.ps7}','${visibleWatchdogMetadata.modules}')){$item=Get-Item -LiteralPath $target;while($null -ne $item){if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'VISIBLE_HOST_REPARSE_REFUSED'};$item=$item.Parent;if($null -eq $item -and $target -eq '${visibleWatchdogMetadata.ps7}'){$target='';$item=(Get-Item -LiteralPath '${visibleWatchdogMetadata.ps7}').Directory}}};if($PSVersionTable.PSVersion.Major -ne 7){throw 'VISIBLE_HOST_VERSION_REFUSED'};$root='${visibleWatchdogMetadata.root}';[IO.Directory]::CreateDirectory($root)|Out-Null;$acl=[IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($root),[Security.AccessControl.AccessControlSections]::Access);$acl.SetAccessRuleProtection($true,$false);foreach($rule in @($acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]))){$acl.RemoveAccessRuleAll($rule)};$owner=[Security.Principal.WindowsIdentity]::GetCurrent().User;foreach($sid in @($owner,[Security.Principal.SecurityIdentifier]::new('S-1-5-18'),[Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))){$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow'))};[IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($root),$acl)`;
  const result = spawnSync(visibleWatchdogMetadata.ps7, ['-NoLogo', '-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(setup, 'utf16le').toString('base64')], { windowsHide: true, timeout: NATIVE_DB_VALIDATION.processStopGraceMs });
  writeFileSync(`${visibleWatchdogMetadata.root}\\setup-${randomUUID()}.json`, JSON.stringify({ status: result.status, stdout: result.stdout?.toString(), stderr: result.stderr?.toString(), error: result.error?.name }), 'utf8');
  expect(result.status).toBe(0);
  visibleWatchdogHostFile = `${visibleWatchdogMetadata.root}\\host-${randomUUID()}.ps1`;
  writeFileSync(visibleWatchdogHostFile, visibleWatchdogNativeScript, 'utf8');
}, NATIVE_DB_VALIDATION.processStopGraceMs);

registerVisibleWatchdogHandleCase('independent duplicated-pipe fixture control', () => {
  const result = visibleWatchdogFixture('control-leak');
  expect(result.directExited).toBe(true);
  expect(result.childAlive).toBe(true);
  expect(result.bothEofBeforeRelease).toBe(false);
  expect(result.child?.aliasesAbsent).toBe(false);
  expect(result.child?.sentinelAbsent).toBe(false);
  expect(result.stdout).toBe('direct-visible-stdout');
  expect(result.stderr).toBe('direct-visible-stderr');
});

registerVisibleWatchdogHandleCase('outer pipe EOF independently completes while child lives', () => {
  const result = visibleWatchdogFixture('pipes');
  expect(result.directExited).toBe(true);
  expect(result.bothEofBeforeRelease).toBe(true);
  expect(result.childAlive).toBe(true);
  expect(result.stdout).toBe('direct-visible-stdout');
  expect(result.stderr).toBe('direct-visible-stderr');
  expect(result.child?.aliasesAbsent).toBe(true);
  expect(result.child?.sentinelAbsent).toBe(true);
});

registerVisibleWatchdogHandleCase('private standard handles preserve native child semantics', () => {
  const result = visibleWatchdogFixture('basic');
  expect(result.child?.arguments).toEqual(visibleWatchdogMetadata.expectedArguments);
  expect(result.child?.marker).toBe(visibleWatchdogMetadata.marker);
  expect(result.child?.cwd?.endsWith('\\work')).toBe(true);
  expect(result.child?.hidden).toBe(true);
  expect(result.child?.nulInput).toBe(true);
  expect(result.child?.stdinType).toBe(2);
  expect(result.child?.stdoutType).toBe(1);
  expect(result.child?.stderrType).toBe(1);
  expect(result.logOut).toBe('visible stdout नमस्ते "quoted"\r\n');
  expect(result.logErr).toBe('visible stderr अलग 🏋️\r\n');
  expect(result.logReadWhileAlive).toBe(true);
  expect(result.logWriteRefusedWhileAlive).toBe(true);
});

registerVisibleWatchdogHandleCase('successful disposal closes promptly without child termination', () => {
  const result = visibleWatchdogFixture('dispose');
  expect(result.launcher?.id).toBeGreaterThan(0);
  expect(result.launcher?.id).toBe(result.launcher?.originalId);
  expect(result.launcher?.initiallyExited).toBe(false);
  expect(result.launcher?.refreshedExited).toBe(false);
  expect(result.launcher?.disposedMs).toBeLessThan(NATIVE_DB_VALIDATION.processStopGraceMs);
  expect(result.childAlive).toBe(true);
});

registerVisibleWatchdogHandleCase('original handle observes child exit with stable identity', () => {
  const result = visibleWatchdogFixture('observe-exit');
  expect(result.launcher?.id).toBeGreaterThan(0);
  expect(result.launcher?.exitObserved).toBe(true);
  expect(result.launcher?.exitId).toBe(result.launcher?.originalId);
});

for (const mode of ['stdout-existing', 'stderr-existing', 'stdout-directory', 'stderr-directory', 'proof-relative', 'work-relative', 'executable-relative', 'proof-missing', 'work-missing', 'executable-missing', 'invalid-image', 'proof-broad-explicit', 'proof-broad-inherited', 'proof-reparse', 'ancestor-reparse', 'log-reparse', 'proof-escaped', 'proof-unc']) {
  registerVisibleWatchdogHandleCase(`construction refusal ${mode}`, () => {
    const result = visibleWatchdogFixture(mode);
    expect(result.launcher?.refused).toBe(true);
    expect(result.launcher?.unchanged).toBe(true);
    expect(result.childAlive).toBe(false);
    expect(result.survivorCount).toBe(0);
    expect(result.bothEofBeforeRelease).toBe(true);
  });
}
