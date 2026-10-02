import { createHash } from 'node:crypto';
import { INVITE_TOKEN_PATTERN, MEMBER_INVITE_LIMITS } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';

/**
 * INV token minting and hashing (`openspec/changes/member-invites/proposal.md`,
 * "Web", `lib/member-invite-token.ts`).
 *
 * The database never sees a raw token (INV-001): the route hashes before every
 * RPC, so this module is the only place a token is produced or turned into the
 * lookup key. Both directions are pinned here, with the expected hash computed
 * independently of the implementation under test.
 *
 * `node:crypto` is wrapped, not replaced: every real function still runs, and
 * `randomBytes` records what it was asked for and what it handed back.
 */
const minted = vi.hoisted(() => ({ sizes: [] as number[], outputs: [] as Buffer[] }));

vi.mock('node:crypto', async (importOriginal) => {
  const actual = await importOriginal<typeof import('node:crypto')>();
  const randomBytes = vi.fn((size: number) => {
    const bytes = actual.randomBytes(size);
    minted.sizes.push(size);
    minted.outputs.push(bytes);
    return bytes;
  });
  const wrapped = { ...actual, randomBytes };
  return { ...wrapped, default: wrapped };
});

import { generateInviteToken, hashInviteToken } from '../member-invite-token';

const sha256Hex = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex');

/** Characters a canonical unpadded base64url encoding of 32 bytes may end in (4 data bits). */
const LAST_CHARACTERS = '048AEIMQUYcgkosw';

beforeEach(() => {
  minted.sizes.length = 0;
  minted.outputs.length = 0;
});

describe('generateInviteToken', () => {
  it('returns 43 characters that satisfy the shared token pattern', () => {
    const token = generateInviteToken();
    expect(typeof token).toBe('string');
    expect(token).toHaveLength(43);
    expect(INVITE_TOKEN_PATTERN.test(token)).toBe(true);
  });

  it('is the canonical unpadded base64url of exactly 32 bytes', () => {
    for (let i = 0; i < 50; i += 1) {
      const token = generateInviteToken();
      const bytes = Buffer.from(token, 'base64url');
      expect(bytes).toHaveLength(MEMBER_INVITE_LIMITS.tokenBytes);
      expect(bytes.toString('base64url')).toBe(token);
      expect(token).not.toContain('=');
      expect(LAST_CHARACTERS).toContain(token.slice(-1));
    }
  });

  it('draws its entropy from node:crypto randomBytes(32), once per token, and encodes exactly those bytes', () => {
    const token = generateInviteToken();
    expect(minted.sizes).toEqual([32]);
    expect(minted.outputs).toHaveLength(1);
    expect(token).toBe(minted.outputs[0]?.toString('base64url'));
  });

  it('is unique across many calls', () => {
    const count = 2000;
    const tokens = new Set<string>();
    for (let i = 0; i < count; i += 1) tokens.add(generateInviteToken());
    expect(tokens.size).toBe(count);
  });

  it('is not predictable from time or position: consecutive tokens share no long prefix', () => {
    const first = generateInviteToken();
    const second = generateInviteToken();
    expect(first).not.toBe(second);
    // 32 random bytes: a shared 12-character (72-bit) prefix is not a chance event.
    expect(first.slice(0, 12)).not.toBe(second.slice(0, 12));
  });

  it('uses the whole alphabet, evenly enough to rule out a biased or truncated generator', () => {
    const counts = new Map<string, number>();
    const tokens = 1500;
    for (let i = 0; i < tokens; i += 1) {
      // The final character carries only four bits, so it is excluded from the uniformity check.
      for (const character of generateInviteToken().slice(0, -1)) {
        counts.set(character, (counts.get(character) ?? 0) + 1);
      }
    }
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
    expect(counts.size).toBe(alphabet.length);
    // 1500 tokens x 42 characters / 64 symbols = 984 expected each; +/- 25% is more than 8 sigma.
    for (const character of alphabet) {
      const seen = counts.get(character) ?? 0;
      expect(seen).toBeGreaterThan(740);
      expect(seen).toBeLessThan(1230);
    }
  });
});

describe('hashInviteToken', () => {
  it.each([
    ['43 A characters', 'A'.repeat(43), '0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a'],
    ['a mixed-case token with hyphen and underscore', 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM-_01', 'c975ea5a5f2b0397a18ef135b415af2f964cfa4d4f4f6db562b2c6d461e801c4'],
    ['a base64url-looking token', 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA', '1167b97ee339209bdc6eb36b37f56796c1d9385173fb47e157b2361fee677630'],
  ])('matches the known SHA-256 hex digest for %s', (_label, token, digest) => {
    expect(hashInviteToken(token)).toBe(digest);
    expect(sha256Hex(token)).toBe(digest);
  });

  it('is 64 lowercase hexadecimal characters', () => {
    const hash = hashInviteToken(generateInviteToken());
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
    expect(hash).toBe(hash.toLowerCase());
  });

  it('is deterministic', () => {
    const token = generateInviteToken();
    expect(hashInviteToken(token)).toBe(hashInviteToken(token));
  });

  it('agrees with an independent SHA-256 of the token text for freshly minted tokens', () => {
    for (let i = 0; i < 25; i += 1) {
      const token = generateInviteToken();
      expect(hashInviteToken(token)).toBe(sha256Hex(token));
    }
  });

  it('differs for different tokens, including ones that differ by one character or only by case', () => {
    const token = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
    const oneCharacter = `${token.slice(0, 42)}B`;
    const otherCase = token.toLowerCase();
    const hashes = new Set([hashInviteToken(token), hashInviteToken(oneCharacter), hashInviteToken(otherCase)]);
    expect(hashes.size).toBe(3);
  });

  it('hashes the token text itself, not its decoded bytes and not a link around it', () => {
    const token = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
    const decodedHash = createHash('sha256').update(Buffer.from(token, 'base64url')).digest('hex');
    const linkHash = sha256Hex(`https://app.example/invite/${token}`);
    expect(hashInviteToken(token)).not.toBe(decodedHash);
    expect(hashInviteToken(token)).not.toBe(linkHash);
  });

  it('hashes UTF-8 text, so a non-ASCII input is encoded as UTF-8 bytes', () => {
    expect(hashInviteToken('é')).toBe('4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c');
  });

  it('never returns the token or contains any recognisable part of it', () => {
    const token = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
    const hash = hashInviteToken(token);
    expect(hash).not.toBe(token);
    expect(hash).not.toContain(token);
    // The token starts with upper-case characters; a lower-case hex digest cannot hold them.
    expect(hash).not.toContain(token.slice(0, 10));
  });
});
