import { createHash } from 'node:crypto';
import { beforeAll, describe, expect, it, vi } from 'vitest';

// Independent visible tests from the frozen 3aa8518b DBV contract. All TAP,
// identities, timeout facts and ports below are synthetic; no SQL suite is read.
// Operational runner/guardian/benchmark boundaries have separate tests.
type SchemaIdentity = { migrationsSha256: string; generatedTypesSha256: string };
type DiscoveredInputs = {
  sourceSha: string;
  schemaIdentity: SchemaIdentity;
  files: { path: string; sha256: string; literalPlans: number[] }[];
};
type Manifest = {
  formatVersion: 1;
  sourceSha: string;
  schemaIdentity: SchemaIdentity;
  files: { path: string; sha256: string; plan: number }[];
};
type OriginalTimeout = { originalPresent: boolean; originalValue: string | null };
type NativeResult = {
  completed: boolean;
  exitCode: number | null;
  signal: string | null;
  stdout: string;
  stderr: string;
  elapsedMs: number;
};
type PrivateOutput = { path: string; sha256: string; byteLength: number };
type TimeoutCleanup = {
  original: OriginalTimeout | null;
  observed: OriginalTimeout | null;
  verified: boolean;
};
type ReportingCleanup = { restored: boolean; verified: boolean };
type Timings = { setupMs: number; linkMs: number; nativeMs: number; jobMs: number };
type Evidence = {
  formatVersion: 1;
  runId: string;
  sourceSha: string;
  schemaIdentity: SchemaIdentity;
  manifestSha256: string;
  native: NativeResult;
  outputs: { stdout: PrivateOutput | null; stderr: PrivateOutput | null };
  afterFiles: { path: string; sha256: string }[];
  timings: Timings;
  timeout: TimeoutCleanup;
  reporting: ReportingCleanup;
  preflightFailureCodes: string[];
};
type FileResult = {
  path: string;
  plan: number;
  executed: number;
  failed: number;
  verdict: 'PASS' | 'FAIL' | 'INCOMPLETE';
  durationMs: number | null;
};
type FinalReceipt = {
  formatVersion: 1;
  runId: string;
  sourceSha: string;
  schemaIdentity: SchemaIdentity;
  manifestSha256: string;
  accepted: boolean;
  native: { completed: boolean; exitCode: number | null; signal: string | null };
  files: FileResult[];
  aggregate: { files: number; tests: number; failed: number; verdict: 'PASS' | 'FAIL' | 'INCOMPLETE' };
  timings: Timings;
  timeout: TimeoutCleanup;
  reporting: ReportingCleanup;
  failureCodes: string[];
};
type Harness = {
  buildNativePgtapManifest: (input: unknown) => Manifest;
  verifyNativePgtapRun: (manifest: Manifest, evidence: unknown) => FinalReceipt;
  runNativePgtapValidation: (input: unknown, ports: unknown) => Promise<{ evidence: Evidence; receipt: FinalReceipt }>;
};
type RecoveryReceipt = {
  formatVersion: 1;
  runId: string;
  sourceSha: string;
  manifestSha256: string;
  target: typeof TARGET;
  original: OriginalTimeout;
  capturedAt: string;
  armed: true;
};

const SOURCE = 'a'.repeat(40);
const SCHEMA: SchemaIdentity = { migrationsSha256: 'b'.repeat(64), generatedTypesSha256: 'c'.repeat(64) };
const VISIBLE = 'supabase/tests/visible.sql';
const INDEPENDENT = 'supabase/tests-holdout/independent.pg';
const TARGET = { projectRef: 'pecxrpskmfeuyzngvewq', role: 'postgres', parameter: 'statement_timeout' } as const;
const REPORTING_LINES = ['--timer', '--verbose', '--parse', '--nocolor', '--jobs=1'];
const REPORTING_TEXT = `${REPORTING_LINES.join('\n')}\n`;
const ORIGINAL: OriginalTimeout = { originalPresent: true, originalValue: '127321ms' };
const ABSENT: OriginalTimeout = { originalPresent: false, originalValue: null };
const WORKDIR = 'C:/synthetic-dedicated-checkout';
const RETENTION = 'C:/synthetic-protected-retention';
const RUN_ID = 'synthetic-run-1-attempt-1';
const NOW = Date.parse('2026-10-07T09:00:00.000Z');
const LIMITS = { deadlineUtc: '2026-10-07T10:00:00.000Z', nativeTimeoutMs: 60000 };
const FAILURE_CODES = [
  'MANIFEST_INVALID', 'EVIDENCE_INVALID', 'INPUT_CHANGED', 'REPORTING_UNVERIFIED',
  'TIMEOUT_CAPTURE_INVALID', 'RECEIPT_UNAVAILABLE', 'NATIVE_FAILED', 'NATIVE_INCOMPLETE',
  'TAP_FAILED', 'TAP_INCOMPLETE', 'HASH_CHANGED', 'TIMEOUT_NOT_RESTORED',
  'REPORTING_NOT_RESTORED', 'DEADLINE_EXCEEDED', 'RUNNER_UNTRUSTED',
];
const TIMER = ' ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)';
const SUMMARY = 'Files=2, Tests=3,  0 wallclock secs ( 0.04 usr +  0.01 sys =  0.05 CPU)';
let harness: Harness;

