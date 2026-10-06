import { describe, expect, it, vi } from 'vitest';

// Independent DBV-007/008/009 metadata boundary. Only the frozen declaration
// was read; valid operator metadata does not establish physical teardown.
const modulePath = new URL('../../scripts/pgtap/workload-teardown.mjs', import.meta.url).href;
type TeardownModule = { verifyNativeWorkloadTeardown: (expected: unknown, receipt: unknown) => boolean };
const teardown = await import(modulePath) as TeardownModule;
const verify = teardown.verifyNativeWorkloadTeardown;
const canary = 'PRIVATE_OPERATOR_PROOF_427815';
type Expected = {
  runId: string; sourceSha: string; jobId: string; runnerId: number; runnerEnvironment: string;
};
type Receipt = Expected & {
  formatVersion: number; privateProofSha256: string; nativeProcessesStopped: boolean;
  ownedContainersStopped: boolean; runnerDeregistered: boolean; verifiedAt: string;
};

function expected(): Expected {
  return { runId: '3489123-4', sourceSha: 'a1'.repeat(20), jobId: '7738245120', runnerId: 921, runnerEnvironment: 'self-hosted' };
}

function receipt(): Receipt {
  return {
    formatVersion: 1, ...expected(), privateProofSha256: 'f6'.repeat(32),
    nativeProcessesStopped: true, ownedContainersStopped: true, runnerDeregistered: true,
    verifiedAt: '2026-10-07T18:05:02.004Z',
  };
}

function denied(binding: unknown, evidence: unknown) {
  expect(() => verify(binding, evidence)).not.toThrow();
  expect(verify(binding, evidence)).toBe(false);
}

