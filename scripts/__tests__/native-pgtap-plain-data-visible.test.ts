import { createHash } from 'node:crypto';
import { beforeAll, describe, expect, it, vi } from 'vitest';

// Independent defensive contract tests. No runner implementation, critic or
// held suite is read. All nested objects, native streams and ports are synthetic.
type Receipt = { accepted: boolean; failureCodes: string[]; [key: string]: unknown };
type Harness = {
  buildNativePgtapManifest: (input: unknown) => unknown;
  verifyNativePgtapRun: (manifest: unknown, evidence: unknown) => Receipt;
  runNativePgtapValidation: (input: unknown, ports: unknown) => Promise<{ receipt: Receipt }>;
};
type Path = readonly (string | number)[];
type TrapKind = 'revoked' | 'prototype' | 'ownKeys' | 'descriptor';
const SOURCE = 'a'.repeat(40);
const SCHEMA = { migrationsSha256: 'b'.repeat(64), generatedTypesSha256: 'c'.repeat(64) };
const VISIBLE = 'supabase/tests/visible.sql';
const INDEPENDENT = 'supabase/tests-holdout/independent.pg';
const SENTINEL = 'synthetic-private-plain-data-trap';
const RUN_ID = 'synthetic-run-1';
const ORIGINAL = { originalPresent: false, originalValue: null };
const NATIVE_TEXT = [
  `[09:00:00] ${VISIBLE} ............. `,
  '1..1', 'ok 1 - synthetic private assertion',
  'ok        2 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
  `[09:00:00] ${INDEPENDENT} .. `,
  '1..1', 'ok 1 - synthetic private independent assertion',
  'ok        3 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
  '[09:00:00]', 'All tests successful.',
  'Files=2, Tests=2,  0 wallclock secs ( 0.04 usr +  0.01 sys =  0.05 CPU)',
  'Result: PASS', '',
].join('\n');
const RECEIPT_KEYS = [
  'formatVersion', 'runId', 'sourceSha', 'schemaIdentity', 'manifestSha256', 'accepted',
  'native', 'files', 'aggregate', 'timings', 'timeout', 'reporting', 'failureCodes',
];
const TRAPS: TrapKind[] = ['revoked', 'prototype', 'ownKeys', 'descriptor'];
let harness: Harness;

beforeAll(async () => {
  const modulePath = '../pgtap/native.mjs';
  harness = await import(modulePath) as Harness;
});

function hash(value: string): string {
  return createHash('sha256').update(value, 'utf8').digest('hex');
}

function discovery() {
  return {
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    files: [
      { path: VISIBLE, sha256: 'd'.repeat(64), literalPlans: [1] },
      { path: INDEPENDENT, sha256: 'e'.repeat(64), literalPlans: [1] },
    ],
  };
}

function manifest() {
  return {
    formatVersion: 1,
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    files: [
      { path: INDEPENDENT, sha256: 'e'.repeat(64), plan: 1 },
      { path: VISIBLE, sha256: 'd'.repeat(64), plan: 1 },
    ],
  };
}

function evidence() {
  return {
    formatVersion: 1,
    runId: RUN_ID,
    sourceSha: SOURCE,
    schemaIdentity: { ...SCHEMA },
    manifestSha256: hash(`${JSON.stringify(manifest())}\n`),
    native: { completed: true, exitCode: 0, signal: null, stdout: NATIVE_TEXT, stderr: '', elapsedMs: 5 },
    outputs: {
      stdout: { path: 'C:/synthetic-private-retention/stdout.raw', sha256: hash(NATIVE_TEXT), byteLength: Buffer.byteLength(NATIVE_TEXT, 'utf8') },
      stderr: { path: 'C:/synthetic-private-retention/stderr.raw', sha256: hash(''), byteLength: 0 },
    },
    afterFiles: manifest().files.map(({ path, sha256 }) => ({ path, sha256 })),
    timings: { setupMs: 1, linkMs: 0, nativeMs: 5, jobMs: 6 },
    timeout: { original: { ...ORIGINAL }, observed: { ...ORIGINAL }, verified: true },
    reporting: { restored: true, verified: true },
    preflightFailureCodes: [],
  };
}

function locate(root: object, path: Path): { owner: Record<string | number, unknown>; key: string | number } {
  const key = path.at(-1);
  if (key === undefined) throw new Error('Synthetic empty path');
  let owner: unknown = root;
  for (const segment of path.slice(0, -1)) {
    if (owner === null || typeof owner !== 'object') throw new Error('Synthetic path has no object');
    owner = (owner as Record<string | number, unknown>)[segment];
  }
  if (owner === null || typeof owner !== 'object') throw new Error('Synthetic path has no owner');
  return { owner: owner as Record<string | number, unknown>, key };
}

