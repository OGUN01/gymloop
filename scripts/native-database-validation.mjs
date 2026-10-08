#!/usr/bin/env node
import { Buffer } from 'node:buffer';
import { execFileSync, spawn } from 'node:child_process';
import { createHash, randomBytes } from 'node:crypto';
import { chmod, lstat, mkdir, readFile, readdir, realpath, rm, stat, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { basename, dirname, isAbsolute, join, relative, resolve } from 'node:path';
import { pathToFileURL, URL } from 'node:url';
import { nativeDatabaseValidationEnv, nativeDatabaseProcessEnv, backupKeyEnv } from '../packages/shared/src/config/env.ts';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../packages/shared/src/config/constants.ts';
import { findNonRolledBackTests } from './check-pgtap-rollback.mjs';
import { buildNativePgtapManifest, runNativePgtapValidation, verifyNativePgtapRun } from './pgtap/native.mjs';
import { protectNativePgtapOutput, recoverNativePgtapOutput } from './pgtap/private-output.mjs';
import { exactNativeDataRecord } from './pgtap/data-record.mjs';

const target = Object.freeze({ projectRef: NATIVE_DB_VALIDATION.projectRef, role: NATIVE_DB_VALIDATION.role,
  parameter: NATIVE_DB_VALIDATION.parameter });
const reportingText = `${NATIVE_DB_VALIDATION.reportingLines.join('\n')}\n`;
const suitePaths = ['supabase/tests', 'supabase/tests-holdout'];

function refuse(code = 'EVIDENCE_INVALID') {
  return Object.assign(new Error(`Native database validation refused: ${code}`), { code });
}

function exact(value, fields) {
  return value !== null && typeof value === 'object' && !Array.isArray(value) &&
    Object.keys(value).length === fields.length && fields.every(field => Object.hasOwn(value, field));
}

function hash(bytes) { return createHash('sha256').update(bytes).digest('hex'); }
function jsonBytes(value) { return Buffer.from(`${JSON.stringify(value)}\n`, 'utf8'); }
function inside(parent, path) {
  const part = relative(parent, path);
  return part !== '' && part !== '..' && !part.startsWith(`..${process.platform === 'win32' ? '\\' : '/'}`) && !isAbsolute(part);
}
function sameTimeout(a, b) { return a.originalPresent === b.originalPresent && a.originalValue === b.originalValue; }
function validOriginal(value) {
  return exact(value, ['originalPresent', 'originalValue']) && typeof value.originalPresent === 'boolean' &&
    (value.originalPresent ? typeof value.originalValue === 'string' && value.originalValue.length > 0 : value.originalValue === null);
}
function sourceString(value) {
  return typeof value === 'string' && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(value);
}

async function privateDirectory(path, workdir) {
  const directory = resolve(path);
  if (directory === workdir || inside(workdir, directory)) throw refuse('RECEIPT_UNAVAILABLE');
  await mkdir(directory, { recursive: true, mode: NATIVE_DB_VALIDATION.privateDirectoryMode });
  if ((await lstat(directory)).isSymbolicLink() || await realpath(directory) !== directory) throw refuse('RECEIPT_UNAVAILABLE');
  if (process.platform === 'win32') {
    const script = `$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; Import-Module (Join-Path $PSHOME 'Modules/Microsoft.PowerShell.Security/Microsoft.PowerShell.Security.psd1'); $p=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('${Buffer.from(directory, 'utf8').toString('base64')}')); $a=Get-Acl -LiteralPath $p; $s=[System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value; $ok=@($a.Access | Where-Object { $_.AccessControlType -eq "Allow" -and $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -notin @($s,"S-1-5-18","S-1-5-32-544") }).Count -eq 0; if (-not $ok) { exit 1 }; Write-Output "protected"`;
    const check = await capture('powershell.exe', ['-NoProfile', '-NonInteractive', '-EncodedCommand', Buffer.from(script, 'utf16le').toString('base64')],
      { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.processStopGraceMs });
    if (check.completed !== true || check.exitCode !== 0 || check.signal !== null || check.stderr.trim() !== '' ||
        check.stdout.trim() !== 'protected') throw refuse('RECEIPT_UNAVAILABLE');
  } else {
    await chmod(directory, NATIVE_DB_VALIDATION.privateDirectoryMode);
    const observed = await stat(directory);
    if ((observed.mode & NATIVE_DB_VALIDATION.permissionMask) !== NATIVE_DB_VALIDATION.privateDirectoryMode || observed.uid !== process.getuid()) throw refuse('RECEIPT_UNAVAILABLE');
  }
  return directory;
}

async function privateWrite(path, bytes) {
  await writeFile(path, bytes, { mode: NATIVE_DB_VALIDATION.privateFileMode, flag: 'wx' });
  if (process.platform !== 'win32') await chmod(path, NATIVE_DB_VALIDATION.privateFileMode);
  const back = await readFile(path);
  if (!back.equals(bytes)) throw refuse('RECEIPT_UNAVAILABLE');
  return { path, sha256: hash(back), byteLength: back.length };
}

/** Resolve the pinned Windows npm distribution without executing its shell shim. */
export async function resolveNativeSupabaseExecutable(input) {
  try {
    const data = exactNativeDataRecord(input, ['platform', 'arch', 'path']);
    if (!data || typeof data.platform !== 'string' || data.platform.length === 0 ||
        typeof data.arch !== 'string' || data.arch.length === 0 || typeof data.path !== 'string') throw refuse('RUNNER_UNTRUSTED');
    if (data.platform !== 'win32') return NATIVE_DB_VALIDATION.nativeCommand;
    if (data.arch !== 'x64') throw refuse('RUNNER_UNTRUSTED');
    const directories = data.path.split(';').filter(directory => directory.length > 0);
    if (directories.some(directory => !isAbsolute(directory))) throw refuse('RUNNER_UNTRUSTED');
    for (const directory of directories) {
      const executable = resolve(directory, `${NATIVE_DB_VALIDATION.nativeCommand}.exe`);
      let metadata;
      try { metadata = await lstat(executable); }
      catch (error) { if (error.code === 'ENOENT') continue; throw error; }
      if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(executable) !== executable) throw refuse('RUNNER_UNTRUSTED');
      return executable;
    }
    for (const directory of directories) {
      const shim = resolve(directory, `${NATIVE_DB_VALIDATION.nativeCommand}.cmd`);
      let metadata;
      try { metadata = await lstat(shim); }
      catch (error) { if (error.code === 'ENOENT') continue; throw error; }
      if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(shim) !== shim) throw refuse('RUNNER_UNTRUSTED');
      if (basename(directory) === '.bin' && basename(dirname(directory)) !== 'node_modules') throw refuse('RUNNER_UNTRUSTED');
      const packageJson = basename(directory) === '.bin'
        ? resolve(dirname(directory), 'supabase/package.json')
        : resolve(directory, 'node_modules/supabase/package.json');
      metadata = await lstat(packageJson);
      if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(packageJson) !== packageJson) throw refuse('RUNNER_UNTRUSTED');
      const packageMetadata = JSON.parse(await readFile(packageJson, 'utf8'));
      const packageName = '@supabase/cli-windows-x64';
      if (packageMetadata.name !== NATIVE_DB_VALIDATION.nativeCommand || packageMetadata.version !== NATIVE_DB_VALIDATION.cliVersion ||
          !exact(packageMetadata.bin, ['supabase']) || packageMetadata.bin.supabase !== 'dist/supabase.js' ||
          packageMetadata.optionalDependencies?.[packageName] !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
      const declaredBin = resolve(dirname(packageJson), packageMetadata.bin.supabase);
      metadata = await lstat(declaredBin);
      if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(declaredBin) !== declaredBin) throw refuse('RUNNER_UNTRUSTED');
      const optionalCandidates = [resolve(dirname(packageJson), 'node_modules', packageName, 'package.json'),
        resolve(dirname(dirname(packageJson)), packageName, 'package.json')];
      let optionalPackageJson = null;
      for (const candidate of optionalCandidates) {
        try { metadata = await lstat(candidate); }
        catch (error) { if (error.code === 'ENOENT') continue; throw error; }
        if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(candidate) !== candidate) throw refuse('RUNNER_UNTRUSTED');
        optionalPackageJson = candidate;
        break;
      }
      if (optionalPackageJson === null || createRequire(packageJson).resolve(`${packageName}/package.json`) !== optionalPackageJson) throw refuse('RUNNER_UNTRUSTED');
      const optionalMetadata = JSON.parse(await readFile(optionalPackageJson, 'utf8'));
      if (optionalMetadata.name !== packageName || optionalMetadata.version !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
      const executable = resolve(dirname(optionalPackageJson), 'bin/supabase.exe');
      metadata = await lstat(executable);
      if (!metadata.isFile() || metadata.isSymbolicLink() || await realpath(executable) !== executable) throw refuse('RUNNER_UNTRUSTED');
      return executable;
    }
    throw refuse('RUNNER_UNTRUSTED');
  } catch { throw refuse('RUNNER_UNTRUSTED'); }
}

