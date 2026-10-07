import { execFile } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { platform } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { expect, test } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

const heldHandlePs7 = 'C:\\Users\\Harsh\\.cache\\codex-runtimes\\codex-primary-runtime\\dependencies\\native\\powershell\\pwsh.exe';
const heldHandleCandidate = 'C:\\fr-sealed-20261007\\start-listener-suspended-trial9.ps1';
const heldHandleOutput = 'C:\\fr-sealed-20261007\\watchdog-handle-held-20261008';
const heldHandleLimitsPath = 'C:\\fr-sealed-20261007\\watchdog-limits.json';
const heldHandleLimitsHash = '5799d0354e2cf671851f3e6016ea37de9d98e1441559ec724b2db0805c003320';
const heldHandleExec = promisify(execFile);

interface HeldHandleLimits {
  processStopGraceMs: number;
  nativeCleanupReserveMs: number;
  maxProcessBytes: number;
  timeoutQueryMaxBytes: number;
  millisecondsPerSecond: number;
}

interface HeldHandleReceipt {
  directExit: boolean;
  stdoutEof: boolean;
  stderrEof: boolean;
  outerExitCode: number;
  outerStdout: string;
  outerStderr: string;
  childAliveAtEof: boolean;
  childAliveAfterDispose: boolean;
  stdoutWriteRefused: boolean;
  stderrWriteRefused: boolean;
  privateStdout: string | null;
  privateStderr: string | null;
  failedChildrenRemaining: number;
  retainedBytes: string | null;
  launcher: {
    refused: boolean;
    message: string | null;
    id: number;
    idAfterRefresh: number;
    exitedInitially: boolean;
    exitedAfterRefresh: boolean;
    disposeMs: number;
    signature: boolean;
    leakedObjects: string[];
    modulePath: string;
  };
  child: {
    id: number;
    arguments: string[];
    environment: string;
    modulePath: string;
    seededObjects: number;
    stdinEof: number;
    stdinName: string;
    stdoutPath: string;
    stderrPath: string;
    console: string;
    vendorCommands?: string[];
  } | null;
}

