import { createCipheriv, createDecipheriv, createHash, createSecretKey } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Independent DBV-012 custody contract: no implementation, workflow, visible
// tests, native harness or other source was consulted. Reference envelopes here
// are constructed independently from the frozen wire/AAD declaration.
const modulePath = new URL('../../scripts/pgtap/private-output.mjs', import.meta.url).href;
type PrivateOutputModule = {
  protectNativePgtapOutput: (input: unknown) => Buffer;
  recoverNativePgtapOutput: (input: unknown) => Buffer;
};
const custody = await import(modulePath) as PrivateOutputModule;
const protect = custody.protectNativePgtapOutput;
const recover = custody.recoverNativePgtapOutput;
const widths = { magic: 8, iv: 12, tag: 16, key: 32 };
const magic = Buffer.from('NDBTAP01', 'utf8');
const overhead = widths.magic + widths.iv + widths.tag;
const bound = NATIVE_DB_VALIDATION.maxProcessBytes;
const runId = '918273645';
const manifestSha256 = createHash('sha256').update('independent held manifest identity').digest('hex');
const encryptionKey = Buffer.from(Array.from({ length: widths.key }, (_, index) => index));
const referenceIv = Buffer.from(Array.from({ length: widths.iv }, (_, index) => index + 31));
const canary = 'PRIVATE_HELD_NATIVE_FIXTURE_137924';
const binaryPlaintext = Buffer.concat([
  Buffer.from(`1..1\nok 1 - ${canary} βeta 🧪\n\u0000`, 'utf8'),
  Buffer.from(Array.from({ length: 256 }, (_, index) => index)),
]);

function aad(bindingRun = runId, bindingManifest = manifestSha256) {
  return Buffer.from(JSON.stringify(['NDBTAP01', bindingRun, bindingManifest]), 'utf8');
}

function referenceEnvelope(plaintext = binaryPlaintext, associatedData = aad()) {
  const cipher = createCipheriv('aes-256-gcm', encryptionKey, referenceIv, { authTagLength: widths.tag });
  cipher.setAAD(associatedData);
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([magic, referenceIv, cipher.getAuthTag(), encrypted]);
}

function referenceOpen(ciphertext: Buffer, bindingRun = runId, bindingManifest = manifestSha256) {
  const ivEnd = widths.magic + widths.iv;
  const tagEnd = ivEnd + widths.tag;
  const decipher = createDecipheriv('aes-256-gcm', encryptionKey, ciphertext.subarray(widths.magic, ivEnd), { authTagLength: widths.tag });
  decipher.setAAD(aad(bindingRun, bindingManifest));
  decipher.setAuthTag(ciphertext.subarray(ivEnd, tagEnd));
  return Buffer.concat([decipher.update(ciphertext.subarray(tagEnd)), decipher.final()]);
}

function protectionInput() {
  return { runId, manifestSha256, plaintext: Buffer.from(binaryPlaintext), encryptionKey: Buffer.from(encryptionKey) };
}

function recoveryInput() {
  return { runId, manifestSha256, ciphertext: referenceEnvelope(), encryptionKey: Buffer.from(encryptionKey) };
}

function refusal(operation: (input: unknown) => Buffer, input: unknown) {
  let caught: unknown;
  try { operation(input); } catch (error) { caught = error; }
  expect(caught).toBeInstanceOf(Error);
  expect(caught).toMatchObject({ name: 'Error', code: 'PRIVATE_OUTPUT_INVALID', message: 'Private native output refused.' });
  const error = caught as Error;
  expect(error.toString()).toBe('Error: Private native output refused.');
  expect(error.cause).toBeUndefined();
  for (const representation of [error.message, error.stack ?? '', JSON.stringify(error)]) {
    expect(representation).not.toContain(canary);
    expect(representation).not.toContain(encryptionKey.toString('hex'));
    expect(representation).not.toContain('Unsupported state or unable to authenticate data');
    expect(representation).not.toContain('Invalid authentication tag length');
  }
}

