import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
import { DEL_CODE_POINT, IMPORT_FILE_NAME_MIN_CODE_POINT, NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';

/** @typedef {{migrationsSha256:string,generatedTypesSha256:string}} SchemaIdentity */
/** @typedef {{sourceSha:string,schemaIdentity:SchemaIdentity,files:Array<{path:string,sha256:string,literalPlans:number[]}>}} DiscoveredInputs */
/** @typedef {{formatVersion:number,sourceSha:string,schemaIdentity:SchemaIdentity,files:Array<{path:string,sha256:string,plan:number}>}} Manifest */
/** @typedef {{originalPresent:boolean,originalValue:string|null}} OriginalTimeout */
/** @typedef {{projectRef:string,role:string,parameter:string}} Target */
/** @typedef {{path:string,sha256:string,byteLength:number}} PrivateOutput */
/** @typedef {{completed:boolean,exitCode:number|null,signal:string|null,stdout:string,stderr:string,elapsedMs:number}} NativeResult */
/** @typedef {{setupMs:number,linkMs:number,nativeMs:number,jobMs:number}} Timings */
/** @typedef {{original:OriginalTimeout|null,observed:OriginalTimeout|null,verified:boolean}} TimeoutCleanup */
/** @typedef {{restored:boolean,verified:boolean}} ReportingCleanup */
/** @typedef {{path:string,originalPresent:boolean,originalText:string|null,installedSha256:string}} ReportingInstallation */
/** @typedef {{deadlineUtc:string,nativeTimeoutMs:number}} Limits */
/** @typedef {{formatVersion:number,runId:string,sourceSha:string,manifestSha256:string,target:Target,original:OriginalTimeout,capturedAt:string,armed:true}} RecoveryReceipt */
/** @typedef {{formatVersion:number,runId:string,sourceSha:string,schemaIdentity:SchemaIdentity,manifestSha256:string,native:NativeResult,outputs:{stdout:PrivateOutput|null,stderr:PrivateOutput|null},afterFiles:Array<{path:string,sha256:string}>,timings:Timings,timeout:TimeoutCleanup,reporting:ReportingCleanup,preflightFailureCodes:string[]}} Evidence */
/** @typedef {{path:string,plan:number,executed:number,failed:number,verdict:'PASS'|'FAIL'|'INCOMPLETE',durationMs:number|null}} FileResult */
/** @typedef {{formatVersion:number,runId:string,sourceSha:string,schemaIdentity:SchemaIdentity,manifestSha256:string,accepted:boolean,native:{completed:boolean,exitCode:number|null,signal:string|null},files:FileResult[],aggregate:{files:number,tests:number,failed:number,verdict:'PASS'|'FAIL'|'INCOMPLETE'},timings:Timings,timeout:TimeoutCleanup,reporting:ReportingCleanup,failureCodes:string[]}} FinalReceipt */
/**
 * @typedef {Object} NativePorts
 * @property {(input:{workdir:string})=>Promise<DiscoveredInputs>} collectFiles
 * @property {(input:{workdir:string,lines:string[]})=>Promise<ReportingInstallation>} installReportingConfig
 * @property {(installation:ReportingInstallation)=>Promise<ReportingCleanup>} restoreReportingConfig
 * @property {(target:Target)=>Promise<OriginalTimeout>} queryTimeout
 * @property {(input:{target:Target,setting:OriginalTimeout})=>Promise<void>} alterTimeout
 * @property {(receipt:RecoveryReceipt)=>Promise<{acknowledged:true,sha256:string}>} persistRecoveryReceipt
 * @property {(input:{runId:string,stream:'stdout'|'stderr',text:string,retentionDirectory:string})=>Promise<PrivateOutput>} retainPrivateOutput
 * @property {(input:{command:string,args:string[],cwd:string,limits:Limits})=>Promise<NativeResult>} runNativeCli
 * @property {()=>number} now
 */

const failureCatalogue = new Set([
  'MANIFEST_INVALID', 'EVIDENCE_INVALID', 'INPUT_CHANGED', 'REPORTING_UNVERIFIED',
  'TIMEOUT_CAPTURE_INVALID', 'RECEIPT_UNAVAILABLE', 'NATIVE_FAILED', 'NATIVE_INCOMPLETE',
  'TAP_FAILED', 'TAP_INCOMPLETE', 'HASH_CHANGED', 'TIMEOUT_NOT_RESTORED',
  'REPORTING_NOT_RESTORED', 'DEADLINE_EXCEEDED', 'RUNNER_UNTRUSTED',
]);
const target = Object.freeze({
  projectRef: NATIVE_DB_VALIDATION.projectRef,
  role: NATIVE_DB_VALIDATION.role,
  parameter: NATIVE_DB_VALIDATION.parameter,
});
const reportingText = `${NATIVE_DB_VALIDATION.reportingLines.join('\n')}\n`;
const suitePaths = NATIVE_DB_VALIDATION.nativeArgs.filter(argument => argument.startsWith('supabase/'));
const invalidData = Symbol('invalid native data');

function plainData(value, ancestors = new Set()) {
  if (typeof value === 'function') return invalidData;
  if (value === null || typeof value !== 'object') return value;
  if (ancestors.has(value)) return invalidData;
  try {
    const prototype = Object.getPrototypeOf(value);
    const array = Array.isArray(value);
    if (array ? prototype !== Array.prototype : prototype !== Object.prototype && prototype !== null) return invalidData;
    const keys = Reflect.ownKeys(value);
    let copy;
    if (array) {
      const length = Object.getOwnPropertyDescriptor(value, 'length');
      if (!length || !Object.hasOwn(length, 'value') || !count(length.value) || keys.length !== length.value + 1) return invalidData;
      copy = [];
      for (let index = 0; index < length.value; index += 1) {
        const descriptor = Object.getOwnPropertyDescriptor(value, String(index));
        if (!descriptor || !descriptor.enumerable || !Object.hasOwn(descriptor, 'value')) return invalidData;
      }
    } else copy = Object.create(null);
    ancestors.add(value);
    try {
      for (const key of keys) {
        if (array && key === 'length') continue;
        if (typeof key !== 'string') return invalidData;
        const descriptor = Object.getOwnPropertyDescriptor(value, key);
        copy[key] = descriptor?.enumerable && Object.hasOwn(descriptor, 'value')
          ? plainData(descriptor.value, ancestors) : invalidData;
      }
      return copy;
    } finally { ancestors.delete(value); }
  } catch { return invalidData; }
}

function exactObject(value, keys) {
  try {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    const prototype = Object.getPrototypeOf(value);
    if (prototype !== Object.prototype && prototype !== null) return false;
    const ownKeys = Reflect.ownKeys(value);
    return ownKeys.length === keys.length && ownKeys.every(key => {
      if (!keys.includes(key)) return false;
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      return descriptor?.enumerable === true && Object.hasOwn(descriptor, 'value');
    });
  } catch { return false; }
}

function callbackPorts(value, keys) {
  if (!exactObject(value, keys)) return invalidData;
  try {
    const copy = Object.create(null);
    for (const key of keys) {
      const descriptor = Object.getOwnPropertyDescriptor(value, key);
      if (!descriptor?.enumerable || !Object.hasOwn(descriptor, 'value') || typeof descriptor.value !== 'function') return invalidData;
      copy[key] = descriptor.value;
    }
    return copy;
  } catch { return invalidData; }
}

function text(value) {
  return typeof value === 'string' && value.length > 0;
}

function count(value) {
  return Number.isSafeInteger(value) && value >= 0;
}

function positive(value) {
  return count(value) && value > 0;
}

function hex(value, length) {
  return typeof value === 'string' && value.length === length && /^[a-f0-9]+$/.test(value);
}

function sha(value) {
  return hex(value, NATIVE_DB_VALIDATION.digestHexLength);
}

function sourceSha(value) {
  return hex(value, NATIVE_DB_VALIDATION.sourceShaLength);
}

function schemaIdentity(value) {
  return exactObject(value, ['migrationsSha256', 'generatedTypesSha256']) &&
    sha(value.migrationsSha256) && sha(value.generatedTypesSha256);
}

function containsControl(value) {
  return Array.from(value).some(character => {
    const point = character.codePointAt(0);
    return point < IMPORT_FILE_NAME_MIN_CODE_POINT || point === DEL_CODE_POINT;
  });
}

function normalizedPath(value) {
  if (!text(value) || containsControl(value)) return null;
  const normalized = value.replaceAll('\\', '/');
  if (normalized.split('/').some(part => part === '.' || part === '..' || part === '')) return null;
  if (!suitePaths.some(suite => normalized.startsWith(`${suite}/`))) return null;
  return /\.(?:sql|pg)$/.test(normalized) ? normalized : null;
}

function ordinal(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function digest(value) {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function manifestDigest(manifest) {
  return digest(`${JSON.stringify(manifest)}\n`);
}

function manifestRefusal() {
  const error = new Error('Native pgTAP manifest is invalid');
  error.code = 'MANIFEST_INVALID';
  return error;
}

/** @param {unknown} input @returns {Manifest} */
export function buildNativePgtapManifest(input) {
  input = plainData(input);
  if (!exactObject(input, ['sourceSha', 'schemaIdentity', 'files']) ||
      !sourceSha(input.sourceSha) || !schemaIdentity(input.schemaIdentity) || !Array.isArray(input.files)) {
    throw manifestRefusal();
  }
  const paths = new Set();
  let plans = 0;
  const files = input.files.map(file => {
    if (!exactObject(file, ['path', 'sha256', 'literalPlans']) || !sha(file.sha256) ||
        !Array.isArray(file.literalPlans) || file.literalPlans.length !== 1 || !positive(file.literalPlans[0])) {
      throw manifestRefusal();
    }
    const path = normalizedPath(file.path);
    if (path === null || paths.has(path)) throw manifestRefusal();
    paths.add(path);
    plans += file.literalPlans[0];
    if (!count(plans)) throw manifestRefusal();
    return { path, sha256: file.sha256, plan: file.literalPlans[0] };
  }).sort((left, right) => ordinal(left.path, right.path));
  if (!suitePaths.every(suite => files.some(file => file.path.startsWith(`${suite}/`)))) throw manifestRefusal();
  return {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    sourceSha: input.sourceSha,
    schemaIdentity: {
      migrationsSha256: input.schemaIdentity.migrationsSha256,
      generatedTypesSha256: input.schemaIdentity.generatedTypesSha256,
    },
    files,
  };
}

function canonicalManifest(value) {
  value = plainData(value);
  if (!exactObject(value, ['formatVersion', 'sourceSha', 'schemaIdentity', 'files']) ||
      value.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || !Array.isArray(value.files)) throw manifestRefusal();
  const files = value.files.map(file => {
    if (!exactObject(file, ['path', 'sha256', 'plan']) || normalizedPath(file.path) !== file.path) throw manifestRefusal();
    return { path: file.path, sha256: file.sha256, literalPlans: [file.plan] };
  });
  const manifest = buildNativePgtapManifest({ sourceSha: value.sourceSha, schemaIdentity: value.schemaIdentity, files });
  if (manifest.files.some((file, index) => file.path !== value.files[index].path)) throw manifestRefusal();
  return manifest;
}

function originalTimeout(value) {
  return exactObject(value, ['originalPresent', 'originalValue']) && typeof value.originalPresent === 'boolean' &&
    (value.originalPresent ? text(value.originalValue) : value.originalValue === null);
}

function sameTimeout(left, right) {
  return originalTimeout(left) && originalTimeout(right) && left.originalPresent === right.originalPresent &&
    left.originalValue === right.originalValue;
}

function privateOutput(value) {
  return exactObject(value, ['path', 'sha256', 'byteLength']) && text(value.path) && sha(value.sha256) && count(value.byteLength);
}

function nativeResult(value) {
  return exactObject(value, ['completed', 'exitCode', 'signal', 'stdout', 'stderr', 'elapsedMs']) &&
    typeof value.completed === 'boolean' && (value.exitCode === null || count(value.exitCode)) &&
    (value.signal === null || text(value.signal)) && (value.exitCode === null || value.signal === null) &&
    typeof value.stdout === 'string' && typeof value.stderr === 'string' && count(value.elapsedMs);
}

function timings(value) {
  return exactObject(value, ['setupMs', 'linkMs', 'nativeMs', 'jobMs']) && Object.values(value).every(count);
}

function timeoutCleanup(value) {
  return exactObject(value, ['original', 'observed', 'verified']) && typeof value.verified === 'boolean' &&
    (value.original === null || originalTimeout(value.original)) && (value.observed === null || originalTimeout(value.observed));
}

function reportingCleanup(value) {
  return exactObject(value, ['restored', 'verified']) && typeof value.restored === 'boolean' && typeof value.verified === 'boolean';
}

function afterFiles(value) {
  if (!Array.isArray(value)) return false;
  const paths = new Set();
  return value.every(file => {
    if (!exactObject(file, ['path', 'sha256']) || normalizedPath(file.path) !== file.path || !sha(file.sha256) || paths.has(file.path)) return false;
    paths.add(file.path);
    return true;
  });
}

function failureCodes(value) {
  return Array.isArray(value) && new Set(value).size === value.length && value.every(code => failureCatalogue.has(code));
}

function validEvidence(value) {
  return exactObject(value, ['formatVersion', 'runId', 'sourceSha', 'schemaIdentity', 'manifestSha256', 'native',
    'outputs', 'afterFiles', 'timings', 'timeout', 'reporting', 'preflightFailureCodes']) &&
    value.formatVersion === NATIVE_DB_VALIDATION.formatVersion && text(value.runId) && sourceSha(value.sourceSha) &&
    schemaIdentity(value.schemaIdentity) && sha(value.manifestSha256) && nativeResult(value.native) &&
    exactObject(value.outputs, ['stdout', 'stderr']) &&
    (value.outputs.stdout === null || privateOutput(value.outputs.stdout)) &&
    (value.outputs.stderr === null || privateOutput(value.outputs.stderr)) && afterFiles(value.afterFiles) &&
    timings(value.timings) && timeoutCleanup(value.timeout) && reportingCleanup(value.reporting) && failureCodes(value.preflightFailureCodes);
}

function sanitizedNative(value) {
  return {
    completed: typeof value?.completed === 'boolean' ? value.completed : false,
    exitCode: count(value?.exitCode) ? value.exitCode : null,
    signal: text(value?.signal) ? value.signal : null,
    stdout: typeof value?.stdout === 'string' ? value.stdout : '',
    stderr: typeof value?.stderr === 'string' ? value.stderr : '',
    elapsedMs: count(value?.elapsedMs) ? value.elapsedMs : 0,
  };
}

function sanitizedTimeout(value) {
  return {
    original: originalTimeout(value?.original) ? { originalPresent: value.original.originalPresent, originalValue: value.original.originalValue } : null,
    observed: originalTimeout(value?.observed) ? { originalPresent: value.observed.originalPresent, originalValue: value.observed.originalValue } : null,
    verified: value?.verified === true,
  };
}

function sanitizedReporting(value) {
  return { restored: value?.restored === true, verified: value?.verified === true };
}

function emptyManifest() {
  return {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    sourceSha: '0'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    schemaIdentity: {
      migrationsSha256: '0'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      generatedTypesSha256: '0'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
    },
    files: [],
  };
}

function nativeDiagnostic(value) {
  return value.split(/\r\n|\n|\r/).some(line => {
    if (/^\s*#|^(?:ok|not ok)\s+\d+(?:\s|$)/.test(line)) return false;
    return /^\s*(?:(?:psql|postgres|supabase):.*?\s*)?(?:ERROR|FATAL|PANIC):|^\s*Dubious,|^\s*Bail out!|^\s*Non-zero exit status:|connection to server.*failed/i.test(line);
  });
}

function parseNativeOutput(manifest, stdout, stderr, failures) {
  const observations = new Map();
  let current = null;
  let headers = 0;
  let successMarkers = 0;
  const summaries = [];
  const verdicts = [];
  let failedDiagnostic = nativeDiagnostic(stdout) || nativeDiagnostic(stderr);
  let incomplete = false;
  const lines = stdout.split(/\r\n|\n|\r/);
  for (const line of lines) {
    const header = /^\[\d\d:\d\d:\d\d\]\s+(.+?)\s+\.+\s*$/.exec(line);
    if (header) {
      headers += 1;
      const reported = header[1].replaceAll('\\', '/');
      const file = manifest.files.find(item => reported === item.path || reported.endsWith(`/${item.path}`));
      if (!file || observations.has(file.path)) {
        incomplete = true;
        current = null;
      } else {
        current = { file, plans: [], executed: 0, failed: 0, durationMs: null, timers: 0, versions: 0, incomplete: false, failedDiagnostic: false };
        observations.set(file.path, current);
      }
      continue;
    }
    if (/^\[\d\d:\d\d:\d\d\]\s*$/.test(line)) { current = null; continue; }
    if (line === 'All tests successful.') { successMarkers += 1; current = null; continue; }
    const summary = /^Files=(\d+),\s*Tests=(\d+),\s+.+$/.exec(line);
    if (summary) { summaries.push({ files: Number(summary[1]), tests: Number(summary[2]) }); current = null; continue; }
    const verdict = /^Result:\s*(PASS|FAIL)\s*$/.exec(line);
    if (verdict) { verdicts.push(verdict[1]); current = null; continue; }
    if (nativeDiagnostic(line)) {
      failedDiagnostic = true;
      if (current) current.failedDiagnostic = true;
      continue;
    }
    if (!line.trim() || /^\s*#/.test(line)) continue;
    if (!current) {
      // Summary diagnostics from a failed native client do not become TAP authority.
      if (!/^Test Summary Report$|^-+$|^.+\(Wstat:|^\s+(?:Failed tests:|Parse errors:|Bad plan\.)/.test(line)) incomplete = true;
      continue;
    }
    const timer = /^(ok|not ok)\s+(\d+)\s+ms\s+\(.+\)\s*$/.exec(line);
    if (timer) {
      current.timers += 1;
      const duration = Number(timer[2]);
      if (!count(duration) || current.timers !== 1) current.incomplete = true;
      else current.durationMs = duration;
      if (timer[1] === 'not ok') { current.failedDiagnostic = true; failedDiagnostic = true; }
      continue;
    }
    const plan = /^1\.\.(\d+)(?:\s*#.*)?\s*$/.exec(line);
    if (plan) {
      current.plans.push(Number(plan[1]));
      if (current.timers > 0) current.incomplete = true;
      continue;
    }
    const assertion = /^(not ok|ok)\s+(\d+)(?:\s|$)/.exec(line);
    if (assertion) {
      current.executed += 1;
      if (Number(assertion[2]) !== current.executed || current.timers > 0) current.incomplete = true;
      if (assertion[1] === 'not ok') current.failed += 1;
      continue;
    }
    if (/^TAP version \d+$/.test(line)) {
      current.versions += 1;
      if (current.versions !== 1 || current.plans.length > 0 || current.executed > 0 || current.timers > 0) current.incomplete = true;
      continue;
    }
    if (/^All \d+ subtests passed\s*$/.test(line)) continue;
    if (/^\s*(?:ERROR|FATAL|PANIC)\b/i.test(line)) { current.incomplete = true; continue; }
    // Uppercase SQL status identifiers are not native lowercase test tokens.
    if (/^\s*[A-Z][A-Z0-9_]*\s*$/.test(line)) continue;
    // Native SQL result rows are non-test output; malformed control records still refuse.
    if (/^\s*(?:(?:not\s+)?ok\b|1\.|TAP\s+version\b|All\s+(?:tests\b|.*\bsubtests\b)|Files\b|Result\b|(?:ERROR|FATAL|PANIC)\b|(?:psql|postgres|supabase):|\[\d\d:)/i.test(line)) current.incomplete = true;
  }
  const files = manifest.files.map(file => {
    const observed = observations.get(file.path);
    const complete = observed && !observed.incomplete && observed.plans.length === 1 &&
      observed.plans[0] === file.plan && observed.executed === file.plan && observed.timers === 1 && observed.durationMs !== null;
    if (!complete) incomplete = true;
    if (!observed || observed.durationMs === null || observed.timers !== 1) failures.add('REPORTING_UNVERIFIED');
    return {
      path: file.path, plan: file.plan, executed: observed?.executed ?? 0, failed: observed?.failed ?? 0,
      verdict: observed?.failed > 0 || observed?.failedDiagnostic ? 'FAIL' : complete ? 'PASS' : 'INCOMPLETE',
      durationMs: observed?.durationMs ?? null,
    };
  });
  const tests = files.reduce((total, file) => total + file.executed, 0);
  const failed = files.reduce((total, file) => total + file.failed, 0);
  const expectedTests = manifest.files.reduce((total, file) => total + file.plan, 0);
  const summary = summaries[0];
  if (headers !== manifest.files.length || summaries.length !== 1 || !count(summary?.files) || !count(summary?.tests) ||
      summary.files !== manifest.files.length || summary.tests !== expectedTests || summary.tests !== tests ||
      verdicts.length !== 1 || successMarkers !== 1 || lines.filter(line => line.trim()).at(-1) !== 'Result: PASS') incomplete = true;
  if (failed > 0 || failedDiagnostic || verdicts.includes('FAIL')) failures.add('TAP_FAILED');
  if (incomplete) failures.add('TAP_INCOMPLETE');
  return {
    files,
    aggregate: { files: headers, tests, failed, verdict: failed > 0 || failedDiagnostic || verdicts.includes('FAIL') ? 'FAIL' : incomplete ? 'INCOMPLETE' : 'PASS' },
  };
}

/** @param {Manifest} manifestInput @param {unknown} evidence @returns {FinalReceipt} */
export function verifyNativePgtapRun(manifestInput, evidence) {
  evidence = plainData(evidence);
  const failures = new Set();
  let manifest;
  try { manifest = canonicalManifest(manifestInput); }
  catch { manifest = emptyManifest(); failures.add('MANIFEST_INVALID'); }
  if (!validEvidence(evidence)) failures.add('EVIDENCE_INVALID');
  if (Array.isArray(evidence?.preflightFailureCodes)) {
    for (const code of evidence.preflightFailureCodes) if (failureCatalogue.has(code)) failures.add(code);
  }
  const native = sanitizedNative(evidence?.native);
  if (!native.completed || native.exitCode === null && native.signal === null) failures.add('NATIVE_INCOMPLETE');
  if (native.exitCode !== null && native.exitCode !== 0 || native.signal !== null) failures.add('NATIVE_FAILED');
  const parsed = parseNativeOutput(manifest, native.stdout, native.stderr, failures);
  const manifestSha256 = manifestDigest(manifest);
  if (evidence?.sourceSha !== manifest.sourceSha || !schemaIdentity(evidence?.schemaIdentity) ||
      evidence.schemaIdentity.migrationsSha256 !== manifest.schemaIdentity.migrationsSha256 ||
      evidence.schemaIdentity.generatedTypesSha256 !== manifest.schemaIdentity.generatedTypesSha256 ||
      evidence?.manifestSha256 !== manifestSha256) failures.add('INPUT_CHANGED');
  if (!afterFiles(evidence?.afterFiles) || evidence.afterFiles.length !== manifest.files.length ||
      manifest.files.some(file => !evidence.afterFiles.some(after => after.path === file.path && after.sha256 === file.sha256))) failures.add('INPUT_CHANGED');
  for (const stream of ['stdout', 'stderr']) {
    const output = evidence?.outputs?.[stream];
    if (!privateOutput(output) || output.sha256 !== digest(native[stream]) || output.byteLength !== Buffer.byteLength(native[stream], 'utf8')) failures.add('HASH_CHANGED');
  }
  const timeout = sanitizedTimeout(evidence?.timeout);
  if (!timeoutCleanup(evidence?.timeout) || !timeout.verified || !sameTimeout(timeout.original, timeout.observed)) failures.add('TIMEOUT_NOT_RESTORED');
  const reporting = sanitizedReporting(evidence?.reporting);
  if (!reportingCleanup(evidence?.reporting) || !reporting.restored || !reporting.verified) failures.add('REPORTING_NOT_RESTORED');
  const failureList = [...failures].sort(ordinal);
  return {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    runId: text(evidence?.runId) ? evidence.runId : 'unavailable',
    sourceSha: manifest.sourceSha,
    schemaIdentity: manifest.schemaIdentity,
    manifestSha256,
    accepted: failureList.length === 0,
    native: { completed: native.completed, exitCode: native.exitCode, signal: native.signal },
    files: parsed.files,
    aggregate: parsed.aggregate,
    timings: timings(evidence?.timings) ? { setupMs: evidence.timings.setupMs, linkMs: evidence.timings.linkMs, nativeMs: evidence.timings.nativeMs, jobMs: evidence.timings.jobMs } : { setupMs: 0, linkMs: 0, nativeMs: native.elapsedMs, jobMs: 0 },
    timeout,
    reporting,
    failureCodes: failureList,
  };
}

function utcTimestamp(value) {
  if (!text(value) || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(value)) return false;
  const parsed = Date.parse(value);
  return count(parsed) && new Date(parsed).toISOString() === value;
}

function insideDirectory(path, directory) {
  if (!text(path) || !text(directory) || containsControl(path + directory)) return false;
  let child = path.replaceAll('\\', '/');
  let parent = directory.replaceAll('\\', '/').replace(/\/+$/, '');
  if (child.split('/').some(part => part === '.' || part === '..') || parent.split('/').some(part => part === '.' || part === '..')) return false;
  if (/^[A-Za-z]:\//.test(parent)) { child = child.toLowerCase(); parent = parent.toLowerCase(); }
  return child.startsWith(`${parent}/`) && child.length > parent.length + 1;
}

function validInstallation(value, workdir) {
  return exactObject(value, ['path', 'originalPresent', 'originalText', 'installedSha256']) && text(value.path) &&
    value.path.replaceAll('\\', '/') === `${workdir.replaceAll('\\', '/').replace(/\/+$/, '')}/${suitePaths[0]}/.proverc` &&
    typeof value.originalPresent === 'boolean' &&
    (value.originalPresent ? value.originalText === reportingText : value.originalText === null) && value.installedSha256 === digest(reportingText);
}

function sameManifest(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

/**
 * @param {unknown} input
 * @param {NativePorts} ports
 * @returns {Promise<{evidence:Evidence,receipt:FinalReceipt}>}
 */
export async function runNativePgtapValidation(input, ports) {
  input = plainData(input);
  const portKeys = ['collectFiles', 'installReportingConfig', 'restoreReportingConfig', 'queryTimeout', 'alterTimeout',
    'persistRecoveryReceipt', 'retainPrivateOutput', 'runNativeCli', 'now'];
  ports = callbackPorts(ports, portKeys);
  const failures = new Set();
  let manifest;
  try { manifest = canonicalManifest(input?.manifest); }
  catch { manifest = emptyManifest(); failures.add('MANIFEST_INVALID'); }
  const evidence = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    runId: text(input?.runId) ? input.runId : 'unavailable',
    sourceSha: manifest.sourceSha,
    schemaIdentity: manifest.schemaIdentity,
    manifestSha256: manifestDigest(manifest),
    native: sanitizedNative(null),
    outputs: { stdout: null, stderr: null },
    afterFiles: [],
    timings: { setupMs: 0, linkMs: 0, nativeMs: 0, jobMs: 0 },
    timeout: { original: null, observed: null, verified: false },
    reporting: { restored: false, verified: false },
    preflightFailureCodes: [],
  };
  const validInput = exactObject(input, ['manifest', 'runId', 'workdir', 'retentionDirectory', 'limits']) &&
    text(input.runId) && text(input.workdir) && text(input.retentionDirectory) &&
    exactObject(input.limits, ['deadlineUtc', 'nativeTimeoutMs']) && utcTimestamp(input.limits.deadlineUtc) && positive(input.limits.nativeTimeoutMs);
  if (!validInput || !exactObject(ports, portKeys) || !portKeys.every(key => typeof ports[key] === 'function')) failures.add('EVIDENCE_INVALID');
  if (failures.size > 0) {
    evidence.preflightFailureCodes = [...failures].sort(ordinal);
    return { evidence, receipt: verifyNativePgtapRun(manifest, evidence) };
  }
  const runId = input.runId;
  const workdir = input.workdir;
  const retentionDirectory = input.retentionDirectory;
  const limits = Object.freeze({ deadlineUtc: input.limits.deadlineUtc, nativeTimeoutMs: input.limits.nativeTimeoutMs });
  const deadline = Date.parse(limits.deadlineUtc);
  let started = null;
  let installed;
  let installationReturned = false;
  let armed = false;
  let nativeAttempted = false;
  const clock = () => {
    try {
      const value = ports.now();
      if (!count(value)) throw new Error('Invalid clock');
      return value;
    } catch { failures.add('EVIDENCE_INVALID'); return null; }
  };
  const expired = () => {
    const value = clock();
    if (value === null || value >= deadline) { failures.add('DEADLINE_EXCEEDED'); return true; }
    return false;
  };
  const execute = async () => {
    started = clock();
    if (started === null || expired()) return;
    try {
      const before = buildNativePgtapManifest(await ports.collectFiles({ workdir }));
      if (!sameManifest(manifest, before)) failures.add('INPUT_CHANGED');
    } catch { failures.add('INPUT_CHANGED'); }
    if (failures.size > 0 || expired()) return;
    try {
      installed = await ports.installReportingConfig({ workdir, lines: [...NATIVE_DB_VALIDATION.reportingLines] });
      installationReturned = true;
      if (!validInstallation(plainData(installed), workdir)) failures.add('REPORTING_UNVERIFIED');
    } catch { failures.add('REPORTING_UNVERIFIED'); }
    if (failures.size > 0 || expired()) return;
    try {
      const original = plainData(await ports.queryTimeout(target));
      if (!originalTimeout(original)) failures.add('TIMEOUT_CAPTURE_INVALID');
      else evidence.timeout.original = Object.freeze({ originalPresent: original.originalPresent, originalValue: original.originalValue });
    } catch { failures.add('TIMEOUT_CAPTURE_INVALID'); }
    if (failures.size > 0 || expired()) return;
    try {
      const capturedAt = clock();
      if (capturedAt === null) failures.add('RECEIPT_UNAVAILABLE');
      else {
        const acknowledgement = plainData(await ports.persistRecoveryReceipt({
          formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId, sourceSha: manifest.sourceSha,
          manifestSha256: evidence.manifestSha256, target, original: evidence.timeout.original,
          capturedAt: new Date(capturedAt).toISOString(), armed: true,
        }));
        if (!exactObject(acknowledgement, ['acknowledged', 'sha256']) || acknowledgement.acknowledged !== true || !sha(acknowledgement.sha256)) failures.add('RECEIPT_UNAVAILABLE');
      }
    } catch { failures.add('RECEIPT_UNAVAILABLE'); }
    if (failures.size > 0 || expired()) return;
    armed = true;
    try { await ports.alterTimeout({ target, setting: { originalPresent: true, originalValue: NATIVE_DB_VALIDATION.temporaryTimeout } }); }
    catch { failures.add('NATIVE_FAILED'); }
    if (failures.size > 0 || expired()) return;
    const nativeStarted = clock();
    if (nativeStarted === null) return;
    evidence.timings.setupMs = Math.max(0, nativeStarted - started);
    nativeAttempted = true;
    try {
      const result = plainData(await ports.runNativeCli({ command: NATIVE_DB_VALIDATION.nativeCommand, args: [...NATIVE_DB_VALIDATION.nativeArgs], cwd: workdir, limits }));
      if (!nativeResult(result)) failures.add('EVIDENCE_INVALID');
      evidence.native = sanitizedNative(result);
    } catch { failures.add('NATIVE_INCOMPLETE'); }
    evidence.timings.nativeMs = evidence.native.elapsedMs;
    if (evidence.native.elapsedMs > limits.nativeTimeoutMs) failures.add('DEADLINE_EXCEEDED');
    expired();
    for (const stream of ['stdout', 'stderr']) {
      try {
        const output = plainData(await ports.retainPrivateOutput({ runId, stream, text: evidence.native[stream], retentionDirectory }));
        if (!privateOutput(output) || !insideDirectory(output.path, retentionDirectory)) failures.add('RECEIPT_UNAVAILABLE');
        else evidence.outputs[stream] = { path: output.path, sha256: output.sha256, byteLength: output.byteLength };
      } catch { failures.add('RECEIPT_UNAVAILABLE'); }
    }
  };
  try {
    await execute();
  } finally {
    if (nativeAttempted) {
      try {
        const after = buildNativePgtapManifest(await ports.collectFiles({ workdir }));
        evidence.afterFiles = after.files.map(({ path, sha256 }) => ({ path, sha256 }));
        if (!sameManifest(manifest, after)) failures.add('INPUT_CHANGED');
      } catch { failures.add('INPUT_CHANGED'); }
    }
    if (armed) {
      let restored = false;
      try { await ports.alterTimeout({ target, setting: evidence.timeout.original }); restored = true; }
      catch { failures.add('TIMEOUT_NOT_RESTORED'); }
      try {
        const observed = plainData(await ports.queryTimeout(target));
        if (originalTimeout(observed)) evidence.timeout.observed = { originalPresent: observed.originalPresent, originalValue: observed.originalValue };
        evidence.timeout.verified = restored && sameTimeout(evidence.timeout.original, evidence.timeout.observed);
      } catch { failures.add('TIMEOUT_NOT_RESTORED'); }
    }
    if (installationReturned) {
      try {
        const cleanup = plainData(await ports.restoreReportingConfig(installed));
        if (!reportingCleanup(cleanup)) failures.add('EVIDENCE_INVALID');
        evidence.reporting = sanitizedReporting(cleanup);
      } catch { failures.add('REPORTING_NOT_RESTORED'); }
    }
    const ended = clock();
    if (ended !== null && started !== null) evidence.timings.jobMs = Math.max(0, ended - started);
    expired();
  }
  return finish();

  function finish() {
    evidence.preflightFailureCodes = [...failures].sort(ordinal);
    return { evidence, receipt: verifyNativePgtapRun(manifest, evidence) };
  }
}