// This fixture owns its native handles and job. It never substitutes a constructor.
const heldHandleNativeSource = String.raw`
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
namespace HeldHandleIsolationFixture {
 public static class Native {
  public enum Access : uint { Read = 0x80000000, QueryProcess = 0x1000, QueryThread = 0x0800, Synchronize = 0x00100000, DuplicateProcessHandle = 0x0040 }
  public enum Share : uint { Read = 1 }
  public enum Creation : uint { OpenExisting = 3 }
  public enum Duplicate : uint { SameAccess = 2 }
  public enum JobClass : int { BasicProcessIds = 3, ExtendedLimits = 9 }
  public enum JobFlags : uint { KillOnClose = 0x2000 }
  public enum InformationClass : int { ExtendedHandles = 64, ObjectName = 1 }
  public enum HandleFlags : uint { Inherit = 1 }
  public enum ErrorCode : int { InvalidHandle = 6 }
  public enum Standard : int { Input = -10, Output = -11, Error = -12 }
  public enum NtStatus : int { BufferTooSmall = unchecked((int)0xc0000004) }
  [StructLayout(LayoutKind.Sequential)] public struct Security { public int Length; public IntPtr Descriptor; public int Inherit; }
  [StructLayout(LayoutKind.Sequential)] public struct BasicLimit { public long PerProcess; public long PerJob; public uint Flags; public UIntPtr Min; public UIntPtr Max; public uint Active; public UIntPtr Affinity; public uint Priority; public uint Scheduling; }
  [StructLayout(LayoutKind.Sequential)] public struct Io { public ulong ReadCount, WriteCount, OtherCount, ReadBytes, WriteBytes, OtherBytes; }
  [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimit { public BasicLimit Basic; public Io Counters; public UIntPtr ProcessMemory, JobMemory, PeakProcess, PeakJob; }
  [StructLayout(LayoutKind.Sequential)] public struct HandleRow { public IntPtr Object, Pid, Value; public uint Access; public ushort Backtrace, Type; public uint Attributes, Reserved; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateEventW(ref Security security, bool manual, bool initial, string name);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateFileW(string path, Access access, Share share, ref Security security, Creation creation, uint flags, IntPtr template);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern IntPtr CreateJobObjectW(IntPtr security, string name);
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode, EntryPoint="CreateJobObjectW")] static extern IntPtr CreateInheritableJob(ref Security security, string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool SetInformationJobObject(IntPtr job, JobClass kind, ref ExtendedLimit value, uint length);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool QueryInformationJobObject(IntPtr job, JobClass kind, IntPtr value, uint length, out uint returned);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool CloseHandle(IntPtr handle);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool DuplicateHandle(IntPtr from, IntPtr source, IntPtr to, out IntPtr result, uint access, bool inherit, Duplicate flags);
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll")] static extern uint GetCurrentProcessId();
  [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
  [DllImport("kernel32.dll")] static extern uint GetProcessId(IntPtr handle);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool GetHandleInformation(IntPtr handle, out HandleFlags flags);
  [DllImport("kernelbase.dll", SetLastError=true)] static extern bool CompareObjectHandles(IntPtr first, IntPtr second);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(Access access, bool inherit, uint id);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenThread(Access access, bool inherit, uint id);
  [DllImport("kernel32.dll")] static extern IntPtr GetStdHandle(Standard standard);
  [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] static extern uint GetFinalPathNameByHandleW(IntPtr handle, StringBuilder path, uint length, uint flags);
  [DllImport("ntdll.dll")] static extern int NtQuerySystemInformation(InformationClass kind, IntPtr value, int length, out int returned);
  [DllImport("ntdll.dll")] static extern int NtQueryObject(IntPtr handle, InformationClass kind, IntPtr value, int length, out int returned);
  static void Good(IntPtr value) { if(value == IntPtr.Zero || value == new IntPtr(-1)) throw new Exception("held fixture native operation failed"); }
  public static IntPtr NewJob() {
   IntPtr job=CreateJobObjectW(IntPtr.Zero,null); Good(job);
   ExtendedLimit limits=new ExtendedLimit(); limits.Basic.Flags=(uint)JobFlags.KillOnClose;
   if(!SetInformationJobObject(job,JobClass.ExtendedLimits,ref limits,(uint)Marshal.SizeOf(typeof(ExtendedLimit)))) { CloseHandle(job); throw new Exception("held fixture job refused"); }
   return job;
  }
  public static int JobCount(IntPtr job, int initial, int ceiling) {
   for(int bytes=initial;bytes<=ceiling;bytes=checked(bytes*2)) {
    IntPtr data=Marshal.AllocHGlobal(bytes);
    try { uint returned; if(QueryInformationJobObject(job,JobClass.BasicProcessIds,data,(uint)bytes,out returned)) return Marshal.ReadInt32(data,4); }
    finally { Marshal.FreeHGlobal(data); }
   }
   throw new Exception("held fixture job observation refused");
  }
  public static IntPtr[] Seed(string marker, string file) {
   Security security=new Security(); security.Length=Marshal.SizeOf(typeof(Security)); security.Inherit=1;
   List<IntPtr> handles=new List<IntPtr>();
   try {
    IntPtr value=CreateEventW(ref security,true,true,"Local\\HeldSentinel-"+marker); Good(value); handles.Add(value);
    value=CreateFileW(file,Access.Read,Share.Read,ref security,Creation.OpenExisting,0,IntPtr.Zero); Good(value); handles.Add(value);
    value=CreateInheritableJob(ref security,"Local\\HeldSeedJob-"+marker); Good(value); handles.Add(value);
    value=OpenProcess(Access.QueryProcess|Access.Synchronize,true,GetCurrentProcessId()); Good(value); handles.Add(value);
    value=OpenThread(Access.QueryThread|Access.Synchronize,true,GetCurrentThreadId()); Good(value); handles.Add(value);
    foreach(Standard standard in new Standard[]{Standard.Output,Standard.Error}) {
     if(!DuplicateHandle(GetCurrentProcess(),GetStdHandle(standard),GetCurrentProcess(),out value,0,true,Duplicate.SameAccess)) throw new Exception("held fixture duplicate refused");
     Good(value); handles.Add(value);
    }
    return handles.ToArray();
   } catch { foreach(IntPtr handle in handles) CloseHandle(handle); throw; }
  }
  static HandleRow[] Rows(int initial, int ceiling) {
   int bytes=initial;
   while(bytes<=ceiling) {
    IntPtr data=Marshal.AllocHGlobal(bytes);
    int needed;
    try {
     int status=NtQuerySystemInformation(InformationClass.ExtendedHandles,data,bytes,out needed);
     if(status==0) {
      long count=Marshal.ReadIntPtr(data).ToInt64(); int size=Marshal.SizeOf(typeof(HandleRow));
      if(count<0 || count>(bytes-2*IntPtr.Size)/size) throw new Exception("held fixture handle observation invalid");
      HandleRow[] rows=new HandleRow[count];
      for(int i=0;i<count;i++) rows[i]=(HandleRow)Marshal.PtrToStructure(IntPtr.Add(data,2*IntPtr.Size+i*size),typeof(HandleRow));
      return rows;
     }
     if(status!=(int)NtStatus.BufferTooSmall) throw new Exception("held fixture handle observation refused");
    } finally { Marshal.FreeHGlobal(data); }
    bytes=checked(Math.Max(bytes*2,needed+initial));
   }
   throw new Exception("held fixture handle observation exceeds sealed bound");
  }
  public static string[] SeedObjects(IntPtr[] handles, int initial, int ceiling) {
   List<string> objects=new List<string>();
   foreach(IntPtr handle in handles) {
    HandleFlags flags;
    if(!GetHandleInformation(handle,out flags) || (flags & HandleFlags.Inherit)==0) throw new Exception("held fixture seed is not inheritable");
    objects.Add(handle.ToInt64().ToString());
   }
   return objects.ToArray();
  }
  public static string[] ObserveChildObjects(IntPtr[] seeds, int childPid, int initial, int ceiling) {
   IntPtr child=OpenProcess(Access.DuplicateProcessHandle|Access.QueryProcess|Access.Synchronize,false,(uint)childPid); Good(child);
   try {
    if(GetProcessId(child)!=childPid) throw new Exception("held fixture exact child identity unavailable");
    HashSet<string> leaked=new HashSet<string>(); HandleRow[] rows=Rows(initial,ceiling);
    HashSet<ushort> seedTypes=new HashSet<ushort>();
    foreach(IntPtr seed in seeds) {
     bool found=false;
     foreach(HandleRow row in rows) if(row.Pid.ToInt64()==GetCurrentProcessId() && row.Value==seed) { seedTypes.Add(row.Type); found=true; break; }
     if(!found) throw new Exception("held fixture stable seed absent from inventory");
    }
    foreach(HandleRow row in rows) if(row.Pid.ToInt64()==childPid && seedTypes.Contains(row.Type)) {
     IntPtr duplicate;
     if(!DuplicateHandle(child,row.Value,GetCurrentProcess(),out duplicate,0,false,Duplicate.SameAccess)) {
      if(Marshal.GetLastWin32Error()==(int)ErrorCode.InvalidHandle) continue;
      throw new Exception("held fixture child handle observation refused ("+Marshal.GetLastWin32Error()+")");
     }
     try { for(int i=0;i<seeds.Length;i++) if(CompareObjectHandles(seeds[i],duplicate)) leaked.Add(i.ToString()); }
     finally { CloseHandle(duplicate); }
    }
    string[] answer=new string[leaked.Count]; leaked.CopyTo(answer); return answer;
   } finally { CloseHandle(child); }
  }
  public static string StandardPath(Standard standard) {
   StringBuilder value=new StringBuilder(32768); uint count=GetFinalPathNameByHandleW(GetStdHandle(standard),value,(uint)value.Capacity,0);
   if(count==0 || count>=value.Capacity) throw new Exception("held fixture standard path unavailable");
   return value.ToString();
  }
  public static string InputName(int initial) {
   IntPtr data=Marshal.AllocHGlobal(initial);
   try { int needed; if(NtQueryObject(GetStdHandle(Standard.Input),InformationClass.ObjectName,data,initial,out needed)!=0) throw new Exception("held fixture input observation refused"); return Marshal.PtrToStringUni(Marshal.ReadIntPtr(data,IntPtr.Size),Marshal.ReadInt16(data)/2); }
   finally { Marshal.FreeHGlobal(data); }
  }
 }
}
`;