function accessor(root: object, path: Path, throwing = false): () => number {
  const { owner, key } = locate(root, path);
  const value = owner[key];
  let reads = 0;
  Object.defineProperty(owner, key, {
    enumerable: true,
    configurable: true,
    get() {
      reads += 1;
      if (throwing) throw new Error(SENTINEL);
      return value;
    },
  });
  return () => reads;
}

function poisoned(target: object, kind: TrapKind): object {
  if (kind === 'revoked') {
    const { proxy, revoke } = Proxy.revocable(target, {});
    revoke();
    return proxy;
  }
  if (kind === 'prototype') return new Proxy(target, { getPrototypeOf() { throw new Error(SENTINEL); } });
  if (kind === 'ownKeys') return new Proxy(target, { ownKeys() { throw new Error(SENTINEL); } });
  return new Proxy(target, { getOwnPropertyDescriptor() { throw new Error(SENTINEL); } });
}

function poisonAt(root: object, path: Path, kind: TrapKind): void {
  const { owner, key } = locate(root, path);
  const target = owner[key];
  if (target === null || typeof target !== 'object') throw new Error('Synthetic trap target is not object');
  owner[key] = poisoned(target, kind);
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
  expect(JSON.stringify(error)).not.toContain(SENTINEL);
}

function sanitizedRed(receipt: Receipt, code = 'EVIDENCE_INVALID'): void {
  expect(receipt.accepted).toBe(false);
  expect(receipt.failureCodes).toContain(code);
  expect(receipt.failureCodes).toEqual([...new Set(receipt.failureCodes)].sort());
  expect(Object.keys(receipt).sort()).toEqual([...RECEIPT_KEYS].sort());
  const serialized = JSON.stringify(receipt);
  expect(serialized).not.toContain(SENTINEL);
  expect(serialized).not.toContain('synthetic private assertion');
  expect(serialized).not.toContain('synthetic-private-retention');
}

function effectPorts() {
  return {
    collectFiles: vi.fn(async () => discovery()),
    installReportingConfig: vi.fn(async () => ({ path: 'C:/synthetic/supabase/tests/.proverc', originalPresent: false, originalText: null, installedSha256: hash('--timer\n--verbose\n--parse\n--nocolor\n--jobs=1\n') })),
    restoreReportingConfig: vi.fn(async () => ({ restored: true, verified: true })),
    queryTimeout: vi.fn(async () => ({ ...ORIGINAL })),
    alterTimeout: vi.fn(async () => undefined),
    persistRecoveryReceipt: vi.fn(async () => ({ acknowledged: true, sha256: 'f'.repeat(64) })),
    retainPrivateOutput: vi.fn(async () => ({ path: 'C:/synthetic-private-retention/stdout.raw', sha256: hash(NATIVE_TEXT), byteLength: Buffer.byteLength(NATIVE_TEXT, 'utf8') })),
    runNativeCli: vi.fn(async () => evidence().native),
    now: vi.fn(() => Date.parse('2026-10-07T09:00:00.000Z')),
  };
}

function runInput() {
  return {
    manifest: manifest(),
    runId: RUN_ID,
    workdir: 'C:/synthetic-dedicated-checkout',
    retentionDirectory: 'C:/synthetic-private-retention',
    limits: { deadlineUtc: '2026-10-07T10:00:00.000Z', nativeTimeoutMs: 60000 },
  };
}

async function runRefused(input: unknown, code?: string): Promise<void> {
  const ports = effectPorts();
  const { receipt } = await harness.runNativePgtapValidation(input, ports);
  sanitizedRed(receipt, code ?? (receipt.failureCodes.includes('MANIFEST_INVALID') ? 'MANIFEST_INVALID' : 'EVIDENCE_INVALID'));
  for (const port of Object.values(ports)) expect(port).not.toHaveBeenCalled();
}

function trailingHole<T>(values: T[]): T[] {
  const array = [...values];
  array.length += 1;
  return array;
}

