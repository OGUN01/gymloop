import { Buffer } from 'node:buffer';
import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants.ts';

function privateOutputRefusal() {
  return Object.assign(new Error('Private native output refused.'), { code: 'PRIVATE_OUTPUT_INVALID' });
}
function privateOutputView(value, maximum, minimum = 0) {
  if (!Buffer.isBuffer(value)) throw privateOutputRefusal();
  const prototype = Object.getPrototypeOf(Uint8Array.prototype);
  const buffer = Object.getOwnPropertyDescriptor(prototype, 'buffer').get.call(value);
  const offset = Object.getOwnPropertyDescriptor(prototype, 'byteOffset').get.call(value);
  const length = Object.getOwnPropertyDescriptor(prototype, 'byteLength').get.call(value);
  if (length < minimum || length > maximum) throw privateOutputRefusal();
  return Buffer.from(new Uint8Array(buffer, offset, length));
}
function privateOutputArguments(input, payloadName) {
  if (input === null || typeof input !== 'object' || Array.isArray(input)) throw privateOutputRefusal();
  const prototype = Object.getPrototypeOf(input);
  if (prototype !== Object.prototype && prototype !== null) throw privateOutputRefusal();
  const keys = ['runId', 'manifestSha256', payloadName, 'encryptionKey'];
  const descriptors = Object.getOwnPropertyDescriptors(input);
  const ownKeys = Reflect.ownKeys(descriptors);
  if (ownKeys.length !== keys.length || !ownKeys.every(key => {
    const descriptor = descriptors[key];
    return keys.includes(key) && descriptor.enumerable && Object.hasOwn(descriptor, 'value');
  })) throw privateOutputRefusal();
  input = Object.fromEntries(keys.map(key => [key, descriptors[key].value]));
  const magic = Buffer.from(NATIVE_DB_VALIDATION.encryptedOutputMagic, 'utf8');
  const overhead = magic.length + PHASE8_BACKUP_LIMITS.ivBytes + PHASE8_BACKUP_LIMITS.tagBytes;
  const encryptionKey = privateOutputView(input.encryptionKey, PHASE8_BACKUP_LIMITS.keyBytes, PHASE8_BACKUP_LIMITS.keyBytes);
  const payload = privateOutputView(input[payloadName], NATIVE_DB_VALIDATION.maxProcessBytes + (payloadName === 'plaintext' ? 0 : overhead),
    payloadName === 'plaintext' ? 0 : overhead);
  if (typeof input.runId !== 'string' || !/^[1-9][0-9]*$/.test(input.runId)
    || typeof input.manifestSha256 !== 'string'
    || !new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(input.manifestSha256)
    || encryptionKey.length !== PHASE8_BACKUP_LIMITS.keyBytes) throw privateOutputRefusal();
  return { magic, overhead, input: { ...input, encryptionKey, [payloadName]: payload } };
}
function privateOutputAad(input) {
  return Buffer.from(JSON.stringify([NATIVE_DB_VALIDATION.encryptedOutputMagic, input.runId, input.manifestSha256]), 'utf8');
}

/** Encrypt opaque native bytes; only an authenticated run/manifest may recover them. */
export function protectNativePgtapOutput(input) {
  try {
    const argumentsSnapshot = privateOutputArguments(input, 'plaintext');
    const { magic } = argumentsSnapshot;
    input = argumentsSnapshot.input;
    const nonce = randomBytes(PHASE8_BACKUP_LIMITS.ivBytes);
    const cipher = createCipheriv('aes-256-gcm', input.encryptionKey, nonce);
    cipher.setAAD(privateOutputAad(input));
    const encrypted = Buffer.concat([cipher.update(input.plaintext), cipher.final()]);
    return Buffer.concat([magic, nonce, cipher.getAuthTag(), encrypted]);
  } catch { throw privateOutputRefusal(); }
}

/** Refuse altered identity, bytes, keys or format without returning partial plaintext. */
export function recoverNativePgtapOutput(input) {
  try {
    const argumentsSnapshot = privateOutputArguments(input, 'ciphertext');
    const { magic, overhead } = argumentsSnapshot;
    input = argumentsSnapshot.input;
    const ciphertext = input.ciphertext;
    if (!ciphertext.subarray(0, magic.length).equals(magic)) throw privateOutputRefusal();
    const nonceEnd = magic.length + PHASE8_BACKUP_LIMITS.ivBytes;
    const decipher = createDecipheriv('aes-256-gcm', input.encryptionKey, ciphertext.subarray(magic.length, nonceEnd));
    decipher.setAAD(privateOutputAad(input));
    decipher.setAuthTag(ciphertext.subarray(nonceEnd, overhead));
    return Buffer.concat([decipher.update(ciphertext.subarray(overhead)), decipher.final()]);
  } catch { throw privateOutputRefusal(); }
}