// Retain bytes internally; errors never include a child stream or command arguments.
async function capture(command, args, options = {}) {
  const started = Date.now();
  const inherited = options.env ?? nativeDatabaseProcessEnv();
  let executable = command;
  if (process.platform === 'win32' && command === NATIVE_DB_VALIDATION.nativeCommand) {
    const paths = Object.entries(inherited).filter(([name]) => name.toLowerCase() === 'path');
    if (paths.length !== 1) throw refuse('RUNNER_UNTRUSTED');
    executable = await resolveNativeSupabaseExecutable({ platform: process.platform, arch: process.arch, path: paths[0][1] });
  }
  const child = spawn(executable, args, { cwd: options.cwd, env: inherited, windowsHide: true,
    stdio: ['ignore', 'pipe', 'pipe'], shell: false });
  const streams = { stdout: [], stderr: [] };
  let length = 0;
  let stopped = false;
  let spawnError = false;
  let timer;
  let killTimer;
  const stop = () => {
    if (stopped) return;
    stopped = true;
    child.kill('SIGTERM');
    killTimer = globalThis.setTimeout(() => child.kill('SIGKILL'), NATIVE_DB_VALIDATION.processStopGraceMs);
  };
  for (const stream of ['stdout', 'stderr']) child[stream].on('data', bytes => {
    length += bytes.length;
    if (length > (options.maxBytes ?? NATIVE_DB_VALIDATION.maxProcessBytes)) stop();
    else streams[stream].push(bytes);
  });
  if (options.timeoutMs) timer = globalThis.setTimeout(stop, options.timeoutMs);
  child.on('error', () => { spawnError = true; });
  const result = await new Promise(resolveResult => child.on('close', (code, signal) => {
    if (timer) globalThis.clearTimeout(timer);
    if (killTimer) globalThis.clearTimeout(killTimer);
    const stdoutBytes = Buffer.concat(streams.stdout);
    const stderrBytes = Buffer.concat(streams.stderr);
    const stdout = stdoutBytes.toString('utf8');
    const stderr = stderrBytes.toString('utf8');
    const validUtf8 = Buffer.from(stdout, 'utf8').equals(stdoutBytes) && Buffer.from(stderr, 'utf8').equals(stderrBytes);
    resolveResult({ completed: !stopped && !spawnError && validUtf8, exitCode: code === null || code < 0 ? null : code,
      signal: signal || null, stdout, stderr, elapsedMs: Date.now() - started });
  }));
  return result;
}

async function checked(command, args, options) {
  const result = await capture(command, args, options);
  if (!result.completed || result.exitCode !== 0 || result.signal !== null) throw refuse();
  return result.stdout;
}

async function safeTree(root, directory, predicate) {
  const found = [];
  const inspect = async path => {
    const metadata = await lstat(path);
    if (metadata.isSymbolicLink() || !inside(root, path) || await realpath(path) !== path) throw refuse('MANIFEST_INVALID');
    if (metadata.isDirectory()) {
      for (const entry of (await readdir(path)).sort()) await inspect(join(path, entry));
    } else if (metadata.isFile() && predicate(path)) found.push(path);
    else if (!metadata.isFile()) throw refuse('MANIFEST_INVALID');
  };
  await inspect(resolve(root, directory));
  return found;
}

