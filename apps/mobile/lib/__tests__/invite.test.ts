import { beforeEach, describe, expect, it, vi } from 'vitest';
import { buildInviteLink, parseInviteToken } from '@gymloop/shared';

/**
 * INV-022 (mobile, pure logic): `apps/mobile/lib/invite.ts`.
 *
 * The truth table is written from the contract sentence "null/invalid token ->
 * invalid_link; no session -> save_and_sign_in; session + unlinked -> redeem;
 * any other session -> already_linked", with a reference function below so the
 * whole cross product is checked, not a hand-picked sample. The five refusal
 * sentences are pinned literally from the proposal (not imported from shared).
 */

const store = vi.hoisted(() => ({
  values: new Map<string, string>(),
  sets: [] as Array<[string, string]>,
  deletes: [] as string[],
}));
vi.mock('expo-secure-store', () => ({
  getItemAsync: vi.fn(async (key: string) => store.values.get(key) ?? null),
  setItemAsync: vi.fn(async (key: string, value: string) => { store.sets.push([key, value]); store.values.set(key, value); }),
  deleteItemAsync: vi.fn(async (key: string) => { store.deletes.push(key); store.values.delete(key); }),
}));

type Kind = 'unlinked' | 'member' | 'staff' | 'platform' | 'impersonation' | 'none';
type Action = 'invalid_link' | 'save_and_sign_in' | 'redeem' | 'already_linked';
type InviteModule = {
  PENDING_INVITE_KEY: string;
  resolveInviteEntry(input: { token: string | null; sessionPresent: boolean; identityKind: Kind }): { action: Action };
  inviteOutcomeMessage(code: string): string;
  savePendingInvite(token: string): Promise<void>;
  takePendingInvite(): Promise<string | null>;
};
const invite = async () => await import('../invite') as unknown as InviteModule;

const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';
const token = (seed: number): string =>
  Array.from({ length: 43 }, (_, index) => ALPHABET[(index * 7 + seed * 13) % ALPHABET.length]).join('');
const TOKEN = token(1);
const OTHER_TOKEN = token(2);
const VALID_TOKEN = /^[A-Za-z0-9_-]{43}$/;

const COPY = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch: "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked: "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const;

beforeEach(() => {
  store.values = new Map();
  store.sets = [];
  store.deletes = [];
});

describe('INV-022 pending invite storage key', () => {
  it('is gymloop.pending-invite', async () => {
    expect((await invite()).PENDING_INVITE_KEY).toBe('gymloop.pending-invite');
  });
});

