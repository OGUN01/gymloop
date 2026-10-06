import { createHash } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';

// Independent synthetic contract tests. No application SQL, visible suite,
// implementation or workflow was consulted by this author. Native formatting
// was checked using official pg_prove 3.36 with a synthetic psql executable.
const modulePath = new URL('../../scripts/pgtap/native.mjs', import.meta.url).href;
type Schema = { migrationsSha256: string; generatedTypesSha256: string };
type File = { path: string; sha256: string; plan: number };
type Manifest = { formatVersion: number; sourceSha: string; schemaIdentity: Schema; files: File[] };
type Original = { originalPresent: boolean; originalValue: string | null };
type Native = { completed: boolean; exitCode: number | null; signal: string | null; stdout: string; stderr: string; elapsedMs: number };
type Output = { path: string; sha256: string; byteLength: number };
type Timings = { setupMs: number; linkMs: number; nativeMs: number; jobMs: number };
type Timeout = { original: Original | null; observed: Original | null; verified: boolean };
type Reporting = { restored: boolean; verified: boolean };
type Evidence = {
  formatVersion: number; runId: string; sourceSha: string; schemaIdentity: Schema;
  manifestSha256: string; native: Native;
  outputs: { stdout: Output | null; stderr: Output | null };
  afterFiles: { path: string; sha256: string }[]; timings: Timings;
  timeout: Timeout; reporting: Reporting; preflightFailureCodes: string[];
};
type FileResult = { path: string; plan: number; executed: number; failed: number; verdict: string; durationMs: number | null };
type Receipt = {
  formatVersion: number; runId: string; sourceSha: string; schemaIdentity: Schema;
  manifestSha256: string; accepted: boolean;
  native: { completed: boolean; exitCode: number | null; signal: string | null };
  files: FileResult[]; aggregate: { files: number; tests: number; failed: number; verdict: string };
  timings: Timings; timeout: Timeout; reporting: Reporting; failureCodes: string[];
};
type Harness = {
  buildNativePgtapManifest: (input: unknown) => Manifest;
  verifyNativePgtapRun: (manifest: unknown, evidence: unknown) => Receipt;
  runNativePgtapValidation: (input: unknown, ports: unknown) => Promise<{ evidence: Evidence; receipt: Receipt }>;
};
const harness = await import(modulePath) as Harness;
const sourceSha = '128fea993a8bb8a19a120a5a9e991095f7a20d84';
const runId = 'held-native-run';
const workdir = 'C:/db-held-worker';
const retentionDirectory = 'C:/protected-held-evidence/held-native-run';
const target = { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' };
const lines = ['--timer', '--verbose', '--parse', '--nocolor', '--jobs=1'];
const approvedConfig = `${lines.join('\n')}\n`;
const clockNow = Date.parse('2026-10-07T12:00:00.000Z');
const limits = { deadlineUtc: '2026-10-07T12:04:00.000Z', nativeTimeoutMs: 60000 };
const privateCanary = 'PRIVATE_SYNTHETIC_FIXTURE_MEMBER_938421';
const stderrCanary = 'PRIVATE_SYNTHETIC_DIAGNOSTIC_19842';
const failureCodes = [
  'MANIFEST_INVALID', 'EVIDENCE_INVALID', 'INPUT_CHANGED', 'REPORTING_UNVERIFIED',
  'TIMEOUT_CAPTURE_INVALID', 'RECEIPT_UNAVAILABLE', 'NATIVE_FAILED', 'NATIVE_INCOMPLETE',
  'TAP_FAILED', 'TAP_INCOMPLETE', 'HASH_CHANGED', 'TIMEOUT_NOT_RESTORED',
  'REPORTING_NOT_RESTORED', 'DEADLINE_EXCEEDED', 'RUNNER_UNTRUSTED',
];

function digest(text: string) {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function schema() {
  return { migrationsSha256: digest('synthetic schema identity'), generatedTypesSha256: digest('synthetic generated identity') };
}

function manifest(): Manifest {
  return {
    formatVersion: 1,
    sourceSha,
    schemaIdentity: schema(),
    files: [
      { path: 'supabase/tests-holdout/nested/held.sql', sha256: digest('synthetic held fixture'), plan: 2 },
      { path: 'supabase/tests/alpha.sql', sha256: digest('synthetic visible alpha'), plan: 2 },
      { path: 'supabase/tests/nested/zeta.pg', sha256: digest('synthetic visible zeta'), plan: 1 },
    ],
  };
}

function discovered() {
  return {
    sourceSha,
    schemaIdentity: schema(),
    files: manifest().files.slice().reverse().map(({ path, sha256, plan }) => ({ path, sha256, literalPlans: [plan] })),
  };
}

// The header, raw TAP, completion timer and aggregate shape are from the pinned
// official client's native formatter, using invented fixture paths/values only.
function nativeStdout() {
  return [
    '[12:00:01] supabase/tests/alpha.sql ............. ',
    '1..2',
    `ok 1 - ${privateCanary} alpha`,
    'ok 2 - synthetic beta',
    'ok       12 ms ( 0.00 usr  0.00 sys +  0.01 cusr  0.00 csys =  0.01 CPU)',
    '[12:00:01] supabase/tests/nested/zeta.pg ........ ',
    '1..1',
    'ok 1 - synthetic gamma',
    'ok        0 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
    '[12:00:01] supabase/tests-holdout/nested/held.sql .. ',
    '1..2',
    'ok 1 - synthetic held delta',
    'ok 2 - synthetic held epsilon',
    'ok        8 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
    '[12:00:01]',
    'All tests successful.',
    'Files=3, Tests=5,  0 wallclock secs ( 0.04 usr  0.03 sys +  0.01 cusr  0.00 csys =  0.08 CPU)',
    'Result: PASS',
    '',
  ].join('\n');
}

function output(stream: string, text: string): Output {
  return { path: `${retentionDirectory}/${stream}.log`, sha256: digest(text), byteLength: Buffer.byteLength(text, 'utf8') };
}

function original(): Original {
  return { originalPresent: true, originalValue: '91001ms' };
}

function nativeResult(): Native {
  return { completed: true, exitCode: 0, signal: null, stdout: nativeStdout(), stderr: `# ${stderrCanary}\n`, elapsedMs: 45 };
}

function evidence(): Evidence {
  const native = nativeResult();
  return {
    formatVersion: 1, runId, sourceSha, schemaIdentity: schema(),
    manifestSha256: digest(`${JSON.stringify(manifest())}\n`),
    native,
    outputs: { stdout: output('stdout', native.stdout), stderr: output('stderr', native.stderr) },
    afterFiles: manifest().files.map(({ path, sha256 }) => ({ path, sha256 })),
    timings: { setupMs: 9, linkMs: 3, nativeMs: 45, jobMs: 57 },
    timeout: { original: original(), observed: original(), verified: true },
    reporting: { restored: true, verified: true },
    preflightFailureCodes: [],
  };
}

function refreshOutputs(value: Evidence) {
  value.outputs = { stdout: output('stdout', value.native.stdout), stderr: output('stderr', value.native.stderr) };
}

function sanitized(receipt: Receipt) {
  expect(Object.keys(receipt).sort()).toEqual([
    'accepted', 'aggregate', 'failureCodes', 'files', 'formatVersion', 'manifestSha256',
    'native', 'reporting', 'runId', 'schemaIdentity', 'sourceSha', 'timeout', 'timings',
  ]);
  expect(Object.keys(receipt.native).sort()).toEqual(['completed', 'exitCode', 'signal']);
  expect(Object.keys(receipt.aggregate).sort()).toEqual(['failed', 'files', 'tests', 'verdict']);
  expect(receipt.failureCodes).toEqual([...new Set(receipt.failureCodes)].sort());
  for (const code of receipt.failureCodes) expect(failureCodes).toContain(code);
  for (const file of receipt.files) {
    expect(Object.keys(file).sort()).toEqual(['durationMs', 'executed', 'failed', 'path', 'plan', 'verdict']);
  }
  const publicText = JSON.stringify(receipt);
  expect(publicText).not.toContain(privateCanary);
  expect(publicText).not.toContain(stderrCanary);
  expect(publicText).not.toContain(retentionDirectory);
  expect(publicText).not.toContain('stdout.log');
  expect(publicText).not.toContain('stderr.log');
  expect(publicText).not.toContain('All tests successful.');
}

function denied(value: unknown, code?: string) {
  const receipt = harness.verifyNativePgtapRun(manifest(), value);
  expect(receipt.accepted).toBe(false);
  expect(receipt.failureCodes.length).toBeGreaterThan(0);
  if (code !== undefined) expect(receipt.failureCodes).toContain(code);
  sanitized(receipt);
  return receipt;
}

function invalidManifest(value: unknown) {
  let caught: unknown;
  try { harness.buildNativePgtapManifest(value); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(Error);
  expect(caught).toMatchObject({ code: 'MANIFEST_INVALID' });
}

function portFixture(captured: Original = original()) {
  const events: string[] = [];
  const installation = {
    path: `${workdir}/supabase/tests/.proverc`, originalPresent: false,
    originalText: null as string | null, installedSha256: digest(approvedConfig),
  };
  const ports = {
    collectFiles: vi.fn(async (input: { workdir: string }) => { void input; events.push('collect'); return discovered(); }),
    installReportingConfig: vi.fn(async (input: { workdir: string; lines: string[] }) => { void input; events.push('install'); return installation; }),
    restoreReportingConfig: vi.fn(async (input: typeof installation) => { void input; events.push('report-restore'); return { restored: true, verified: true }; }),
    queryTimeout: vi.fn(async (input: typeof target) => { void input; events.push('query'); return structuredClone(captured); }),
    alterTimeout: vi.fn(async (input: { target: typeof target; setting: Original }) => { events.push(input.setting.originalValue === '10min' ? 'raise' : 'restore'); }),
    persistRecoveryReceipt: vi.fn(async (receipt: unknown) => { events.push('persist'); return { acknowledged: true as const, sha256: digest(`${JSON.stringify(receipt)}\n`) }; }),
    retainPrivateOutput: vi.fn(async (input: { runId: string; stream: string; text: string; retentionDirectory: string }) => { events.push(`retain-${input.stream}`); return output(input.stream, input.text); }),
    runNativeCli: vi.fn(async (input: unknown) => { void input; events.push('native'); return nativeResult(); }),
    now: vi.fn(() => clockNow),
  };
  return { ports, events, installation };
}

function runInput() {
  return { manifest: manifest(), runId, workdir, retentionDirectory, limits: structuredClone(limits) };
}

describe('DBV-001 held exact manifest identity', () => {
  it('freezes all nested SQL/PG metadata in ordinal path order without a historical file count', () => {
    const input = discovered();
    const before = JSON.stringify(input);
    expect(harness.buildNativePgtapManifest(input)).toEqual(manifest());
    expect(JSON.stringify(input)).toBe(before);
  });

  it('includes a newly discovered file rather than accepting an unchanged-looking historical manifest', () => {
    const input = discovered();
    input.files.push({ path: 'supabase/tests/newly-added.sql', sha256: digest('new independent metadata'), literalPlans: [7] });
    const frozen = harness.buildNativePgtapManifest(input);
    expect(frozen.files).toHaveLength(4);
    expect(frozen.files).toContainEqual({ path: 'supabase/tests/newly-added.sql', sha256: digest('new independent metadata'), plan: 7 });
    expect(frozen.files.reduce((total, file) => total + file.plan, 0)).toBe(12);
  });

  it.each([
    'supabase/tests/../outside.sql', 'supabase/tests-holdout/../../secret.sql',
    '/supabase/tests/alpha.sql', 'C:/supabase/tests/alpha.sql',
    'supabase\\tests\\alpha.sql', 'supabase/tests/alpha.sql\u0000',
    'supabase/tests/./alpha.sql', 'supabase/tests//alpha.sql',
    'other/tests/alpha.sql', 'supabase/tests-holdout-copy/alpha.sql',
    'supabase/tests/alpha.ts', '',
  ])('rejects invalid or escaping discovered path %s', path => {
    const input = discovered();
    input.files[0] = { path, sha256: digest('invalid path metadata'), literalPlans: [1] };
    invalidManifest(input);
  });

  it.each([[], [0], [-1], [1.5], [Number.MAX_SAFE_INTEGER + 1], [2, 2], ['2'], [null]].map(literalPlans => ({ literalPlans })))('rejects absent, nonliteral or ambiguous plans $literalPlans', ({ literalPlans }) => {
    const input = discovered();
    Object.assign(input.files[0]!, { literalPlans });
    invalidManifest(input);
  });

  it('rejects an empty suite, duplicates and unsupported file metadata', () => {
    const input = discovered();
    invalidManifest({ ...input, files: [] });
    invalidManifest({ ...input, files: input.files.filter(file => file.path.startsWith('supabase/tests/')) });
    invalidManifest({ ...input, files: input.files.filter(file => file.path.startsWith('supabase/tests-holdout/')) });
    invalidManifest({ ...input, files: [...input.files, structuredClone(input.files[0]!)] });
    invalidManifest({ ...input, files: input.files.map(file => ({ ...file, symlink: false })) });
  });

  it.each([sourceSha.toUpperCase(), sourceSha.slice(1), 'g'.repeat(40), `${sourceSha}\n`, 42, null])('rejects invalid Git source identity %s', value => {
    invalidManifest({ ...discovered(), sourceSha: value });
  });

  it.each(['migrationsSha256', 'generatedTypesSha256'])('rejects invalid schema identity %s', key => {
    invalidManifest({ ...discovered(), schemaIdentity: { ...schema(), [key]: 'a'.repeat(63) } });
    invalidManifest({ ...discovered(), schemaIdentity: { ...schema(), [key]: 'A'.repeat(64) } });
  });

  it('rejects unknown/missing fields at every manifest input level without coercion', () => {
    invalidManifest({ ...discovered(), formatVersion: 1 });
    invalidManifest({ sourceSha, files: discovered().files });
    invalidManifest({ ...discovered(), schemaIdentity: { ...schema(), hostedSucceeded: true } });
    invalidManifest({ ...discovered(), files: discovered().files.map(file => ({ ...file, plan: 2 })) });
    invalidManifest({ ...discovered(), files: discovered().files.map(({ path, literalPlans }) => ({ path, literalPlans })) });
    invalidManifest({ ...discovered(), files: discovered().files.map(file => ({ ...file, sha256: 'not-a-sha' })) });
    invalidManifest(Object.assign(Object.create({ approved: true }), discovered()));
    for (const value of [null, undefined, true, [], 'manifest']) invalidManifest(value);
  });
});

describe('DBV-002/003/004/011/012 held native evidence authority', () => {
  it('accepts the complete pinned-client output with all hashes, plans, native timers and verified cleanup', () => {
    const receipt = harness.verifyNativePgtapRun(manifest(), evidence());
    expect(receipt.accepted).toBe(true);
    expect(receipt.failureCodes).toEqual([]);
    expect(receipt.manifestSha256).toBe(digest(`${JSON.stringify(manifest())}\n`));
    expect(receipt.aggregate).toEqual({ files: 3, tests: 5, failed: 0, verdict: 'PASS' });
    expect(receipt.files).toHaveLength(3);
    expect(receipt.files).toEqual(expect.arrayContaining([
      { path: 'supabase/tests/alpha.sql', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 12 },
      { path: 'supabase/tests/nested/zeta.pg', plan: 1, executed: 1, failed: 0, verdict: 'PASS', durationMs: 0 },
      { path: 'supabase/tests-holdout/nested/held.sql', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 8 },
    ]));
    sanitized(receipt);
  });

  it.each([
    ['nonzero exit', { completed: true, exitCode: 3, signal: null }],
    ['interrupted', { completed: true, exitCode: null, signal: 'SIGTERM' }],
    ['connection lost', { completed: false, exitCode: null, signal: null }],
    ['missing status', { completed: true, exitCode: null, signal: null }],
    ['contradictory status', { completed: true, exitCode: 0, signal: 'SIGTERM' }],
    ['not completed despite zero', { completed: false, exitCode: 0, signal: null }],
  ])('refuses %s despite an entire success-looking stream', (_name, status) => {
    const value = evidence();
    Object.assign(value.native, status);
    denied(value);
  });

  it.each([
    ['assertion failure', (text: string) => text.replace('ok 2 - synthetic beta', 'not ok 2 - synthetic beta')],
    ['missing first plan', (text: string) => text.replace('1..2\n', '')],
    ['extra plan', (text: string) => text.replace('1..2\n', '1..2\n1..2\n')],
    ['wrong per-file plan with same aggregate', (text: string) => text.replace('1..2\n', '1..3\n').replace('1..1\n', '1..0\n')],
    ['nonliteral TAP plan', (text: string) => text.replace('1..2\n', '1..two\n')],
    ['out of order assertion', (text: string) => text.replace('ok 2 - synthetic beta', 'ok 3 - synthetic beta')],
    ['duplicate assertion', (text: string) => text.replace('ok 2 - synthetic beta', 'ok 1 - synthetic beta')],
    ['malformed TAP', (text: string) => text.replace('ok 2 - synthetic beta', 'ok banana - synthetic beta')],
    ['missing assertion', (text: string) => text.replace('ok 2 - synthetic beta\n', '')],
    ['bail out', (text: string) => text.replace('ok 2 - synthetic beta', 'Bail out! synthetic fixture failed')],
    ['missing timer', (text: string) => text.replace('ok       12 ms ( 0.00 usr  0.00 sys +  0.01 cusr  0.00 csys =  0.01 CPU)\n', 'ok\n')],
    ['negative timer', (text: string) => text.replace('12 ms', '-12 ms')],
    ['invalid timer', (text: string) => text.replace('12 ms', 'NaN ms')],
    ['missing file header', (text: string) => text.replace('[12:00:01] supabase/tests/nested/zeta.pg ........ \n', '')],
    ['unexpected file', (text: string) => text.replace('supabase/tests/nested/zeta.pg', 'supabase/tests/rogue.pg')],
    ['duplicate file', (text: string) => text.replace('supabase/tests/nested/zeta.pg', 'supabase/tests/alpha.sql')],
    ['missing success completion', (text: string) => text.replace('All tests successful.\n', '')],
    ['missing aggregate counts', (text: string) => text.replace(/^Files=.*\n/m, '')],
    ['wrong aggregate files', (text: string) => text.replace('Files=3', 'Files=2')],
    ['wrong aggregate tests', (text: string) => text.replace('Tests=5', 'Tests=6')],
    ['missing native verdict', (text: string) => text.replace('Result: PASS\n', '')],
    ['native failed verdict', (text: string) => text.replace('Result: PASS', 'Result: FAIL')],
    ['duplicate aggregate', (text: string) => `${text}Files=3, Tests=5, 0 wallclock secs\nResult: PASS\n`],
    ['truncated final file', (text: string) => text.slice(0, text.indexOf('ok 2 - synthetic held epsilon'))],
  ])('refuses %s using raw native bytes', (_name, transform) => {
    const value = evidence();
    value.native.stdout = transform(value.native.stdout);
    refreshOutputs(value);
    denied(value);
  });

  it('retains a SQL/client error after passing assertions as a failed native attempt', () => {
    const value = evidence();
    value.native.exitCode = 1;
    value.native.stderr += 'psql: ERROR: synthetic client error after TAP\n';
    refreshOutputs(value);
    denied(value, 'NATIVE_FAILED');
  });

  it.each([
    ['missing raw stdout receipt', (value: Evidence) => { value.outputs.stdout = null; }],
    ['missing raw stderr receipt', (value: Evidence) => { value.outputs.stderr = null; }],
    ['stdout hash changed', (value: Evidence) => { value.outputs.stdout!.sha256 = digest('truncated saved output'); }],
    ['stderr hash changed', (value: Evidence) => { value.outputs.stderr!.sha256 = digest('different error output'); }],
    ['stdout byte length changed', (value: Evidence) => { value.outputs.stdout!.byteLength -= 1; }],
    ['stderr byte length changed', (value: Evidence) => { value.outputs.stderr!.byteLength = 0; }],
    ['missing after file', (value: Evidence) => { value.afterFiles.pop(); }],
    ['duplicate after file', (value: Evidence) => { value.afterFiles.push(structuredClone(value.afterFiles[0]!)); }],
    ['changed SQL hash', (value: Evidence) => { value.afterFiles[0]!.sha256 = digest('changed SQL bytes'); }],
    ['unexpected after file', (value: Evidence) => { value.afterFiles.push({ path: 'supabase/tests/new.sql', sha256: digest('unexpected') }); }],
    ['source changed', (value: Evidence) => { value.sourceSha = 'f'.repeat(40); }],
    ['migration identity changed', (value: Evidence) => { value.schemaIdentity.migrationsSha256 = digest('new migrations'); }],
    ['types identity changed', (value: Evidence) => { value.schemaIdentity.generatedTypesSha256 = digest('new types'); }],
    ['wrong manifest hash', (value: Evidence) => { value.manifestSha256 = digest(JSON.stringify(manifest())); }],
    ['cleanup verification missing', (value: Evidence) => { value.timeout.verified = false; }],
    ['original capture absent', (value: Evidence) => { value.timeout.original = null; }],
    ['observed catalog absent', (value: Evidence) => { value.timeout.observed = null; }],
    ['assumed default restored', (value: Evidence) => { value.timeout.observed = { originalPresent: true, originalValue: '2min' }; }],
    ['timeout presence changed', (value: Evidence) => { value.timeout.observed = { originalPresent: false, originalValue: null }; }],
    ['reporting not restored', (value: Evidence) => { value.reporting.restored = false; }],
    ['reporting restore unverified', (value: Evidence) => { value.reporting.verified = false; }],
    ['preflight failure', (value: Evidence) => { value.preflightFailureCodes = ['DEADLINE_EXCEEDED']; }],
  ])('refuses %s without accepting substitute totals', (_name, mutate) => {
    const value = evidence(); mutate(value); denied(value);
  });

  it.each([
    ['top-level extra key', (value: Evidence) => Object.assign(value, { accepted: true })],
    ['native extra key', (value: Evidence) => Object.assign(value.native, { fileResults: [] })],
    ['output extra key', (value: Evidence) => Object.assign(value.outputs.stdout!, { retained: true })],
    ['after-file extra key', (value: Evidence) => Object.assign(value.afterFiles[0]!, { passed: true })],
    ['schema extra key', (value: Evidence) => Object.assign(value.schemaIdentity, { identityVerified: true })],
    ['timings extra key', (value: Evidence) => Object.assign(value.timings, { seconds: 1 })],
    ['cleanup extra key', (value: Evidence) => Object.assign(value.timeout, { role: 'postgres' })],
    ['original extra key', (value: Evidence) => Object.assign(value.timeout.original!, { effectiveValue: '91001ms' })],
    ['reporting extra key', (value: Evidence) => Object.assign(value.reporting, { smokePassed: true })],
    ['unsupported format', (value: Evidence) => Object.assign(value, { formatVersion: 2 })],
    ['coerced status', (value: Evidence) => Object.assign(value.native, { exitCode: '0' })],
    ['negative elapsed time', (value: Evidence) => { value.native.elapsedMs = -1; }],
    ['fractional elapsed time', (value: Evidence) => { value.native.elapsedMs = 1.25; }],
    ['invalid count', (value: Evidence) => { value.outputs.stdout!.byteLength = Number.MAX_SAFE_INTEGER + 1; }],
    ['inconsistent absent timeout', (value: Evidence) => { value.timeout.original = { originalPresent: false, originalValue: '0' }; }],
    ['inconsistent present timeout', (value: Evidence) => { value.timeout.original = { originalPresent: true, originalValue: null }; }],
    ['unknown preflight code', (value: Evidence) => { value.preflightFailureCodes = ['ALL_OK']; }],
  ])('marks malformed %s evidence invalid while retaining cleanup facts', (_name, mutate) => {
    const value = evidence(); mutate(value); denied(value, 'EVIDENCE_INVALID');
  });

  it('keeps independently known cleanup failures when evidence is also malformed', () => {
    const value = evidence();
    Object.assign(value.native, { exitCode: '0' });
    value.timeout.verified = false;
    value.reporting.restored = false;
    const receipt = denied(value, 'EVIDENCE_INVALID');
    expect(receipt.timeout).toEqual(value.timeout);
    expect(receipt.reporting).toEqual(value.reporting);
    expect(receipt.failureCodes).toContain('TIMEOUT_NOT_RESTORED');
    expect(receipt.failureCodes).toContain('REPORTING_NOT_RESTORED');
  });

  it('accepts exact original absence and refuses a fabricated replacement default', () => {
    const value = evidence();
    value.timeout = { original: { originalPresent: false, originalValue: null }, observed: { originalPresent: false, originalValue: null }, verified: true };
    expect(harness.verifyNativePgtapRun(manifest(), value).accepted).toBe(true);
    value.timeout.observed = { originalPresent: true, originalValue: '2min' };
    denied(value, 'TIMEOUT_NOT_RESTORED');
  });

  it('checks retained UTF-8 bytes rather than JavaScript character counts', () => {
    const value = evidence();
    value.native.stdout = value.native.stdout.replace('synthetic beta', 'synthetic βeta 🧪');
    refreshOutputs(value);
    expect(harness.verifyNativePgtapRun(manifest(), value).accepted).toBe(true);
    value.outputs.stdout!.byteLength = value.native.stdout.length;
    denied(value);
  });

  it('never throws for absent or structurally unusable evidence', () => {
    for (const value of [null, undefined, [], false, 'PASS', {}]) {
      expect(() => harness.verifyNativePgtapRun(manifest(), value)).not.toThrow();
      denied(value, 'EVIDENCE_INVALID');
    }
  });
});

describe('DBV-002/003/004/005/006/007/009/011/012 held orchestration custody', () => {
  it('uses only the exact full native command and persists a bound receipt before temporary alteration', async () => {
    const { ports, events, installation } = portFixture();
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(true);
    expect(ports.collectFiles).toHaveBeenCalledTimes(2);
    for (const [input] of ports.collectFiles.mock.calls) expect(input).toEqual({ workdir });
    expect(ports.installReportingConfig).toHaveBeenCalledExactlyOnceWith({ workdir, lines });
    expect(ports.runNativeCli).toHaveBeenCalledExactlyOnceWith({
      command: 'supabase', args: ['test', 'db', '--linked', 'supabase/tests', 'supabase/tests-holdout'], cwd: workdir, limits,
    });
    expect(ports.queryTimeout).toHaveBeenCalledTimes(2);
    for (const [input] of ports.queryTimeout.mock.calls) expect(input).toEqual(target);
    expect(ports.alterTimeout.mock.calls).toEqual([
      [{ target, setting: { originalPresent: true, originalValue: '10min' } }],
      [{ target, setting: original() }],
    ]);
    expect(ports.persistRecoveryReceipt).toHaveBeenCalledExactlyOnceWith({
      formatVersion: 1, runId, sourceSha, manifestSha256: digest(`${JSON.stringify(manifest())}\n`),
      target, original: original(), capturedAt: '2026-10-07T12:00:00.000Z', armed: true,
    });
    expect(events.indexOf('collect')).toBeLessThan(events.indexOf('raise'));
    expect(events.indexOf('persist')).toBeLessThan(events.indexOf('raise'));
    expect(events.indexOf('raise')).toBeLessThan(events.indexOf('native'));
    expect(events.indexOf('native')).toBeLessThan(events.indexOf('restore'));
    expect(ports.restoreReportingConfig).toHaveBeenCalledExactlyOnceWith(installation);
    expect(ports.retainPrivateOutput.mock.calls).toEqual(expect.arrayContaining([
      [{ runId, stream: 'stdout', text: nativeResult().stdout, retentionDirectory }],
      [{ runId, stream: 'stderr', text: nativeResult().stderr, retentionDirectory }],
    ]));
    expect(result.evidence.outputs.stdout).toEqual(output('stdout', nativeResult().stdout));
    expect(result.evidence.outputs.stderr).toEqual(output('stderr', nativeResult().stderr));
    expect(result.evidence.native.stdout).toBe(nativeResult().stdout);
    sanitized(result.receipt);
  });

  it.each([
    { originalPresent: false, originalValue: null },
    { originalPresent: true, originalValue: '0' },
    { originalPresent: true, originalValue: '00:01:31.001' },
    { originalPresent: true, originalValue: '17s' },
  ])('restores the exact captured catalog fact %s rather than a guessed effective value', async captured => {
    const { ports } = portFixture(captured);
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(true);
    expect(ports.alterTimeout.mock.calls.at(-1)).toEqual([{ target, setting: captured }]);
    expect(result.receipt.timeout).toEqual({ original: captured, observed: captured, verified: true });
  });

  it('restores exact approved pre-existing reporting bytes', async () => {
    const { ports, installation } = portFixture();
    installation.originalPresent = true;
    installation.originalText = approvedConfig;
    expect((await harness.runNativePgtapValidation(runInput(), ports)).receipt.accepted).toBe(true);
    expect(ports.restoreReportingConfig).toHaveBeenCalledExactlyOnceWith(installation);
  });

  it.each(['--ignore-exit\n', '--jobs=2\n', '--timer\n--shuffle\n', `${approvedConfig}--formatter=forged\n`])('refuses unapproved original reporting configuration %s', async config => {
    const { ports, installation } = portFixture();
    installation.originalPresent = true;
    installation.originalText = config;
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    expect(ports.alterTimeout).not.toHaveBeenCalled();
    sanitized(result.receipt);
  });

  it.each(['source', 'schema', 'files', 'plan'])('rejects a preflight %s mismatch before database execution', async field => {
    const { ports } = portFixture();
    const input = discovered();
    if (field === 'source') input.sourceSha = 'b'.repeat(40);
    if (field === 'schema') input.schemaIdentity.migrationsSha256 = digest('different schema');
    if (field === 'files') input.files.pop();
    if (field === 'plan') input.files[0]!.literalPlans = [8];
    ports.collectFiles.mockResolvedValue(input);
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.alterTimeout).not.toHaveBeenCalled();
    expect(ports.runNativeCli).not.toHaveBeenCalled();
  });

  it('checks post-native discovery and hashes even when all native assertions passed', async () => {
    const { ports } = portFixture();
    const changed = discovered(); changed.files[0]!.sha256 = digest('post-run changed bytes');
    ports.collectFiles.mockResolvedValueOnce(discovered()).mockResolvedValueOnce(changed);
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.alterTimeout.mock.calls.at(-1)).toEqual([{ target, setting: original() }]);
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each(['capture rejection', 'malformed capture', 'missing capture', 'contradictory capture'])('refuses %s before ALTER and native execution', async failure => {
    const { ports } = portFixture();
    if (failure === 'capture rejection') ports.queryTimeout.mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'malformed capture') ports.queryTimeout.mockResolvedValueOnce({ originalPresent: true, originalValue: null });
    if (failure === 'missing capture') ports.queryTimeout.mockImplementationOnce(async () => undefined as unknown as Original);
    if (failure === 'contradictory capture') ports.queryTimeout.mockResolvedValueOnce({ originalPresent: false, originalValue: '2min' });
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(result.receipt.failureCodes).toContain('TIMEOUT_CAPTURE_INVALID');
    expect(ports.persistRecoveryReceipt).not.toHaveBeenCalled();
    expect(ports.alterTimeout).not.toHaveBeenCalled();
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    sanitized(result.receipt);
  });

  it.each(['rejected', 'not acknowledged', 'invalid receipt hash'])('refuses recovery custody %s before ALTER', async failure => {
    const { ports } = portFixture();
    if (failure === 'rejected') ports.persistRecoveryReceipt.mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'not acknowledged') ports.persistRecoveryReceipt.mockImplementationOnce(async () => ({ acknowledged: false, sha256: digest('not acknowledged') }) as unknown as { acknowledged: true; sha256: string });
    if (failure === 'invalid receipt hash') ports.persistRecoveryReceipt.mockResolvedValueOnce({ acknowledged: true, sha256: 'not-a-sha256' });
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(result.receipt.failureCodes).toContain('RECEIPT_UNAVAILABLE');
    expect(ports.alterTimeout).not.toHaveBeenCalled();
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    sanitized(result.receipt);
  });

  it('arms restoration before an uncertain temporary ALTER acknowledgement', async () => {
    const { ports } = portFixture();
    ports.alterTimeout.mockRejectedValueOnce(new Error('synthetic connection lost after possible ALTER commit'));
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    expect(ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(ports.alterTimeout.mock.calls.at(-1)).toEqual([{ target, setting: original() }]);
    expect(ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(result.evidence.timeout).toEqual({ original: original(), observed: original(), verified: true });
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each(['native rejection', 'nonzero native', 'native interruption', 'native timeout'])('keeps %s red after successful cleanup', async failure => {
    const { ports } = portFixture();
    if (failure === 'native rejection') ports.runNativeCli.mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'nonzero native') ports.runNativeCli.mockResolvedValueOnce({ ...nativeResult(), exitCode: 2 });
    if (failure === 'native interruption') ports.runNativeCli.mockResolvedValueOnce({ ...nativeResult(), completed: false, exitCode: null, signal: 'SIGTERM' });
    if (failure === 'native timeout') ports.runNativeCli.mockResolvedValueOnce({ ...nativeResult(), completed: false, exitCode: null, signal: null, stdout: nativeStdout().slice(0, 40) });
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.runNativeCli).toHaveBeenCalledTimes(1);
    expect(ports.alterTimeout.mock.calls.at(-1)).toEqual([{ target, setting: original() }]);
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
    expect(result.receipt.timeout.verified).toBe(true);
    sanitized(result.receipt);
  });

  it.each(['restore alteration', 'catalog verification', 'catalog mismatch', 'reporting restore', 'reporting verification', 'output persistence'])('fails closed for %s and still attempts other cleanup', async failure => {
    const { ports } = portFixture();
    if (failure === 'restore alteration') ports.alterTimeout.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'catalog verification') ports.queryTimeout.mockResolvedValueOnce(original()).mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'catalog mismatch') ports.queryTimeout.mockResolvedValueOnce(original()).mockResolvedValueOnce({ originalPresent: true, originalValue: '2min' });
    if (failure === 'reporting restore') ports.restoreReportingConfig.mockRejectedValueOnce(new Error(privateCanary));
    if (failure === 'reporting verification') ports.restoreReportingConfig.mockResolvedValueOnce({ restored: true, verified: false });
    if (failure === 'output persistence') ports.retainPrivateOutput.mockRejectedValueOnce(new Error(privateCanary));
    const result = await harness.runNativePgtapValidation(runInput(), ports);
    expect(result.receipt.accepted).toBe(false);
    expect(ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
    sanitized(result.receipt);
  });

  it('does not accept a retained stream with a forged hash or an escaped private path', async () => {
    for (const retained of [
      { ...output('stdout', nativeStdout()), sha256: digest('wrong retained bytes') },
      { ...output('stdout', nativeStdout()), path: 'C:/public-output/forged.log' },
    ]) {
      const { ports } = portFixture();
      ports.retainPrivateOutput.mockResolvedValueOnce(retained);
      const result = await harness.runNativePgtapValidation(runInput(), ports);
      expect(result.receipt.accepted).toBe(false);
      expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
      expect(ports.alterTimeout.mock.calls.at(-1)).toEqual([{ target, setting: original() }]);
    }
  });

  it('refuses an expired overall deadline before a shared-project alteration', async () => {
    const { ports } = portFixture();
    const input = runInput(); input.limits.deadlineUtc = '2026-10-07T11:59:59.999Z';
    const result = await harness.runNativePgtapValidation(input, ports);
    expect(result.receipt.accepted).toBe(false);
    expect(result.receipt.failureCodes).toContain('DEADLINE_EXCEEDED');
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    expect(ports.alterTimeout).not.toHaveBeenCalled();
  });
});
