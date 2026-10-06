import { createCipheriv, createDecipheriv } from 'node:crypto';
import { beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants';

// Independent standard-crypto and descriptor oracles. No project source is read.
type RunnerBoundary = {
  verifyNativeRunnerJob: (expected: unknown, observed: unknown) => { trusted: boolean; failureCodes: string[] };
  chooseNativeRunnerLabels: (input: unknown) => string[];
};
type TeardownBoundary = { verifyNativeWorkloadTeardown: (expected: unknown, receipt: unknown) => boolean };
type CryptoBoundary = {
  protectNativePgtapOutput: (input: unknown) => Buffer;
  recoverNativePgtapOutput: (input: unknown) => Buffer;
};
const SOURCE = 'a'.repeat(40);
const RUN_ID = '37486763608';
const MANIFEST = 'b'.repeat(64);
const LABEL = `fitcruxx-db-win-x64-${RUN_ID}-1-${SOURCE.slice(0, 12)}`;
const KEY = Buffer.from(Array.from({ length: PHASE8_BACKUP_LIMITS.keyBytes }, (_, index) => index));
const RAW = Buffer.concat([Buffer.from('synthetic-owned-bytes-private\r\n\0', 'utf8'), Buffer.from([0xff, 0x80, 0xfe])]);
const MAGIC = Buffer.from('NDBTAP01', 'utf8');
const TAG_START = MAGIC.length + PHASE8_BACKUP_LIMITS.ivBytes;
const BODY_START = TAG_START + PHASE8_BACKUP_LIMITS.tagBytes;
const SENTINEL = 'synthetic-private-owned-byte-trap';
const TYPED_ARRAY_PROTOTYPE = Object.getPrototypeOf(Uint8Array.prototype) as object;
const VIEW_BUFFER = Object.getOwnPropertyDescriptor(TYPED_ARRAY_PROTOTYPE, 'buffer')?.get as (this: unknown) => ArrayBuffer;
const VIEW_OFFSET = Object.getOwnPropertyDescriptor(TYPED_ARRAY_PROTOTYPE, 'byteOffset')?.get as (this: unknown) => number;
const VIEW_LENGTH = Object.getOwnPropertyDescriptor(TYPED_ARRAY_PROTOTYPE, 'byteLength')?.get as (this: unknown) => number;
let runnerBoundary: RunnerBoundary;
let teardownBoundary: TeardownBoundary;
let cryptoBoundary: CryptoBoundary;

beforeAll(async () => {
  const runnerPath = '../pgtap/runner-job.mjs';
  const teardownPath = '../pgtap/workload-teardown.mjs';
  const cryptoPath = '../pgtap/private-output.mjs';
  runnerBoundary = await import(runnerPath) as RunnerBoundary;
  teardownBoundary = await import(teardownPath) as TeardownBoundary;
  cryptoBoundary = await import(cryptoPath) as CryptoBoundary;
});

function trustedExpected() {
  return { sourceSha: SOURCE, runId: RUN_ID, runAttempt: '1', label: LABEL };
}

function trustedJob() {
  return {
    repository: 'OGUN01/gymloop', eventName: 'push', ref: 'refs/heads/main', sourceSha: SOURCE,
    runId: RUN_ID, runAttempt: '1', workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
  };
}

function trustedObserved() { return { ...trustedJob(), runnerOs: 'Windows', job: 'pgtap' }; }

function readyRunner() {
  return { id: 1, status: 'online', busy: false, ephemeral: true, guardVerified: true, label: LABEL, sourceSha: SOURCE, runId: RUN_ID, runAttempt: '1' };
}

function teardownExpected() {
  return { runId: `${RUN_ID}-1`, sourceSha: SOURCE, jobId: '123456789', runnerId: 42, runnerEnvironment: 'self-hosted' };
}

function teardownReceipt() {
  return {
    formatVersion: 1, ...teardownExpected(), privateProofSha256: 'c'.repeat(64),
    nativeProcessesStopped: true, ownedContainersStopped: true, runnerDeregistered: true,
    verifiedAt: '2026-10-07T09:00:00.000Z',
  };
}

function lyingGet<T extends object>(target: T, replacements: Record<string, unknown>) {
  let reads = 0;
  const proxy = new Proxy(target, {
    get(object, key, receiver) {
      reads += 1;
      return Object.prototype.hasOwnProperty.call(replacements, key) ? Reflect.get(replacements, key) : Reflect.get(object, key, receiver);
    },
  });
  return { proxy, reads: () => reads };
}

function untrusted(expected: unknown, observed: unknown): void {
  expect(runnerBoundary.verifyNativeRunnerJob(expected, observed)).toEqual({ trusted: false, failureCodes: ['RUNNER_UNTRUSTED'] });
}

function actualBytes(value: Buffer): Buffer {
  return Buffer.from(VIEW_BUFFER.call(value), VIEW_OFFSET.call(value), VIEW_LENGTH.call(value));
}

function aad(): Buffer { return Buffer.from(JSON.stringify(['NDBTAP01', RUN_ID, MANIFEST]), 'utf8'); }

function independentSeal(plaintext = RAW): Buffer {
  const iv = Buffer.alloc(PHASE8_BACKUP_LIMITS.ivBytes, 0x5a);
  const cipher = createCipheriv('aes-256-gcm', KEY, iv, { authTagLength: PHASE8_BACKUP_LIMITS.tagBytes });
  cipher.setAAD(aad());
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), encrypted]);
}

