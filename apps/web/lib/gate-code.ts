import { createHash, randomBytes } from 'node:crypto';
import { GATE_CODE_BYTES } from '@gymloop/shared';

/**
 * The gate code: minted here, hashed here, and stored only as its hash
 * (ATT-003).
 *
 * `qr_sessions` has one column for the code and it is called `token_hash`. There
 * is nowhere to put the code itself, which is the requirement — a reader of the
 * database cannot mint a scan, because what the database holds is not what a
 * scanner presents. That only holds if this module is the only place a code is
 * produced or compared, so both directions live in one file.
 *
 * `node:crypto` rather than Web Crypto: Route Handlers run on the Node.js
 * runtime in Next 16, `createHash` is synchronous where `crypto.subtle.digest`
 * is not, and this module is imported by no client component. It could not live
 * in `packages/shared`, which forbids Node builtins by construction
 * (`.dependency-cruiser.mjs`, `shared-not-to-node-core`).
 *
 * A plain SHA-256 and not a password KDF, deliberately: the input is 64 bits of
 * fresh randomness with a fifteen-minute life, not a human-chosen secret, so
 * there is no dictionary to slow an attacker down through.
 */

/** A fresh gate code — uppercase hex, unguessable, typeable when a camera is not. */
export function newGateCode(): string {
  return randomBytes(GATE_CODE_BYTES).toString('hex').toUpperCase();
}

/**
 * The lookup key for a gate code.
 *
 * Normalised first, so a code typed in lower case, or with the spaces the screen
 * displays it with, still finds its session. Normalising in one function rather
 * than at each call site is what keeps minting and matching in agreement.
 */
export function hashGateCode(code: string): string {
  return createHash('sha256').update(code.replace(/\s+/g, '').toUpperCase()).digest('hex');
}