const heldHandleChildMain = String.raw`
public static class HeldHandleChild {
 public static void Main(string[] args) {
  System.Web.Script.Serialization.JavaScriptSerializer json=new System.Web.Script.Serialization.JavaScriptSerializer();
  var request=json.Deserialize<System.Collections.Generic.Dictionary<string,object>>(System.IO.File.ReadAllText(args[0]));
  var limits=(System.Collections.Generic.Dictionary<string,object>)request["Limits"];
  var seeds=json.Deserialize<string[]>(System.IO.File.ReadAllText(args[8]));
  int initial=System.Convert.ToInt32(limits["timeoutQueryMaxBytes"]), ceiling=System.Convert.ToInt32(limits["maxProcessBytes"]);
  System.Console.OutputEncoding=new System.Text.UTF8Encoding(false);
  System.Console.WriteLine((string)request["StdoutText"]); System.Console.Error.WriteLine((string)request["StderrText"]);
  var answer=new System.Collections.Generic.Dictionary<string,object>();
  answer["id"]=System.Diagnostics.Process.GetCurrentProcess().Id; answer["arguments"]=args;
  answer["environment"]=System.Environment.GetEnvironmentVariable("GYMLOOP_HELD_HANDLE_MARKER");
  answer["modulePath"]=System.Environment.GetEnvironmentVariable("PSModulePath");
  answer["seededObjects"]=seeds.Length;
  answer["stdinEof"]=System.Console.In.Read(); answer["stdinName"]=HeldHandleIsolationFixture.Native.InputName(initial);
  answer["stdoutPath"]=HeldHandleIsolationFixture.Native.StandardPath(HeldHandleIsolationFixture.Native.Standard.Output);
  answer["stderrPath"]=HeldHandleIsolationFixture.Native.StandardPath(HeldHandleIsolationFixture.Native.Standard.Error);
  answer["console"]=HeldHandleIsolationFixture.Native.GetConsoleWindow().ToInt64().ToString();
  System.IO.File.WriteAllText((string)request["ChildReceipt"],json.Serialize(answer),new System.Text.UTF8Encoding(false));
  using(var ready=System.Threading.EventWaitHandle.OpenExisting(args[6])) using(var release=System.Threading.EventWaitHandle.OpenExisting(args[7])) {
   ready.Set(); if(!release.WaitOne(System.Convert.ToInt32(limits["nativeCleanupReserveMs"]))) System.Environment.Exit(1);
  }
 }
}
`;

const heldHandleNativeChildScript = String.raw`
param([string]$RequestPath,[string]$Marker,[string]$Unicode,[string]$Quoted,[string]$Empty,[string]$Trailing,[string]$ReadyName,[string]$ReleaseName,[string]$SeedPath)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Type -TypeDefinition ([IO.File]::ReadAllText($request.NativeSource))
$seeds=[string[]](Get-Content -LiteralPath $SeedPath -Raw -Encoding UTF8 | ConvertFrom-Json)
$limits=$request.Limits
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::WriteLine($request.StdoutText); [Console]::Error.WriteLine($request.StderrText)
$commands=@('Get-FileHash','ConvertTo-Json','Get-Item','Get-Acl') | ForEach-Object { (Get-Command -Name $_ -ErrorAction Stop).Module.Path }
$receipt=@{
 id=$PID; arguments=@($RequestPath,$Marker,$Unicode,$Quoted,$Empty,$Trailing,$ReadyName,$ReleaseName,$SeedPath)
 environment=[Environment]::GetEnvironmentVariable('GYMLOOP_HELD_HANDLE_MARKER'); modulePath=[Environment]::GetEnvironmentVariable('PSModulePath')
 seededObjects=$seeds.Count
 stdinEof=[Console]::In.Read(); stdinName=[HeldHandleIsolationFixture.Native]::InputName($limits.timeoutQueryMaxBytes)
 stdoutPath=[HeldHandleIsolationFixture.Native]::StandardPath([HeldHandleIsolationFixture.Native+Standard]::Output)
 stderrPath=[HeldHandleIsolationFixture.Native]::StandardPath([HeldHandleIsolationFixture.Native+Standard]::Error)
 console=[HeldHandleIsolationFixture.Native]::GetConsoleWindow().ToInt64().ToString(); vendorCommands=@($commands)
}
[IO.File]::WriteAllText($request.ChildReceipt,($receipt | ConvertTo-Json -Depth 10), (New-Object Text.UTF8Encoding($false)))
$ready=[Threading.EventWaitHandle]::OpenExisting($ReadyName); $release=[Threading.EventWaitHandle]::OpenExisting($ReleaseName)
try { [void]$ready.Set(); if(!$release.WaitOne([int]$limits.nativeCleanupReserveMs)){ exit 1 } } finally { $ready.Dispose(); $release.Dispose() }
`;

