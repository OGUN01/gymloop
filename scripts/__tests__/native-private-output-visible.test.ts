import { createCipheriv, createDecipheriv } from 'node:crypto';
import { beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants';

// Independent visible tests from the frozen private native-output custody
// boundary. The decoder/sealer below uses only standard Node AES-GCM, not any
// project crypto implementation, filesystem, environment or network.
type PrivateOutputBoundary = {
  protectNativePgtapOutput: (input: unknown) => Buffer;
  recoverNativePgtapOutput: (input: unknown) => Buffer;
};
type ProtectionInput = { runId: string; manifestSha256: string; plaintext: Buffer; encryptionKey: Buffer };
type RecoveryInput = { runId: string; manifestSha256: string; ciphertext: Buffer; encryptionKey: Buffer };
const MAGIC = Buffer.from('NDBTAP01', 'utf8');
const RUN_ID = '37486763608';
const MANIFEST = 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
const KEY = Buffer.from(Array.from({ length: PHASE8_BACKUP_LIMITS.keyBytes }, (_, index) => index));
const RAW = Buffer.concat([
  Buffer.from('synthetic private raw TAP\r\n1..1\nok 1 - privacy-sentinel\n\0', 'utf8'),
  Buffer.from([0xff, 0x80, 0xfe, 0x00]),
]);
const IV_START = MAGIC.length;
const TAG_START = IV_START + PHASE8_BACKUP_LIMITS.ivBytes;
const BODY_START = TAG_START + PHASE8_BACKUP_LIMITS.tagBytes;
const ENVELOPE_MAX = NATIVE_DB_VALIDATION.maxProcessBytes + BODY_START;
const ERROR_MESSAGE = 'Private native output refused.';
const ERROR_CODE = 'PRIVATE_OUTPUT_INVALID';
let boundary: PrivateOutputBoundary;

beforeAll(async () => {
  // Runtime absence is the expected tests-first red; it is never skipped.
  const modulePath = '../pgtap/private-output.mjs';
  boundary = await import(modulePath) as PrivateOutputBoundary;
});

function additionalData(runId = RUN_ID, manifestSha256 = MANIFEST): Buffer {
  return Buffer.from(JSON.stringify(['NDBTAP01', runId, manifestSha256]), 'utf8');
}

function independentSeal(plaintext = RAW, runId = RUN_ID, manifestSha256 = MANIFEST, key = KEY): Buffer {
  const iv = Buffer.alloc(PHASE8_BACKUP_LIMITS.ivBytes, 0x5a);
  const cipher = createCipheriv('aes-256-gcm', key, iv, { authTagLength: PHASE8_BACKUP_LIMITS.tagBytes });
  cipher.setAAD(additionalData(runId, manifestSha256));
  const encrypted = Buffer.concat([cipher.update(plaintext), cipher.final()]);
  return Buffer.concat([MAGIC, iv, cipher.getAuthTag(), encrypted]);
}

function independentOpen(ciphertext: Buffer, runId = RUN_ID, manifestSha256 = MANIFEST, key = KEY): Buffer {
  const iv = ciphertext.subarray(IV_START, TAG_START);
  const tag = ciphertext.subarray(TAG_START, BODY_START);
  const decipher = createDecipheriv('aes-256-gcm', key, iv, { authTagLength: PHASE8_BACKUP_LIMITS.tagBytes });
  decipher.setAAD(additionalData(runId, manifestSha256));
  decipher.setAuthTag(tag);
  return Buffer.concat([decipher.update(ciphertext.subarray(BODY_START)), decipher.final()]);
}

function protection(): ProtectionInput {
  return { runId: RUN_ID, manifestSha256: MANIFEST, plaintext: Buffer.from(RAW), encryptionKey: Buffer.from(KEY) };
}

function recovery(): RecoveryInput {
  return { runId: RUN_ID, manifestSha256: MANIFEST, ciphertext: independentSeal(), encryptionKey: Buffer.from(KEY) };
}

function refused(action: () => unknown): void {
  let thrown: unknown;
  try {
    action();
  } catch (error) {
    thrown = error;
  }
  expect(thrown).toBeInstanceOf(Error);
  const error = thrown as Error & { code?: unknown; cause?: unknown };
  expect(error.constructor).toBe(Error);
  expect(error.name).toBe('Error');
  expect(error.message).toBe(ERROR_MESSAGE);
  expect(error.code).toBe(ERROR_CODE);
  expect(error.cause).toBeUndefined();
  expect(JSON.stringify(error)).not.toContain('privacy-sentinel');
  expect(JSON.stringify(error)).not.toContain('unsupported state');
}

function bothRefuse(change: Record<string, unknown>): void {
  refused(() => boundary.protectNativePgtapOutput({ ...protection(), ...change }));
  refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ...change }));
}