function independentOpen(ciphertext: Buffer): Buffer {
  const bytes = actualBytes(ciphertext);
  const decipher = createDecipheriv('aes-256-gcm', KEY, bytes.subarray(MAGIC.length, TAG_START), { authTagLength: PHASE8_BACKUP_LIMITS.tagBytes });
  decipher.setAAD(aad());
  decipher.setAuthTag(bytes.subarray(TAG_START, BODY_START));
  return Buffer.concat([decipher.update(bytes.subarray(BODY_START)), decipher.final()]);
}

function protectInput(plaintext = Buffer.from(RAW), encryptionKey = Buffer.from(KEY)) {
  return { runId: RUN_ID, manifestSha256: MANIFEST, plaintext, encryptionKey };
}

function recoverInput(ciphertext = independentSeal(), encryptionKey = Buffer.from(KEY)) {
  return { runId: RUN_ID, manifestSha256: MANIFEST, ciphertext, encryptionKey };
}

function privateRefused(action: () => unknown): void {
  let thrown: unknown;
  try { action(); } catch (error) { thrown = error; }
  expect(thrown).toBeInstanceOf(Error);
  const error = thrown as Error & { code?: unknown; cause?: unknown };
  expect(error.constructor).toBe(Error);
  expect(error.message).toBe('Private native output refused.');
  expect(error.code).toBe('PRIVATE_OUTPUT_INVALID');
  expect(error.cause).toBeUndefined();
}

function overrideGetter(target: Buffer, key: string, value: unknown, throwing = false) {
  let reads = 0;
  Object.defineProperty(target, key, { configurable: true, get() { reads += 1; if (throwing) throw new Error(SENTINEL); return value; } });
  return () => reads;
}

function overrideMethod(target: Buffer, key: string, value: unknown) {
  let calls = 0;
  Object.defineProperty(target, key, { configurable: true, value: () => { calls += 1; return value; } });
  return () => calls;
}

describe('DBV-008 descriptor-native runner identities and readiness', () => {
  it('cannot accept an untrusted repository hidden by a successful Proxy.get lie', () => {
    const observed = lyingGet({ ...trustedObserved(), repository: 'outsider/gymloop' }, { repository: 'OGUN01/gymloop' });
    untrusted(trustedExpected(), observed.proxy);
    expect(observed.reads()).toBe(0);
  });

  it('cannot replace a mismatched expected source identity through Proxy.get', () => {
    const expected = lyingGet({ ...trustedExpected(), sourceSha: 'd'.repeat(40) }, { sourceSha: SOURCE });
    untrusted(expected.proxy, trustedObserved());
    expect(expected.reads()).toBe(0);
  });

  it('keeps a truly busy runner hosted even if its get trap claims idle', () => {
    const runner = lyingGet({ ...readyRunner(), busy: true }, { busy: false });
    expect(runnerBoundary.chooseNativeRunnerLabels({ job: trustedJob(), runner: runner.proxy })).toEqual(['ubuntu-latest']);
    expect(runner.reads()).toBe(0);
  });

  it('keeps an unproved guard hosted even if its get trap claims proof', () => {
    const runner = lyingGet({ ...readyRunner(), guardVerified: false }, { guardVerified: true });
    expect(runnerBoundary.chooseNativeRunnerLabels({ job: trustedJob(), runner: runner.proxy })).toEqual(['ubuntu-latest']);
    expect(runner.reads()).toBe(0);
  });

  it('cannot replace an untrusted outer job descriptor with a trusted get result', () => {
    const input = lyingGet({ job: { ...trustedJob(), eventName: 'pull_request' }, runner: readyRunner() }, { job: trustedJob() });
    expect(runnerBoundary.chooseNativeRunnerLabels(input.proxy)).toEqual(['ubuntu-latest']);
    expect(input.reads()).toBe(0);
  });
});

