import { createCipheriv, createDecipheriv, createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Independent authority regression author: public frozen contracts only.
// No implementation, visible suite, workflow or earlier holdout bodies read.
type Jobs = {
  verifyNativeRunnerJob: (expected: unknown, observed: unknown) => { trusted: boolean; failureCodes: string[] };
  chooseNativeRunnerLabels: (input: unknown) => string[];
};
type Workload = { verifyNativeWorkloadTeardown: (expected: unknown, receipt: unknown) => boolean };
type CryptoBoundary = { protectNativePgtapOutput: (input: unknown) => Buffer; recoverNativePgtapOutput: (input: unknown) => Buffer };
const jobsPath = new URL('../../scripts/pgtap/runner-job.mjs', import.meta.url).href;
const workloadPath = new URL('../../scripts/pgtap/workload-teardown.mjs', import.meta.url).href;
const cryptoPath = new URL('../../scripts/pgtap/private-output.mjs', import.meta.url).href;
const jobs = await import(jobsPath) as Jobs;
const workload = await import(workloadPath) as Workload;
const cryptoBoundary = await import(cryptoPath) as CryptoBoundary;
const sha = 'b7'.repeat(20);
const run = '554312';
const attempt = '3';
const label = `fitcruxx-db-win-x64-${run}-${attempt}-${sha.slice(0, 12)}`;
const manifestSha256 = createHash('sha256').update('independent owned-byte manifest').digest('hex');
const key = Buffer.from(Array.from({ length: 32 }, (_, index) => index + 1));
const iv = Buffer.from(Array.from({ length: 12 }, (_, index) => index + 71));
const magic = Buffer.from('NDBTAP01');
const overhead = 36;
const canary = 'PRIVATE_OWNED_BYTES_657341';
const plaintext = Buffer.concat([Buffer.from(`${canary}\n\u0000β🧪\n`), Buffer.from([0, 255, 128, 17, 254])]);
const typedArrayPrototype = Object.getPrototypeOf(Uint8Array.prototype) as object;
const intrinsicBuffer = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'buffer')!.get!;
const intrinsicOffset = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteOffset')!.get!;
const intrinsicLength = Object.getOwnPropertyDescriptor(typedArrayPrototype, 'byteLength')!.get!;

// Test assertions inspect actual internal bytes without consulting caller
// Buffer methods or caller properties, so poisoned metadata cannot fool QA.
function actualBytes(value: Buffer) {
  return Buffer.from(new Uint8Array(intrinsicBuffer.call(value) as ArrayBuffer, intrinsicOffset.call(value) as number, intrinsicLength.call(value) as number));
}