describe('DBV-012 private raw-output wire format and exact recovery', () => {
  it('publishes exactly the two frozen public entries', () => {
    expect(Object.keys(boundary).sort()).toEqual(['protectNativePgtapOutput', 'recoverNativePgtapOutput'].sort());
    expect(typeof boundary.protectNativePgtapOutput).toBe('function');
    expect(typeof boundary.recoverNativePgtapOutput).toBe('function');
  });

  it.each([
    ['raw binary TAP with CRLF, NUL and invalid UTF-8', RAW],
    ['empty output', Buffer.alloc(0)],
    ['all byte values', Buffer.from(Array.from({ length: 256 }, (_, index) => index))],
  ])('protects and recovers %s byte-for-byte', (_name, plaintext) => {
    const encrypted = boundary.protectNativePgtapOutput({ ...protection(), plaintext });
    expect(Buffer.isBuffer(encrypted)).toBe(true);
    expect(encrypted.length).toBe(BODY_START + plaintext.length);
    expect(encrypted.subarray(0, IV_START)).toEqual(MAGIC);
    const recovered = boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext: encrypted });
    expect(Buffer.isBuffer(recovered)).toBe(true);
    expect(recovered).toEqual(plaintext);
  });

  it.each([RAW, Buffer.alloc(0)])('produces the exact standard AES-256-GCM envelope for independent decoding', plaintext => {
    const ciphertext = boundary.protectNativePgtapOutput({ ...protection(), plaintext });
    expect(ciphertext.subarray(0, MAGIC.length)).toEqual(Buffer.from('NDBTAP01', 'utf8'));
    expect(ciphertext.subarray(IV_START, TAG_START)).toHaveLength(PHASE8_BACKUP_LIMITS.ivBytes);
    expect(ciphertext.subarray(TAG_START, BODY_START)).toHaveLength(PHASE8_BACKUP_LIMITS.tagBytes);
    expect(independentOpen(ciphertext)).toEqual(plaintext);
  });

  it.each([RAW, Buffer.alloc(0)])('recovers an independently sealed standard envelope', plaintext => {
    const ciphertext = independentSeal(plaintext);
    expect(boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext })).toEqual(plaintext);
  });

  it('binds the exact ordered JSON AAD rather than concatenated or object-shaped identities', () => {
    const ciphertext = boundary.protectNativePgtapOutput(protection());
    expect(independentOpen(ciphertext)).toEqual(RAW);
    const wrongData = [
      Buffer.from(JSON.stringify([RUN_ID, MANIFEST, 'NDBTAP01']), 'utf8'),
      Buffer.from(JSON.stringify({ format: 'NDBTAP01', runId: RUN_ID, manifestSha256: MANIFEST }), 'utf8'),
      Buffer.from(`NDBTAP01${RUN_ID}${MANIFEST}`, 'utf8'),
      Buffer.from(`${JSON.stringify(['NDBTAP01', RUN_ID, MANIFEST])}\n`, 'utf8'),
    ];
    for (const aad of wrongData) {
      const decipher = createDecipheriv('aes-256-gcm', KEY, ciphertext.subarray(IV_START, TAG_START), { authTagLength: PHASE8_BACKUP_LIMITS.tagBytes });
      decipher.setAAD(aad);
      decipher.setAuthTag(ciphertext.subarray(TAG_START, BODY_START));
      decipher.update(ciphertext.subarray(BODY_START));
      expect(() => decipher.final()).toThrow();
    }
  });

  it('uses a fresh twelve-byte nonce for every repeated protection', () => {
    const envelopes = Array.from({ length: 8 }, () => boundary.protectNativePgtapOutput(protection()));
    expect(new Set(envelopes.map(value => value.subarray(IV_START, TAG_START).toString('hex'))).size).toBe(envelopes.length);
    expect(new Set(envelopes.map(value => value.toString('hex'))).size).toBe(envelopes.length);
    for (const ciphertext of envelopes) expect(independentOpen(ciphertext)).toEqual(RAW);
  });

  it('accepts exact decimal strings beyond Number safe-integer range without coercion', () => {
    const runId = '90071992547409931234567890';
    const ciphertext = boundary.protectNativePgtapOutput({ ...protection(), runId });
    expect(independentOpen(ciphertext, runId)).toEqual(RAW);
    expect(boundary.recoverNativePgtapOutput({ ...recovery(), runId, ciphertext })).toEqual(RAW);
  });

  it('accepts the full lowercase hexadecimal manifest vocabulary', () => {
    const manifestSha256 = '0123456789abcdef'.repeat(4);
    const ciphertext = boundary.protectNativePgtapOutput({ ...protection(), manifestSha256 });
    expect(independentOpen(ciphertext, RUN_ID, manifestSha256)).toEqual(RAW);
    expect(boundary.recoverNativePgtapOutput({ ...recovery(), manifestSha256, ciphertext })).toEqual(RAW);
  });

  it('accepts exactly the central plaintext limit and fixed envelope overhead', () => {
    const plaintext = Buffer.alloc(NATIVE_DB_VALIDATION.maxProcessBytes, 0xa5);
    const ciphertext = boundary.protectNativePgtapOutput({ ...protection(), plaintext });
    expect(ciphertext.length).toBe(ENVELOPE_MAX);
    const recovered = boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext });
    expect(recovered.length).toBe(NATIVE_DB_VALIDATION.maxProcessBytes);
    expect(recovered.equals(plaintext)).toBe(true);
    expect(plaintext.every(value => value === 0xa5)).toBe(true);
  });
});

