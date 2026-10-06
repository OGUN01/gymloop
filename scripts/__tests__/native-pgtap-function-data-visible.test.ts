import { createHash } from 'node:crypto';
import { beforeAll, describe, expect, it, vi } from 'vitest';

// Independent visible tests: ordinary protocol data may not be callable. The
// nine declared callback ports remain functions. No implementation is read.
type Receipt = { accepted: boolean; failureCodes: string[]; [key: string]: unknown };
type Harness = {
  buildNativePgtapManifest: (input: unknown) => unknown;
  verifyNativePgtapRun: (manifest: unknown, evidence: unknown) => Receipt;
  runNativePgtapValidation: (input: unknown, ports: unknown) => Promise<{ receipt: Receipt }>;
};
type Path = readonly (string | number)[];
const SOURCE = 'a'.repeat(40);
const SCHEMA = { migrationsSha256: 'b'.repeat(64), generatedTypesSha256: 'c'.repeat(64) };
const VISIBLE = 'supabase/tests/visible.sql';
const INDEPENDENT = 'supabase/tests-holdout/independent.pg';
const SENTINEL = 'synthetic-private-function-data-trap';
const RUN_ID = 'synthetic-run-1';
const RETENTION = 'C:/synthetic-private-function-retention';
const ORIGINAL = { originalPresent: false, originalValue: null };
const REPORTING_TEXT = '--timer\n--verbose\n--parse\n--nocolor\n--jobs=1\n';
const NATIVE_TEXT = [
  `[09:00:00] ${VISIBLE} ............. `,
  '1..1', 'ok 1 - synthetic private function assertion',
  'ok        2 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
  `[09:00:00] ${INDEPENDENT} .. `,
  '1..1', 'ok 1 - synthetic private independent function assertion',
  'ok        3 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
  '[09:00:00]', 'All tests successful.',
  'Files=2, Tests=2,  0 wallclock secs ( 0.04 usr +  0.01 sys =  0.05 CPU)',
  'Result: PASS', '',
].join('\n');
const RECEIPT_KEYS = ['formatVersion', 'runId', 'sourceSha', 'schemaIdentity', 'manifestSha256', 'accepted', 'native', 'files', 'aggregate', 'timings', 'timeout', 'reporting', 'failureCodes'];
let harness: Harness;

beforeAll(async () => {
  const modulePath = '../pgtap/native.mjs';
  harness = await import(modulePath) as Harness;
});