const heldHandleLauncherScript = String.raw`
param([string]$RequestPath)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$limits=$request.Limits
$allowed=[Threading.EventWaitHandle]::OpenExisting($request.AllowName)
try { if(!$allowed.WaitOne([int]$limits.processStopGraceMs)){ throw 'held fixture launch permission expired' } } finally { $allowed.Dispose() }
Add-Type -TypeDefinition ([IO.File]::ReadAllText($request.NativeSource))
$errors=$null; $tokens=$null
$ast=[Management.Automation.Language.Parser]::ParseFile($request.Candidate,[ref]$tokens,[ref]$errors)
if($errors.Count){ throw 'opaque candidate parse failed' }
$bindings=@($ast.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq 'launcherType' },$true))
if($bindings.Count -ne 1){ throw 'opaque candidate launcher type missing' }
$opaque=$bindings[0].Right.Expression.SafeGetValue()
if($opaque -isnot [string]){ throw 'opaque candidate launcher type invalid' }
Add-Type -TypeDefinition $opaque | Out-Null
$watchdogType='NativeDbPrivateSuspended.Watchdog' -as [type]
if(!$watchdogType){ throw 'opaque candidate private class missing' }
$ctor=$watchdogType.GetConstructor([type[]]@([string],[string],[string],[string],[int]))
$signature=$null -ne $ctor -and $watchdogType.GetProperty('Id').PropertyType -eq [int] -and $watchdogType.GetProperty('HasExited').PropertyType -eq [bool]
foreach($method in @('Refresh','Dispose')) { $info=$watchdogType.GetMethod($method,[type[]]@()); $signature=$signature -and $null -ne $info -and $info.ReturnType -eq [void] }
if(!$signature){ throw 'private observation signature differs from contract' }
function HeldFixtureQuote([string]$Value) {
 $out=New-Object Text.StringBuilder; [void]$out.Append('"'); $slashes=0
 foreach($character in $Value.ToCharArray()) {
  if($character -eq '\'){ $slashes++; continue }
  if($character -eq '"'){ [void]$out.Append(('\' * ($slashes*2+1))); [void]$out.Append('"'); $slashes=0; continue }
  [void]$out.Append(('\' * $slashes)); [void]$out.Append($character); $slashes=0
 }
 [void]$out.Append(('\' * ($slashes*2))); [void]$out.Append('"'); return $out.ToString()
}
$handles=[HeldHandleIsolationFixture.Native]::Seed($request.Marker,$request.SentinelPath)
$watchdog=$null; $ready=$null; $release=$null
$answer=@{refused=$false;message=$null;id=0;idAfterRefresh=0;exitedInitially=$false;exitedAfterRefresh=$false;disposeMs=0;signature=$signature;leakedObjects=@();modulePath=[Environment]::GetEnvironmentVariable('PSModulePath')}
try {
 $objects=[HeldHandleIsolationFixture.Native]::SeedObjects($handles,$limits.timeoutQueryMaxBytes,$limits.maxProcessBytes)
 [IO.File]::WriteAllText($request.SeedPath,(ConvertTo-Json -InputObject ([object[]]$objects)),(New-Object Text.UTF8Encoding($false)))
 $arguments=@($request.ChildArguments | ForEach-Object { HeldFixtureQuote ([string]$_) }) -join ' '
 try { $watchdog=$ctor.Invoke([object[]]@([string]$request.Executable,[string]$arguments,[string]$request.Directory,[string]$request.Proof,[int]$limits.processStopGraceMs)) }
 catch { $answer.refused=$true; $errorValue=$_.Exception; while($errorValue.InnerException){ $errorValue=$errorValue.InnerException }; $answer.message=$errorValue.Message }
 if($null -ne $watchdog) {
  $answer.id=[int]$watchdog.Id; $watchdog.Refresh(); $answer.idAfterRefresh=[int]$watchdog.Id; $answer.exitedInitially=[bool]$watchdog.HasExited
  $ready=[Threading.EventWaitHandle]::OpenExisting($request.ReadyName); $release=[Threading.EventWaitHandle]::OpenExisting($request.ReleaseName)
  if(!$ready.WaitOne([int]$limits.processStopGraceMs)){ throw 'held fixture child did not become observable' }
  $answer.leakedObjects=@([HeldHandleIsolationFixture.Native]::ObserveChildObjects($handles,$answer.id,$limits.timeoutQueryMaxBytes,$limits.maxProcessBytes))
  if($request.Mode -eq 'refresh') {
   [void]$release.Set(); $clock=[Diagnostics.Stopwatch]::StartNew()
   while(!$watchdog.HasExited -and $clock.ElapsedMilliseconds -lt $limits.processStopGraceMs){ $watchdog.Refresh(); [Threading.Thread]::Yield() | Out-Null }
   $watchdog.Refresh(); $answer.idAfterRefresh=[int]$watchdog.Id; $answer.exitedAfterRefresh=[bool]$watchdog.HasExited
  }
  $clock=[Diagnostics.Stopwatch]::StartNew(); $watchdog.Dispose(); $clock.Stop(); $answer.disposeMs=$clock.ElapsedMilliseconds; $watchdog=$null
 }
 [IO.File]::WriteAllText($request.LauncherReceipt,($answer | ConvertTo-Json -Depth 10),(New-Object Text.UTF8Encoding($false)))
 [Console]::WriteLine('HELD-DIRECT-OUT'); [Console]::Error.WriteLine('HELD-DIRECT-ERR')
} finally {
 if($null -ne $watchdog){ $watchdog.Dispose() }
 if($null -ne $ready){ $ready.Dispose() }; if($null -ne $release){ $release.Dispose() }
 foreach($handle in $handles){ [void][HeldHandleIsolationFixture.Native]::CloseHandle($handle) }
}
`;