describe('DBV-012 immutable buffer custody and ordinary argument objects', () => {
  it('never changes caller plaintext, key or argument object during protection', () => {
    const input = protection();
    const plaintextBefore = Buffer.from(input.plaintext);
    const keyBefore = Buffer.from(input.encryptionKey);
    const descriptorsBefore = Object.getOwnPropertyDescriptors(input);
    Object.freeze(input);
    const ciphertext = boundary.protectNativePgtapOutput(input);
    expect(input.plaintext).toEqual(plaintextBefore);
    expect(input.encryptionKey).toEqual(keyBefore);
    expect(Object.getOwnPropertyDescriptors(input)).toEqual(Object.fromEntries(Object.entries(descriptorsBefore).map(([name, descriptor]) => [name, { ...descriptor, writable: false, configurable: false }])));
    expect(ciphertext).not.toBe(input.plaintext);
  });

  it('never changes caller ciphertext, key or argument object during recovery', () => {
    const input = recovery();
    const ciphertextBefore = Buffer.from(input.ciphertext);
    const keyBefore = Buffer.from(input.encryptionKey);
    Object.freeze(input);
    const plaintext = boundary.recoverNativePgtapOutput(input);
    expect(plaintext).toEqual(RAW);
    expect(input.ciphertext).toEqual(ciphertextBefore);
    expect(input.encryptionKey).toEqual(keyBefore);
    expect(plaintext).not.toBe(input.ciphertext);
  });

  it('accepts exact own data properties on a null-prototype object', () => {
    const protectInput = Object.assign(Object.create(null), protection()) as ProtectionInput;
    const ciphertext = boundary.protectNativePgtapOutput(protectInput);
    const recoverInput = Object.assign(Object.create(null), recovery(), { ciphertext }) as RecoveryInput;
    expect(boundary.recoverNativePgtapOutput(recoverInput)).toEqual(RAW);
    expect(Object.getPrototypeOf(protectInput)).toBeNull();
    expect(Object.getPrototypeOf(recoverInput)).toBeNull();
  });

  it('accepts subarray Buffers while preserving their surrounding backing bytes', () => {
    const plaintextBacking = Buffer.concat([Buffer.from([0x11]), RAW, Buffer.from([0x22])]);
    const keyBacking = Buffer.concat([Buffer.from([0x33]), KEY, Buffer.from([0x44])]);
    const plaintextBefore = Buffer.from(plaintextBacking);
    const keyBefore = Buffer.from(keyBacking);
    const plaintext = plaintextBacking.subarray(1, plaintextBacking.length - 1);
    const encryptionKey = keyBacking.subarray(1, keyBacking.length - 1);
    const ciphertext = boundary.protectNativePgtapOutput({ ...protection(), plaintext, encryptionKey });
    const ciphertextBacking = Buffer.concat([Buffer.from([0x55]), ciphertext, Buffer.from([0x66])]);
    const ciphertextBefore = Buffer.from(ciphertextBacking);
    expect(boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext: ciphertextBacking.subarray(1, ciphertextBacking.length - 1), encryptionKey })).toEqual(RAW);
    expect(plaintextBacking).toEqual(plaintextBefore);
    expect(keyBacking).toEqual(keyBefore);
    expect(ciphertextBacking).toEqual(ciphertextBefore);
  });

  it.each([null, undefined, [], true, 1, 'privacy-sentinel', new Date(0), new Map()])('refuses nonordinary input %j without diagnostics', input => {
    refused(() => boundary.protectNativePgtapOutput(input));
    refused(() => boundary.recoverNativePgtapOutput(input));
  });

  it('refuses a function carrying otherwise valid own fields', () => {
    const input = Object.assign(() => undefined, protection());
    refused(() => boundary.protectNativePgtapOutput(input));
    refused(() => boundary.recoverNativePgtapOutput(Object.assign(() => undefined, recovery())));
  });

  it('refuses an array carrying otherwise valid own fields', () => {
    refused(() => boundary.protectNativePgtapOutput(Object.assign([], protection())));
    refused(() => boundary.recoverNativePgtapOutput(Object.assign([], recovery())));
  });

  it('refuses custom prototypes and inherited required data properties', () => {
    const customProtect = Object.assign(Object.create({ trusted: true }), protection());
    const customRecover = Object.assign(Object.create({ trusted: true }), recovery());
    refused(() => boundary.protectNativePgtapOutput(customProtect));
    refused(() => boundary.recoverNativePgtapOutput(customRecover));
    refused(() => boundary.protectNativePgtapOutput(Object.create(protection())));
    refused(() => boundary.recoverNativePgtapOutput(Object.create(recovery())));
  });

  it.each(['runId', 'manifestSha256', 'encryptionKey'])('refuses missing shared own field %s', field => {
    const protectInput: Record<string, unknown> = { ...protection() };
    const recoverInput: Record<string, unknown> = { ...recovery() };
    delete protectInput[field];
    delete recoverInput[field];
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(recoverInput));
  });

  it('refuses missing plaintext and ciphertext fields', () => {
    const protectInput = { runId: RUN_ID, manifestSha256: MANIFEST, encryptionKey: KEY };
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(protectInput));
  });

  it.each(['unknown enumerable', 'unknown nonenumerable', 'enumerable symbol', 'nonenumerable symbol'])('refuses an %s property', variation => {
    const protectInput = protection();
    const recoverInput = recovery();
    const name = variation.includes('symbol') ? Symbol('privacy-sentinel') : 'privacy-sentinel';
    for (const input of [protectInput, recoverInput]) Object.defineProperty(input, name, { value: 'privacy-sentinel', enumerable: !variation.includes('nonenumerable') });
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(recoverInput));
  });

  it.each(['runId', 'manifestSha256', 'encryptionKey', 'payload'])('refuses a nonenumerable required %s property', field => {
    const protectInput = protection();
    const recoverInput = recovery();
    Object.defineProperty(protectInput, field === 'payload' ? 'plaintext' : field, { enumerable: false });
    Object.defineProperty(recoverInput, field === 'payload' ? 'ciphertext' : field, { enumerable: false });
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(recoverInput));
  });

  it.each(['runId', 'manifestSha256', 'encryptionKey', 'payload', 'unknown'])('refuses %s accessors without invoking getter or setter', field => {
    let observed = 0;
    const protectInput = protection();
    const recoverInput = recovery();
    for (const [input, payloadName] of [[protectInput, 'plaintext'], [recoverInput, 'ciphertext']] as const) {
      Object.defineProperty(input, field === 'payload' ? payloadName : field, {
        enumerable: true,
        get() { observed += 1; throw new Error('privacy-sentinel getter'); },
        set() { observed += 1; throw new Error('privacy-sentinel setter'); },
      });
    }
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(recoverInput));
    expect(observed).toBe(0);
  });

  it('does not change malformed caller inputs while refusing them', () => {
    const protectInput = { ...protection(), runId: '01' };
    const recoverInput = { ...recovery(), runId: '01' };
    const plaintextBefore = Buffer.from(protectInput.plaintext);
    const ciphertextBefore = Buffer.from(recoverInput.ciphertext);
    const keyBefore = Buffer.from(KEY);
    refused(() => boundary.protectNativePgtapOutput(protectInput));
    refused(() => boundary.recoverNativePgtapOutput(recoverInput));
    expect(protectInput.plaintext).toEqual(plaintextBefore);
    expect(recoverInput.ciphertext).toEqual(ciphertextBefore);
    expect(protectInput.encryptionKey).toEqual(keyBefore);
    expect(recoverInput.encryptionKey).toEqual(keyBefore);
  });
});