function hash(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function manifest() {
  return {
    formatVersion: 1, sourceSha: SOURCE, schemaIdentity: { ...SCHEMA },
    files: [
      { path: INDEPENDENT, sha256: 'e'.repeat(64), plan: 1 },
      { path: VISIBLE, sha256: 'd'.repeat(64), plan: 1 },
    ],
  };
}

function discovery() {
  return {
    sourceSha: SOURCE, schemaIdentity: { ...SCHEMA },
    files: [
      { path: VISIBLE, sha256: 'd'.repeat(64), literalPlans: [1] },
      { path: INDEPENDENT, sha256: 'e'.repeat(64), literalPlans: [1] },
    ],
  };
}

function retained(stream: string, text: string) {
  return { path: `${RETENTION}/${stream}.raw`, sha256: hash(text), byteLength: Buffer.byteLength(text, 'utf8') };
}

function evidence() {
  return {
    formatVersion: 1, runId: RUN_ID, sourceSha: SOURCE, schemaIdentity: { ...SCHEMA },
    manifestSha256: hash(`${JSON.stringify(manifest())}\n`),
    native: { completed: true, exitCode: 0, signal: null, stdout: NATIVE_TEXT, stderr: '', elapsedMs: 5 },
    outputs: { stdout: retained('stdout', NATIVE_TEXT), stderr: retained('stderr', '') },
    afterFiles: manifest().files.map(({ path, sha256 }) => ({ path, sha256 })),
    timings: { setupMs: 1, linkMs: 0, nativeMs: 5, jobMs: 6 },
    timeout: { original: { ...ORIGINAL }, observed: { ...ORIGINAL }, verified: true },
    reporting: { restored: true, verified: true }, preflightFailureCodes: [],
  };
}

function runInput() {
  return {
    manifest: manifest(), runId: RUN_ID, workdir: 'C:/synthetic-dedicated-checkout', retentionDirectory: RETENTION,
    limits: { deadlineUtc: '2026-10-07T10:00:00.000Z', nativeTimeoutMs: 60000 },
  };
}

function callbackPorts() {
  return {
    collectFiles: vi.fn(async () => discovery()),
    installReportingConfig: vi.fn(async () => ({ path: 'C:/synthetic-dedicated-checkout/supabase/tests/.proverc', originalPresent: false, originalText: null, installedSha256: hash(REPORTING_TEXT) })),
    restoreReportingConfig: vi.fn(async () => ({ restored: true, verified: true })),
    queryTimeout: vi.fn(async () => ({ ...ORIGINAL })),
    alterTimeout: vi.fn(async () => undefined),
    persistRecoveryReceipt: vi.fn(async (receipt: unknown) => ({ acknowledged: true, sha256: hash(`${JSON.stringify(receipt)}\n`) })),
    retainPrivateOutput: vi.fn(async (output: { stream: string; text: string }) => retained(output.stream, output.text)),
    runNativeCli: vi.fn(async () => evidence().native),
    now: vi.fn(() => Date.parse('2026-10-07T09:00:00.000Z')),
  };
}

function callableData(data: object, field: string | number, throwing: boolean) {
  let reads = 0;
  let calls = 0;
  const value = Reflect.get(data, field);
  const callable = Object.assign(() => { calls += 1; throw new Error(SENTINEL); }, data);
  Object.defineProperty(callable, field, {
    enumerable: true, configurable: true,
    get() { reads += 1; if (throwing) throw new Error(SENTINEL); return value; },
  });
  return { callable, observed: () => ({ reads, calls }) };
}

function replace(root: object, path: Path, field: string | number, throwing: boolean): () => { reads: number; calls: number } {
  let owner: unknown = root;
  for (const segment of path.slice(0, -1)) {
    if (owner === null || typeof owner !== 'object') throw new Error('Synthetic path owner invalid');
    owner = Reflect.get(owner, segment);
  }
  const key = path.at(-1);
  if (owner === null || typeof owner !== 'object' || key === undefined) throw new Error('Synthetic path invalid');
  const target: unknown = Reflect.get(owner, key);
  if (target === null || typeof target !== 'object') throw new Error('Synthetic target invalid');
  const poison = callableData(target, field, throwing);
  Reflect.set(owner, key, poison.callable);
  return poison.observed;
}

function manifestRefused(input: unknown): void {
  let thrown: unknown;
  try { harness.buildNativePgtapManifest(input); } catch (error) { thrown = error; }
  expect(thrown).toBeInstanceOf(Error);
  const error = thrown as Error & { code?: unknown; cause?: unknown };
  expect(error.constructor).toBe(Error);
  expect(error.code).toBe('MANIFEST_INVALID');
  expect(error.cause).toBeUndefined();
  expect(String(error)).not.toContain(SENTINEL);
}

function red(receipt: Receipt, code: string): void {
  expect(receipt.accepted).toBe(false);
  expect(receipt.failureCodes).toContain(code);
  expect(receipt.failureCodes).toEqual([...new Set(receipt.failureCodes)].sort());
  expect(Object.keys(receipt).sort()).toEqual([...RECEIPT_KEYS].sort());
  const serialized = JSON.stringify(receipt);
  expect(serialized).not.toContain(SENTINEL);
  expect(serialized).not.toContain('synthetic private function assertion');
  expect(serialized).not.toContain(RETENTION);
}

async function runRefused(input: unknown, code: string): Promise<void> {
  const ports = callbackPorts();
  red((await harness.runNativePgtapValidation(input, ports)).receipt, code);
  for (const port of Object.values(ports)) expect(port).not.toHaveBeenCalled();
}

const BUILD_RECORDS: readonly (readonly [string, Path, string | number])[] = [
  ['schema', ['schemaIdentity'], 'migrationsSha256'],
  ['files array', ['files'], 0],
  ['file record', ['files', 0], 'path'],
  ['literal plans array', ['files', 0, 'literalPlans'], 0],
];
const EVIDENCE_RECORDS: readonly (readonly [string, Path, string | number])[] = [
  ['schema', ['schemaIdentity'], 'migrationsSha256'],
  ['NativeResult', ['native'], 'stdout'],
  ['outputs', ['outputs'], 'stdout'],
  ['stdout custody', ['outputs', 'stdout'], 'path'],
  ['stderr custody', ['outputs', 'stderr'], 'sha256'],
  ['timeout', ['timeout'], 'verified'],
  ['original timeout', ['timeout', 'original'], 'originalPresent'],
  ['observed timeout', ['timeout', 'observed'], 'originalValue'],
  ['reporting', ['reporting'], 'verified'],
  ['timings', ['timings'], 'nativeMs'],
  ['preflight code array', ['preflightFailureCodes'], 0],
];

describe('DBV-001 callable values are invalid manifest data', () => {
  it('refuses function-valued DiscoveredInputs with benign or throwing getters', () => {
    for (const throwing of [false, true]) {
      const poison = callableData(discovery(), 'sourceSha', throwing);
      manifestRefused(poison.callable);
      expect(poison.observed()).toEqual({ reads: 0, calls: 0 });
    }
  });

  it.each(BUILD_RECORDS)('refuses a function-valued %s before reading its accessor', (_name, path, field) => {
    for (const throwing of [false, true]) {
      const input = discovery();
      const observed = replace(input, path, field, throwing);
      manifestRefused(input);
      expect(observed()).toEqual({ reads: 0, calls: 0 });
    }
  });
});

describe('DBV-004/012 callable evidence is refused and never evaluated', () => {
  it('keeps ordinary synthetic evidence accepted as the control', () => {
    expect(harness.verifyNativePgtapRun(manifest(), evidence()).accepted).toBe(true);
  });

  it('returns sanitized EVIDENCE_INVALID for function-valued top-level Evidence', () => {
    for (const throwing of [false, true]) {
      const poison = callableData(evidence(), 'runId', throwing);
      red(harness.verifyNativePgtapRun(manifest(), poison.callable), 'EVIDENCE_INVALID');
      expect(poison.observed()).toEqual({ reads: 0, calls: 0 });
    }
  });

  it.each(EVIDENCE_RECORDS)('returns sanitized EVIDENCE_INVALID for a function-valued %s', (_name, path, field) => {
    for (const throwing of [false, true]) {
      const input = evidence();
      const observed = replace(input, path, field, throwing);
      red(harness.verifyNativePgtapRun(manifest(), input), 'EVIDENCE_INVALID');
      expect(observed()).toEqual({ reads: 0, calls: 0 });
    }
  });
});

describe('DBV-001/004 run data is separate from the nine callable ports', () => {
  it('refuses a function-valued run input before any port invocation', async () => {
    for (const throwing of [false, true]) {
      const poison = callableData(runInput(), 'runId', throwing);
      await runRefused(poison.callable, 'EVIDENCE_INVALID');
      expect(poison.observed()).toEqual({ reads: 0, calls: 0 });
    }
  });

  it('refuses a function-valued supplied Manifest before any port invocation', async () => {
    for (const throwing of [false, true]) {
      const input = runInput();
      const observed = replace(input, ['manifest'], 'formatVersion', throwing);
      await runRefused(input, 'MANIFEST_INVALID');
      expect(observed()).toEqual({ reads: 0, calls: 0 });
    }
  });

  it('refuses function-valued limits before evaluating deadline or calling ports', async () => {
    for (const throwing of [false, true]) {
      const input = runInput();
      const observed = replace(input, ['limits'], 'deadlineUtc', throwing);
      await runRefused(input, 'EVIDENCE_INVALID');
      expect(observed()).toEqual({ reads: 0, calls: 0 });
    }
  });

  it('refuses a function-valued manifest schema before any port invocation', async () => {
    const input = runInput();
    const observed = replace(input, ['manifest', 'schemaIdentity'], 'migrationsSha256', true);
    await runRefused(input, 'MANIFEST_INVALID');
    expect(observed()).toEqual({ reads: 0, calls: 0 });
  });

  it('refuses a function-valued manifest file before any port invocation', async () => {
    const input = runInput();
    const observed = replace(input, ['manifest', 'files', 0], 'path', true);
    await runRefused(input, 'MANIFEST_INVALID');
    expect(observed()).toEqual({ reads: 0, calls: 0 });
  });

  it('accepts all nine declared function callbacks and completes both exact cleanups', async () => {
    const ports = callbackPorts();
    expect(Object.values(ports)).toHaveLength(9);
    expect(Object.values(ports).every(port => typeof port === 'function')).toBe(true);
    const { receipt } = await harness.runNativePgtapValidation(runInput(), ports);
    expect(receipt.accepted).toBe(true);
    expect(ports.collectFiles).toHaveBeenCalledTimes(2);
    expect(ports.runNativeCli).toHaveBeenCalledTimes(1);
    expect(ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });

  it('keeps a collection callback rejection as INPUT_CHANGED rather than invalidating callback functions', async () => {
    const ports = callbackPorts();
    ports.collectFiles.mockRejectedValueOnce(new Error(SENTINEL));
    red((await harness.runNativePgtapValidation(runInput(), ports)).receipt, 'INPUT_CHANGED');
    expect(ports.runNativeCli).not.toHaveBeenCalled();
  });

  it('keeps a reporting callback rejection as REPORTING_UNVERIFIED without calling native', async () => {
    const ports = callbackPorts();
    ports.installReportingConfig.mockRejectedValueOnce(new Error(SENTINEL));
    red((await harness.runNativePgtapValidation(runInput(), ports)).receipt, 'REPORTING_UNVERIFIED');
    expect(ports.runNativeCli).not.toHaveBeenCalled();
    expect(ports.alterTimeout).not.toHaveBeenCalled();
  });

  it('keeps a native callback rejection incomplete while still restoring armed cleanup', async () => {
    const ports = callbackPorts();
    ports.runNativeCli.mockRejectedValueOnce(new Error(SENTINEL));
    red((await harness.runNativePgtapValidation(runInput(), ports)).receipt, 'NATIVE_INCOMPLETE');
    expect(ports.alterTimeout).toHaveBeenCalledTimes(2);
    expect(ports.queryTimeout).toHaveBeenCalledTimes(2);
    expect(ports.restoreReportingConfig).toHaveBeenCalledTimes(1);
  });
});