const heldHandleDriverScript = String.raw`
param([string]$RequestPath)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$limits=$request.Limits
function HeldFixtureProtect([string]$Path) {
 [void][IO.Directory]::CreateDirectory($Path)
 $owner=[Security.Principal.WindowsIdentity]::GetCurrent().User
 $acl=New-Object Security.AccessControl.DirectorySecurity
 $acl.SetOwner($owner); $acl.SetAccessRuleProtection($true,$false)
 foreach($sid in @($owner,(New-Object Security.Principal.SecurityIdentifier('S-1-5-18')),(New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))) {
  $rule=New-Object Security.AccessControl.FileSystemAccessRule($sid,[Security.AccessControl.FileSystemRights]::FullControl,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
  [void]$acl.AddAccessRule($rule)
 }
 [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path),$acl)
}
function HeldFixtureBroad([string]$Path,[bool]$Inherited) {
 $target=$Path
 if($Inherited){ $target=[IO.Directory]::GetParent($Path).FullName }
 $acl=[IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($target),[Security.AccessControl.AccessControlSections]::Access)
 $rule=New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')),[Security.AccessControl.FileSystemRights]::ReadAndExecute,([Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit),[Security.AccessControl.PropagationFlags]::None,[Security.AccessControl.AccessControlType]::Allow)
 [void]$acl.AddAccessRule($rule); [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($target),$acl)
 if($Inherited){ $childAcl=[IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($Path),[Security.AccessControl.AccessControlSections]::Access); $childAcl.SetAccessRuleProtection($false,$true); [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path),$childAcl) }
}
function HeldFixtureOrdinary([string]$Path) {
 $full=[IO.Path]::GetFullPath($Path)
 if($full -cne $Path -or !$full.StartsWith([IO.Path]::GetPathRoot($full),[StringComparison]::OrdinalIgnoreCase)){ throw 'held fixture executable metadata not absolute' }
 $entry=Get-Item -LiteralPath $Path -Force
 while($null -ne $entry){ if($entry.Attributes -band [IO.FileAttributes]::ReparsePoint){ throw 'held fixture executable metadata reparsed' }; if($entry -is [IO.FileInfo]){ $entry=$entry.Directory } else { $entry=$entry.Parent } }
}
function HeldFixtureRead([string]$Path) {
 $stream=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::ReadWrite)
 $reader=New-Object IO.StreamReader($stream,(New-Object Text.UTF8Encoding($false)),$true)
 try { return $reader.ReadToEnd() } finally { $reader.Dispose(); $stream.Dispose() }
}
function HeldFixtureCanWriteLog([string]$Path) {
 try { $writer=[IO.File]::Open($Path,[IO.FileMode]::Open,[IO.FileAccess]::Write,[IO.FileShare]::ReadWrite); $writer.Dispose(); return $true } catch [IO.IOException] { return $false }
}
HeldFixtureOrdinary $request.Ps7
HeldFixtureOrdinary $request.NativePs5
HeldFixtureOrdinary $request.NativeModules
if($PSVersionTable.PSVersion.Major -ne 7){ throw 'held fixture host is not PowerShell7' }
HeldFixtureProtect $request.Root; HeldFixtureProtect $request.Proof; HeldFixtureProtect $request.Directory
Add-Type -TypeDefinition ([IO.File]::ReadAllText($request.NativeSource))
$setup=New-Object Diagnostics.ProcessStartInfo
$setup.FileName=$request.NativePs5; $setup.UseShellExecute=$false; $setup.CreateNoWindow=$true; $setup.RedirectStandardOutput=$true; $setup.RedirectStandardError=$true
$setup.Environment['PSModulePath']=$request.NativeModules
foreach($argument in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$request.CompileScript,$RequestPath)){ $setup.ArgumentList.Add($argument) }
$setupChild=[Diagnostics.Process]::Start($setup)
try {
 $setupOut=$setupChild.StandardOutput.ReadToEndAsync(); $setupErr=$setupChild.StandardError.ReadToEndAsync()
 if(!$setupChild.WaitForExit([int]$limits.nativeCleanupReserveMs)){ $setupChild.Kill(); throw 'held fixture compiler exceeded sealed bound' }
 [void]$setupOut.GetAwaiter().GetResult(); $compileError=$setupErr.GetAwaiter().GetResult()
 if($setupChild.ExitCode -ne 0){ throw ('held fixture compilation failed: '+$compileError) }
} finally { $setupChild.Dispose() }
[IO.File]::WriteAllText($request.SentinelPath,'private held sentinel', (New-Object Text.UTF8Encoding($false)))
$originalBytes=$null
$heldAclChallenge=$null
switch($request.Variant) {
 'existing-stdout' { $originalBytes='unchanged held stdout'; [IO.File]::WriteAllText((Join-Path $request.Proof 'watchdog.stdout.log'),$originalBytes) }
 'existing-stderr' { $originalBytes='unchanged held stderr'; [IO.File]::WriteAllText((Join-Path $request.Proof 'watchdog.stderr.log'),$originalBytes) }
 'directory-log' { [void][IO.Directory]::CreateDirectory((Join-Path $request.Proof 'watchdog.stdout.log')) }
 'broad-explicit' { HeldFixtureBroad $request.Proof $false }
 'broad-inherited' { $heldAclChallenge=Join-Path $request.Root 'acl-challenge'; HeldFixtureProtect $heldAclChallenge; $request.Proof=Join-Path $heldAclChallenge 'proof'; HeldFixtureProtect $request.Proof; HeldFixtureBroad $request.Proof $true }
 'proof-reparse' { $target=$request.Proof; $request.Proof=Join-Path $request.Root 'proof-junction'; New-Item -Path $request.Proof -ItemType Junction -Target $target | Out-Null }
 'directory-reparse' { $target=$request.Directory; $request.Directory=Join-Path $request.Root 'work-junction'; New-Item -Path $request.Directory -ItemType Junction -Target $target | Out-Null }
 'executable-reparse' { $target=[IO.Path]::GetDirectoryName($request.Executable); $link=Join-Path $request.Root 'exe-junction'; New-Item -Path $link -ItemType Junction -Target $target | Out-Null; $request.Executable=Join-Path $link ([IO.Path]::GetFileName($request.Executable)) }
 'log-reparse' { $outside=Join-Path $request.Root 'outside-log'; [void][IO.Directory]::CreateDirectory($outside); New-Item -Path (Join-Path $request.Proof 'watchdog.stdout.log') -ItemType Junction -Target $outside | Out-Null }
 'relative-proof' { $request.Proof='proof' }
 'relative-executable' { $request.Executable='child.exe' }
 'relative-directory' { $request.Directory='work' }
 'missing-executable' { $request.Executable=Join-Path $request.Root 'not-there.exe' }
 'invalid-image' { $request.Executable=Join-Path $request.Root 'invalid.exe'; [IO.File]::WriteAllText($request.Executable,'not a Windows executable') }
 'missing-directory' { $request.Directory=Join-Path $request.Root 'not-there-work' }
 'missing-proof' { $request.Proof=Join-Path $request.Root 'not-there-proof' }
 'unc-proof' { $request.Proof='\\localhost\C$\held-watchdog-refusal' }
 'locked-stdout' { }
 'native-powershell' { $request.Executable=$request.NativePs5; $request.ChildArguments=@('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$request.NativeChildScript)+@($request.ChildArguments) }
}
[IO.File]::WriteAllText($RequestPath,($request | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
$locked=$null; $process=$null; $job=[IntPtr]::Zero; $child=$null; $ready=$null; $release=$null; $allow=$null
$receipt=@{directExit=$false;stdoutEof=$false;stderrEof=$false;outerExitCode=-1;outerStdout='';outerStderr='';childAliveAtEof=$false;childAliveAfterDispose=$false;stdoutWriteRefused=$false;stderrWriteRefused=$false;privateStdout=$null;privateStderr=$null;failedChildrenRemaining=-1;retainedBytes=$null;launcher=$null;child=$null}
try {
 if($request.Variant -eq 'locked-stdout'){ $locked=[IO.File]::Open((Join-Path $request.Proof 'watchdog.stdout.log'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None); $bytes=[Text.Encoding]::UTF8.GetBytes('locked held bytes'); $locked.Write($bytes,0,$bytes.Length); $locked.Flush(); $originalBytes='locked held bytes' }
 $ready=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$request.ReadyName)
 $release=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$request.ReleaseName)
 $allow=New-Object Threading.EventWaitHandle($false,[Threading.EventResetMode]::ManualReset,$request.AllowName)
 $start=New-Object Diagnostics.ProcessStartInfo
 $start.FileName=$request.NativePs5; $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
 $start.Environment['PSModulePath']=$request.NativeModules; $start.Environment['GYMLOOP_HELD_HANDLE_MARKER']=$request.Marker
 foreach($argument in @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',$request.LauncherScript,$RequestPath)){ $start.ArgumentList.Add($argument) }
 $job=[HeldHandleIsolationFixture.Native]::NewJob(); $process=[Diagnostics.Process]::Start($start)
 if(![HeldHandleIsolationFixture.Native]::AssignProcessToJobObject($job,$process.Handle)){ throw 'held fixture exact launcher assignment failed' }
 $stdoutTask=$process.StandardOutput.ReadToEndAsync(); $stderrTask=$process.StandardError.ReadToEndAsync(); [void]$allow.Set()
 $receipt.directExit=$process.WaitForExit([int]$limits.nativeCleanupReserveMs)
 if(!$receipt.directExit){ throw 'held fixture direct launcher exceeded sealed bound' }
 $receipt.outerExitCode=$process.ExitCode
 $clock=[Diagnostics.Stopwatch]::StartNew()
 $receipt.stdoutEof=$stdoutTask.Wait([int]$limits.processStopGraceMs)
 $remaining=[Math]::Max(0,[int]($limits.processStopGraceMs-$clock.ElapsedMilliseconds))
 $receipt.stderrEof=$stderrTask.Wait($remaining)
 if($receipt.stdoutEof){ $receipt.outerStdout=$stdoutTask.GetAwaiter().GetResult() }
 if($receipt.stderrEof){ $receipt.outerStderr=$stderrTask.GetAwaiter().GetResult() }
 if((Test-Path -LiteralPath $request.LauncherReceipt -PathType Leaf)){ $receipt.launcher=Get-Content -LiteralPath $request.LauncherReceipt -Raw -Encoding UTF8 | ConvertFrom-Json }
 if((Test-Path -LiteralPath $request.ChildReceipt -PathType Leaf)) {
  $receipt.child=Get-Content -LiteralPath $request.ChildReceipt -Raw -Encoding UTF8 | ConvertFrom-Json
  if($request.Mode -ne 'refresh'){ $child=[Diagnostics.Process]::GetProcessById([int]$receipt.child.id); [void]$child.SafeHandle; $receipt.childAliveAtEof=!$child.HasExited; $receipt.childAliveAfterDispose=!$child.HasExited }
 }
 if($null -ne $receipt.launcher -and $receipt.launcher.refused){ $receipt.failedChildrenRemaining=[HeldHandleIsolationFixture.Native]::JobCount($job,$limits.timeoutQueryMaxBytes,$limits.maxProcessBytes) }
 if($null -ne $locked){ $locked.Dispose(); $locked=$null }
 $stdoutPath=Join-Path $request.Proof 'watchdog.stdout.log'; $stderrPath=Join-Path $request.Proof 'watchdog.stderr.log'
 if((Test-Path -LiteralPath $stdoutPath -PathType Leaf)){ $receipt.privateStdout=HeldFixtureRead $stdoutPath; $receipt.stdoutWriteRefused=!(HeldFixtureCanWriteLog $stdoutPath) }
 if((Test-Path -LiteralPath $stderrPath -PathType Leaf)){ $receipt.privateStderr=HeldFixtureRead $stderrPath; $receipt.stderrWriteRefused=!(HeldFixtureCanWriteLog $stderrPath) }
 if($null -ne $originalBytes){ if($request.Variant -eq 'existing-stderr'){ $receipt.retainedBytes=$receipt.privateStderr } else { $receipt.retainedBytes=$receipt.privateStdout } }
 [IO.File]::WriteAllText($request.Receipt,($receipt | ConvertTo-Json -Depth 20),(New-Object Text.UTF8Encoding($false)))
} finally {
 if($null -ne $release){ [void]$release.Set() }
 if($null -ne $child){ [void]$child.WaitForExit([int]$limits.processStopGraceMs); $child.Dispose() }
 if($job -ne [IntPtr]::Zero){ [void][HeldHandleIsolationFixture.Native]::CloseHandle($job) }
 if($null -ne $process){ [void]$process.WaitForExit([int]$limits.processStopGraceMs); $process.Dispose() }
 if($null -ne $locked){ $locked.Dispose() }; if($null -ne $ready){ $ready.Dispose() }; if($null -ne $release){ $release.Dispose() }; if($null -ne $allow){ $allow.Dispose() }
 if($request.Variant -eq 'broad-explicit' -or $request.Variant -eq 'broad-inherited'){ HeldFixtureProtect $request.Proof }
 if($null -ne $heldAclChallenge){ HeldFixtureProtect $heldAclChallenge }
}
`;

