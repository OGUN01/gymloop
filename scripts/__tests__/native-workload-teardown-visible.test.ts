import { beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Independent tests of operator-receipt validity only. These synthetic receipts
// do not prove physical process/container/runner teardown and launch no actors.
type Boundary = { verifyNativeWorkloadTeardown: (expected: unknown, receipt: unknown) => boolean };
const SOURCE = 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
const PROOF = 'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
const SENTINEL = 'synthetic-private-teardown-trap';
let boundary: Boundary;

beforeAll(async () => {
  const modulePath = '../pgtap/workload-teardown.mjs';
  boundary = await import(modulePath) as Boundary;
  if (typeof boundary.verifyNativeWorkloadTeardown !== 'function') throw new Error('Frozen export absent: verifyNativeWorkloadTeardown');
});

function expected() {
  return { runId: '37486763608-1', sourceSha: SOURCE, jobId: '123456789', runnerId: 42, runnerEnvironment: 'self-hosted' };
}

function receipt() {
  return {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    ...expected(),
    privateProofSha256: PROOF,
    nativeProcessesStopped: true,
    ownedContainersStopped: true,
    runnerDeregistered: true,
    verifiedAt: '2026-10-07T09:00:00.000Z',
  };
}

function rejected(binding: unknown, proof: unknown): void {
  expect(boundary.verifyNativeWorkloadTeardown(binding, proof)).toBe(false);
}

function matchingInvalidIdentity(field: string, value: unknown): void {
  rejected({ ...expected(), [field]: value }, { ...receipt(), [field]: value });
}

function hostile(target: object, kind: string): object {
  if (kind === 'revoked') {
    const { proxy, revoke } = Proxy.revocable(target, {});
    revoke();
    return proxy;
  }
  if (kind === 'prototype') return new Proxy(target, { getPrototypeOf() { throw new Error(SENTINEL); } });
  if (kind === 'ownKeys') return new Proxy(target, { ownKeys() { throw new Error(SENTINEL); } });
  return new Proxy(target, { getOwnPropertyDescriptor() { throw new Error(SENTINEL); } });
}

describe('DBV-007/008/009 trusted workload teardown receipt boundary', () => {
  it('accepts an exact self-hosted identity and all three completed state facts', () => {
    expect(boundary.verifyNativeWorkloadTeardown(expected(), receipt())).toBe(true);
  });

  it('accepts an exact github-hosted identity only with the same complete receipt', () => {
    const binding = { ...expected(), runnerEnvironment: 'github-hosted' };
    expect(boundary.verifyNativeWorkloadTeardown(binding, { ...receipt(), runnerEnvironment: 'github-hosted' })).toBe(true);
    rejected(binding, null);
    rejected(binding, { ...receipt(), runnerEnvironment: 'github-hosted', ownedContainersStopped: false });
  });

  it('accepts exact own enumerable data fields on null-prototype objects', () => {
    const binding = Object.assign(Object.create(null), expected());
    const proof = Object.assign(Object.create(null), receipt());
    expect(boundary.verifyNativeWorkloadTeardown(binding, proof)).toBe(true);
    expect(Object.getPrototypeOf(binding)).toBeNull();
    expect(Object.getPrototypeOf(proof)).toBeNull();
  });

  it('rejects a mismatch in any of the five independently bound identities', () => {
    const mismatches = { runId: '37486763608-2', sourceSha: 'c'.repeat(40), jobId: '123456790', runnerId: 43, runnerEnvironment: 'github-hosted' };
    for (const [field, value] of Object.entries(mismatches)) rejected(expected(), { ...receipt(), [field]: value });
  });

  it('rejects a wrong or coerced receipt format version', () => {
    for (const formatVersion of [0, 2, '1', null, undefined, true]) rejected(expected(), { ...receipt(), formatVersion });
  });

  it('requires two positive decimal run/attempt strings joined by exactly one hyphen', () => {
    for (const runId of ['', '1', '0-1', '1-0', '01-1', '1-01', '1-1-1', '+1-1', '1.0-1', '1e3-1', '1-1 ', '1-1\n', 1, null]) matchingInvalidIdentity('runId', runId);
  });

  it('requires exact lowercase hexadecimal source identity without coercion', () => {
    for (const sourceSha of ['', 'a'.repeat(39), 'a'.repeat(41), 'A'.repeat(40), 'g'.repeat(40), `${SOURCE}\n`, 1, null, Buffer.from(SOURCE)]) matchingInvalidIdentity('sourceSha', sourceSha);
  });

  it('requires a positive decimal string job ID without leading zero or normalization', () => {
    for (const jobId of ['', '0', '01', '-1', '+1', '1.0', '1e3', '1 ', '1\n', 1, null, undefined]) matchingInvalidIdentity('jobId', jobId);
  });

  it('requires a positive safe integer runner ID', () => {
    for (const runnerId of [0, -1, 1.5, Number.MAX_SAFE_INTEGER + 1, Number.NaN, Number.POSITIVE_INFINITY, '42', null, undefined]) matchingInvalidIdentity('runnerId', runnerId);
  });

  it('requires the exact self-hosted or github-hosted environment vocabulary', () => {
    for (const runnerEnvironment of ['', 'self_hosted', 'github_hosted', 'Self-hosted', 'self-hosted ', 'unknown', true, null]) matchingInvalidIdentity('runnerEnvironment', runnerEnvironment);
  });

  it('requires the exact lowercase private proof digest width', () => {
    for (const privateProofSha256 of ['', 'b'.repeat(63), 'b'.repeat(65), 'B'.repeat(64), 'g'.repeat(64), `${PROOF}\n`, 1, null, Buffer.from(PROOF)]) rejected(expected(), { ...receipt(), privateProofSha256 });
  });

  it('requires all three state fields to be the strict boolean true', () => {
    for (const field of ['nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered']) {
      for (const value of [false, 'true', 1, null, undefined]) rejected(expected(), { ...receipt(), [field]: value });
    }
  });

  it('requires a finite canonical UTC ISO verified timestamp', () => {
    const invalid = [
      '', 'tomorrow', '2026-10-07', '2026-10-07T09:00:00Z', '2026-10-07T09:00:00.0Z',
      '2026-10-07T09:00:00.0000Z', '2026-10-07T09:00:00.000+00:00',
      '2026-10-07T09:00:00.000z', '2026-02-30T09:00:00.000Z',
      '2026-13-07T09:00:00.000Z', '2026-10-07T09:00:00.000Z\n',
      0, Number.NaN, null, new Date('2026-10-07T09:00:00.000Z'),
    ];
    for (const verifiedAt of invalid) rejected(expected(), { ...receipt(), verifiedAt });
    expect(boundary.verifyNativeWorkloadTeardown(expected(), { ...receipt(), verifiedAt: '1970-01-01T00:00:00.000Z' })).toBe(true);
  });

  it('rejects missing, unknown, nonenumerable and symbolic fields on either exact shape', () => {
    for (const key of Object.keys(expected())) {
      const binding: Record<string, unknown> = { ...expected() };
      delete binding[key];
      rejected(binding, receipt());
    }
    for (const key of Object.keys(receipt())) {
      const proof: Record<string, unknown> = { ...receipt() };
      delete proof[key];
      rejected(expected(), proof);
    }
    for (const variation of ['unknown', 'nonenumerable', 'symbol']) {
      const binding = expected();
      const proof = receipt();
      if (variation === 'unknown') {
        Object.defineProperty(binding, 'extra', { value: SENTINEL, enumerable: true });
        Object.defineProperty(proof, 'extra', { value: SENTINEL, enumerable: true });
      } else if (variation === 'nonenumerable') {
        Object.defineProperty(binding, 'runId', { enumerable: false });
        Object.defineProperty(proof, 'formatVersion', { enumerable: false });
      } else {
        Object.defineProperty(binding, Symbol(SENTINEL), { value: true });
        Object.defineProperty(proof, Symbol(SENTINEL), { value: true });
      }
      rejected(binding, receipt());
      rejected(expected(), proof);
    }
  });

  it('rejects benign and throwing accessors without evaluating any field getter', () => {
    let reads = 0;
    for (const throwing of [false, true]) {
      for (const key of Object.keys(expected())) {
        const binding = expected();
        Object.defineProperty(binding, key, { enumerable: true, get() { reads += 1; if (throwing) throw new Error(SENTINEL); return Reflect.get(expected(), key); } });
        rejected(binding, receipt());
      }
      for (const key of Object.keys(receipt())) {
        const proof = receipt();
        Object.defineProperty(proof, key, { enumerable: true, get() { reads += 1; if (throwing) throw new Error(SENTINEL); return Reflect.get(receipt(), key); } });
        rejected(expected(), proof);
      }
    }
    expect(reads).toBe(0);
  });

  it('returns false without propagating revoked or throwing reflection proxy errors', () => {
    for (const kind of ['revoked', 'prototype', 'ownKeys', 'descriptor']) {
      rejected(hostile(expected(), kind), receipt());
      rejected(expected(), hostile(receipt(), kind));
    }
  });

  it('does not mutate frozen identity or receipt data', () => {
    const binding = Object.freeze(expected());
    const proof = Object.freeze(receipt());
    const beforeBinding = JSON.stringify(binding);
    const beforeProof = JSON.stringify(proof);
    expect(boundary.verifyNativeWorkloadTeardown(binding, proof)).toBe(true);
    expect(JSON.stringify(binding)).toBe(beforeBinding);
    expect(JSON.stringify(proof)).toBe(beforeProof);
  });

  it('returns only false for primitives, arrays, custom prototypes and inherited data', () => {
    for (const malformed of [null, undefined, true, 1, SENTINEL, [], new Date(0), new Map()]) {
      rejected(malformed, receipt());
      rejected(expected(), malformed);
    }
    rejected(Object.assign([], expected()), receipt());
    rejected(expected(), Object.assign([], receipt()));
    rejected(Object.assign(Object.create({ trusted: true }), expected()), receipt());
    rejected(expected(), Object.assign(Object.create({ trusted: true }), receipt()));
    rejected(Object.create(expected()), receipt());
    rejected(expected(), Object.create(receipt()));
  });

  it('keeps large decimal run and job identities as exact strings without safe-number coercion', () => {
    const binding = { ...expected(), runId: '900719925474099312-99', jobId: '900719925474099311' };
    expect(boundary.verifyNativeWorkloadTeardown(binding, { ...receipt(), ...binding })).toBe(true);
    rejected(binding, { ...receipt(), ...binding, jobId: '900719925474099312' });
  });
});