describe('INV-022 resolveInviteEntry', () => {
  const reference = (tokenInput: string | null, sessionPresent: boolean, kind: Kind): Action => {
    if (tokenInput === null || !VALID_TOKEN.test(tokenInput)) return 'invalid_link';
    if (!sessionPresent) return 'save_and_sign_in';
    return kind === 'unlinked' ? 'redeem' : 'already_linked';
  };
  const kinds: Kind[] = ['unlinked', 'member', 'staff', 'platform', 'impersonation', 'none'];
  const tokens: Array<[string, string | null]> = [
    ['null', null],
    ['empty', ''],
    ['whitespace', '   '],
    ['one character short', TOKEN.slice(0, 42)],
    ['one character long', `${TOKEN}A`],
    ['standard-base64 plus', `${TOKEN.slice(0, 42)}+`],
    ['padding', `${TOKEN.slice(0, 42)}=`],
    ['leading space', ` ${TOKEN.slice(1)}`],
    ['trailing newline', `${TOKEN.slice(0, 42)}\n`],
    ['non-ASCII', `${TOKEN.slice(0, 42)}é`],
    ['a full invite URL (parse first, then resolve)', `https://app.fitcruxx.example/invite/${TOKEN}`],
    ['a valid token', TOKEN],
    ['another valid token', OTHER_TOKEN],
  ];

  it.each(tokens)('%s: the whole session x identity table matches the contract', async (_label, tokenInput) => {
    const { resolveInviteEntry } = await invite();
    for (const sessionPresent of [false, true]) {
      for (const identityKind of kinds) {
        // A live session whose identity is "none" is not a case the contract names; it is checked separately below.
        if (sessionPresent && identityKind === 'none' && tokenInput !== null && VALID_TOKEN.test(tokenInput)) continue;
        expect(
          resolveInviteEntry({ token: tokenInput, sessionPresent, identityKind }),
          `token=${String(tokenInput)} session=${String(sessionPresent)} identity=${identityKind}`,
        ).toEqual({ action: reference(tokenInput, sessionPresent, identityKind) });
      }
    }
  });

  it('a null or malformed token is invalid_link even with a perfectly good unlinked session', async () => {
    const { resolveInviteEntry } = await invite();
    expect(resolveInviteEntry({ token: null, sessionPresent: true, identityKind: 'unlinked' })).toEqual({ action: 'invalid_link' });
    expect(resolveInviteEntry({ token: 'nope', sessionPresent: true, identityKind: 'unlinked' })).toEqual({ action: 'invalid_link' });
  });

  it('no session saves the invite and sends the person to sign in, whatever identity was cached', async () => {
    const { resolveInviteEntry } = await invite();
    expect(resolveInviteEntry({ token: TOKEN, sessionPresent: false, identityKind: 'none' })).toEqual({ action: 'save_and_sign_in' });
    expect(resolveInviteEntry({ token: TOKEN, sessionPresent: false, identityKind: 'member' })).toEqual({ action: 'save_and_sign_in' });
  });

  it('a signed-in unlinked account redeems; every linked kind is already_linked (D1: never a second binding)', async () => {
    const { resolveInviteEntry } = await invite();
    expect(resolveInviteEntry({ token: TOKEN, sessionPresent: true, identityKind: 'unlinked' })).toEqual({ action: 'redeem' });
    for (const identityKind of ['member', 'staff', 'platform', 'impersonation'] as const) {
      expect(resolveInviteEntry({ token: TOKEN, sessionPresent: true, identityKind })).toEqual({ action: 'already_linked' });
    }
  });

  it('is pure: the same input gives the same answer and touches no storage', async () => {
    const { resolveInviteEntry } = await invite();
    const input = { token: TOKEN, sessionPresent: false, identityKind: 'none' as const };
    expect(resolveInviteEntry(input)).toEqual(resolveInviteEntry(input));
    expect(store.sets).toEqual([]);
    expect(store.deletes).toEqual([]);
  });
});

describe('INV-022/INV-023 inviteOutcomeMessage', () => {
  it.each(Object.entries(COPY))('%s maps to exactly its contract sentence', async (code, sentence) => {
    expect((await invite()).inviteOutcomeMessage(code)).toBe(sentence);
  });

  it.each([
    'unknown',
    '',
    'linked',
    'already_linked_here',
    'Email_Mismatch',
    ' email_mismatch',
    'constructor',
    '__proto__',
    'toString',
    'hasOwnProperty',
    '42501',
  ])('%j (not a refusal outcome) falls back to the invite_unavailable sentence', async (code) => {
    expect((await invite()).inviteOutcomeMessage(code)).toBe(COPY.invite_unavailable);
  });

  it('never states a cause the server did not name: no outcome mentions a number, a gym or an address', async () => {
    const { inviteOutcomeMessage } = await invite();
    for (const code of [...Object.keys(COPY), 'unknown']) {
      expect(inviteOutcomeMessage(code)).not.toMatch(/\d|@|does not exist|no account|not found/i);
    }
  });
});