describe('DBV-007/009 descriptor-native operator teardown facts', () => {
  it('cannot turn a false container-stop fact into true through Proxy.get', () => {
    const receipt = lyingGet({ ...teardownReceipt(), ownedContainersStopped: false }, { ownedContainersStopped: true });
    expect(teardownBoundary.verifyNativeWorkloadTeardown(teardownExpected(), receipt.proxy)).toBe(false);
    expect(receipt.reads()).toBe(0);
  });

  it('cannot turn a mismatched expected runner identity into a matching get result', () => {
    const expected = lyingGet({ ...teardownExpected(), runnerId: 43 }, { runnerId: 42 });
    expect(teardownBoundary.verifyNativeWorkloadTeardown(expected.proxy, teardownReceipt())).toBe(false);
    expect(expected.reads()).toBe(0);
  });

  it('cannot manufacture a valid proof digest by overriding property reads', () => {
    const receipt = lyingGet({ ...teardownReceipt(), privateProofSha256: 'C'.repeat(64) }, { privateProofSha256: 'c'.repeat(64) });
    expect(teardownBoundary.verifyNativeWorkloadTeardown(teardownExpected(), receipt.proxy)).toBe(false);
    expect(receipt.reads()).toBe(0);
  });
});

describe('DBV-012 crypto uses owned Buffer view bytes and frozen descriptors', () => {
  it('round-trips an independent standard AES-256-GCM control', () => {
    expect(cryptoBoundary.recoverNativePgtapOutput(recoverInput())).toEqual(RAW);
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput()))).toEqual(RAW);
  });

  it('cannot replace descriptor-native short key bytes through argument Proxy.get', () => {
    const input = lyingGet(protectInput(Buffer.from(RAW), Buffer.alloc(PHASE8_BACKUP_LIMITS.keyBytes - 1)), { encryptionKey: KEY });
    privateRefused(() => cryptoBoundary.protectNativePgtapOutput(input.proxy));
    expect(input.reads()).toBe(0);
  });

  it('cannot replace descriptor-native tampered ciphertext through argument Proxy.get', () => {
    const correct = independentSeal();
    const corrupt = Buffer.from(correct);
    corrupt[TAG_START] = (corrupt[TAG_START] ?? 0) ^ 1;
    const input = lyingGet(recoverInput(corrupt), { ciphertext: correct });
    privateRefused(() => cryptoBoundary.recoverNativePgtapOutput(input.proxy));
    expect(input.reads()).toBe(0);
  });

  it('ignores fake large plaintext sizing and throwing own methods on a valid Buffer', () => {
    const plaintext = Buffer.from(RAW);
    const before = Buffer.from(plaintext);
    const lengthReads = overrideGetter(plaintext, 'length', NATIVE_DB_VALIDATION.maxProcessBytes + 1);
    const byteReads = overrideGetter(plaintext, 'byteLength', NATIVE_DB_VALIDATION.maxProcessBytes + 1, true);
    const subarrayCalls = overrideMethod(plaintext, 'subarray', Buffer.from(SENTINEL));
    const equalsCalls = overrideMethod(plaintext, 'equals', false);
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput(plaintext)))).toEqual(RAW);
    expect(actualBytes(plaintext)).toEqual(before);
    expect([lengthReads(), byteReads(), subarrayCalls(), equalsCalls()]).toEqual([0, 0, 0, 0]);
  });

  it('uses actual 32-byte key bytes without evaluating a throwing own length getter', () => {
    const key = Buffer.from(KEY);
    const reads = overrideGetter(key, 'length', 0, true);
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput(Buffer.from(RAW), key)))).toEqual(RAW);
    expect(actualBytes(key)).toEqual(KEY);
    expect(reads()).toBe(0);
  });

  it('refuses an actual short key despite claimed correct size and replacement subarray', () => {
    const key = Buffer.alloc(PHASE8_BACKUP_LIMITS.keyBytes - 1);
    const lengthReads = overrideGetter(key, 'length', PHASE8_BACKUP_LIMITS.keyBytes);
    const byteReads = overrideGetter(key, 'byteLength', PHASE8_BACKUP_LIMITS.keyBytes);
    const calls = overrideMethod(key, 'subarray', KEY);
    privateRefused(() => cryptoBoundary.protectNativePgtapOutput(protectInput(Buffer.from(RAW), key)));
    expect([lengthReads(), byteReads(), calls()]).toEqual([0, 0, 0]);
  });

  it('recovers actual ciphertext bytes without consulting fake short size or slicing methods', () => {
    const ciphertext = independentSeal();
    const before = Buffer.from(ciphertext);
    const reads = overrideGetter(ciphertext, 'length', 1);
    const calls = overrideMethod(ciphertext, 'subarray', Buffer.from(SENTINEL));
    const equalsCalls = overrideMethod(ciphertext, 'equals', false);
    expect(cryptoBoundary.recoverNativePgtapOutput(recoverInput(ciphertext))).toEqual(RAW);
    expect(actualBytes(ciphertext)).toEqual(before);
    expect([reads(), calls(), equalsCalls()]).toEqual([0, 0, 0]);
  });

  it('authenticates corrupt actual bytes despite a lying slice and equals method', () => {
    const correct = independentSeal();
    const corrupt = Buffer.from(correct);
    corrupt[TAG_START] = (corrupt[TAG_START] ?? 0) ^ 1;
    const before = Buffer.from(corrupt);
    const calls = overrideMethod(corrupt, 'subarray', correct);
    const equalsCalls = overrideMethod(corrupt, 'equals', true);
    privateRefused(() => cryptoBoundary.recoverNativePgtapOutput(recoverInput(corrupt)));
    expect(actualBytes(corrupt)).toEqual(before);
    expect([calls(), equalsCalls()]).toEqual([0, 0]);
  });

  it('accepts unrelated caller Buffer properties without interpreting or invoking them', () => {
    let calls = 0;
    const plaintext = Buffer.from(RAW);
    const key = Buffer.from(KEY);
    const ciphertext = independentSeal();
    for (const buffer of [plaintext, key, ciphertext]) {
      Object.defineProperty(buffer, 'unrelated', { value: () => { calls += 1; throw new Error(SENTINEL); } });
      Object.defineProperty(buffer, Symbol(SENTINEL), { value: SENTINEL });
    }
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput(plaintext, key)))).toEqual(RAW);
    expect(cryptoBoundary.recoverNativePgtapOutput(recoverInput(ciphertext, key))).toEqual(RAW);
    expect(calls).toBe(0);
  });

  it('ignores per-Buffer prototype sizing and method overrides without changing actual bytes', () => {
    let calls = 0;
    const prototype = Object.create(Buffer.prototype);
    for (const field of ['length', 'byteLength', 'byteOffset', 'buffer']) Object.defineProperty(prototype, field, { get() { calls += 1; throw new Error(SENTINEL); } });
    for (const method of ['subarray', 'equals']) Object.defineProperty(prototype, method, { value: () => { calls += 1; throw new Error(SENTINEL); } });
    const plaintext = Buffer.from(RAW);
    const key = Buffer.from(KEY);
    const ciphertext = independentSeal();
    for (const buffer of [plaintext, key, ciphertext]) Object.setPrototypeOf(buffer, prototype);
    expect(Buffer.isBuffer(plaintext)).toBe(true);
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput(plaintext, key)))).toEqual(RAW);
    expect(cryptoBoundary.recoverNativePgtapOutput(recoverInput(ciphertext, key))).toEqual(RAW);
    expect(actualBytes(plaintext)).toEqual(RAW);
    expect(actualBytes(key)).toEqual(KEY);
    expect(calls).toBe(0);
  });

  it('refuses actual over-limit plaintext even when caller sizing claims an empty Buffer', () => {
    const plaintext = Buffer.alloc(NATIVE_DB_VALIDATION.maxProcessBytes + 1);
    const reads = overrideGetter(plaintext, 'length', 0);
    const byteReads = overrideGetter(plaintext, 'byteLength', 0);
    privateRefused(() => cryptoBoundary.protectNativePgtapOutput(protectInput(plaintext)));
    expect(VIEW_LENGTH.call(plaintext)).toBe(NATIVE_DB_VALIDATION.maxProcessBytes + 1);
    expect([reads(), byteReads()]).toEqual([0, 0]);
  });

  it('uses an actual sliced key view despite false backing-buffer and offset properties', () => {
    const backing = Buffer.concat([Buffer.from([0x11]), KEY, Buffer.from([0x22])]);
    const before = Buffer.from(backing);
    const key = backing.subarray(1, backing.length - 1);
    const bufferReads = overrideGetter(key, 'buffer', new ArrayBuffer(0), true);
    const offsetReads = overrideGetter(key, 'byteOffset', 0, true);
    expect(independentOpen(cryptoBoundary.protectNativePgtapOutput(protectInput(Buffer.from(RAW), key)))).toEqual(RAW);
    expect(backing).toEqual(before);
    expect([bufferReads(), offsetReads()]).toEqual([0, 0]);
  });

  it('uses an actual sliced ciphertext view despite false backing-buffer and offset properties', () => {
    const ciphertext = independentSeal();
    const backing = Buffer.concat([Buffer.from([0x33]), ciphertext, Buffer.from([0x44])]);
    const before = Buffer.from(backing);
    const view = backing.subarray(1, backing.length - 1);
    const bufferReads = overrideGetter(view, 'buffer', new ArrayBuffer(0), true);
    const offsetReads = overrideGetter(view, 'byteOffset', 0, true);
    expect(cryptoBoundary.recoverNativePgtapOutput(recoverInput(view))).toEqual(RAW);
    expect(backing).toEqual(before);
    expect([bufferReads(), offsetReads()]).toEqual([0, 0]);
  });
});