describe('DBV-012 held independent encrypted native-output wire contract', () => {
  it('exports exactly the two frozen pure custody entries', () => {
    expect(Object.keys(custody).sort()).toEqual(['protectNativePgtapOutput', 'recoverNativePgtapOutput']);
  });

  it('creates the exact uncompressed AES-256-GCM layout independently decryptable with the frozen AAD', () => {
    const input = protectionInput();
    const ciphertext = protect(input);
    expect(Buffer.isBuffer(ciphertext)).toBe(true);
    expect(ciphertext.length).toBe(input.plaintext.length + overhead);
    expect(ciphertext.subarray(0, widths.magic).equals(magic)).toBe(true);
    expect(referenceOpen(ciphertext).equals(input.plaintext)).toBe(true);
    expect(ciphertext.includes(Buffer.from(canary, 'utf8'))).toBe(false);
    expect(ciphertext.includes(input.plaintext)).toBe(false);
  });

  it('recovers a separately constructed authenticated envelope byte-for-byte, including invalid UTF-8 and NUL', () => {
    const input = recoveryInput();
    const plaintext = recover(input);
    expect(Buffer.isBuffer(plaintext)).toBe(true);
    expect(plaintext.equals(binaryPlaintext)).toBe(true);
  });

  it('accepts empty plaintext and authenticates the minimum fixed-width envelope', () => {
    const input = { ...protectionInput(), plaintext: Buffer.alloc(0) };
    const ciphertext = protect(input);
    expect(ciphertext.length).toBe(overhead);
    expect(referenceOpen(ciphertext).length).toBe(0);
    expect(recover({ ...recoveryInput(), ciphertext }).length).toBe(0);
    expect(recover({ ...recoveryInput(), ciphertext: referenceEnvelope(Buffer.alloc(0)) }).length).toBe(0);
  });

  it('supports large positive decimal run identities without numeric conversion or truncation', () => {
    const bindingRun = '900719925474099312345678901234567890';
    const input = { ...protectionInput(), runId: bindingRun };
    const ciphertext = protect(input);
    expect(referenceOpen(ciphertext, bindingRun).equals(input.plaintext)).toBe(true);
    expect(recover({ ...recoveryInput(), runId: bindingRun, ciphertext }).equals(input.plaintext)).toBe(true);
  });

  it('generates a fresh 12-byte nonce for every repeated protection call', () => {
    const ivs = new Set<string>();
    const envelopes = new Set<string>();
    for (let iteration = 0; iteration < 40; iteration += 1) {
      const ciphertext = protect(protectionInput());
      ivs.add(ciphertext.subarray(widths.magic, widths.magic + widths.iv).toString('hex'));
      envelopes.add(ciphertext.toString('hex'));
      expect(referenceOpen(ciphertext).equals(binaryPlaintext)).toBe(true);
    }
    expect(ivs.size).toBe(40);
    expect(envelopes.size).toBe(40);
  });

  it('accepts the central maximum exactly and preserves the fixed envelope overhead', () => {
    const plaintext = Buffer.alloc(bound, 0xa6);
    const ciphertext = protect({ runId, manifestSha256, plaintext, encryptionKey });
    expect(ciphertext.length).toBe(bound + overhead);
    const recovered = recover({ runId, manifestSha256, ciphertext, encryptionKey });
    expect(recovered.length).toBe(bound);
    expect(recovered.equals(plaintext)).toBe(true);
    expect(plaintext[0]).toBe(0xa6);
    expect(plaintext[bound - 1]).toBe(0xa6);
  });

  it('rejects plaintext and ciphertext one byte beyond their respective central maxima', () => {
    refusal(protect, { ...protectionInput(), plaintext: Buffer.alloc(bound + 1) });
    refusal(recover, { ...recoveryInput(), ciphertext: Buffer.alloc(bound + overhead + 1) });
  });
});