const heldHandleCompilerScript = String.raw`
param([string]$RequestPath)
$ErrorActionPreference='Stop'
$request=Get-Content -LiteralPath $RequestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$source=[IO.File]::ReadAllText($request.NativeSource)+[IO.File]::ReadAllText($request.ChildMainSource)
Add-Type -TypeDefinition $source -ReferencedAssemblies 'System.dll','System.Core.dll','System.Web.Extensions.dll' -OutputAssembly $request.Executable -OutputType ConsoleApplication
`;

async function executeHeldHandleIsolation(variant = 'success', mode = 'dispose') {
  const candidate = await readFile(heldHandleCandidate);
  const limitsBytes = await readFile(heldHandleLimitsPath);
  expect(createHash('sha256').update(limitsBytes).digest('hex')).toBe(heldHandleLimitsHash);
  const limits = JSON.parse(limitsBytes.toString('utf8')) as HeldHandleLimits;
  const marker = randomUUID();
  const root = join(heldHandleOutput, marker);
  await mkdir(root, { recursive: true });
  const proof = join(root, 'proof');
  const work = join(root, 'work');
  const requestPath = join(root, 'request.json');
  const nativeSource = join(root, 'held-native.cs');
  const childMainSource = join(root, 'held-child-main.cs');
  const launcherScript = join(root, 'held-launcher.ps1');
  const driverScript = join(root, 'held-driver.ps1');
  const compileScript = join(root, 'held-compiler.ps1');
  const nativeChildScript = join(root, 'held-native-child.ps1');
  const executable = join(root, 'held-child.exe');
  const childArguments = [requestPath, marker, 'हिंदी Δ gym 🏋', 'before "quoted token" after', '', 'C:\\held path\\ending\\', `Local\\HeldReady-${marker}`, `Local\\HeldRelease-${marker}`, join(root, 'seed-objects.json')];
  const metadata = {
    Root: root, Proof: proof, Directory: work, Candidate: heldHandleCandidate,
    Ps7: heldHandlePs7, NativePs5: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe', NativeModules: 'C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\Modules',
    NativeSource: nativeSource, ChildMainSource: childMainSource, LauncherScript: launcherScript, CompileScript: compileScript, NativeChildScript: nativeChildScript,
    Executable: executable, ChildArguments: childArguments, Marker: marker, Limits: limits, Variant: variant, Mode: mode,
    SeedPath: childArguments[8], ReadyName: childArguments[6], ReleaseName: childArguments[7], AllowName: `Local\\HeldAllow-${marker}`,
    SentinelPath: join(root, 'sentinel.txt'), LauncherReceipt: join(root, 'launcher.json'), ChildReceipt: join(root, 'child.json'), Receipt: join(root, 'receipt.json'),
    StdoutText: 'held stdout हिंदी Δ', StderrText: 'held stderr नमस्ते Ω', CandidateHash: createHash('sha256').update(candidate).digest('hex'),
  };
  await Promise.all([
    writeFile(nativeSource, heldHandleNativeSource), writeFile(childMainSource, heldHandleChildMain),
    writeFile(launcherScript, heldHandleLauncherScript), writeFile(driverScript, heldHandleDriverScript),
    writeFile(compileScript, heldHandleCompilerScript), writeFile(nativeChildScript, heldHandleNativeChildScript),
    writeFile(requestPath, JSON.stringify(metadata)),
  ]);
  try {
    const result = await heldHandleExec(heldHandlePs7, ['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', driverScript, requestPath], { windowsHide: true, timeout: limits.nativeCleanupReserveMs + limits.processStopGraceMs, maxBuffer: limits.maxProcessBytes });
    await writeFile(join(root, 'driver-output.json'), JSON.stringify(result));
  } catch (error) {
    await writeFile(join(root, 'driver-error.txt'), String(error));
    throw error;
  }
  return { receipt: JSON.parse(await readFile(metadata.Receipt, 'utf8')) as HeldHandleReceipt, metadata: variant === 'native-powershell' ? { ...metadata, NativeModules: 'C:\\Windows\\system32\\WindowsPowerShell\\v1.0\\Modules' } : metadata, childArguments, limits };
}

