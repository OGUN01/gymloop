/**
 * Client command keys for idempotent member commands. These are dedupe keys,
 * never secrets. Resolution stays inside the JavaScript realm: importing
 * `expo-crypto` from a screen would deadlock the native-module bridge in
 * non-native runtimes, so only the WebCrypto `randomUUID` on `globalThis` is
 * used and every supported runtime for these surfaces must provide it.
 */
export function nextCommandKey(): string {
  const globalCrypto = globalThis as { crypto?: { randomUUID?: () => string } };
  if (typeof globalCrypto.crypto?.randomUUID === 'function') return globalCrypto.crypto.randomUUID();
  throw new Error('No command key source is available on this device.');
}
