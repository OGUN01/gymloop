import { createHash, randomBytes } from 'node:crypto';
import { MEMBER_INVITE_LIMITS } from '@gymloop/shared';

/**
 * The only place an invite token is produced or turned into its lookup key
 * (INV-001).
 *
 * The database never sees a raw token: a route generates one, hands Postgres its
 * SHA-256, and puts the token only in the link it returns to the person who
 * asked for it. The same rule as the check-in poster code, and for the same
 * reason - a leaked table or backup then holds nothing that opens a door.
 */

/** 32 bytes of `node:crypto` randomness as 43 unpadded base64url characters. */
export function generateInviteToken(): string {
  return randomBytes(MEMBER_INVITE_LIMITS.tokenBytes).toString('base64url');
}

/**
 * The lowercase-hex SHA-256 of the token's UTF-8 text - the text, not its
 * decoded bytes and not a link around it, because that is what every redeemer
 * has in hand and what the database column (`member_invites.token_hash`) holds.
 */
export function hashInviteToken(token: string): string {
  return createHash('sha256').update(token, 'utf8').digest('hex');
}