beforeAll(async () => {
  // A variable keeps this test type-checkable before the implementation exists.
  // Runtime module absence is the intended first red, not an optional skip.
  const modulePath = '../pgtap/native.mjs';
  harness = await import(modulePath) as Harness;
});

function sha256(text: string): string {
  return createHash('sha256').update(text, 'utf8').digest('hex');
}

function manifestHash(manifest: Manifest): string {
  return sha256(`${JSON.stringify(manifest)}\n`);
}

function discovery(): DiscoveredInputs {
  return {
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    files: [
      { path: VISIBLE, sha256: 'd'.repeat(64), literalPlans: [2] },
      { path: INDEPENDENT, sha256: 'e'.repeat(64), literalPlans: [1] },
    ],
  };
}

function expectedManifest(): Manifest {
  return {
    formatVersion: 1,
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    files: [
      { path: INDEPENDENT, sha256: 'e'.repeat(64), plan: 1 },
      { path: VISIBLE, sha256: 'd'.repeat(64), plan: 2 },
    ],
  };
}

function nativeText(prefix = ''): string {
  // Matches pinned pg_prove 3.36 output observed by this author using only a
  // disposable stub psql, exact five-line .proverc and native client image.
  return [
    `[09:00:00] ${prefix}${VISIBLE} ............. `,
    '1..2',
    'ok 1 - synthetic private assertion one',
    'ok 2 - synthetic private assertion two',
    `ok        2${TIMER}`,
    `[09:00:00] ${prefix}${INDEPENDENT} .. `,
    '1..1',
    'ok 1 - synthetic private independent assertion',
    `ok        3${TIMER}`,
    '[09:00:00]',
    'All tests successful.',
    SUMMARY,
    'Result: PASS',
    '',
  ].join('\n');
}

function retained(stream: string, text: string): PrivateOutput {
  return { path: `${RETENTION}/${RUN_ID}/${stream}.raw`, sha256: sha256(text), byteLength: Buffer.byteLength(text, 'utf8') };
}

function evidence(stdout = nativeText(), stderr = ''): Evidence {
  const manifest = expectedManifest();
  return {
    formatVersion: 1,
    runId: RUN_ID,
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    manifestSha256: manifestHash(manifest),
    native: { completed: true, exitCode: 0, signal: null, stdout, stderr, elapsedMs: 5 },
    outputs: { stdout: retained('stdout', stdout), stderr: retained('stderr', stderr) },
    afterFiles: manifest.files.map(({ path, sha256 }) => ({ path, sha256 })),
    timings: { setupMs: 1, linkMs: 0, nativeMs: 5, jobMs: 6 },
    timeout: { original: { ...ORIGINAL }, observed: { ...ORIGINAL }, verified: true },
    reporting: { restored: true, verified: true },
    preflightFailureCodes: [],
  };
}

function red(receipt: FinalReceipt, code?: string): void {
  expect(receipt.accepted).toBe(false);
  expect(receipt.failureCodes.length).toBeGreaterThan(0);
  expect(receipt.failureCodes).toEqual([...new Set(receipt.failureCodes)].sort());
  expect(receipt.failureCodes.every(value => FAILURE_CODES.includes(value))).toBe(true);
  if (code) expect(receipt.failureCodes).toContain(code);
}

function fakePorts(original: OriginalTimeout = ORIGINAL) {
  const events: string[] = [];
  const manifest = expectedManifest();
  const input = { manifest, runId: RUN_ID, workdir: WORKDIR, retentionDirectory: RETENTION, limits: { ...LIMITS } };
  const installed: { path: string; originalPresent: boolean; originalText: string | null; installedSha256: string } = {
    path: `${WORKDIR}/supabase/tests/.proverc`,
    originalPresent: false,
    originalText: null,
    installedSha256: sha256(REPORTING_TEXT),
  };
  const ports = {
    collectFiles: vi.fn(async (_input: { workdir: string }) => {
      void _input;
      events.push('collect');
      return discovery();
    }),
    installReportingConfig: vi.fn(async (_input: { workdir: string; lines: string[] }) => {
      void _input;
      events.push('install');
      return { ...installed };
    }),
    restoreReportingConfig: vi.fn(async (_installed: typeof installed): Promise<ReportingCleanup> => {
      void _installed;
      events.push('reporting-restore');
      return { restored: true, verified: true };
    }),
    queryTimeout: vi.fn(async (_target: typeof TARGET): Promise<OriginalTimeout> => {
      void _target;
      events.push('query');
      return { ...original };
    }),
    alterTimeout: vi.fn(async (_input: { target: typeof TARGET; setting: OriginalTimeout }) => {
      void _input;
      events.push('alter');
    }),
    persistRecoveryReceipt: vi.fn(async (receipt: RecoveryReceipt) => {
      events.push('persist');
      return { acknowledged: true as const, sha256: sha256(`${JSON.stringify(receipt)}\n`) };
    }),
    retainPrivateOutput: vi.fn(async (output: { runId: string; stream: string; text: string; retentionDirectory: string }) => {
      events.push(`retain-${output.stream}`);
      return retained(output.stream, output.text);
    }),
    runNativeCli: vi.fn(async (_input: { command: string; args: string[]; cwd: string; limits: typeof LIMITS }): Promise<NativeResult> => {
      void _input;
      events.push('native');
      return evidence().native;
    }),
    now: vi.fn(() => NOW),
  };
  return { events, input, installed, ports };
}