describe('INV-022 the pending invite survives sign-in in SecureStore', () => {
  it('save then take returns the token once and leaves nothing behind', async () => {
    const { savePendingInvite, takePendingInvite, PENDING_INVITE_KEY } = await invite();
    await savePendingInvite(TOKEN);
    expect(store.sets).toHaveLength(1);
    expect(store.sets[0]?.[0]).toBe(PENDING_INVITE_KEY);
    expect(store.sets[0]?.[1]).toContain(TOKEN);
    expect(await takePendingInvite()).toBe(TOKEN);
    expect(store.values.has(PENDING_INVITE_KEY), 'take clears the entry').toBe(false);
    expect(await takePendingInvite()).toBeNull();
  });

  it('keeps only the latest link: a second save replaces the first', async () => {
    const { savePendingInvite, takePendingInvite } = await invite();
    await savePendingInvite(TOKEN);
    await savePendingInvite(OTHER_TOKEN);
    expect(await takePendingInvite()).toBe(OTHER_TOKEN);
    expect(await takePendingInvite()).toBeNull();
  });

  it('write only the one key, and nothing else', async () => {
    const { savePendingInvite, takePendingInvite, PENDING_INVITE_KEY } = await invite();
    await savePendingInvite(TOKEN);
    await takePendingInvite();
    for (const [key] of store.sets) expect(key).toBe(PENDING_INVITE_KEY);
    for (const key of store.deletes) expect(key).toBe(PENDING_INVITE_KEY);
  });

  it('take with nothing stored is null', async () => {
    expect(await (await invite()).takePendingInvite()).toBeNull();
  });

  it.each([
    ['text', 'junk'],
    ['empty', ''],
    ['a token one character too long', `${TOKEN}A`],
    ['a token with a disallowed character', `${TOKEN.slice(0, 42)}+`],
    ['json without a token', '{"token":"short"}'],
  ])('a stored non-token value (%s) is discarded: null, and the entry is deleted', async (_label, value) => {
    const { takePendingInvite, PENDING_INVITE_KEY } = await invite();
    store.values.set(PENDING_INVITE_KEY, value);
    expect(await takePendingInvite()).toBeNull();
    expect(store.values.has(PENDING_INVITE_KEY)).toBe(false);
  });
});

describe('INV-022 pasting what the member was sent (parseInviteToken, buildInviteLink)', () => {
  it.each([
    ['a bare token', TOKEN],
    ['a bare token with surrounding whitespace', `  \n${TOKEN}\t `],
    ['an https invite link', `https://fitcruxx.vercel.app/invite/${TOKEN}`],
    ['an https invite link on another host', `https://gym.example.in/invite/${TOKEN}`],
    ['an https invite link with a query string', `https://fitcruxx.vercel.app/invite/${TOKEN}?utm_source=whatsapp`],
    ['an https invite link with a hash', `https://fitcruxx.vercel.app/invite/${TOKEN}#top`],
    ['an https invite link, padded', `  https://fitcruxx.vercel.app/invite/${TOKEN}  `],
    ['a fitcruxx link', `fitcruxx://invite/${TOKEN}`],
    ['a fitcruxx link, padded', `\nfitcruxx://invite/${TOKEN}\n`],
  ])('%s -> the token', (_label, pasted) => {
    expect(parseInviteToken(pasted)).toBe(TOKEN);
  });

  it.each([
    ['empty', ''],
    ['spaces', '    '],
    ['words', 'hello there'],
    ['a short token', TOKEN.slice(0, 42)],
    ['a long token', `${TOKEN}A`],
    ['an https link with a short token', `https://fitcruxx.vercel.app/invite/${TOKEN.slice(0, 42)}`],
    ['an https link to another path', `https://fitcruxx.vercel.app/other/${TOKEN}`],
    ['the sign-in callback', `fitcruxx://auth/callback?code=${TOKEN}`],
    ['a fitcruxx link with a short token', `fitcruxx://invite/${TOKEN.slice(0, 42)}`],
    ['a script URL', 'javascript:alert(1)'],
    ['two tokens', `${TOKEN} ${OTHER_TOKEN}`],
  ])('%s -> null', (_label, pasted) => {
    expect(parseInviteToken(pasted)).toBeNull();
  });

  it('buildInviteLink is origin + /invite/ + token, and parses back to the same token', () => {
    const link = buildInviteLink('https://fitcruxx.vercel.app', TOKEN);
    expect(link).toBe(`https://fitcruxx.vercel.app/invite/${TOKEN}`);
    expect(parseInviteToken(link)).toBe(TOKEN);
  });
});