describe('DBV-007/008/009 held trusted workload-teardown receipt validation', () => {
  it('offers only the frozen workload-verification export', () => {
    expect(Object.keys(teardown)).toEqual(['verifyNativeWorkloadTeardown']);
  });

  it.each(['self-hosted', 'github-hosted'])('accepts exact complete trusted metadata for %s', runnerEnvironment => {
    expect(verify({ ...expected(), runnerEnvironment }, { ...receipt(), runnerEnvironment })).toBe(true);
  });

  it('accepts exact null-prototype data records', () => {
    expect(verify(Object.assign(Object.create(null), expected()), Object.assign(Object.create(null), receipt()))).toBe(true);
  });

  it('does not mutate frozen metadata or its descriptors', () => {
    const binding = Object.freeze(expected()); const proof = Object.freeze(receipt());
    const before = JSON.stringify({ binding, proof });
    const bindingDescriptors = Object.getOwnPropertyDescriptors(binding);
    const proofDescriptors = Object.getOwnPropertyDescriptors(proof);
    expect(verify(binding, proof)).toBe(true);
    expect(JSON.stringify({ binding, proof })).toBe(before);
    expect(Object.getOwnPropertyDescriptors(binding)).toEqual(bindingDescriptors);
    expect(Object.getOwnPropertyDescriptors(proof)).toEqual(proofDescriptors);
  });

  it('accepts positive decimal identities beyond Number precision without coercing them', () => {
    const identity = { ...expected(), runId: '90071992547409931234-90071992547409931235', jobId: '90071992547409931236', runnerId: Number.MAX_SAFE_INTEGER };
    expect(verify(identity, { ...receipt(), ...identity })).toBe(true);
  });

  it('validates canonical timestamp syntax without inventing an expiry rule', () => {
    for (const verifiedAt of ['1970-01-01T00:00:00.000Z', '2024-02-29T23:59:59.999Z', '2099-12-31T23:59:59.001Z']) {
      expect(verify(expected(), { ...receipt(), verifiedAt })).toBe(true);
    }
  });

  it('rejects every missing expected or receipt property', () => {
    for (const key of Object.keys(expected())) {
      const binding: Record<string, unknown> = expected(); delete binding[key]; denied(binding, receipt());
    }
    for (const key of Object.keys(receipt())) {
      const proof: Record<string, unknown> = receipt(); delete proof[key]; denied(expected(), proof);
    }
  });

  it('rejects unknown keys even when hidden or symbolic', () => {
    denied({ ...expected(), approved: true }, receipt());
    denied(expected(), { ...receipt(), physicalTeardownProven: true });
    for (const [makeRecord, isBinding] of [[expected, true], [receipt, false]] as const) {
      const hidden = makeRecord(); Object.defineProperty(hidden, canary, { value: true, enumerable: false });
      const symbolic = makeRecord(); Object.defineProperty(symbolic, Symbol(canary), { value: true, enumerable: false });
      const visibleSymbol = { ...makeRecord(), [Symbol(canary)]: true };
      for (const malformed of [hidden, symbolic, visibleSymbol]) {
        if (isBinding) denied(malformed, receipt()); else denied(expected(), malformed);
      }
    }
  });

  it('rejects non-enumerable declared data properties at both levels', () => {
    for (const key of Object.keys(expected())) {
      const binding = expected(); Object.defineProperty(binding, key, { enumerable: false }); denied(binding, receipt());
    }
    for (const key of Object.keys(receipt())) {
      const proof = receipt(); Object.defineProperty(proof, key, { enumerable: false }); denied(expected(), proof);
    }
  });

  it('rejects accessors without evaluating their private getters', () => {
    let getterCalls = 0;
    for (const key of Object.keys(expected())) {
      const binding = expected(); Object.defineProperty(binding, key, { enumerable: true, get() { getterCalls += 1; throw new Error(canary); } });
      denied(binding, receipt());
    }
    for (const key of Object.keys(receipt())) {
      const proof = receipt(); Object.defineProperty(proof, key, { enumerable: true, get() { getterCalls += 1; throw new Error(canary); } });
      denied(expected(), proof);
    }
    expect(getterCalls).toBe(0);
  });

  it('rejects non-ordinary records, arrays and custom prototypes', () => {
    class Lookalike { constructor() { Object.assign(this, receipt()); } }
    denied(expected(), new Lookalike());
    denied(Object.assign(Object.create({ trusted: true }), expected()), receipt());
    denied(expected(), Object.assign(Object.create({ trusted: true }), receipt()));
    for (const invalid of [null, undefined, [], true, 1, 'receipt', new Date(), new Map(), new Set()]) {
      denied(invalid, receipt()); denied(expected(), invalid);
    }
  });

  it('rejects each mismatched real-job identity independently', () => {
    const alternatives = {
      runId: '3489123-5', sourceSha: 'b2'.repeat(20), jobId: '7738245121', runnerId: 922, runnerEnvironment: 'github-hosted',
    };
    for (const [key, value] of Object.entries(alternatives)) {
      denied(expected(), { ...receipt(), [key]: value });
      denied({ ...expected(), [key]: value }, receipt());
    }
  });

  it('requires exactly one positive run/attempt separator without leading zeros or textual coercion', () => {
    for (const runId of ['0-1', '1-0', '01-1', '1-01', '1', '1-2-3', '1--2', '-1-2', '1-+2', '1-2.0', '1e3-2', '1-2\n', '1-2 ', '１-2', 12, null]) {
      denied({ ...expected(), runId }, { ...receipt(), runId });
    }
  });

  it('requires canonical 40-character lowercase source identity in both records', () => {
    for (const sourceSha of ['a'.repeat(39), 'a'.repeat(41), 'A'.repeat(40), 'g'.repeat(40), `${expected().sourceSha}\n`, '', 1, null]) {
      denied({ ...expected(), sourceSha }, { ...receipt(), sourceSha });
    }
  });

  it('requires a positive decimal job string rather than a number or formatted identifier', () => {
    for (const jobId of ['', '0', '01', '-1', '+1', '1.0', '1e3', '1\n', '1 ', '１', 1, null]) {
      denied({ ...expected(), jobId }, { ...receipt(), jobId });
    }
  });

  it('requires a positive safe integer runner id without string coercion', () => {
    for (const runnerId of [0, -1, 1.5, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1, '921', true, null]) {
      denied({ ...expected(), runnerId }, { ...receipt(), runnerId });
    }
  });

  it('requires one of the two exact runner environments', () => {
    for (const runnerEnvironment of ['Self-hosted', 'Github-hosted', 'self-hosted ', 'hosted', 'Windows', '', true, null]) {
      denied({ ...expected(), runnerEnvironment }, { ...receipt(), runnerEnvironment });
    }
  });

  it('requires literal numeric format version one', () => {
    for (const formatVersion of [0, 2, '1', true, null, NaN]) denied(expected(), { ...receipt(), formatVersion });
  });

  it('requires the complete lowercase SHA-256 protected-proof digest', () => {
    for (const privateProofSha256 of ['', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'z'.repeat(64), `${receipt().privateProofSha256}\n`, 1, null]) {
      denied(expected(), { ...receipt(), privateProofSha256 });
    }
  });

  it('requires all three cleanup claims to be literal true simultaneously', () => {
    for (const key of ['nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered']) {
      for (const value of [false, 'true', 1, [], {}, null, undefined]) denied(expected(), { ...receipt(), [key]: value });
    }
  });

  it('rejects noncanonical, impossible or nonfinite UTC timestamps', () => {
    for (const verifiedAt of [
      '2026-10-07T18:05:02Z', '2026-10-07T18:05:02.004+00:00', '2026-10-07t18:05:02.004z',
      '2026-10-07T18:05:02.004Z\n', '2026-02-30T18:05:02.004Z', '2026-13-07T18:05:02.004Z',
      '2026-10-07T18:05:60.004Z', '2026-10-07', '', 'Invalid Date', Infinity, 0, new Date(), null,
    ]) denied(expected(), { ...receipt(), verifiedAt });
  });

  it('returns false safely when ordinary-record reflection traps throw private errors', () => {
    const handlers: ProxyHandler<object>[] = [
      { getPrototypeOf() { throw new Error(canary); } },
      { ownKeys() { throw new Error(canary); } },
      { getOwnPropertyDescriptor() { throw new Error(canary); } },
    ];
    for (const handler of handlers) {
      denied(new Proxy(expected(), handler), receipt());
      denied(expected(), new Proxy(receipt(), handler));
    }
  });

  it('returns false rather than throwing for revoked proxies', () => {
    const binding = Proxy.revocable(expected(), {}); binding.revoke();
    const proof = Proxy.revocable(receipt(), {}); proof.revoke();
    denied(binding.proxy, receipt()); denied(expected(), proof.proxy);
    denied(binding.proxy, proof.proxy);
  });

  it('reflects no private error or diagnostic facts publicly', () => {
    const spies = (['log', 'warn', 'error', 'debug', 'info'] as const).map(name => vi.spyOn(console, name).mockImplementation(() => {}));
    try {
      denied(expected(), { ...receipt(), privateProofSha256: canary });
      denied(new Proxy(expected(), { ownKeys() { throw new Error(canary); } }), receipt());
      expect(verify(expected(), receipt())).toBe(true);
      for (const spy of spies) expect(spy).not.toHaveBeenCalled();
    } finally { for (const spy of spies) spy.mockRestore(); }
  });
});