// SQL bodies are inspected in memory only. Comments and quoted tokens cannot invent a plan.
function planMetadata(sql) {
  let code = '';
  let cursor = 0;
  while (cursor < sql.length) {
    if (sql.startsWith('--', cursor)) {
      const end = sql.indexOf('\n', cursor);
      cursor = end < 0 ? sql.length : end + 1;
      code += '\n';
    } else if (sql.startsWith('/*', cursor)) {
      let depth = 1;
      cursor += '/*'.length;
      while (cursor < sql.length && depth > 0) {
        if (sql.startsWith('/*', cursor)) { depth += 1; cursor += '/*'.length; }
        else if (sql.startsWith('*/', cursor)) { depth -= 1; cursor += '*/'.length; }
        else cursor += 1;
      }
      if (depth !== 0) return [];
      code += ' ';
    } else if (sql[cursor] === "'" || sql[cursor] === '"') {
      const quote = sql[cursor];
      const escaped = quote === "'" && /[eE]/.test(sql[cursor - 1] ?? '') && !/[\w$]/.test(sql[cursor - 'E\''.length] ?? '');
      cursor += 1;
      let closed = false;
      while (cursor < sql.length) {
        if (escaped && sql[cursor] === '\\') cursor += '\\x'.length;
        else if (sql[cursor] === quote) {
          cursor += 1;
          if (sql[cursor] === quote) cursor += 1;
          else { closed = true; break; }
        } else cursor += 1;
      }
      if (!closed) return [];
      code += ' quoted_token ';
    } else {
      const tag = sql[cursor] === '$' ? /^\$(?:[A-Za-z_][A-Za-z_0-9]*)?\$/.exec(sql.slice(cursor)) : null;
      if (tag) {
        const end = sql.indexOf(tag[0], cursor + tag[0].length);
        if (end < 0) return [];
        cursor = end + tag[0].length;
        code += ' quoted_token ';
      } else { code += sql[cursor]; cursor += 1; }
    }
  }
  const calls = [...code.matchAll(/\b(?:\w+\.)?plan\s*\(/gi)];
  const plans = code.split(';').flatMap(statement => {
    const match = /^\s*select\s+(?:\*\s+from\s+)?(?:pgtap\.)?plan\s*\(\s*([1-9]\d*)\s*\)\s*$/i.exec(statement);
    return match ? [Number(match[1])] : [];
  });
  return calls.length === plans.length ? plans : [];
}

async function schemaHashes(workdir) {
  const migrations = await safeTree(workdir, 'supabase/migrations', path => path.endsWith('.sql'));
  const records = [];
  for (const path of migrations) records.push({ path: relative(workdir, path).replaceAll('\\', '/'), sha256: hash(await readFile(path)) });
  return { migrationsSha256: hash(jsonBytes(records)), generatedTypesSha256: hash(await readFile(join(workdir, 'packages/db/types/database.ts'))) };
}

async function collectFiles(workdir, expectedSource, schemaReceipt, runtime) {
  const current = (await checked('git', ['rev-parse', 'HEAD'], { cwd: workdir })).trim();
  if (current !== expectedSource || !sourceString(current)) throw refuse('INPUT_CHANGED');
  const changed = await checked('git', ['status', '--porcelain', '--untracked-files=all', '--', ...suitePaths,
    'supabase/migrations', 'packages/db/types/database.ts'], { cwd: workdir });
  if (changed.split(/\r?\n/).some(line => line && !line.endsWith('supabase/tests/.proverc'))) throw refuse('INPUT_CHANGED');
  const identity = await schemaHashes(workdir);
  if (!exact(schemaReceipt, ['formatVersion', 'sourceSha', 'runId', 'runAttempt', 'migrate', 'drift', 'schemaIdentity']) ||
      schemaReceipt.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || schemaReceipt.sourceSha !== expectedSource ||
      schemaReceipt.runId !== runtime.GITHUB_RUN_ID || schemaReceipt.runAttempt !== runtime.GITHUB_RUN_ATTEMPT ||
      schemaReceipt.migrate !== 'success' || schemaReceipt.drift !== 'success' ||
      !exact(schemaReceipt.schemaIdentity, ['migrationsSha256', 'generatedTypesSha256']) ||
      identity.migrationsSha256 !== schemaReceipt.schemaIdentity.migrationsSha256 ||
      identity.generatedTypesSha256 !== schemaReceipt.schemaIdentity.generatedTypesSha256) throw refuse('INPUT_CHANGED');
  const files = [];
  for (const directory of suitePaths) {
    const paths = await safeTree(workdir, directory, path => /\.(?:sql|pg)$/.test(path));
    if (paths.length === 0) throw refuse('MANIFEST_INVALID');
    for (const path of paths) {
      const bytes = await readFile(path);
      const text = bytes.toString('utf8');
      if (!Buffer.from(text, 'utf8').equals(bytes) || findNonRolledBackTests([{ path, content: text }]).length > 0) throw refuse('MANIFEST_INVALID');
      files.push({ path: relative(workdir, path).replaceAll('\\', '/'), sha256: hash(bytes), literalPlans: planMetadata(text) });
    }
  }
  return { sourceSha: current, schemaIdentity: identity, files };
}

async function installReportingConfig({ workdir, lines }) {
  if (JSON.stringify(lines) !== JSON.stringify(NATIVE_DB_VALIDATION.reportingLines)) throw refuse('REPORTING_UNVERIFIED');
  const path = join(workdir, 'supabase/tests/.proverc');
  let originalText = null;
  let originalPresent = false;
  try {
    const metadata = await lstat(path);
    if (!metadata.isFile() || metadata.isSymbolicLink()) throw refuse('REPORTING_UNVERIFIED');
    const bytes = await readFile(path);
    originalText = bytes.toString('utf8');
    if (!Buffer.from(originalText, 'utf8').equals(bytes) ||
        ![reportingText, reportingText.replaceAll('\n', '\r\n')].includes(originalText)) throw refuse('REPORTING_UNVERIFIED');
    originalPresent = true;
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  try {
    await writeFile(path, reportingText, { flag: originalPresent ? 'w' : 'wx' });
    if (hash(await readFile(path)) !== hash(reportingText)) throw refuse('REPORTING_UNVERIFIED');
  } catch {
    if (originalPresent) await writeFile(path, originalText);
    else await rm(path, { force: true });
    throw refuse('REPORTING_UNVERIFIED');
  }
  return { path, originalPresent, originalText, installedSha256: hash(reportingText) };
}

async function restoreReportingConfig(installation) {
  if (hash(await readFile(installation.path)) !== installation.installedSha256) return { restored: false, verified: false };
  if (installation.originalPresent) {
    await writeFile(installation.path, installation.originalText);
    return { restored: true, verified: (await readFile(installation.path)).equals(Buffer.from(installation.originalText, 'utf8')) };
  }
  await rm(installation.path);
  try { await lstat(installation.path); return { restored: true, verified: false }; }
  catch (error) { if (error.code !== 'ENOENT') throw error; return { restored: true, verified: true }; }
}

async function query(workdir, directory, sql) {
  const path = join(directory, `catalog-${randomBytes(PHASE8_BACKUP_LIMITS.ivBytes).toString('hex')}.sql`);
  await privateWrite(path, Buffer.from(sql, 'utf8'));
  try {
    return await checked('supabase', ['db', 'query', '--linked', '--output-format', 'json', '-f', path],
      { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs, maxBytes: NATIVE_DB_VALIDATION.timeoutQueryMaxBytes });
  } finally { await rm(path, { force: true }); }
}

async function queryTimeout(workdir, directory, requested) {
  if (JSON.stringify(requested) !== JSON.stringify(target)) throw refuse('TIMEOUT_CAPTURE_INVALID');
  const output = await query(workdir, directory, `WITH role_target AS (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'postgres'),
    setting AS (SELECT substring(entry FROM length('statement_timeout=') + 1) AS value
      FROM pg_catalog.pg_db_role_setting AS settings CROSS JOIN LATERAL unnest(settings.setconfig) AS entry
      WHERE settings.setrole = (SELECT oid FROM role_target) AND settings.setdatabase = 0 AND entry LIKE 'statement_timeout=%')
    SELECT (SELECT count(*) FROM setting) > 0 AS "originalPresent", (SELECT min(value) FROM setting) AS "originalValue",
      (SELECT count(*)::integer FROM setting) AS "entryCount", (SELECT count(*)::integer FROM role_target) AS "roleCount";`);
  let result;
  try { result = JSON.parse(output); } catch { throw refuse('TIMEOUT_CAPTURE_INVALID'); }
  if (result && !Array.isArray(result) && typeof result === 'object') {
    if (result._tag === 'Error' || Object.hasOwn(result, 'error') || Object.hasOwn(result, 'errors')) throw refuse('TIMEOUT_CAPTURE_INVALID');
    result = result.rows;
  }
  if (!Array.isArray(result) || result.length !== 1 || !exact(result[0], ['originalPresent', 'originalValue', 'entryCount', 'roleCount'])) throw refuse('TIMEOUT_CAPTURE_INVALID');
  const row = result[0];
  const original = { originalPresent: row.originalPresent, originalValue: row.originalValue };
  if (!validOriginal(original) || row.roleCount !== 1 || row.entryCount !== (original.originalPresent ? 1 : 0)) throw refuse('TIMEOUT_CAPTURE_INVALID');
  return original;
}

function valueLiteral(value) {
  let tag = '$dbv_value$';
  while (value.includes(tag)) tag = tag.replace('$dbv_', '$dbv_x');
  return `${tag}${value}${tag}`;
}

async function alterTimeout(workdir, directory, input) {
  if (!exact(input, ['target', 'setting']) || JSON.stringify(input.target) !== JSON.stringify(target) || !validOriginal(input.setting)) throw refuse('TIMEOUT_CAPTURE_INVALID');
  let outerTag = '$dbv_alter$';
  while (input.setting.originalValue?.includes(outerTag)) outerTag = outerTag.replace('$dbv_', '$dbv_x');
  const sql = input.setting.originalPresent
    ? `DO ${outerTag} BEGIN EXECUTE format('ALTER ROLE postgres SET statement_timeout = %L', ${valueLiteral(input.setting.originalValue)}); END ${outerTag};`
    : 'ALTER ROLE postgres RESET statement_timeout;';
  await query(workdir, directory, sql);
}

async function uploadArtifact(runtime, name, path, directory) {
  if (runtime.GITHUB_ACTIONS !== 'true' || !runtime.ACTIONS_RUNTIME_TOKEN || !runtime.ACTIONS_RESULTS_URL) throw refuse('RECEIPT_UNAVAILABLE');
  const distribution = resolve(runtime.RUNNER_WORKSPACE, '..', '_actions/actions/upload-artifact/v5/dist/upload/index.js');
  if (!(await stat(distribution)).isFile()) throw refuse('RECEIPT_UNAVAILABLE');
  const output = join(directory, `upload-${randomBytes(PHASE8_BACKUP_LIMITS.ivBytes).toString('hex')}.txt`);
  await privateWrite(output, Buffer.alloc(0));
  const env = { ...nativeDatabaseProcessEnv(), INPUT_NAME: name, INPUT_PATH: path, 'INPUT_IF-NO-FILES-FOUND': 'error',
    'INPUT_RETENTION-DAYS': String(NATIVE_DB_VALIDATION.artifactRetentionDays), 'INPUT_COMPRESSION-LEVEL': '0',
    INPUT_OVERWRITE: 'false', 'INPUT_INCLUDE-HIDDEN-FILES': 'false', GITHUB_OUTPUT: output };
  const result = await capture(process.execPath, [distribution], { cwd: process.cwd(), env,
    timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs, maxBytes: NATIVE_DB_VALIDATION.timeoutQueryMaxBytes });
  if (!result.completed || result.exitCode !== 0) throw refuse('RECEIPT_UNAVAILABLE');
  const receipt = await readFile(output, 'utf8');
  const id = /^artifact-id<<([^\r\n]+)\r?\n([1-9]\d*)\r?\n\1$/m.exec(receipt)?.[2];
  const digest = new RegExp(`^artifact-digest<<([^\\r\\n]+)\\r?\\n([a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}})\\r?\\n\\1$`, 'm').exec(receipt)?.[2];
  if (!id || !digest) throw refuse('RECEIPT_UNAVAILABLE');
  await rm(output);
  return { id, digest };
}

async function boundedResponseBytes(response, maxBytes) {
  if (!response.body) throw refuse('RECEIPT_UNAVAILABLE');
  const chunks = [];
  let byteLength = 0;
  for await (const bytes of response.body) {
    byteLength += bytes.length;
    if (byteLength > maxBytes) throw refuse('RECEIPT_UNAVAILABLE');
    chunks.push(Buffer.from(bytes));
  }
  return Buffer.concat(chunks);
}

async function artifactApi(runtime, path, expectedStatus) {
  if (runtime.GITHUB_API_URL !== 'https://api.github.com' || !runtime.GITHUB_TOKEN ||
      runtime.GITHUB_REPOSITORY !== NATIVE_DB_VALIDATION.repository) throw refuse('RECEIPT_UNAVAILABLE');
  const response = await globalThis.fetch(`${runtime.GITHUB_API_URL}/repos/${NATIVE_DB_VALIDATION.repository}/${path}`, {
    headers: { authorization: `Bearer ${runtime.GITHUB_TOKEN}`, accept: 'application/vnd.github+json',
      'x-github-api-version': '2022-11-28', 'user-agent': 'gymloop-native-database-validation' },
    redirect: 'manual', signal: globalThis.AbortSignal.timeout(NATIVE_DB_VALIDATION.nativeCleanupReserveMs),
  });
  if (response.status !== expectedStatus) throw refuse('RECEIPT_UNAVAILABLE');
  return response;
}

async function readReceiptArtifact(runtime, artifact, filename) {
  try {
  if (runtime.GITHUB_ACTIONS !== 'true' || runtime.RUNNER_ENVIRONMENT !== 'github-hosted' || runtime.RUNNER_OS !== 'Linux' ||
      !['manifest.json', 'recovery.json'].includes(filename) ||
      !Number.isSafeInteger(artifact?.id) || artifact.id <= 0 || artifact.expired !== false ||
      !Number.isSafeInteger(artifact.size_in_bytes) || artifact.size_in_bytes <= 0 ||
      artifact.size_in_bytes > NATIVE_DB_VALIDATION.timeoutQueryMaxBytes ||
      !new RegExp(`^sha256:[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(artifact.digest)) throw refuse('RECEIPT_UNAVAILABLE');
  const redirect = await artifactApi(runtime, `actions/artifacts/${artifact.id}/zip`, NATIVE_DB_VALIDATION.artifactRedirectStatus);
  const location = redirect.headers.get('location');
  if (!location) throw refuse('RECEIPT_UNAVAILABLE');
  const url = new URL(location);
  if (url.protocol !== 'https:' || url.username || url.password || url.hash) throw refuse('RECEIPT_UNAVAILABLE');
  const response = await globalThis.fetch(location, { redirect: 'error',
    signal: globalThis.AbortSignal.timeout(NATIVE_DB_VALIDATION.nativeCleanupReserveMs) });
  if (response.status !== NATIVE_DB_VALIDATION.artifactMetadataStatus) throw refuse('RECEIPT_UNAVAILABLE');
  const archive = await boundedResponseBytes(response, NATIVE_DB_VALIDATION.timeoutQueryMaxBytes);
  if (archive.length !== artifact.size_in_bytes || artifact.digest !== `sha256:${hash(archive)}`) throw refuse('RECEIPT_UNAVAILABLE');
  const script = [
    'import io,stat,sys,zipfile',
    'with zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read())) as z:',
    ' members=z.infolist()',
    ' if len(members)!=1: raise SystemExit(1)',
    ' member=members[0]',
    ' mode=member.external_attr>>int(sys.argv[3])',
    ' if member.filename!=sys.argv[1] or member.is_dir() or stat.S_IFMT(mode) not in (0,stat.S_IFREG): raise SystemExit(1)',
    ' if member.file_size>int(sys.argv[2]) or member.flag_bits&1 or member.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED): raise SystemExit(1)',
    ' sys.stdout.buffer.write(z.read(member))',
  ].join('\n');
  const body = execFileSync('python3', ['-c', script, filename, String(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes),
    String(NATIVE_DB_VALIDATION.artifactUnixModeShiftBits)], { input: archive, maxBuffer: NATIVE_DB_VALIDATION.timeoutQueryMaxBytes,
    timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs, stdio: ['pipe', 'pipe', 'pipe'] });
  const value = JSON.parse(body.toString('utf8'));
  if (!body.equals(jsonBytes(value))) throw refuse('RECEIPT_UNAVAILABLE');
  return { value, hash: hash(body), archiveSha256: hash(archive) };
  } catch { throw refuse('RECEIPT_UNAVAILABLE'); }
}

function privateZipMember(archive, expectedSize) {
  const script = [
    'import io,stat,sys,zipfile',
    'archive=zipfile.ZipFile(io.BytesIO(sys.stdin.buffer.read()))',
    'members=archive.infolist()',
    'if len(members)!=1: raise SystemExit(1)',
    'member=members[0]',
    'mode=member.external_attr >> int(sys.argv[2])',
    'if member.filename!="private-evidence.encrypted" or member.is_dir() or stat.S_ISLNK(mode): raise SystemExit(1)',
    'if stat.S_IFMT(mode) not in (0,stat.S_IFREG): raise SystemExit(1)',
    'if member.flag_bits & 1 or member.compress_type not in (zipfile.ZIP_STORED,zipfile.ZIP_DEFLATED): raise SystemExit(1)',
    'if member.file_size!=int(sys.argv[1]): raise SystemExit(1)',
    'body=archive.read(member)',
    'if len(body)!=int(sys.argv[1]): raise SystemExit(1)',
    'sys.stdout.buffer.write(body)',
  ].join('\n');
  try {
    return execFileSync(process.platform === 'win32' ? 'python' : 'python3', ['-c', script, String(expectedSize),
      String(NATIVE_DB_VALIDATION.artifactUnixModeShiftBits)], {
      input: archive, maxBuffer: expectedSize + 1, timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs,
      windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
    });
  } catch { throw refuse('RECEIPT_UNAVAILABLE'); }
}

async function readBackPrivateArtifact(runtime, name, acknowledgement, ciphertext, evidence) {
  if (!/^[1-9]\d*$/.test(acknowledgement.id) ||
      !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(acknowledgement.digest)) throw refuse('RECEIPT_UNAVAILABLE');
  const metadataResponse = await artifactApi(runtime, `actions/artifacts/${acknowledgement.id}`, NATIVE_DB_VALIDATION.artifactMetadataStatus);
  const metadata = JSON.parse((await boundedResponseBytes(metadataResponse, NATIVE_DB_VALIDATION.timeoutQueryMaxBytes)).toString('utf8'));
  const archiveLimit = ciphertext.length + NATIVE_DB_VALIDATION.timeoutQueryMaxBytes;
  if (metadata === null || typeof metadata !== 'object' || Array.isArray(metadata) || !Number.isSafeInteger(metadata.id) ||
      metadata.id <= 0 || String(metadata.id) !== acknowledgement.id ||
      metadata.name !== name || metadata.expired !== false || metadata.digest !== `sha256:${acknowledgement.digest}` ||
      !Number.isSafeInteger(metadata.size_in_bytes) || metadata.size_in_bytes <= 0 || metadata.size_in_bytes > archiveLimit ||
      metadata.workflow_run === null || typeof metadata.workflow_run !== 'object' ||
      String(metadata.workflow_run.id) !== runtime.GITHUB_RUN_ID || metadata.workflow_run.head_sha !== evidence.sourceSha ||
      !Number.isSafeInteger(metadata.workflow_run.repository_id) || metadata.workflow_run.repository_id <= 0 ||
      metadata.workflow_run.head_repository_id !== metadata.workflow_run.repository_id) throw refuse('RECEIPT_UNAVAILABLE');
  const attemptResponse = await artifactApi(runtime, `actions/runs/${runtime.GITHUB_RUN_ID}/attempts/${runtime.GITHUB_RUN_ATTEMPT}`,
    NATIVE_DB_VALIDATION.artifactMetadataStatus);
  const attempt = JSON.parse((await boundedResponseBytes(attemptResponse, NATIVE_DB_VALIDATION.timeoutQueryMaxBytes)).toString('utf8'));
  const workflowPath = NATIVE_DB_VALIDATION.workflowRef.slice(`${NATIVE_DB_VALIDATION.repository}/`.length).split('@')[0];
  if (attempt === null || typeof attempt !== 'object' || Array.isArray(attempt) || String(attempt.id) !== runtime.GITHUB_RUN_ID ||
      String(attempt.run_attempt) !== runtime.GITHUB_RUN_ATTEMPT || attempt.head_sha !== evidence.sourceSha || attempt.path !== workflowPath ||
      attempt.repository?.full_name !== NATIVE_DB_VALIDATION.repository) throw refuse('RECEIPT_UNAVAILABLE');
  const redirect = await artifactApi(runtime, `actions/artifacts/${acknowledgement.id}/zip`, NATIVE_DB_VALIDATION.artifactRedirectStatus);
  const location = redirect.headers.get('location');
  if (!location) throw refuse('RECEIPT_UNAVAILABLE');
  const blobUrl = new URL(location);
  if (blobUrl.protocol !== 'https:' || blobUrl.username || blobUrl.password || blobUrl.hash) throw refuse('RECEIPT_UNAVAILABLE');
  // The signed blob URL receives no repository or runtime authorization header.
  const download = await globalThis.fetch(location, { redirect: 'error',
    signal: globalThis.AbortSignal.timeout(NATIVE_DB_VALIDATION.nativeCleanupReserveMs) });
  if (download.status !== NATIVE_DB_VALIDATION.artifactMetadataStatus) throw refuse('RECEIPT_UNAVAILABLE');
  const archive = await boundedResponseBytes(download, archiveLimit);
  if (archive.length !== metadata.size_in_bytes || hash(archive) !== acknowledgement.digest) throw refuse('RECEIPT_UNAVAILABLE');
  const received = privateZipMember(archive, ciphertext.length);
  if (!received.equals(ciphertext)) throw refuse('RECEIPT_UNAVAILABLE');
  return received;
}

async function persistRecoveryReceipt(runtime, directory, manifest, receipt) {
  if (receipt.runId !== `${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}` || receipt.sourceSha !== manifest.sourceSha ||
      receipt.manifestSha256 !== hash(jsonBytes(manifest))) throw refuse('RECEIPT_UNAVAILABLE');
  const bytes = jsonBytes(receipt);
  const path = join(directory, 'recovery.json');
  await privateWrite(path, bytes);
  // The pinned official client only returns artifact outputs after finalizing its remote upload.
  await uploadArtifact(runtime, `native-db-recovery-${receipt.runId}`, path, directory);
  return { acknowledged: true, sha256: hash(bytes) };
}

async function verifyRuntime(runtime, sourceSha, workdir) {
  if (runtime.GITHUB_ACTIONS !== 'true' || runtime.GITHUB_REPOSITORY !== NATIVE_DB_VALIDATION.repository ||
      runtime.GITHUB_SHA !== sourceSha || !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ID ?? '') || !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ATTEMPT ?? '')) throw refuse('RUNNER_UNTRUSTED');
  if (runtime.RUNNER_ENVIRONMENT === 'self-hosted' && (runtime.GITHUB_REF !== NATIVE_DB_VALIDATION.mainRef ||
      !['push', 'workflow_dispatch'].includes(runtime.GITHUB_EVENT_NAME) || runtime.GITHUB_WORKFLOW_REF !== NATIVE_DB_VALIDATION.workflowRef ||
      runtime.RUNNER_OS !== NATIVE_DB_VALIDATION.runnerOs || runtime.GITHUB_JOB !== NATIVE_DB_VALIDATION.job)) throw refuse('RUNNER_UNTRUSTED');
  const version = (await checked('supabase', ['--version'], { cwd: workdir })).trim();
  if (version !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
  if ((await readFile(join(workdir, 'supabase/.temp/project-ref'), 'utf8')).trim() !== target.projectRef) throw refuse('RUNNER_UNTRUSTED');
  const digests = JSON.parse(await checked('docker', ['image', 'inspect', '--format', '{{json .RepoDigests}}', NATIVE_DB_VALIDATION.clientImage], { cwd: workdir }));
  if (!Array.isArray(digests) || !digests.some(value => typeof value === 'string' && value.endsWith(`@${NATIVE_DB_VALIDATION.clientDigest}`))) throw refuse('RUNNER_UNTRUSTED');
}

// This client-only integration probe never connects to PostgreSQL. The official
// psql executable is replaced only inside these disposable synthetic containers.
async function ensureClientSmoke(runtime, sourceSha, workdir, directory) {
  const inherited = nativeDatabaseProcessEnv();
  const overrides = ['SUPABASE_INTERNAL_IMAGE_REGISTRY', 'DEBUG', 'BITBUCKET_CLONE_DIR', 'HARNESS_OPTIONS',
    'PG_PROVE_SWITCHES', 'PGPROVE_SWITCHES', 'PERL5OPT', 'PERL5LIB'];
  if (overrides.some(name => typeof inherited[name] === 'string' && inherited[name].trim().length > 0)) throw refuse('RUNNER_UNTRUSTED');
  const cliVersion = (await checked('supabase', ['--version'], { cwd: workdir })).trim();
  if (cliVersion !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
  const parent = resolve(workdir, '.dbv');
  const smokeRoot = join(parent, `client-smoke-${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}`);
  if (!inside(parent, smokeRoot)) throw refuse('REPORTING_UNVERIFIED');
  await mkdir(smokeRoot, { recursive: false });
  const stub = join(smokeRoot, 'psql');
  const stubText = '#!/bin/sh\nfile=""\nwhile [ "$#" -gt 0 ]; do\n  if [ "$1" = "-f" ] || [ "$1" = "--file" ]; then shift; file="$1"; fi\n  shift\ndone\nif [ -z "$file" ]; then exit 1; fi\ncat "$file"\ncase "$file" in\n  */client-error.sql|*/connection-loss.sql) echo "ERROR: synthetic client failure" >&2; exit 1;;\nesac\n';
  await writeFile(stub, stubText, { mode: NATIVE_DB_VALIDATION.smokeExecutableMode, flag: 'wx' });
  if (process.platform !== 'win32') await chmod(stub, NATIVE_DB_VALIDATION.smokeExecutableMode);
  const success = '1..2\nok 1 - synthetic one\nok 2 - synthetic two\n';
  const independent = '1..1\nok 1 - synthetic independent\n';
  const fixtures = [
    { name: 'success', file: 'visible.sql', tap: success },
    { name: 'assertion-failure', file: 'visible.sql', tap: '1..2\nok 1 - synthetic one\nnot ok 2 - synthetic two\n' },
    { name: 'missing-plan', file: 'visible.sql', tap: 'ok 1 - synthetic one\nok 2 - synthetic two\n' },
    { name: 'extra-plan', file: 'visible.sql', tap: `${success}1..2\n` },
    { name: 'broken-plan', file: 'visible.sql', tap: success.replace('1..2', '1..3') },
    { name: 'malformed', file: 'visible.sql', tap: success.replace('ok 2', 'ok 3') },
    { name: 'truncated', file: 'visible.sql', tap: '1..2\nok 1 - synthetic one\n' },
    { name: 'client-error', file: 'client-error.sql', tap: success },
    { name: 'connection-loss', file: 'connection-loss.sql', tap: '1..2\nok 1 - synthetic one\n' },
  ];
  const dockerPath = path => path.replaceAll('\\', '/').replace(/^[A-Za-z]:/, '');
  const results = [];
  try {
    const pinned = `supabase/pg_prove@${NATIVE_DB_VALIDATION.clientDigest}`;
    await checked('docker', ['pull', pinned], { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
    await checked('docker', ['tag', pinned, NATIVE_DB_VALIDATION.clientImage], { cwd: workdir });
    await checked('docker', ['pull', NATIVE_DB_VALIDATION.nativeClientImage], { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
    const officialId = (await checked('docker', ['image', 'inspect', '--format', '{{.Id}}', pinned], { cwd: workdir })).trim();
    const nativeId = (await checked('docker', ['image', 'inspect', '--format', '{{.Id}}', NATIVE_DB_VALIDATION.nativeClientImage], { cwd: workdir })).trim();
    if (officialId !== nativeId || !new RegExp(`^sha256:[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(nativeId)) throw refuse('RUNNER_UNTRUSTED');
    const version = await checked('docker', ['run', '--rm', '--network', 'host', pinned, 'pg_prove', '--version'],
      { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
    if (version.trim() !== `pg_prove ${NATIVE_DB_VALIDATION.clientImage.split(':').at(-1)}`) throw refuse('REPORTING_UNVERIFIED');
    for (const fixture of fixtures) {
      const caseRoot = join(smokeRoot, fixture.name);
      const visible = join(caseRoot, 'supabase/tests');
      const held = join(caseRoot, 'supabase/tests-holdout');
      await mkdir(visible, { recursive: true });
      await mkdir(held, { recursive: true });
      const files = [{ path: join(visible, '.proverc'), content: reportingText },
        { path: join(visible, fixture.file), content: fixture.tap }, { path: join(held, 'independent.pg'), content: independent }];
      for (const file of files) await writeFile(file.path, file.content, { flag: 'wx' });
      const metadata = files.map(file => ({ path: relative(caseRoot, file.path).replaceAll('\\', '/'), sha256: hash(file.content), byteLength: Buffer.byteLength(file.content, 'utf8') }));
      const clientVisible = dockerPath(visible);
      const clientHeld = dockerPath(held);
      const result = await capture('docker', ['run', '--rm', '--network', 'host', '--security-opt', 'label:disable',
        '-v', `${visible}:${clientVisible}:ro`, '-v', `${held}:${clientHeld}:ro`,
        '-v', `${stub}:/usr/libexec/postgresql16/psql:ro`, '-w', clientVisible, pinned,
        'pg_prove', '--ext', '.pg', '--ext', '.sql', '-r', clientVisible, clientHeld],
        { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
      const unchanged = (await Promise.all(files.map(async file => hash(await readFile(file.path)) === hash(file.content)))).every(Boolean);
      const timers = [...result.stdout.matchAll(/^(?:ok|not ok)\s+\d+ ms \(/gm)].length;
      const expectedTimers = files.filter(file => /\.(?:sql|pg)$/.test(file.path)).length;
      const raw = result.stdout.includes('1..') && /^ok 1 - synthetic (?:one|independent)$/m.test(result.stdout);
      const positive = fixture.name === 'success';
      const checkPassed = result.completed && result.signal === null && result.exitCode === (positive ? 0 : 1) && unchanged &&
        (!positive || (timers === expectedTimers && raw && /^Result: PASS$/m.test(result.stdout) && /^Files=2, Tests=3,/m.test(result.stdout)));
      results.push({ name: fixture.name, exitCode: result.exitCode, completed: result.completed, signal: result.signal,
        nativeMs: result.elapsedMs, stdoutSha256: hash(result.stdout), stderrSha256: hash(result.stderr),
        timerCount: timers, rawTapPresent: raw, inputsUnchanged: unchanged, fileMetadata: metadata, checkPassed });
    }
    const accepted = results.length === fixtures.length && results.every(result => result.checkPassed);
    const receipt = { formatVersion: NATIVE_DB_VALIDATION.formatVersion, sourceSha, cliVersion: NATIVE_DB_VALIDATION.cliVersion,
      clientDigest: NATIVE_DB_VALIDATION.clientDigest, runnerOs: runtime.RUNNER_OS, network: 'host',
      nativeClientImage: NATIVE_DB_VALIDATION.nativeClientImage, nativeClientImageId: nativeId,
      imageSelectionSource: 'https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/shared/legacy-docker-registry.ts',
      firstDirectoryCwd: true, readOnlyBinds: true, reportingLines: [...NATIVE_DB_VALIDATION.reportingLines],
      stubSha256: hash(stubText), capturedAt: new Date().toISOString(), cases: results, accepted };
    await privateWrite(join(directory, 'client-smoke.json'), jsonBytes(receipt));
    if (!accepted) throw refuse('REPORTING_UNVERIFIED');
    console.log(`Native client-only smoke: ${results.length} cases passed; no database connection.`);
  } finally {
    await removeSmokeFiles(parent, smokeRoot);
  }
}

async function removeSmokeFiles(parent, path) {
  const resolved = await realpath(path);
  if (resolved !== path || !inside(parent, resolved)) throw refuse('REPORTING_UNVERIFIED');
  await rm(resolved, { recursive: true });
}

function privateEncryptionKey() {
  const encodedKey = backupKeyEnv().BACKUP_ENCRYPTION_KEY_B64;
  const key = Buffer.from(encodedKey, 'base64');
  if (key.length !== PHASE8_BACKUP_LIMITS.keyBytes || key.toString('base64') !== encodedKey) {
    key.fill(0);
    throw refuse('RECEIPT_UNAVAILABLE');
  }
  return key;
}

async function verifyPrivateCustody(runtime, directory, evidence) {
  const bytes = await readFile(join(directory, 'private-custody.json'));
  const custody = JSON.parse(bytes.toString('utf8'));
  if (!exact(custody, ['formatVersion', 'runId', 'sourceSha', 'manifestSha256', 'artifactId', 'digest',
    'plaintextSha256', 'ciphertextSha256', 'verified', 'verifiedAt']) || !bytes.equals(jsonBytes(custody)) ||
      custody.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || custody.runId !== evidence.runId ||
      custody.runId !== `${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}` || custody.sourceSha !== evidence.sourceSha ||
      custody.manifestSha256 !== evidence.manifestSha256 || custody.verified !== true ||
      new Date(custody.verifiedAt).toISOString() !== custody.verifiedAt) throw refuse('RECEIPT_UNAVAILABLE');
  const plaintext = jsonBytes(evidence);
  const ciphertext = await readFile(join(directory, 'private-evidence.encrypted'));
  if (hash(plaintext) !== custody.plaintextSha256 || hash(ciphertext) !== custody.ciphertextSha256) throw refuse('RECEIPT_UNAVAILABLE');
  const key = privateEncryptionKey();
  try {
    const received = await readBackPrivateArtifact(runtime, `native-db-private-${evidence.runId}`,
      { id: custody.artifactId, digest: custody.digest }, ciphertext, evidence);
    const recovered = recoverNativePgtapOutput({ runId: runtime.GITHUB_RUN_ID, manifestSha256: evidence.manifestSha256,
      ciphertext: received, encryptionKey: key });
    if (!recovered.equals(plaintext)) throw refuse('RECEIPT_UNAVAILABLE');
  } finally { key.fill(0); }
}

async function protectEvidence(runtime, directory, evidence) {
  const key = privateEncryptionKey();
  try {
    const plaintext = jsonBytes(evidence);
    const ciphertext = protectNativePgtapOutput({ runId: runtime.GITHUB_RUN_ID, manifestSha256: evidence.manifestSha256,
      plaintext, encryptionKey: key });
    const recovery = bytes => recoverNativePgtapOutput({ runId: runtime.GITHUB_RUN_ID,
      manifestSha256: evidence.manifestSha256, ciphertext: bytes, encryptionKey: key });
    if (!recovery(ciphertext).equals(plaintext)) throw refuse('RECEIPT_UNAVAILABLE');
    const path = join(directory, 'private-evidence.encrypted');
    await privateWrite(path, ciphertext);
    const name = `native-db-private-${evidence.runId}`;
    const acknowledgement = await uploadArtifact(runtime, name, path, directory);
    const readBack = await readBackPrivateArtifact(runtime, name, acknowledgement, ciphertext, evidence);
    if (!recovery(readBack).equals(plaintext)) throw refuse('RECEIPT_UNAVAILABLE');
    await privateWrite(join(directory, 'private-custody.json'), jsonBytes({ formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: evidence.runId, sourceSha: evidence.sourceSha, manifestSha256: evidence.manifestSha256,
      artifactId: acknowledgement.id, digest: acknowledgement.digest, plaintextSha256: hash(plaintext),
      ciphertextSha256: hash(ciphertext), verified: true, verifiedAt: new Date().toISOString() }));
  } finally { key.fill(0); }
}

function options(argv, runtime) {
  const args = argv.length ? argv : [runtime.INPUT_COMMAND ?? runtime.DBV_RUN_COMMAND, '--manifest', runtime.INPUT_MANIFEST ?? runtime.DBV_MANIFEST,
    '--receipt', runtime.INPUT_RECEIPT ?? runtime.DBV_RECEIPT, '--out-dir', runtime['INPUT_OUT-DIR'] ?? runtime.DBV_OUT_DIR,
    '--source-sha', runtime['INPUT_SOURCE-SHA'] ?? runtime.DBV_SOURCE_SHA];
  const [command, ...tail] = args;
  if (!['manifest', 'run', 'verify', 'restore', 'restore-prior'].includes(command)) throw refuse();
  const result = { command };
  while (tail.length > 0) {
    const key = tail.shift();
    const value = tail.shift();
    const allowed = ['--manifest', '--receipt', '--out-dir', '--source-sha',
      ...(command === 'restore-prior' ? ['--target-run-id', '--target-run-attempt'] : [])];
    if (!allowed.includes(key) || Object.hasOwn(result, key) ||
        typeof value !== 'string' || value.length === 0) throw refuse();
    result[key] = value;
  }
  if (!sourceString(result['--source-sha']) || !result['--manifest'] || !result['--receipt'] ||
      (!result['--out-dir'] && command !== 'manifest')) throw refuse();
  if (command === 'restore-prior' && (!/^[1-9]\d*$/.test(result['--target-run-id'] ?? '') ||
      !/^[1-9]\d*$/.test(result['--target-run-attempt'] ?? ''))) throw refuse();
  if (!result['--out-dir']) result['--out-dir'] = join(runtime.RUNNER_TEMP, `native-db-${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}`);
  return result;
}

async function validatedManifest(path, expectedSource) {
  const value = JSON.parse(await readFile(path, 'utf8'));
  if (!exact(value, ['formatVersion', 'sourceSha', 'schemaIdentity', 'files']) || value.formatVersion !== NATIVE_DB_VALIDATION.formatVersion ||
      value.sourceSha !== expectedSource || !Array.isArray(value.files)) throw refuse('MANIFEST_INVALID');
  const manifest = buildNativePgtapManifest({ sourceSha: value.sourceSha, schemaIdentity: value.schemaIdentity,
    files: value.files.map(file => {
      if (!exact(file, ['path', 'sha256', 'plan'])) throw refuse('MANIFEST_INVALID');
      return { path: file.path, sha256: file.sha256, literalPlans: [file.plan] };
    }) });
  if (!jsonBytes(value).equals(jsonBytes(manifest))) throw refuse('MANIFEST_INVALID');
  return manifest;
}

function boundRecoveryReceipt(bytes, manifest, binding, artifactName) {
  if (!exact(binding, ['runId', 'runAttempt', 'sourceSha'])) throw refuse('TIMEOUT_CAPTURE_INVALID');
  const recovery = JSON.parse(bytes.toString('utf8'));
  const prefix = `${binding.runId}-`;
  const receiptAttempt = typeof recovery.runId === 'string' && recovery.runId.startsWith(prefix) ? recovery.runId.slice(prefix.length) : '';
  if (!exact(recovery, ['formatVersion', 'runId', 'sourceSha', 'manifestSha256', 'target', 'original', 'capturedAt', 'armed']) ||
      recovery.formatVersion !== NATIVE_DB_VALIDATION.formatVersion ||
      !/^[1-9]\d*$/.test(binding.runId ?? '') || !/^[1-9]\d*$/.test(binding.runAttempt ?? '') || !sourceString(binding.sourceSha) ||
      !/^[1-9]\d*$/.test(receiptAttempt) || BigInt(receiptAttempt) > BigInt(binding.runAttempt) ||
      artifactName !== `native-db-recovery-${recovery.runId}` ||
      recovery.sourceSha !== binding.sourceSha || recovery.manifestSha256 !== hash(jsonBytes(manifest)) ||
      JSON.stringify(recovery.target) !== JSON.stringify(target) || !validOriginal(recovery.original) || recovery.armed !== true ||
      typeof recovery.capturedAt !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(recovery.capturedAt) ||
      !Number.isSafeInteger(Date.parse(recovery.capturedAt)) || Date.parse(recovery.capturedAt) < 0 ||
      new Date(recovery.capturedAt).toISOString() !== recovery.capturedAt ||
      !bytes.equals(jsonBytes(recovery))) throw refuse('TIMEOUT_CAPTURE_INVALID');
  return recovery;
}

async function guardian(runtime, opts, manifest, directory, workdir, binding = {
  runId: runtime.GITHUB_RUN_ID, runAttempt: runtime.GITHUB_RUN_ATTEMPT, sourceSha: opts['--source-sha'],
}) {
  const bytes = await readFile(opts['--receipt']);
  const recovery = boundRecoveryReceipt(bytes, manifest, binding,
    runtime.DBV_RECOVERY_ARTIFACT ?? `native-db-recovery-${binding.runId}-${binding.runAttempt}`);
  let restored = false;
  let observed = null;
  try { await alterTimeout(workdir, directory, { target, setting: recovery.original }); restored = true; } catch { /* fresh verification still runs */ }
  try { observed = await queryTimeout(workdir, directory, target); } catch { /* missing observation is red */ }
  const verified = restored && observed !== null && sameTimeout(recovery.original, observed);
  const receipt = { formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId: recovery.runId,
    sourceSha: recovery.sourceSha, manifestSha256: recovery.manifestSha256, recoverySha256: hash(bytes),
    original: recovery.original, observed, verified, verifiedAt: new Date().toISOString() };
  const path = join(directory, 'restoration.json');
  await privateWrite(path, jsonBytes(receipt));
  if (!verified) throw refuse('TIMEOUT_NOT_RESTORED');
  console.log('Native database timeout restoration verified.');
}

async function recoverPriorTimeout(runtime, opts, directory, workdir) {
  const targetRun = opts['--target-run-id'];
  const targetAttempt = opts['--target-run-attempt'];
  const sourceSha = opts['--source-sha'];
  const recoveryWorkflow = NATIVE_DB_VALIDATION.workflowRef.replace('/db.yml@', '/native-database-recovery.yml@');
  if (runtime.GITHUB_ACTIONS !== 'true' || runtime.GITHUB_REPOSITORY !== NATIVE_DB_VALIDATION.repository ||
      runtime.GITHUB_EVENT_NAME !== 'workflow_dispatch' || runtime.GITHUB_REF !== NATIVE_DB_VALIDATION.mainRef ||
      runtime.GITHUB_WORKFLOW_REF !== recoveryWorkflow || runtime.GITHUB_JOB !== 'timeout-guardian' ||
      runtime.RUNNER_ENVIRONMENT !== 'github-hosted' || runtime.RUNNER_OS !== 'Linux' ||
      runtime.GITHUB_SHA !== sourceSha || !sourceString(sourceSha) ||
      ![runtime.GITHUB_RUN_ID, runtime.GITHUB_RUN_ATTEMPT, targetRun, targetAttempt].every(value =>
        typeof value === 'string' && /^[1-9]\d*$/.test(value))) throw refuse('RUNNER_UNTRUSTED');
  if ((await checked('git', ['rev-parse', 'HEAD'], { cwd: workdir })).trim() !== sourceSha ||
      (await checked('supabase', ['--version'], { cwd: workdir })).trim() !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
  const runResponse = await artifactApi(runtime, `actions/runs/${targetRun}/attempts/${targetAttempt}`, NATIVE_DB_VALIDATION.artifactMetadataStatus);
  const run = JSON.parse((await boundedResponseBytes(runResponse, NATIVE_DB_VALIDATION.timeoutQueryMaxBytes)).toString('utf8'));
  if (String(run?.id) !== targetRun || String(run.run_attempt) !== targetAttempt || !sourceString(run.head_sha) ||
      !['push', 'workflow_dispatch'].includes(run.event) || run.head_branch !== 'main' || run.status !== 'completed' ||
      typeof run.conclusion !== 'string' || run.conclusion.length === 0 || run.path !== '.github/workflows/db.yml' ||
      run.repository?.full_name !== NATIVE_DB_VALIDATION.repository) throw refuse('RECEIPT_UNAVAILABLE');
  const artifacts = [];
  let total = null;
  let page = 1;
  do {
    const response = await artifactApi(runtime, `actions/runs/${targetRun}/artifacts?page=${page}`, NATIVE_DB_VALIDATION.artifactMetadataStatus);
    const result = JSON.parse((await boundedResponseBytes(response, NATIVE_DB_VALIDATION.timeoutQueryMaxBytes)).toString('utf8'));
    if (!Number.isSafeInteger(result?.total_count) || result.total_count < 0 || !Array.isArray(result.artifacts) ||
        (total !== null && result.total_count !== total) || (result.artifacts.length === 0 && artifacts.length < result.total_count)) throw refuse('RECEIPT_UNAVAILABLE');
    total = result.total_count;
    artifacts.push(...result.artifacts);
    if (artifacts.length > total || artifacts.some(item => !Number.isSafeInteger(item?.id) || item.id <= 0) ||
        new Set(artifacts.map(item => item.id)).size !== artifacts.length) throw refuse('RECEIPT_UNAVAILABLE');
    page += 1;
  } while (artifacts.length < total);
  const binding = { runId: targetRun, runAttempt: targetAttempt, sourceSha: run.head_sha };
  const selected = [];
  for (const kind of ['manifest', 'recovery']) {
    const name = `native-db-${kind}-${targetRun}-${targetAttempt}`;
    const matches = artifacts.filter(item => item.name === name);
    if (matches.length !== 1) throw refuse('RECEIPT_UNAVAILABLE');
    const artifact = matches[0];
    if (artifact.expired !== false || !Number.isSafeInteger(artifact.size_in_bytes) || artifact.size_in_bytes <= 0 ||
        artifact.size_in_bytes > NATIVE_DB_VALIDATION.timeoutQueryMaxBytes ||
        !new RegExp(`^sha256:[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(artifact.digest) ||
        String(artifact.workflow_run?.id) !== targetRun || artifact.workflow_run.head_sha !== run.head_sha ||
        !Number.isSafeInteger(artifact.workflow_run.repository_id) || artifact.workflow_run.repository_id <= 0 ||
        artifact.workflow_run.head_repository_id !== artifact.workflow_run.repository_id) throw refuse('RECEIPT_UNAVAILABLE');
    selected.push(await readReceiptArtifact(runtime, artifact, `${kind}.json`));
  }
  const manifestPath = join(directory, 'prior-manifest.json');
  const recoveryPath = join(directory, 'prior-recovery.json');
  await privateWrite(manifestPath, jsonBytes(selected[0].value));
  await privateWrite(recoveryPath, jsonBytes(selected[1].value));
  const manifest = await validatedManifest(manifestPath, binding.sourceSha);
  const recoveryName = `native-db-recovery-${targetRun}-${targetAttempt}`;
  if (selected[1].value?.runId !== `${targetRun}-${targetAttempt}` ||
      (runtime.DBV_RECOVERY_ARTIFACT !== undefined && runtime.DBV_RECOVERY_ARTIFACT !== recoveryName)) throw refuse('TIMEOUT_CAPTURE_INVALID');
  boundRecoveryReceipt(jsonBytes(selected[1].value), manifest, binding, recoveryName);
  await checked('supabase', ['link', '--project-ref', NATIVE_DB_VALIDATION.projectRef, '--yes'],
    { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
  if ((await readFile(join(workdir, 'supabase/.temp/project-ref'), 'utf8')).trim() !== NATIVE_DB_VALIDATION.projectRef) throw refuse('RUNNER_UNTRUSTED');
  await guardian(runtime, { ...opts, '--receipt': recoveryPath }, manifest, directory, workdir, binding);
}

async function main() {
  const runtime = nativeDatabaseValidationEnv();
  const [, , ...argv] = process.argv;
  const opts = options(argv, runtime);
  const workdir = await realpath(process.cwd());
  const directory = await privateDirectory(opts['--out-dir'], workdir);
  const sourceSha = opts['--source-sha'];
  if (opts.command === 'restore-prior') {
    await recoverPriorTimeout(runtime, opts, directory, workdir);
    return;
  }
  if (opts.command === 'manifest') {
    const schemaReceipt = JSON.parse(await readFile(opts['--receipt'], 'utf8'));
    const manifest = buildNativePgtapManifest(await collectFiles(workdir, sourceSha, schemaReceipt, runtime));
    await writeFile(opts['--manifest'], jsonBytes(manifest), { flag: 'wx' });
    console.log(`Native database manifest: ${manifest.files.length} files / ${manifest.files.reduce((sum, file) => sum + file.plan, 0)} planned assertions.`);
    return;
  }
  const manifest = await validatedManifest(opts['--manifest'], sourceSha);
  if (opts.command === 'verify') {
    const evidence = JSON.parse(await readFile(join(directory, 'evidence.json'), 'utf8'));
    for (const stream of ['stdout', 'stderr']) {
      const output = evidence.outputs?.[stream];
      if (!output || !inside(directory, resolve(output.path))) throw refuse('RECEIPT_UNAVAILABLE');
      const bytes = await readFile(output.path);
      if (bytes.length !== output.byteLength || hash(bytes) !== output.sha256 || bytes.toString('utf8') !== evidence.native[stream]) throw refuse('HASH_CHANGED');
    }
    const verificationEvidence = await retainedVerificationEvidence(evidence, () => verifyPrivateCustody(runtime, directory, evidence));
    const receipt = verifyNativePgtapRun(manifest, verificationEvidence);
    await writeFile(opts['--receipt'], jsonBytes(receipt));
    console.log(`Native database validation: ${receipt.aggregate.verdict}; ${receipt.aggregate.files} files / ${receipt.aggregate.tests} assertions.`);
    if (!receipt.accepted) throw refuse(receipt.failureCodes[0]);
    return;
  }
  if (opts.command === 'restore') {
    if (runtime.GITHUB_ACTIONS !== 'true' || runtime.GITHUB_REPOSITORY !== NATIVE_DB_VALIDATION.repository ||
        runtime.GITHUB_SHA !== sourceSha || runtime.GITHUB_JOB !== 'timeout-guardian' ||
        runtime.RUNNER_ENVIRONMENT !== 'github-hosted' || runtime.RUNNER_OS !== 'Linux' ||
        !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ID ?? '') || !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ATTEMPT ?? '')) throw refuse('RUNNER_UNTRUSTED');
    if ((await checked('git', ['rev-parse', 'HEAD'], { cwd: workdir })).trim() !== sourceSha ||
        (await checked('supabase', ['--version'], { cwd: workdir })).trim() !== NATIVE_DB_VALIDATION.cliVersion) throw refuse('RUNNER_UNTRUSTED');
    if ((await readFile(join(workdir, 'supabase/.temp/project-ref'), 'utf8')).trim() !== target.projectRef) throw refuse('RUNNER_UNTRUSTED');
    await guardian(runtime, opts, manifest, directory, workdir);
    return;
  }
  const started = Date.now();
  const setupStarted = Date.parse(runtime.DBV_SETUP_STARTED_AT);
  if (!Number.isSafeInteger(setupStarted) || new Date(setupStarted).toISOString() !== runtime.DBV_SETUP_STARTED_AT ||
      setupStarted > started || started - setupStarted >= NATIVE_DB_VALIDATION.maxRunnerLifetimeMs) throw refuse('RUNNER_UNTRUSTED');
  const schemaReceipt = JSON.parse(await readFile(runtime.DBV_SCHEMA_RECEIPT, 'utf8'));
  if (runtime.GITHUB_ACTIONS !== 'true' || runtime.GITHUB_SHA !== sourceSha || runtime.GITHUB_REPOSITORY !== NATIVE_DB_VALIDATION.repository ||
      !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ID ?? '') || !/^[1-9]\d*$/.test(runtime.GITHUB_RUN_ATTEMPT ?? '')) throw refuse('RUNNER_UNTRUSTED');
  await ensureClientSmoke(runtime, sourceSha, workdir, directory);
  const linkStarted = Date.now();
  await checked('supabase', ['link', '--project-ref', target.projectRef, '--yes'], { cwd: workdir, timeoutMs: NATIVE_DB_VALIDATION.nativeCleanupReserveMs });
  const linkMs = Date.now() - linkStarted;
  await verifyRuntime(runtime, sourceSha, workdir);
  let nativeStarted = null;
  const { evidence } = await runNativePgtapValidation({ manifest, runId: `${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}`,
    workdir, retentionDirectory: directory, limits: { deadlineUtc: new Date(setupStarted + NATIVE_DB_VALIDATION.maxRunnerLifetimeMs).toISOString(),
      nativeTimeoutMs: NATIVE_DB_VALIDATION.maxRunnerLifetimeMs - NATIVE_DB_VALIDATION.nativeCleanupReserveMs } }, {
    collectFiles: ({ workdir: supplied }) => collectFiles(supplied, sourceSha, schemaReceipt, runtime),
    installReportingConfig, restoreReportingConfig,
    queryTimeout: requested => queryTimeout(workdir, directory, requested),
    alterTimeout: input => alterTimeout(workdir, directory, input),
    persistRecoveryReceipt: receipt => persistRecoveryReceipt(runtime, directory, manifest, receipt),
    retainPrivateOutput: async ({ runId, stream, text, retentionDirectory }) => {
      if (retentionDirectory !== directory || runId !== `${runtime.GITHUB_RUN_ID}-${runtime.GITHUB_RUN_ATTEMPT}`) throw refuse('RECEIPT_UNAVAILABLE');
      return privateWrite(join(directory, `${stream}.txt`), Buffer.from(text, 'utf8'));
    },
    runNativeCli: ({ command, args, cwd, limits }) => {
      nativeStarted = Date.now();
      return capture(command, args, { cwd,
        timeoutMs: Math.min(limits.nativeTimeoutMs, Math.max(1, Date.parse(limits.deadlineUtc) - nativeStarted)) });
    },
    now: () => Date.now(),
  });
  evidence.timings.linkMs = linkMs;
  evidence.timings.setupMs = (nativeStarted ?? Date.now()) - setupStarted;
  const evidenceCapturedAt = new Date().toISOString();
  evidence.timings.jobMs = Date.parse(evidenceCapturedAt) - setupStarted;
  await privateWrite(join(directory, 'timing-boundary.json'), jsonBytes({ formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    runId: evidence.runId, sourceSha, manifestSha256: evidence.manifestSha256, setupStartedAt: runtime.DBV_SETUP_STARTED_AT,
    nativeStartedAt: nativeStarted === null ? null : new Date(nativeStarted).toISOString(), evidenceCapturedAt,
    jobMsBoundary: 'first-workflow-step-through-evidence-capture', fullCiJobWallRecordedBy: 'hosted-github-job-metadata' }));
  await privateWrite(join(directory, 'evidence.json'), jsonBytes(evidence));
  const verificationEvidence = await retainedVerificationEvidence(evidence, () => protectEvidence(runtime, directory, evidence));
  const receipt = verifyNativePgtapRun(manifest, verificationEvidence);
  await writeFile(opts['--receipt'], jsonBytes(receipt));
  console.log(`Native database validation: ${receipt.aggregate.verdict}; ${receipt.aggregate.files} files / ${receipt.aggregate.tests} assertions; native ${receipt.timings.nativeMs}ms.`);
  if (!receipt.accepted) throw refuse(receipt.failureCodes[0]);
}

async function retainedVerificationEvidence(evidence, retain) {
  try { await retain(); return evidence; }
  catch {
    const failures = new Set(Array.isArray(evidence.preflightFailureCodes) ? evidence.preflightFailureCodes : []);
    failures.add('RECEIPT_UNAVAILABLE');
    return { ...evidence, preflightFailureCodes: [...failures].sort() };
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch(error => { console.error(`::error::Native database validation failed (${error.code ?? 'EVIDENCE_INVALID'}).`); process.exitCode = 1; });
}