function registerHeldHandleIsolation(name: string, body: () => Promise<void>) {
  const register = platform() === 'win32' ? test : test.skip;
  register(name, body, NATIVE_DB_VALIDATION.nativeCleanupReserveMs + NATIVE_DB_VALIDATION.processStopGraceMs + NATIVE_DB_VALIDATION.processStopGraceMs);
}

registerHeldHandleIsolation('held native pipe EOF and unrelated handle isolation remain independent of the descendant lifetime', async () => {
  const { receipt, metadata, childArguments } = await executeHeldHandleIsolation();
  expect(receipt.directExit).toBe(true);
  expect(receipt.outerExitCode).toBe(0);
  expect(receipt.stdoutEof).toBe(true);
  expect(receipt.stderrEof).toBe(true);
  expect(receipt.outerStdout).toBe('HELD-DIRECT-OUT\r\n');
  expect(receipt.outerStderr).toBe('HELD-DIRECT-ERR\r\n');
  expect(receipt.childAliveAtEof).toBe(true);
  expect(receipt.launcher.refused).toBe(false);
  expect(receipt.launcher.signature).toBe(true);
  expect(receipt.child).not.toBeNull();
  expect(receipt.child?.id).toBe(receipt.launcher.id);
  expect(receipt.child?.seededObjects).toBe(7);
  expect(receipt.launcher.leakedObjects).toEqual([]);
  expect(receipt.child?.arguments).toEqual(childArguments);
  expect(receipt.child?.environment).toBe(metadata.Marker);
  expect(receipt.child?.modulePath).toBe(receipt.launcher.modulePath);
  expect(receipt.child?.modulePath.split(';')).toContain(metadata.NativeModules);
  expect(receipt.child?.stdinEof).toBe(-1);
  expect(receipt.child?.stdinName.toLowerCase()).toBe('\\device\\null');
  expect(receipt.child?.console).toBe('0');
  expect(receipt.child?.stdoutPath.replace(/^\\\\\?\\/, '').toLowerCase()).toBe(join(metadata.Proof, 'watchdog.stdout.log').toLowerCase());
  expect(receipt.child?.stderrPath.replace(/^\\\\\?\\/, '').toLowerCase()).toBe(join(metadata.Proof, 'watchdog.stderr.log').toLowerCase());
  expect(receipt.privateStdout).toBe(`${metadata.StdoutText}\r\n`);
  expect(receipt.privateStderr).toBe(`${metadata.StderrText}\r\n`);
  expect(receipt.stdoutWriteRefused).toBe(true);
  expect(receipt.stderrWriteRefused).toBe(true);
});