const DISCOVERY_ACCESSORS: readonly (readonly [string, Path])[] = [
  ['source', ['sourceSha']], ['schema', ['schemaIdentity']], ['files', ['files']],
  ['migration digest', ['schemaIdentity', 'migrationsSha256']],
  ['types digest', ['schemaIdentity', 'generatedTypesSha256']],
  ['array entry', ['files', 0]], ['file path', ['files', 0, 'path']],
  ['file hash', ['files', 0, 'sha256']], ['plans array', ['files', 0, 'literalPlans']],
  ['plan array entry', ['files', 0, 'literalPlans', 0]],
];
const EVIDENCE_ACCESSORS: readonly (readonly [string, Path])[] = [
  ['format', ['formatVersion']], ['run', ['runId']], ['source', ['sourceSha']],
  ['schema', ['schemaIdentity']], ['manifest digest', ['manifestSha256']],
  ['migration digest', ['schemaIdentity', 'migrationsSha256']],
  ['native record', ['native']], ['native success', ['native', 'completed']],
  ['native exit', ['native', 'exitCode']], ['native stdout', ['native', 'stdout']],
  ['native stderr', ['native', 'stderr']], ['outputs record', ['outputs']],
  ['stdout custody', ['outputs', 'stdout']], ['stdout hash', ['outputs', 'stdout', 'sha256']],
  ['after files', ['afterFiles']], ['after array entry', ['afterFiles', 0]],
  ['after file hash', ['afterFiles', 0, 'sha256']], ['timing record', ['timings']],
  ['native timing', ['timings', 'nativeMs']], ['timeout record', ['timeout']],
  ['original timeout', ['timeout', 'original']], ['original presence', ['timeout', 'original', 'originalPresent']],
  ['observed timeout', ['timeout', 'observed']], ['cleanup verification', ['timeout', 'verified']],
  ['reporting record', ['reporting']], ['reporting verified', ['reporting', 'verified']],
  ['preflight code array', ['preflightFailureCodes']],
];
const MANIFEST_ACCESSORS: readonly (readonly [string, Path])[] = [
  ['manifest version', ['manifest', 'formatVersion']], ['manifest source', ['manifest', 'sourceSha']],
  ['manifest schema', ['manifest', 'schemaIdentity']], ['manifest schema digest', ['manifest', 'schemaIdentity', 'migrationsSha256']],
  ['manifest files', ['manifest', 'files']], ['manifest array entry', ['manifest', 'files', 0]],
  ['manifest path', ['manifest', 'files', 0, 'path']], ['manifest hash', ['manifest', 'files', 0, 'sha256']],
  ['manifest plan', ['manifest', 'files', 0, 'plan']],
];

describe('DBV-001/004 plain data controls', () => {
  it('accepts the synthetic ordinary-data control before testing hostile shapes', () => {
    expect(harness.buildNativePgtapManifest(discovery())).toEqual(manifest());
    expect(harness.verifyNativePgtapRun(manifest(), evidence()).accepted).toBe(true);
  });
});

describe('DBV-001 malformed discovery is only a normalized manifest refusal', () => {
  it.each(DISCOVERY_ACCESSORS)('rejects benign accessor %s without evaluating it', (_name, path) => {
    const input = discovery();
    const reads = accessor(input, path);
    manifestRefused(input);
    expect(reads()).toBe(0);
  });

  it.each(DISCOVERY_ACCESSORS)('rejects throwing accessor %s without leaking or evaluating it', (_name, path) => {
    const input = discovery();
    const reads = accessor(input, path, true);
    manifestRefused(input);
    expect(reads()).toBe(0);
  });

  it.each(TRAPS)('normalizes a root %s proxy refusal', kind => {
    manifestRefused(poisoned(discovery(), kind));
  });

  it.each(TRAPS)('normalizes a nested schema %s proxy refusal', kind => {
    const input = discovery();
    poisonAt(input, ['schemaIdentity'], kind);
    manifestRefused(input);
  });

  it.each(TRAPS)('normalizes a nested file %s proxy refusal', kind => {
    const input = discovery();
    poisonAt(input, ['files', 0], kind);
    manifestRefused(input);
  });

  it.each(TRAPS)('normalizes a nested plan array %s proxy refusal', kind => {
    const input = discovery();
    poisonAt(input, ['files', 0, 'literalPlans'], kind);
    manifestRefused(input);
  });

  it('refuses a sparse files array despite both suite records being present', () => {
    const input = discovery();
    input.files = trailingHole(input.files);
    manifestRefused(input);
  });

  it('refuses a sparse literal plan array', () => {
    const input = discovery();
    const first = input.files[0];
    if (!first) throw new Error('Synthetic first file absent');
    first.literalPlans = new Array<number>(1);
    manifestRefused(input);
  });
});