function binding() { return { sourceSha: sha, runId: run, runAttempt: attempt, label }; }
function observed() {
  return { repository: 'OGUN01/gymloop', eventName: 'push', ref: 'refs/heads/main', sourceSha: sha, runId: run, runAttempt: attempt, workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main', runnerOs: 'Windows', job: 'pgtap' };
}
function selectionJob() {
  const { repository, eventName, ref, sourceSha, runId, runAttempt, workflowRef } = observed();
  return { repository, eventName, ref, sourceSha, runId, runAttempt, workflowRef };
}
function runner() { return { id: 841, status: 'online', busy: false, ephemeral: true, guardVerified: true, label, sourceSha: sha, runId: run, runAttempt: attempt }; }
function workloadBinding() { return { runId: `${run}-${attempt}`, sourceSha: sha, jobId: '79854321', runnerId: 841, runnerEnvironment: 'self-hosted' }; }
function workloadReceipt() { return { formatVersion: 1, ...workloadBinding(), privateProofSha256: 'a9'.repeat(32), nativeProcessesStopped: true, ownedContainersStopped: true, runnerDeregistered: true, verifiedAt: '2026-10-07T18:01:22.003Z' }; }
function protectInput() { return { runId: run, manifestSha256, plaintext: Buffer.from(plaintext), encryptionKey: Buffer.from(key) }; }
function recoverInput() { return { runId: run, manifestSha256, ciphertext: sealed(), encryptionKey: Buffer.from(key) }; }

function sealed() {
  const cipher = createCipheriv('aes-256-gcm', key, iv);
  cipher.setAAD(Buffer.from(JSON.stringify(['NDBTAP01', run, manifestSha256])));
  const ciphertext = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([magic, iv, cipher.getAuthTag(), ciphertext]);
}

function independentlyOpen(value: Buffer) {
  const clean = actualBytes(value);
  const decipher = createDecipheriv('aes-256-gcm', key, clean.subarray(8, 20));
  decipher.setAAD(Buffer.from(JSON.stringify(['NDBTAP01', run, manifestSha256])));
  decipher.setAuthTag(clean.subarray(20, overhead));
  return Buffer.concat([decipher.update(clean.subarray(overhead)), decipher.final()]);
}

function lyingGet<T extends object>(owned: T, alternate: object) {
  const alternateDescriptors = Object.getOwnPropertyDescriptors(alternate);
  return new Proxy(owned, {
    get(target, property, receiver) {
      if (Object.hasOwn(alternateDescriptors, property)) return alternateDescriptors[property as string]!.value;
      return Reflect.get(target, property, receiver);
    },
  });
}

function shadow(buffer: Buffer, name: string, value: unknown) {
  Object.defineProperty(buffer, name, { value, configurable: true, enumerable: true, writable: true });
  return buffer;
}

function refused(operation: (input: unknown) => Buffer, input: unknown) {
  let caught: unknown;
  try { operation(input); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(Error);
  expect(caught).toMatchObject({ name: 'Error', code: 'PRIVATE_OUTPUT_INVALID', message: 'Private native output refused.' });
  expect((caught as Error).cause).toBeUndefined();
  expect(String(caught)).not.toContain(canary);
}

describe('DBV-008/009 owned data descriptors remain the identity authority', () => {
  it('does not let an observed PR descriptor acquire push authority through Proxy.get', () => {
    const owned = { ...observed(), eventName: 'pull_request' };
    expect(jobs.verifyNativeRunnerJob(binding(), lyingGet(owned, observed()))).toEqual({ trusted: false, failureCodes: ['RUNNER_UNTRUSTED'] });
    expect(owned.eventName).toBe('pull_request');
  });

  it('does not let Proxy.get replace the expected captured run identity', () => {
    const owned = { ...binding(), runId: '554313' };
    expect(jobs.verifyNativeRunnerJob(lyingGet(owned, binding()), observed()).trusted).toBe(false);
    expect(owned.runId).toBe('554313');
  });

  it('does not select a runner supplied only by a Proxy.get over an owned null readiness fact', () => {
    const owned = { job: selectionJob(), runner: null };
    expect(jobs.chooseNativeRunnerLabels(lyingGet(owned, { job: selectionJob(), runner: runner() }))).toEqual(['ubuntu-latest']);
  });

  it('does not replace a nested job owned source/event with a trusted property-access view', () => {
    const owned = { ...selectionJob(), eventName: 'pull_request_target', sourceSha: 'c8'.repeat(20) };
    expect(jobs.chooseNativeRunnerLabels({ job: lyingGet(owned, selectionJob()), runner: runner() })).toEqual(['ubuntu-latest']);
  });

  it('does not replace a busy runner data descriptor with a false property-access value', () => {
    const owned = { ...runner(), busy: true };
    expect(jobs.chooseNativeRunnerLabels({ job: selectionJob(), runner: lyingGet(owned, runner()) })).toEqual(['ubuntu-latest']);
  });

  it('does not replace an unverified guard data descriptor with true', () => {
    const owned = { ...runner(), guardVerified: false };
    expect(jobs.chooseNativeRunnerLabels({ job: selectionJob(), runner: lyingGet(owned, runner()) })).toEqual(['ubuntu-latest']);
  });

  it('keeps every false operator cleanup fact false despite a green Proxy.get view', () => {
    for (const fact of ['nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered']) {
      const owned = { ...workloadReceipt(), [fact]: false };
      expect(workload.verifyNativeWorkloadTeardown(workloadBinding(), lyingGet(owned, workloadReceipt()))).toBe(false);
      expect(Object.getOwnPropertyDescriptor(owned, fact)!.value).toBe(false);
    }
  });

  it('does not rebind operator proof to a different owned source through Proxy.get', () => {
    const owned = { ...workloadBinding(), sourceSha: 'd4'.repeat(20) };
    expect(workload.verifyNativeWorkloadTeardown(lyingGet(owned, workloadBinding()), workloadReceipt())).toBe(false);
  });

  it('does not replace an invalid owned proof digest with a valid getter view', () => {
    const owned = { ...workloadReceipt(), privateProofSha256: 'A'.repeat(64) };
    expect(workload.verifyNativeWorkloadTeardown(workloadBinding(), lyingGet(owned, workloadReceipt()))).toBe(false);
  });

  it('does not replace an owned short encryption key through argument Proxy.get', () => {
    const owned = { ...protectInput(), encryptionKey: Buffer.alloc(31) };
    refused(cryptoBoundary.protectNativePgtapOutput, lyingGet(owned, protectInput()));
  });

  it('does not replace an invalid owned private-output run identity through Proxy.get', () => {
    const owned = { ...protectInput(), runId: '0554312' };
    refused(cryptoBoundary.protectNativePgtapOutput, lyingGet(owned, protectInput()));
  });

  it('authenticates descriptor-owned ciphertext even when Proxy.get returns another valid envelope', () => {
    const corrupted = sealed(); corrupted[overhead] = corrupted[overhead]! ^ 1;
    const owned = { ...recoverInput(), ciphertext: corrupted };
    refused(cryptoBoundary.recoverNativePgtapOutput, lyingGet(owned, recoverInput()));
  });
});

describe('DBV-012 actual Buffer bytes remain the crypto and bound authority', () => {
  it('accepts an actual 32-byte key with a caller length property that says 31', () => {
    const encryptionKey = shadow(Buffer.from(key), 'length', 31);
    const ciphertext = cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), encryptionKey });
    expect(independentlyOpen(ciphertext).equals(plaintext)).toBe(true);
    expect(actualBytes(encryptionKey).equals(key)).toBe(true);
  });

  it('refuses an actual short key even when its caller length property says 32', () => {
    const encryptionKey = shadow(Buffer.alloc(31), 'length', 32);
    refused(cryptoBoundary.protectNativePgtapOutput, { ...protectInput(), encryptionKey });
    refused(cryptoBoundary.recoverNativePgtapOutput, { ...recoverInput(), encryptionKey });
  });

  it('encrypts all actual plaintext bytes when a caller length property claims zero', () => {
    const supplied = shadow(Buffer.from(plaintext), 'length', 0);
    const ciphertext = cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), plaintext: supplied });
    expect(actualBytes(ciphertext).length).toBe(plaintext.length + overhead);
    expect(independentlyOpen(ciphertext).equals(plaintext)).toBe(true);
  });

  it('recovers valid actual ciphertext despite false shorter and larger caller lengths', () => {
    for (const fakeLength of [0, 7, NATIVE_DB_VALIDATION.maxProcessBytes + overhead + 1]) {
      const ciphertext = shadow(sealed(), 'length', fakeLength);
      expect(actualBytes(cryptoBoundary.recoverNativePgtapOutput({ ...recoverInput(), ciphertext })).equals(plaintext)).toBe(true);
    }
  });

  it('uses the genuine internal backing buffer and offsets of Buffer subviews', () => {
    const keyBacking = Buffer.concat([Buffer.alloc(13, 0x83), key, Buffer.alloc(17, 0x84)]);
    const keyView = keyBacking.subarray(13, 45);
    const plainBacking = Buffer.concat([Buffer.alloc(9, 0x85), plaintext, Buffer.alloc(11, 0x86)]);
    const plainView = plainBacking.subarray(9, 9 + plaintext.length);
    for (const value of [keyView, plainView]) {
      shadow(value, 'buffer', new ArrayBuffer(1)); shadow(value, 'byteOffset', 0); shadow(value, 'byteLength', 1);
    }
    const ciphertext = cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), plaintext: plainView, encryptionKey: keyView });
    expect(independentlyOpen(ciphertext).equals(plaintext)).toBe(true);
    const valid = sealed();
    const cipherBacking = Buffer.concat([Buffer.alloc(15, 0x87), valid, Buffer.alloc(8, 0x88)]);
    const cipherView = cipherBacking.subarray(15, 15 + valid.length);
    shadow(cipherView, 'buffer', new ArrayBuffer(1)); shadow(cipherView, 'byteOffset', 0); shadow(cipherView, 'byteLength', 1);
    expect(actualBytes(cryptoBoundary.recoverNativePgtapOutput({ ...recoverInput(), ciphertext: cipherView, encryptionKey: keyView })).equals(plaintext)).toBe(true);
    expect(actualBytes(keyView).equals(key)).toBe(true);
    expect(actualBytes(plainView).equals(plaintext)).toBe(true);
  });

  it('refuses corrupt owned body bytes when caller subarray methods offer slices of a valid envelope', () => {
    const valid = sealed(); const corrupted = Buffer.from(valid); corrupted[overhead] = corrupted[overhead]! ^ 1;
    shadow(corrupted, 'subarray', (start?: number, end?: number) => valid.subarray(start, end));
    shadow(corrupted, 'equals', () => true);
    const before = actualBytes(corrupted);
    refused(cryptoBoundary.recoverNativePgtapOutput, { ...recoverInput(), ciphertext: corrupted });
    expect(actualBytes(corrupted).equals(before)).toBe(true);
  });

  it('refuses corrupt owned magic even when caller slices and equality falsely describe the right version', () => {
    const valid = sealed(); const corrupted = Buffer.from(valid); corrupted[0] = corrupted[0]! ^ 1;
    shadow(corrupted, 'subarray', (start?: number, end?: number) => valid.subarray(start, end));
    shadow(corrupted, 'equals', () => true);
    refused(cryptoBoundary.recoverNativePgtapOutput, { ...recoverInput(), ciphertext: corrupted });
  });

  it('does not evaluate caller getters for Buffer metadata, constructor, slices or equality', () => {
    let getterCalls = 0;
    const suppliedPlain = Buffer.from(plaintext); const suppliedKey = Buffer.from(key); const suppliedCipher = sealed();
    for (const value of [suppliedPlain, suppliedKey, suppliedCipher]) {
      for (const name of ['length', 'buffer', 'byteOffset', 'byteLength', 'constructor', 'subarray', 'equals']) {
        Object.defineProperty(value, name, { configurable: true, get() { getterCalls += 1; throw new Error(canary); } });
      }
    }
    expect(independentlyOpen(cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), plaintext: suppliedPlain, encryptionKey: suppliedKey })).equals(plaintext)).toBe(true);
    expect(actualBytes(cryptoBoundary.recoverNativePgtapOutput({ ...recoverInput(), ciphertext: suppliedCipher, encryptionKey: suppliedKey })).equals(plaintext)).toBe(true);
    expect(getterCalls).toBe(0);
  });

  it('preserves authentic Buffers with inherited metadata getters rather than banning caller metadata', () => {
    let getterCalls = 0;
    const suppliedPlain = Buffer.from(plaintext); const suppliedKey = Buffer.from(key); const suppliedCipher = sealed();
    for (const value of [suppliedPlain, suppliedKey, suppliedCipher]) {
      const ownedPrototype = Object.create(Object.getPrototypeOf(value)) as object;
      for (const name of ['length', 'buffer', 'byteOffset', 'byteLength', 'constructor', 'subarray', 'equals']) {
        Object.defineProperty(ownedPrototype, name, { get() { getterCalls += 1; throw new Error(canary); } });
      }
      Object.setPrototypeOf(value, ownedPrototype);
    }
    expect(independentlyOpen(cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), plaintext: suppliedPlain, encryptionKey: suppliedKey })).equals(plaintext)).toBe(true);
    expect(actualBytes(cryptoBoundary.recoverNativePgtapOutput({ ...recoverInput(), ciphertext: suppliedCipher, encryptionKey: suppliedKey })).equals(plaintext)).toBe(true);
    expect(getterCalls).toBe(0);
  });

  it('refuses genuinely oversized plaintext despite a caller zero length', () => {
    const supplied = shadow(Buffer.alloc(NATIVE_DB_VALIDATION.maxProcessBytes + 1, 0x89), 'length', 0);
    refused(cryptoBoundary.protectNativePgtapOutput, { ...protectInput(), plaintext: supplied });
    const raw = actualBytes(supplied);
    expect(raw.length).toBe(NATIVE_DB_VALIDATION.maxProcessBytes + 1);
    expect(raw[0]).toBe(0x89); expect(raw[raw.length - 1]).toBe(0x89);
  });

  it('refuses genuinely oversized ciphertext despite valid caller length and alternate authenticated slices', () => {
    const valid = sealed();
    const supplied = Buffer.alloc(NATIVE_DB_VALIDATION.maxProcessBytes + overhead + 1, 0x8a);
    shadow(supplied, 'length', valid.length);
    shadow(supplied, 'subarray', (start?: number, end?: number) => valid.subarray(start, end));
    shadow(supplied, 'equals', () => true);
    refused(cryptoBoundary.recoverNativePgtapOutput, { ...recoverInput(), ciphertext: supplied });
  });

  it('leaves caller descriptors, prototypes and bytes unchanged when consuming overridden Buffer views', () => {
    const suppliedPlain = shadow(Buffer.from(plaintext), 'length', 0);
    const suppliedKey = shadow(Buffer.from(key), 'length', 31);
    const suppliedCipher = shadow(sealed(), 'length', 1);
    const values = [suppliedPlain, suppliedKey, suppliedCipher];
    const descriptors = values.map(value => Object.getOwnPropertyDescriptors(value));
    const prototypes = values.map(value => Object.getPrototypeOf(value));
    const owned = values.map(actualBytes);
    const protectedOutput = cryptoBoundary.protectNativePgtapOutput({ ...protectInput(), plaintext: suppliedPlain, encryptionKey: suppliedKey });
    const recovered = cryptoBoundary.recoverNativePgtapOutput({ ...recoverInput(), ciphertext: suppliedCipher, encryptionKey: suppliedKey });
    expect(independentlyOpen(protectedOutput).equals(plaintext)).toBe(true);
    expect(actualBytes(recovered).equals(plaintext)).toBe(true);
    for (const [index, value] of values.entries()) {
      expect(Object.getOwnPropertyDescriptors(value)).toEqual(descriptors[index]);
      expect(Object.getPrototypeOf(value)).toBe(prototypes[index]);
      expect(actualBytes(value).equals(owned[index]!)).toBe(true);
    }
  });
});