registerHeldHandleIsolation('held successful disposal is prompt and preserves its independently running exact child', async () => {
  const { receipt, limits } = await executeHeldHandleIsolation();
  expect(receipt.launcher.refused).toBe(false);
  expect(receipt.launcher.disposeMs).toBeLessThan(limits.millisecondsPerSecond);
  expect(receipt.launcher.exitedInitially).toBe(false);
  expect(receipt.launcher.idAfterRefresh).toBe(receipt.launcher.id);
  expect(receipt.childAliveAfterDispose).toBe(true);
  expect(receipt.stdoutEof && receipt.stderrEof).toBe(true);
});

registerHeldHandleIsolation('held refresh observes exit without changing the original identity', async () => {
  const { receipt } = await executeHeldHandleIsolation('success', 'refresh');
  expect(receipt.outerExitCode).toBe(0);
  expect(receipt.launcher.refused).toBe(false);
  expect(receipt.launcher.exitedInitially).toBe(false);
  expect(receipt.launcher.exitedAfterRefresh).toBe(true);
  expect(receipt.launcher.idAfterRefresh).toBe(receipt.launcher.id);
  expect(receipt.child?.id).toBe(receipt.launcher.id);
});

registerHeldHandleIsolation('held native PowerShell child keeps canonical vendor module discovery', async () => {
  const { receipt, metadata } = await executeHeldHandleIsolation('native-powershell');
  expect(receipt.outerExitCode).toBe(0);
  expect(receipt.launcher.refused).toBe(false);
  expect(receipt.childAliveAtEof).toBe(true);
  expect(receipt.child?.environment).toBe(metadata.Marker);
  expect(receipt.child?.modulePath.split(';')).toContain(metadata.NativeModules);
  expect(receipt.child?.modulePath.toLowerCase()).not.toContain('codex');
  expect(receipt.launcher.leakedObjects).toEqual([]);
  expect(receipt.child?.vendorCommands).toHaveLength(4);
  for (const command of receipt.child?.vendorCommands ?? []) expect(command.toLowerCase()).toMatch(/^c:\\windows\\system32\\windowspowershell\\v1\.0\\modules\\/);
  expect(receipt.stdoutEof && receipt.stderrEof).toBe(true);
});

for (const variant of ['existing-stdout', 'existing-stderr', 'locked-stdout']) {
  registerHeldHandleIsolation(`held ${variant} refuses without replacing or truncating original bytes`, async () => {
    const { receipt, metadata } = await executeHeldHandleIsolation(variant);
    expect(receipt.outerExitCode).toBe(0);
    expect(receipt.launcher.refused).toBe(true);
    expect(receipt.launcher.id).toBe(0);
    expect(receipt.failedChildrenRemaining).toBe(0);
    expect(receipt.child).toBeNull();
    expect(receipt.launcher.message).not.toContain(metadata.Root);
    expect(receipt.retainedBytes).toBe(variant === 'existing-stderr' ? 'unchanged held stderr' : variant === 'locked-stdout' ? 'locked held bytes' : 'unchanged held stdout');
  });
}

for (const variant of ['directory-log', 'broad-explicit', 'broad-inherited', 'proof-reparse', 'directory-reparse', 'executable-reparse', 'log-reparse', 'relative-proof', 'relative-executable', 'relative-directory', 'missing-executable', 'invalid-image', 'missing-directory', 'missing-proof', 'unc-proof']) {
  registerHeldHandleIsolation(`held ${variant} cannot construct or leave a failed suspended descendant`, async () => {
    const { receipt, metadata } = await executeHeldHandleIsolation(variant);
    expect(receipt.outerExitCode).toBe(0);
    expect(receipt.launcher.signature).toBe(true);
    expect(receipt.launcher.refused).toBe(true);
    expect(receipt.launcher.id).toBe(0);
    expect(receipt.child).toBeNull();
    expect(receipt.failedChildrenRemaining).toBe(0);
    expect(receipt.launcher.message).not.toContain(metadata.Root);
    expect(receipt.launcher.message).not.toContain(metadata.Marker);
    expect(receipt.stdoutEof && receipt.stderrEof).toBe(true);
  });
}