describe('DBV-001/004 malformed supplied manifest returns a sanitized failed receipt', () => {
  it.each(MANIFEST_ACCESSORS)('rejects supplied %s accessor without evaluating it', (_name, path) => {
    const input = manifest();
    const reads = accessor(input, path.slice(1), true);
    sanitizedRed(harness.verifyNativePgtapRun(input, evidence()), 'MANIFEST_INVALID');
    expect(reads()).toBe(0);
  });

  it.each(TRAPS)('returns MANIFEST_INVALID for a root manifest %s proxy', kind => {
    sanitizedRed(harness.verifyNativePgtapRun(poisoned(manifest(), kind), evidence()), 'MANIFEST_INVALID');
  });

  it.each(TRAPS)('returns MANIFEST_INVALID for a nested manifest record %s proxy', kind => {
    const input = manifest();
    poisonAt(input, ['files', 0], kind);
    sanitizedRed(harness.verifyNativePgtapRun(input, evidence()), 'MANIFEST_INVALID');
  });

  it('rejects a sparse supplied manifest files array', () => {
    const input = manifest();
    input.files = trailingHole(input.files);
    sanitizedRed(harness.verifyNativePgtapRun(input, evidence()), 'MANIFEST_INVALID');
  });
});

describe('DBV-004/012 malformed evidence stays red and sanitized', () => {
  it.each(EVIDENCE_ACCESSORS)('rejects benign evidence accessor %s without evaluating it', (_name, path) => {
    const input = evidence();
    const reads = accessor(input, path);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
    expect(reads()).toBe(0);
  });

  it.each(EVIDENCE_ACCESSORS)('rejects throwing evidence accessor %s without evaluating it', (_name, path) => {
    const input = evidence();
    const reads = accessor(input, path, true);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
    expect(reads()).toBe(0);
  });

  it.each(TRAPS)('returns a sanitized receipt for a root %s proxy', kind => {
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), poisoned(evidence(), kind)));
  });

  it.each(TRAPS)('returns a sanitized receipt for native %s reflection failure', kind => {
    const input = evidence();
    poisonAt(input, ['native'], kind);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
  });

  it.each(TRAPS)('returns a sanitized receipt for cleanup %s reflection failure', kind => {
    const input = evidence();
    poisonAt(input, ['timeout', 'original'], kind);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
  });

  it.each(TRAPS)('returns a sanitized receipt for after-file %s reflection failure', kind => {
    const input = evidence();
    poisonAt(input, ['afterFiles', 0], kind);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
  });

  it('rejects an accessor in a nonempty preflight-code array', () => {
    const input = { ...evidence(), preflightFailureCodes: ['RUNNER_UNTRUSTED'] };
    const reads = accessor(input, ['preflightFailureCodes', 0], true);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
    expect(reads()).toBe(0);
  });

  it('rejects sparse afterFiles even when both matching file records remain', () => {
    const input = evidence();
    input.afterFiles = trailingHole(input.afterFiles);
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
  });

  it('rejects a sparse preflight-code array rather than silently skipping a hole', () => {
    const input = { ...evidence(), preflightFailureCodes: new Array<string>(1) };
    sanitizedRed(harness.verifyNativePgtapRun(manifest(), input));
  });
});

describe('DBV-001/004 invalid orchestration input invokes no ports', () => {
  it.each(MANIFEST_ACCESSORS)('refuses accessor %s before execution or clock ports', async (_name, path) => {
    const input = runInput();
    const reads = accessor(input, path, true);
    await runRefused(input, 'MANIFEST_INVALID');
    expect(reads()).toBe(0);
  });

  it.each(TRAPS)('refuses root run-input %s reflection failure before ports', async kind => {
    await runRefused(poisoned(runInput(), kind));
  });

  it.each(TRAPS)('refuses manifest %s reflection failure before ports', async kind => {
    const input = runInput();
    poisonAt(input, ['manifest'], kind);
    await runRefused(input, 'MANIFEST_INVALID');
  });

  it.each(TRAPS)('refuses nested manifest file %s reflection failure before ports', async kind => {
    const input = runInput();
    poisonAt(input, ['manifest', 'files', 0], kind);
    await runRefused(input, 'MANIFEST_INVALID');
  });

  it('refuses a sparse supplied manifest before any port', async () => {
    const input = runInput();
    input.manifest.files = trailingHole(input.manifest.files);
    await runRefused(input, 'MANIFEST_INVALID');
  });

  it('refuses a revoked supplied manifest array before any port', async () => {
    const input = runInput();
    poisonAt(input, ['manifest', 'files'], 'revoked');
    await runRefused(input, 'MANIFEST_INVALID');
  });
});