describe('DBV-012 strict IDs, hashes, Buffers and central bounds', () => {
  it.each([
    '', '0', '00', '01', '-1', '+1', '1.0', '1e3', ' 1', '1 ', '1\n', '1\r\n', '1\0',
    'privacy-sentinel', 1, null, undefined, true,
  ])('refuses invalid run ID %j without coercion', runId => {
    bothRefuse({ runId });
  });

  it.each([
    '', 'a'.repeat(63), 'a'.repeat(65), 'A'.repeat(64), 'g'.repeat(64), `${'a'.repeat(63)}\n`,
    `${MANIFEST}\n`, ` ${MANIFEST}`, 1, null, undefined, Buffer.from(MANIFEST, 'utf8'),
  ])('refuses invalid manifest SHA %j without normalization', manifestSha256 => {
    bothRefuse({ manifestSha256 });
  });

  it.each([
    Buffer.alloc(0), Buffer.alloc(PHASE8_BACKUP_LIMITS.keyBytes - 1), Buffer.alloc(PHASE8_BACKUP_LIMITS.keyBytes + 1),
    KEY.toString('hex'), new Uint8Array(KEY), new ArrayBuffer(PHASE8_BACKUP_LIMITS.keyBytes),
    Array.from(KEY), { type: 'Buffer', data: Array.from(KEY) }, null, undefined, true,
  ])('refuses invalid encryption key type or byte length %j', encryptionKey => {
    bothRefuse({ encryptionKey });
  });

  it.each(['privacy-sentinel', new Uint8Array(RAW), Array.from(RAW), new ArrayBuffer(0), { type: 'Buffer', data: Array.from(RAW) }, null, undefined])('refuses non-Buffer plaintext %j', plaintext => {
    refused(() => boundary.protectNativePgtapOutput({ ...protection(), plaintext }));
  });

  it.each(['privacy-sentinel', new Uint8Array(RAW), Array.from(RAW), new ArrayBuffer(0), { type: 'Buffer', data: Array.from(RAW) }, null, undefined])('refuses non-Buffer ciphertext %j', ciphertext => {
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
  });

  it('refuses plaintext exactly one byte above the central limit', () => {
    const plaintext = Buffer.alloc(NATIVE_DB_VALIDATION.maxProcessBytes + 1);
    refused(() => boundary.protectNativePgtapOutput({ ...protection(), plaintext }));
    expect(plaintext.every(value => value === 0)).toBe(true);
  });

  it('refuses ciphertext exactly one byte above maximum plaintext plus envelope overhead', () => {
    const ciphertext = Buffer.alloc(ENVELOPE_MAX + 1);
    MAGIC.copy(ciphertext);
    const before = Buffer.from(ciphertext.subarray(0, BODY_START));
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
    expect(ciphertext.subarray(0, BODY_START)).toEqual(before);
  });
});