describe('DBV-012 held authentication and source binding', () => {
  it('rejects a bit change at every envelope position, including magic, nonce, tag and body', () => {
    const ciphertext = referenceEnvelope();
    for (let offset = 0; offset < ciphertext.length; offset += 1) {
      const altered = Buffer.from(ciphertext);
      altered[offset] = altered[offset]! ^ 1;
      refusal(recover, { ...recoveryInput(), ciphertext: altered });
    }
  });

  it.each([0, 1, 7, 8, 19, 20, 35, 36])('rejects a truncated %i-byte envelope', length => {
    refusal(recover, { ...recoveryInput(), ciphertext: referenceEnvelope().subarray(0, length) });
  });

  it('rejects authenticated-body truncation, trailing bytes and a tag from another envelope', () => {
    const ciphertext = referenceEnvelope();
    refusal(recover, { ...recoveryInput(), ciphertext: ciphertext.subarray(0, ciphertext.length - 1) });
    refusal(recover, { ...recoveryInput(), ciphertext: Buffer.concat([ciphertext, Buffer.from([0])]) });
    const different = referenceEnvelope(Buffer.from('different private native fixture'));
    const swappedTag = Buffer.from(ciphertext);
    different.copy(swappedTag, widths.magic + widths.iv, widths.magic + widths.iv, overhead);
    refusal(recover, { ...recoveryInput(), ciphertext: swappedTag });
  });

  it('rejects an empty-payload envelope with a changed authentication tag', () => {
    const ciphertext = referenceEnvelope(Buffer.alloc(0));
    ciphertext[overhead - 1] = ciphertext[overhead - 1]! ^ 0x80;
    refusal(recover, { ...recoveryInput(), ciphertext });
  });

  it('binds both exact run identity and manifest independently of the readable envelope header', () => {
    refusal(recover, { ...recoveryInput(), runId: '918273646' });
    refusal(recover, { ...recoveryInput(), manifestSha256: createHash('sha256').update('other manifest').digest('hex') });
    const otherKey = Buffer.from(encryptionKey); otherKey[0] = otherKey[0]! ^ 1;
    refusal(recover, { ...recoveryInput(), encryptionKey: otherKey });
  });

  it.each([
    Buffer.alloc(0),
    Buffer.from(JSON.stringify([runId, manifestSha256, 'NDBTAP01'])),
    Buffer.from(JSON.stringify(['NDBTAP01', manifestSha256, runId])),
    Buffer.from(JSON.stringify(['NDBTAP01', runId, manifestSha256], null, 2)),
    Buffer.from(JSON.stringify({ magic: 'NDBTAP01', runId, manifestSha256 })),
    Buffer.from(`NDBTAP01:${runId}:${manifestSha256}`),
  ].map(associatedData => ({ associatedData })))('refuses alternate AAD serialization $associatedData', ({ associatedData }) => {
    refusal(recover, { ...recoveryInput(), ciphertext: referenceEnvelope(binaryPlaintext, associatedData) });
  });

  it('refuses plaintext, legacy magic and unauthenticated header-only formats', () => {
    refusal(recover, { ...recoveryInput(), ciphertext: Buffer.from(binaryPlaintext) });
    const legacy = referenceEnvelope(); Buffer.from('NDBTAP00').copy(legacy);
    refusal(recover, { ...recoveryInput(), ciphertext: legacy });
    refusal(recover, { ...recoveryInput(), ciphertext: Buffer.concat([magic, Buffer.alloc(widths.iv + widths.tag), binaryPlaintext]) });
  });
});