describe('DBV-001 complete native manifest', () => {
  it('keeps every supported file exactly once in ordinal path order without historical counts', () => {
    const input = discovery();
    input.files.push({ path: 'supabase/tests/nested/later-added.pg', sha256: 'f'.repeat(64), literalPlans: [7] });
    const actual = harness.buildNativePgtapManifest(input);
    expect(actual).toEqual({
      ...expectedManifest(),
      files: [
        { path: INDEPENDENT, sha256: 'e'.repeat(64), plan: 1 },
        { path: 'supabase/tests/nested/later-added.pg', sha256: 'f'.repeat(64), plan: 7 },
        { path: VISIBLE, sha256: 'd'.repeat(64), plan: 2 },
      ],
    });
    expect(actual.files.reduce((total, file) => total + file.plan, 0)).toBe(10);
    expect(input.files[0]?.path).toBe(VISIBLE);
  });

  it('has the frozen canonical JSON field order, source identity and schema identities', () => {
    const manifest = harness.buildNativePgtapManifest(discovery());
    expect(JSON.stringify(manifest)).toBe(JSON.stringify(expectedManifest()));
    expect(manifestHash(manifest)).toBe(manifestHash(expectedManifest()));
  });

  it.each([
    ['neither suite', []],
    ['absent holdout suite', [discovery().files[0]]],
    ['absent visible suite', [discovery().files[1]]],
  ])('rejects %s before execution', (_name, files) => {
    expect(() => harness.buildNativePgtapManifest({ ...discovery(), files })).toThrow(expect.objectContaining({ code: 'MANIFEST_INVALID' }));
  });

  it.each([
    ['duplicate path', { path: VISIBLE, sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['absolute path', { path: '/supabase/tests/escape.sql', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['Windows absolute path', { path: 'C:/supabase/tests/escape.sql', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['parent traversal', { path: 'supabase/tests/../escape.sql', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['outside suite', { path: 'supabase/escape.sql', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['lookalike suite', { path: 'supabase/tests-holdout-extra/escape.sql', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['unsupported extension', { path: 'supabase/tests/extra.txt', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['empty path', { path: '', sha256: 'f'.repeat(64), literalPlans: [1] }],
    ['missing/comment-only plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [] }],
    ['ambiguous plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [1, 1] }],
    ['zero plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [0] }],
    ['negative plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [-1] }],
    ['fractional plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [1.5] }],
    ['unsafe plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [Number.MAX_SAFE_INTEGER + 1] }],
    ['coerced plan', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: ['1'] }],
    ['malformed hash', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(63), literalPlans: [1] }],
    ['uppercase hash', { path: 'supabase/tests/extra.sql', sha256: 'F'.repeat(64), literalPlans: [1] }],
    ['unknown file key', { path: 'supabase/tests/extra.sql', sha256: 'f'.repeat(64), literalPlans: [1], accepted: true }],
  ])('rejects %s with the ordinary typed refusal', (_name, file) => {
    const input = { ...discovery(), files: [...discovery().files, file] };
    expect(() => harness.buildNativePgtapManifest(input)).toThrow(expect.objectContaining({ code: 'MANIFEST_INVALID' }));
  });

  it.each([
    ['nonobject', null],
    ['array object', []],
    ['unknown key', { ...discovery(), accepted: true }],
    ['missing source', { schemaIdentity: SCHEMA, files: discovery().files }],
    ['wrong source length', { ...discovery(), sourceSha: 'a'.repeat(39) }],
    ['uppercase source', { ...discovery(), sourceSha: 'A'.repeat(40) }],
    ['unknown schema key', { ...discovery(), schemaIdentity: { ...SCHEMA, guessed: true } }],
    ['bad schema hash', { ...discovery(), schemaIdentity: { ...SCHEMA, migrationsSha256: 'bad' } }],
    ['nonarray files', { ...discovery(), files: {} }],
  ])('refuses malformed discovery: %s', (_name, input) => {
    expect(() => harness.buildNativePgtapManifest(input)).toThrow(expect.objectContaining({ code: 'MANIFEST_INVALID' }));
  });
});

describe('DBV-002/003/004/011 retained native evidence', () => {
  it.each(['', '/home/runner/work/synthetic/synthetic/', '/fdb-smoke-20261007/'])('accepts a complete native stream with path prefix %s', prefix => {
    const input = evidence(nativeText(prefix));
    const receipt = harness.verifyNativePgtapRun(expectedManifest(), input);
    expect(receipt.accepted).toBe(true);
    expect(receipt.failureCodes).toEqual([]);
    expect(receipt.aggregate).toEqual({ files: 2, tests: 3, failed: 0, verdict: 'PASS' });
    expect(receipt.files).toEqual(expect.arrayContaining([
      { path: VISIBLE, plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 2 },
      { path: INDEPENDENT, plan: 1, executed: 1, failed: 0, verdict: 'PASS', durationMs: 3 },
    ]));
    expect(receipt.files).toHaveLength(2);
    expect(receipt.manifestSha256).toBe(manifestHash(expectedManifest()));
    expect(receipt.timeout).toEqual(input.timeout);
    expect(receipt.reporting).toEqual(input.reporting);
  });

  it('preserves UTF-8 raw output with native CRLF without changing hashes', () => {
    const stdout = nativeText().replace('synthetic private assertion one', 'synthetic private assertion λ').replaceAll('\n', '\r\n');
    const receipt = harness.verifyNativePgtapRun(expectedManifest(), evidence(stdout));
    expect(receipt.accepted).toBe(true);
  });

  it('publishes only the exact sanitized receipt shape', () => {
    const input = evidence();
    const receipt = harness.verifyNativePgtapRun(expectedManifest(), input);
    expect(Object.keys(receipt).sort()).toEqual([
      'accepted', 'aggregate', 'failureCodes', 'files', 'formatVersion', 'manifestSha256',
      'native', 'reporting', 'runId', 'schemaIdentity', 'sourceSha', 'timeout', 'timings',
    ].sort());
    expect(Object.keys(receipt.native).sort()).toEqual(['completed', 'exitCode', 'signal']);
    const serialized = JSON.stringify(receipt);
    expect(serialized).not.toContain('synthetic private assertion');
    expect(serialized).not.toContain(RETENTION);
    expect(serialized).not.toContain('stdout');
    expect(serialized).not.toContain('stderr');
  });

  it.each([
    ['nonzero native exit', { completed: true, exitCode: 1, signal: null }, 'NATIVE_FAILED'],
    ['connection/client nonzero exit', { completed: true, exitCode: 2, signal: null }, 'NATIVE_FAILED'],
    ['interrupted native process', { completed: true, exitCode: null, signal: 'SIGTERM' }, 'NATIVE_FAILED'],
    ['uncompleted native process', { completed: false, exitCode: null, signal: null }, 'NATIVE_INCOMPLETE'],
    ['missing native status', { completed: true, exitCode: null, signal: null }, 'NATIVE_INCOMPLETE'],
  ])('refuses %s despite complete preceding TAP', (_name, status, code) => {
    const input = evidence();
    Object.assign(input.native, status);
    red(harness.verifyNativePgtapRun(expectedManifest(), input), code);
  });

  const streamCases = [
    ['assertion failure', nativeText().replace('ok 2 - synthetic private assertion two', 'not ok 2 - synthetic private assertion two')],
    ['native aggregate failure', nativeText().replace('Result: PASS', 'Result: FAIL')],
    ['missing aggregate verdict', nativeText().replace('Result: PASS\n', '')],
    ['missing aggregate counts', nativeText().replace(`${SUMMARY}\n`, '')],
    ['wrong aggregate file count', nativeText().replace('Files=2', 'Files=1')],
    ['wrong aggregate test count', nativeText().replace('Tests=3', 'Tests=4')],
    ['duplicate aggregate verdict', `${nativeText()}Result: PASS\n`],
    ['duplicate aggregate counts', `${nativeText()}${SUMMARY}\n`],
    ['missing file', nativeText().replace(`[09:00:00] ${INDEPENDENT} .. \n1..1\nok 1 - synthetic private independent assertion\nok        3${TIMER}\n`, '')],
    ['duplicate file', `${nativeText().split('[09:00:00]\nAll tests successful.')[0]}${nativeText()}`],
    ['unexpected file', nativeText().replace(INDEPENDENT, 'supabase/tests/unexpected.pg')],
    ['missing plan', nativeText().replace('1..2\n', '')],
    ['extra plan', nativeText().replace('1..2\n', '1..2\n1..2\n')],
    ['extra executed assertion', nativeText().replace(`ok        2${TIMER}`, `ok 3 - synthetic excess\nok        2${TIMER}`)],
    ['truncated assertion stream', nativeText().replace('ok 2 - synthetic private assertion two\n', '')],
    ['out of sequence assertion', nativeText().replace('ok 2 - synthetic private assertion two', 'ok 3 - synthetic private assertion two')],
    ['missing timer', nativeText().replace(`ok        2${TIMER}\n`, 'ok\n')],
    ['negative timer', nativeText().replace(`ok        2${TIMER}`, `ok        -2${TIMER}`)],
    ['malformed timer', nativeText().replace(`ok        2${TIMER}`, `ok        nope${TIMER}`)],
    ['native SQL/client error after successful assertions', `${nativeText()}Dubious, test returned 2 (wstat 512, 0x200)\n`],
    ['native bailout', nativeText().replace('ok 2 - synthetic private assertion two', 'Bail out! synthetic connection loss')],
    ['unchanged-looking total with per-file plans swapped', nativeText().replace('1..2\n', '1..1\n').replace('1..1\nok 1 - synthetic private independent', '1..2\nok 1 - synthetic private independent')],
  ];
  it.each(streamCases)('keeps %s red even when exit status is presented as zero', (_name, stdout) => {
    red(harness.verifyNativePgtapRun(expectedManifest(), evidence(stdout)));
  });

  it('keeps an actual native client-error report red after every assertion passes', () => {
    const stdout = [
      `[09:00:00] ${VISIBLE} ............. `, '1..2', 'ok 1 - synthetic one', 'ok 2 - synthetic two',
      'Dubious, test returned 2 (wstat 512, 0x200)', 'All 2 subtests passed ',
      `[09:00:00] ${INDEPENDENT} .. `, '1..1', 'ok 1 - synthetic independent', `ok        3${TIMER}`,
      '[09:00:00]', '', 'Test Summary Report', '-------------------',
      `${VISIBLE} (Wstat: 512 (exited 2) Tests: 2 Failed: 0)`, '  Non-zero exit status: 2',
      SUMMARY, 'Result: FAIL', '',
    ].join('\n');
    const input = evidence(stdout, 'synthetic client error\n');
    input.native.exitCode = 1;
    red(harness.verifyNativePgtapRun(expectedManifest(), input), 'NATIVE_FAILED');
  });

  it.each(['stdout', 'stderr'] as const)('rejects missing or falsified %s retained evidence', stream => {
    const absent = evidence();
    absent.outputs[stream] = null;
    red(harness.verifyNativePgtapRun(expectedManifest(), absent));
    const mismatch = evidence();
    const output = mismatch.outputs[stream];
    if (!output) throw new Error('Synthetic output absent');
    output.sha256 = 'f'.repeat(64);
    red(harness.verifyNativePgtapRun(expectedManifest(), mismatch), 'HASH_CHANGED');
    const short = evidence();
    const shortOutput = short.outputs[stream];
    if (!shortOutput) throw new Error('Synthetic output absent');
    shortOutput.byteLength += 1;
    red(harness.verifyNativePgtapRun(expectedManifest(), short), 'HASH_CHANGED');
  });

  it.each([
    ['source', (input: Evidence) => { input.sourceSha = 'f'.repeat(40); }],
    ['migration identity', (input: Evidence) => { input.schemaIdentity.migrationsSha256 = 'f'.repeat(64); }],
    ['generated type identity', (input: Evidence) => { input.schemaIdentity.generatedTypesSha256 = 'f'.repeat(64); }],
    ['manifest hash', (input: Evidence) => { input.manifestSha256 = 'f'.repeat(64); }],
    ['omitted after file', (input: Evidence) => { input.afterFiles.pop(); }],
    ['new after file', (input: Evidence) => { input.afterFiles.push({ path: 'supabase/tests/new.sql', sha256: 'f'.repeat(64) }); }],
    ['duplicate after file', (input: Evidence) => { input.afterFiles.push({ path: VISIBLE, sha256: 'd'.repeat(64) }); }],
    ['changed test hash', (input: Evidence) => { input.afterFiles = input.afterFiles.map(file => ({ ...file, sha256: 'f'.repeat(64) })); }],
  ])('refuses changed %s', (_name, mutate) => {
    const input = evidence();
    mutate(input);
    red(harness.verifyNativePgtapRun(expectedManifest(), input));
  });

  it.each([
    ['nonobject', null],
    ['unknown top-level key', { ...evidence(), accepted: true }],
    ['version coercion', { ...evidence(), formatVersion: '1' }],
    ['wrong version', { ...evidence(), formatVersion: 2 }],
    ['unknown native key', { ...evidence(), native: { ...evidence().native, accepted: true } }],
    ['exit coercion', { ...evidence(), native: { ...evidence().native, exitCode: '0' } }],
    ['both native exit and signal', { ...evidence(), native: { ...evidence().native, signal: 'SIGTERM' } }],
    ['negative elapsed', { ...evidence(), native: { ...evidence().native, elapsedMs: -1 } }],
    ['fractional timing', { ...evidence(), timings: { ...evidence().timings, setupMs: 0.1 } }],
    ['unsafe timing', { ...evidence(), timings: { ...evidence().timings, jobMs: Number.MAX_SAFE_INTEGER + 1 } }],
    ['unknown timing key', { ...evidence(), timings: { ...evidence().timings, skipped: true } }],
    ['unknown schema key', { ...evidence(), schemaIdentity: { ...SCHEMA, guessed: true } }],
    ['unknown private output key', { ...evidence(), outputs: { ...evidence().outputs, stdout: { ...retained('stdout', nativeText()), raw: 'private' } } }],
    ['inconsistent absent original', { ...evidence(), timeout: { ...evidence().timeout, original: { originalPresent: false, originalValue: '2min' } } }],
    ['inconsistent present original', { ...evidence(), timeout: { ...evidence().timeout, original: { originalPresent: true, originalValue: null } } }],
    ['unknown preflight code', { ...evidence(), preflightFailureCodes: ['TRUST_ME'] }],
    ['duplicate preflight codes', { ...evidence(), preflightFailureCodes: ['RUNNER_UNTRUSTED', 'RUNNER_UNTRUSTED'] }],
  ])('fails closed without throwing away cleanup when evidence is malformed: %s', (_name, input) => {
    const receipt = harness.verifyNativePgtapRun(expectedManifest(), input);
    red(receipt, 'EVIDENCE_INVALID');
  });

  it('preserves independently ascertainable failed cleanup for malformed evidence', () => {
    const input = { ...evidence(), accepted: true, timeout: { ...evidence().timeout, verified: false }, reporting: { restored: false, verified: false } };
    const receipt = harness.verifyNativePgtapRun(expectedManifest(), input);
    red(receipt, 'EVIDENCE_INVALID');
    expect(receipt.failureCodes).toContain('TIMEOUT_NOT_RESTORED');
    expect(receipt.failureCodes).toContain('REPORTING_NOT_RESTORED');
  });

  it.each(['RUNNER_UNTRUSTED', 'REPORTING_UNVERIFIED', 'DEADLINE_EXCEEDED', 'RECEIPT_UNAVAILABLE'])('retains %s rather than green-skipping a preflight failure', code => {
    const input = evidence();
    input.preflightFailureCodes = [code];
    red(harness.verifyNativePgtapRun(expectedManifest(), input), code);
  });
});

describe('DBV-006 exact original timeout and reporting cleanup', () => {
  it.each([ORIGINAL, ABSENT, { originalPresent: true, originalValue: '0' }])('accepts only verified exact restoration of %j', original => {
    const input = evidence();
    input.timeout = { original: { ...original }, observed: { ...original }, verified: true };
    expect(harness.verifyNativePgtapRun(expectedManifest(), input).accepted).toBe(true);
  });

  it.each([
    ['verification false', { original: ORIGINAL, observed: ORIGINAL, verified: false }],
    ['assumed two minutes', { original: ORIGINAL, observed: { originalPresent: true, originalValue: '2min' }, verified: true }],
    ['present instead of original absence', { original: ABSENT, observed: { originalPresent: true, originalValue: '2min' }, verified: true }],
    ['absence instead of original present', { original: ORIGINAL, observed: ABSENT, verified: true }],
    ['missing original fact', { original: null, observed: ORIGINAL, verified: true }],
    ['missing observed fact', { original: ORIGINAL, observed: null, verified: true }],
  ])('rejects timeout cleanup: %s', (_name, timeout) => {
    red(harness.verifyNativePgtapRun(expectedManifest(), { ...evidence(), timeout }), 'TIMEOUT_NOT_RESTORED');
  });

  it.each([
    { restored: false, verified: false },
    { restored: true, verified: false },
    { restored: false, verified: true },
  ])('refuses reporting cleanup %j', reporting => {
    red(harness.verifyNativePgtapRun(expectedManifest(), { ...evidence(), reporting }), 'REPORTING_NOT_RESTORED');
  });
});

describe('DBV-002/005/006/007/009/011/012 native orchestration ports', () => {
  it.each([ORIGINAL, ABSENT])('persists outside-runner recovery before alteration and restores exact %j', async original => {
    const fixture = fakePorts(original);
    const { evidence: actual, receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    expect(receipt.accepted).toBe(true);
    expect(fixture.ports.collectFiles).toHaveBeenCalledTimes(2);
    expect(fixture.ports.collectFiles).toHaveBeenNthCalledWith(1, { workdir: WORKDIR });
    expect(fixture.ports.collectFiles).toHaveBeenNthCalledWith(2, { workdir: WORKDIR });
    expect(fixture.ports.installReportingConfig).toHaveBeenCalledExactlyOnceWith({ workdir: WORKDIR, lines: REPORTING_LINES });
    expect(fixture.ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.queryTimeout).toHaveBeenNthCalledWith(1, TARGET);
    expect(fixture.ports.queryTimeout).toHaveBeenNthCalledWith(2, TARGET);
    expect(fixture.ports.persistRecoveryReceipt).toHaveBeenCalledExactlyOnceWith({
      formatVersion: 1, runId: RUN_ID, sourceSha: SOURCE, manifestSha256: manifestHash(expectedManifest()),
      target: TARGET, original, capturedAt: '2026-10-07T09:00:00.000Z', armed: true,
    });
    expect(fixture.events.indexOf('persist')).toBeLessThan(fixture.events.indexOf('alter'));
    expect(fixture.events.indexOf('collect')).toBeLessThan(fixture.events.indexOf('native'));
    expect(fixture.events.indexOf('install')).toBeLessThan(fixture.events.indexOf('native'));
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.alterTimeout).toHaveBeenNthCalledWith(1, { target: TARGET, setting: { originalPresent: true, originalValue: '10min' } });
    expect(fixture.ports.alterTimeout).toHaveBeenNthCalledWith(2, { target: TARGET, setting: original });
    expect(fixture.ports.runNativeCli).toHaveBeenCalledExactlyOnceWith({
      command: 'supabase', args: ['test', 'db', '--linked', 'supabase/tests', 'supabase/tests-holdout'], cwd: WORKDIR, limits: LIMITS,
    });
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledExactlyOnceWith(fixture.installed);
    expect(fixture.ports.retainPrivateOutput).toHaveBeenCalledTimes(2);
    for (const stream of ['stdout', 'stderr'] as const) {
      expect(fixture.ports.retainPrivateOutput).toHaveBeenCalledWith({ runId: RUN_ID, stream, text: actual.native[stream], retentionDirectory: RETENTION });
    }
    expect(actual.native.stdout).toBe(nativeText());
    expect(actual.timeout).toEqual({ original, observed: original, verified: true });
  });

  it('restores approved pre-existing reporting bytes through the original installation object', async () => {
    const fixture = fakePorts();
    const installed = { ...fixture.installed, originalPresent: true, originalText: REPORTING_TEXT };
    fixture.ports.installReportingConfig.mockResolvedValueOnce(installed);
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    expect(receipt.accepted).toBe(true);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledExactlyOnceWith(installed);
  });

  it.each([
    ['source', { ...discovery(), sourceSha: 'f'.repeat(40) }],
    ['schema', { ...discovery(), schemaIdentity: { ...SCHEMA, migrationsSha256: 'f'.repeat(64) } }],
    ['file hash', { ...discovery(), files: discovery().files.map(file => ({ ...file, sha256: 'f'.repeat(64) })) }],
    ['additional file', { ...discovery(), files: [...discovery().files, { path: 'supabase/tests/later.sql', sha256: 'f'.repeat(64), literalPlans: [1] }] }],
    ['omitted file', { ...discovery(), files: [discovery().files[0]] }],
    ['different plan', { ...discovery(), files: discovery().files.map(file => ({ ...file, literalPlans: [3] })) }],
  ])('rejects a changed pre-execution %s before config or database alteration', async (_name, discovery) => {
    const fixture = fakePorts();
    fixture.ports.collectFiles.mockResolvedValueOnce(discovery as DiscoveredInputs);
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt);
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
    expect(fixture.ports.installReportingConfig).not.toHaveBeenCalled();
  });

  it('rejects a changed after-execution manifest and still verifies both cleanups', async () => {
    const fixture = fakePorts();
    fixture.ports.collectFiles.mockResolvedValueOnce(discovery()).mockResolvedValueOnce({ ...discovery(), sourceSha: 'f'.repeat(40) });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'INPUT_CHANGED');
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['missing capture', null],
    ['duplicate capture array', [ORIGINAL, ORIGINAL]],
    ['unknown capture key', { ...ORIGINAL, effective: '2min' }],
    ['inconsistent absence', { originalPresent: false, originalValue: '2min' }],
    ['inconsistent presence', { originalPresent: true, originalValue: null }],
    ['coerced presence', { originalPresent: 'true', originalValue: '2min' }],
    ['empty setting', { originalPresent: true, originalValue: '' }],
  ])('refuses %s before arming alteration', async (_name, original) => {
    const fixture = fakePorts();
    fixture.ports.queryTimeout.mockResolvedValueOnce(original as OriginalTimeout);
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'TIMEOUT_CAPTURE_INVALID');
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['not acknowledged', { acknowledged: false, sha256: 'f'.repeat(64) }],
    ['bad receipt hash', { acknowledged: true, sha256: 'invalid' }],
    ['unknown receipt acknowledgement key', { acknowledged: true, sha256: 'f'.repeat(64), stored: true }],
  ])('refuses outside-runner custody when %s', async (_name, acknowledgment) => {
    const fixture = fakePorts();
    fixture.ports.persistRecoveryReceipt.mockResolvedValueOnce(acknowledgment as { acknowledged: true; sha256: string });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'RECEIPT_UNAVAILABLE');
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['unapproved original config', { originalPresent: true, originalText: `${REPORTING_TEXT}--ignore-exit\n` }],
    ['original absent but bytes supplied', { originalPresent: false, originalText: REPORTING_TEXT }],
    ['original present without bytes', { originalPresent: true, originalText: null }],
    ['wrong installed reporting hash', { installedSha256: 'f'.repeat(64) }],
  ])('refuses %s before native execution and returns the captured installation for cleanup', async (_name, change) => {
    const fixture = fakePorts();
    const installation = { ...fixture.installed, ...change };
    fixture.ports.installReportingConfig.mockResolvedValueOnce(installation);
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'REPORTING_UNVERIFIED');
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledExactlyOnceWith(installation);
  });

  it.each([
    ['collect rejects', 'collectFiles', 'INPUT_CHANGED'],
    ['reporting install rejects', 'installReportingConfig', 'REPORTING_UNVERIFIED'],
    ['catalog capture rejects', 'queryTimeout', 'TIMEOUT_CAPTURE_INVALID'],
    ['outside receipt rejects', 'persistRecoveryReceipt', 'RECEIPT_UNAVAILABLE'],
  ] as const)('fails closed when %s without calling native', async (_name, port, code) => {
    const fixture = fakePorts();
    fixture.ports[port].mockRejectedValueOnce(new Error('synthetic port rejection'));
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, code);
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
  });

  it('arms cleanup before alteration because a rejected alter may already have committed', async () => {
    const fixture = fakePorts();
    fixture.ports.alterTimeout.mockRejectedValueOnce(new Error('synthetic network loss after commit'));
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt);
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.alterTimeout).toHaveBeenNthCalledWith(2, { target: TARGET, setting: ORIGINAL });
    expect(fixture.ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
  });

  it.each([
    ['native assertion failure', { ...evidence().native, exitCode: 1 }],
    ['native interruption', { ...evidence().native, exitCode: null, signal: 'SIGTERM' }],
    ['native connection loss', { ...evidence().native, completed: false, exitCode: null }],
  ])('retains %s while restoring both resources', async (_name, native) => {
    const fixture = fakePorts();
    fixture.ports.runNativeCli.mockResolvedValueOnce(native);
    const { evidence: actual, receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt);
    expect(actual.native).toEqual(native);
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('catches a native port throw, verifies restoration and emits incomplete evidence', async () => {
    const fixture = fakePorts();
    fixture.ports.runNativeCli.mockRejectedValueOnce(new Error('synthetic client crash'));
    const { evidence: actual, receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'NATIVE_INCOMPLETE');
    expect(actual.native).toMatchObject({ completed: false, exitCode: null, signal: null });
    expect(fixture.ports.alterTimeout).toHaveBeenNthCalledWith(2, { target: TARGET, setting: ORIGINAL });
    expect(fixture.ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each(['stdout', 'stderr'] as const)('does not lose cleanup when private %s retention rejects', async stream => {
    const fixture = fakePorts();
    const retain = fixture.ports.retainPrivateOutput.getMockImplementation();
    if (!retain) throw new Error('Synthetic retain implementation absent');
    fixture.ports.retainPrivateOutput.mockImplementation(async output => {
      if (output.stream === stream) throw new Error('synthetic private retention loss');
      return retain(output);
    });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt);
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('keeps a false retained output hash red even after native success', async () => {
    const fixture = fakePorts();
    fixture.ports.retainPrivateOutput.mockResolvedValueOnce({ ...retained('stdout', nativeText()), sha256: 'f'.repeat(64) });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'HASH_CHANGED');
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('rejects private retention outside the protected directory', async () => {
    const fixture = fakePorts();
    fixture.ports.retainPrivateOutput.mockResolvedValueOnce({ ...retained('stdout', nativeText()), path: `${WORKDIR}/public.stdout` });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt);
  });

  it.each(['alter rejection', 'verify rejection', 'catalog mismatch', 'reporting rejection', 'reporting unverified'])('keeps %s cleanup red after native success', async failure => {
    const fixture = fakePorts();
    if (failure === 'alter rejection') fixture.ports.alterTimeout.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error('synthetic restore failure'));
    if (failure === 'verify rejection') fixture.ports.queryTimeout.mockResolvedValueOnce(ORIGINAL).mockRejectedValueOnce(new Error('synthetic catalog unavailable'));
    if (failure === 'catalog mismatch') fixture.ports.queryTimeout.mockResolvedValueOnce(ORIGINAL).mockResolvedValueOnce({ originalPresent: true, originalValue: '10min' });
    if (failure === 'reporting rejection') fixture.ports.restoreReportingConfig.mockRejectedValueOnce(new Error('synthetic restore failure'));
    if (failure === 'reporting unverified') fixture.ports.restoreReportingConfig.mockResolvedValueOnce({ restored: true, verified: false });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, failure.startsWith('reporting') ? 'REPORTING_NOT_RESTORED' : 'TIMEOUT_NOT_RESTORED');
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('still attempts reporting cleanup once when timeout cleanup throws', async () => {
    const fixture = fakePorts();
    fixture.ports.runNativeCli.mockRejectedValueOnce(new Error('synthetic client crash'));
    fixture.ports.alterTimeout.mockResolvedValueOnce(undefined).mockRejectedValueOnce(new Error('synthetic timeout restoration crash'));
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'TIMEOUT_NOT_RESTORED');
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('blocks an already expired run before any alteration or native sweep', async () => {
    const fixture = fakePorts();
    fixture.ports.now.mockReturnValue(Date.parse(LIMITS.deadlineUtc));
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'DEADLINE_EXCEEDED');
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
  });

  it('keeps a completed native run red once its overall deadline has elapsed and restores', async () => {
    const fixture = fakePorts();
    let finished = false;
    fixture.ports.now.mockImplementation(() => finished ? Date.parse(LIMITS.deadlineUtc) : NOW);
    fixture.ports.runNativeCli.mockImplementation(async () => {
      finished = true;
      return evidence().native;
    });
    const { receipt } = await harness.runNativePgtapValidation(fixture.input, fixture.ports);
    red(receipt, 'DEADLINE_EXCEEDED');
    expect(fixture.ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(fixture.ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it.each([
    ['unknown input key', { accepted: true }],
    ['unknown limit key', { limits: { ...LIMITS, ignoreExit: true } }],
    ['zero timeout', { limits: { ...LIMITS, nativeTimeoutMs: 0 } }],
    ['fractional timeout', { limits: { ...LIMITS, nativeTimeoutMs: 1.5 } }],
    ['malformed UTC deadline', { limits: { ...LIMITS, deadlineUtc: 'tomorrow' } }],
  ])('refuses %s before native execution', async (_name, change) => {
    const fixture = fakePorts();
    const { receipt } = await harness.runNativePgtapValidation({ ...fixture.input, ...change }, fixture.ports);
    red(receipt);
    expect(fixture.ports.runNativeCli).not.toHaveBeenCalled();
    expect(fixture.ports.alterTimeout).not.toHaveBeenCalled();
  });
});