describe('DBV-012 authenticated binding, corruption and safe failure', () => {
  it.each([
    ['different run', { runId: '37486763609' }],
    ['different manifest', { manifestSha256: 'b'.repeat(64) }],
    ['different same-width key', { encryptionKey: Buffer.alloc(PHASE8_BACKUP_LIMITS.keyBytes, 0xa7) }],
  ])('refuses recovery under a %s binding', (_name, change) => {
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ...change }));
  });

  it.each([
    ['magic first byte', 0],
    ['magic last byte', IV_START - 1],
    ['nonce first byte', IV_START],
    ['nonce last byte', TAG_START - 1],
    ['tag first byte', TAG_START],
    ['tag last byte', BODY_START - 1],
    ['ciphertext first byte', BODY_START],
    ['ciphertext last byte', BODY_START + RAW.length - 1],
  ])('refuses tampered %s without changing the corrupt caller Buffer', (_name, offset) => {
    const ciphertext = independentSeal();
    ciphertext[offset] = (ciphertext[offset] ?? 0) ^ 1;
    const before = Buffer.from(ciphertext);
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
    expect(ciphertext).toEqual(before);
  });

  it.each([0, 1, IV_START - 1, IV_START, TAG_START - 1, TAG_START, BODY_START - 1, BODY_START, BODY_START + RAW.length - 1])('refuses truncated envelope at %s bytes', length => {
    const ciphertext = independentSeal().subarray(0, length);
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
  });

  it('refuses appended bytes rather than accepting an authenticated prefix', () => {
    const ciphertext = Buffer.concat([independentSeal(), Buffer.from([0])]);
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
  });

  it('refuses plaintext fallback and an unknown or legacy wire magic', () => {
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext: RAW }));
    const ciphertext = independentSeal();
    Buffer.from('NDBTAP00', 'utf8').copy(ciphertext);
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
  });

  it('refuses an empty payload envelope with a modified authentication tag', () => {
    const ciphertext = independentSeal(Buffer.alloc(0));
    ciphertext[TAG_START] = (ciphertext[TAG_START] ?? 0) ^ 1;
    refused(() => boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }));
  });

  it('does not return partially decrypted bytes on authentication failure', () => {
    const ciphertext = independentSeal();
    ciphertext[TAG_START] = (ciphertext[TAG_START] ?? 0) ^ 1;
    let returned: unknown = undefined;
    refused(() => { returned = boundary.recoverNativePgtapOutput({ ...recovery(), ciphertext }); });
    expect(returned).toBeUndefined();
  });
});