describe('DBV-012 held strict input descriptors and generic refusal', () => {
  it.each([null, undefined, true, 1, 'input', [], new Date(), new Map(), new Set(), Buffer.alloc(4)])('rejects a non-ordinary top-level argument %s', input => {
    refusal(protect, input); refusal(recover, input);
  });

  it('accepts exact null-prototype and frozen data-property objects', () => {
    const input = Object.freeze(Object.assign(Object.create(null), protectionInput()));
    const ciphertext = protect(input);
    const recovery = Object.freeze(Object.assign(Object.create(null), recoveryInput(), { ciphertext }));
    expect(recover(recovery).equals(binaryPlaintext)).toBe(true);
    expect(referenceOpen(protect(Object.freeze(protectionInput()))).equals(binaryPlaintext)).toBe(true);
  });

  it('rejects custom prototypes and instances even if all four fields look valid', () => {
    class Lookalike { constructor() { Object.assign(this, protectionInput()); } }
    refusal(protect, new Lookalike());
    refusal(protect, Object.assign(Object.create({ approved: true }), protectionInput()));
    refusal(recover, Object.assign(Object.create({ approved: true }), recoveryInput()));
  });

  it.each(['runId', 'manifestSha256', 'encryptionKey'])('rejects missing, hidden and accessor authority property %s', name => {
    for (const [operation, makeInput] of [[protect, protectionInput], [recover, recoveryInput]] as const) {
      const missing: Record<string, unknown> = makeInput(); delete missing[name];
      refusal(operation, missing);
      const hidden = makeInput(); Object.defineProperty(hidden, name, { enumerable: false });
      refusal(operation, hidden);
      let getterCalls = 0;
      const accessor = makeInput();
      Object.defineProperty(accessor, name, { enumerable: true, get() { getterCalls += 1; throw new Error(canary); } });
      refusal(operation, accessor);
      expect(getterCalls).toBe(0);
    }
  });

  it('rejects missing/hidden/accessor payload properties without evaluating a getter', () => {
    for (const [operation, makeInput, name] of [[protect, protectionInput, 'plaintext'], [recover, recoveryInput, 'ciphertext']] as const) {
      const missing: Record<string, unknown> = makeInput(); delete missing[name];
      refusal(operation, missing);
      const hidden = makeInput(); Object.defineProperty(hidden, name, { enumerable: false });
      refusal(operation, hidden);
      let getterCalls = 0;
      const accessor = makeInput(); Object.defineProperty(accessor, name, { enumerable: true, get() { getterCalls += 1; return binaryPlaintext; } });
      refusal(operation, accessor);
      expect(getterCalls).toBe(0);
    }
  });

  it('rejects unknown enumerable/non-enumerable properties and every symbol key', () => {
    for (const [operation, makeInput] of [[protect, protectionInput], [recover, recoveryInput]] as const) {
      refusal(operation, { ...makeInput(), approved: true });
      const hidden = makeInput(); Object.defineProperty(hidden, canary, { value: true, enumerable: false });
      refusal(operation, hidden);
      const symbolic = makeInput(); Object.defineProperty(symbolic, Symbol(canary), { value: true, enumerable: false });
      refusal(operation, symbolic);
      refusal(operation, { ...makeInput(), [Symbol(canary)]: true });
    }
    refusal(protect, { ...protectionInput(), ciphertext: referenceEnvelope() });
    refusal(recover, { ...recoveryInput(), plaintext: binaryPlaintext });
  });

  it.each(['', '0', '00', '01', '-1', '+1', '1.0', '1e2', ' 1', '1 ', '1\n', '1\r\n', '1\u0000', '１', '١', 1, 0, null, undefined, true, [], {}, new String('1')])('does not coerce invalid run identity %s', value => {
    refusal(protect, { ...protectionInput(), runId: value });
    refusal(recover, { ...recoveryInput(), runId: value });
  });

  it.each(['', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'g'.repeat(64), `${manifestSha256}\n`, `${manifestSha256} `, 0, null, undefined, [], {}, new String(manifestSha256)])('refuses non-canonical manifest digest %s', value => {
    refusal(protect, { ...protectionInput(), manifestSha256: value });
    refusal(recover, { ...recoveryInput(), manifestSha256: value });
  });

  it.each([0, 1, 16, 31, 33, 48])('refuses a Buffer key with %i bytes', keyLength => {
    const key = Buffer.alloc(keyLength);
    refusal(protect, { ...protectionInput(), encryptionKey: key });
    refusal(recover, { ...recoveryInput(), encryptionKey: key });
  });

  it.each([null, undefined, '', canary, [], {}, new Uint8Array(widths.key), new ArrayBuffer(widths.key), createSecretKey(encryptionKey)])('requires a raw Buffer key without coercion %s', value => {
    refusal(protect, { ...protectionInput(), encryptionKey: value });
    refusal(recover, { ...recoveryInput(), encryptionKey: value });
  });

  it.each([null, undefined, '', canary, [], {}, new Uint8Array(4), new ArrayBuffer(4), new DataView(new ArrayBuffer(4))])('requires Buffer payload bytes without textual fallback %s', value => {
    refusal(protect, { ...protectionInput(), plaintext: value });
    refusal(recover, { ...recoveryInput(), ciphertext: value });
  });

  it('never writes public diagnostic text on success, authentication failure or malformed input', () => {
    const sinks = ['log', 'warn', 'error', 'debug', 'info'] as const;
    const spies = sinks.map(name => vi.spyOn(console, name).mockImplementation(() => {}));
    try {
      const ciphertext = protect(protectionInput());
      recover({ ...recoveryInput(), ciphertext });
      refusal(protect, { ...protectionInput(), plaintext: canary });
      refusal(recover, { ...recoveryInput(), runId: '2' });
      for (const spy of spies) expect(spy).not.toHaveBeenCalled();
    } finally { for (const spy of spies) spy.mockRestore(); }
  });
});

describe('DBV-012 held caller ownership and immutability', () => {
  it('preserves exact object properties and byte buffers through protection', () => {
    const input = protectionInput();
    const descriptorBefore = Object.getOwnPropertyDescriptors(input);
    const plaintextBefore = Buffer.from(input.plaintext);
    const keyBefore = Buffer.from(input.encryptionKey);
    const ciphertext = protect(input);
    expect(Object.getOwnPropertyDescriptors(input)).toEqual(descriptorBefore);
    expect(input.plaintext.equals(plaintextBefore)).toBe(true);
    expect(input.encryptionKey.equals(keyBefore)).toBe(true);
    ciphertext.fill(0);
    expect(input.plaintext.equals(plaintextBefore)).toBe(true);
    expect(input.encryptionKey.equals(keyBefore)).toBe(true);
  });

  it('preserves encrypted input and key through recovery and does not return an alias into them', () => {
    const input = recoveryInput();
    const descriptorBefore = Object.getOwnPropertyDescriptors(input);
    const encryptedBefore = Buffer.from(input.ciphertext);
    const keyBefore = Buffer.from(input.encryptionKey);
    const plaintext = recover(input);
    expect(Object.getOwnPropertyDescriptors(input)).toEqual(descriptorBefore);
    expect(input.ciphertext.equals(encryptedBefore)).toBe(true);
    expect(input.encryptionKey.equals(keyBefore)).toBe(true);
    plaintext.fill(0);
    expect(input.ciphertext.equals(encryptedBefore)).toBe(true);
    expect(input.encryptionKey.equals(keyBefore)).toBe(true);
  });

  it('preserves all caller bytes when authentication fails or validation rejects an argument', () => {
    const input = recoveryInput(); input.ciphertext[overhead] = input.ciphertext[overhead]! ^ 1;
    const encryptedBefore = Buffer.from(input.ciphertext);
    const keyBefore = Buffer.from(input.encryptionKey);
    refusal(recover, input);
    expect(input.ciphertext.equals(encryptedBefore)).toBe(true);
    expect(input.encryptionKey.equals(keyBefore)).toBe(true);
    const invalid = { ...protectionInput(), runId: '01' };
    const plaintextBefore = Buffer.from(invalid.plaintext);
    const invalidKeyBefore = Buffer.from(invalid.encryptionKey);
    refusal(protect, invalid);
    expect(invalid.plaintext.equals(plaintextBefore)).toBe(true);
    expect(invalid.encryptionKey.equals(invalidKeyBefore)).toBe(true);
  });
});
