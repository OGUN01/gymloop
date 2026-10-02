import { describe, expect, it } from 'vitest';
import * as barrel from '../../index';
import { INVITE_COOKIE_NAME, MEMBER_INVITE_LIMITS } from '../../config/constants';
import {
  buildInviteLink,
  INVITE_REDEEM_OUTCOMES,
  INVITE_REFUSAL_COPY,
  INVITE_TOKEN_PATTERN,
  inviteIssueRequestSchema,
  inviteNotice,
  inviteRedeemRequestSchema,
  inviteRefusalMessage,
  inviteRevokeRequestSchema,
  inviteShareMessage,
  memberUnlinkRequestSchema,
  parseInviteToken,
} from '../member-invites';

/**
 * INV shared contract (`openspec/changes/member-invites/proposal.md`, "Shared").
 *
 * Written from the proposal before any implementation exists. The five refusal
 * sentences and the DPDP notice are pinned verbatim on purpose: they are the
 * product's user-visible words for the one feature where a vague refusal either
 * strands a real member or tells a stranger something about someone else's
 * record (INV-008, INV-023).
 */

const MEMBER_ID = '4f8d9a2e-6b1c-4d3e-8a7f-1c2b3d4e5f60';
/** 43 base64url characters: the shape of 32 random bytes with no padding. */
const TOKEN = 'Zm9vYmFyLXRva2VuLWZvci1rbm93bi1hbnN3ZXItMDA';
/** Exercises every character class the pattern admits, including `-` and `_`. */
const MIXED_TOKEN = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLM-_01';

const COPY = {
  invite_unavailable:
    "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified:
    "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const;

describe('fixtures are what the tests say they are', () => {
  it('uses tokens of exactly 43 pattern characters', () => {
    expect(TOKEN).toHaveLength(43);
    expect(MIXED_TOKEN).toHaveLength(43);
    expect(Buffer.from(TOKEN, 'base64url')).toHaveLength(32);
  });
});

describe('INVITE_TOKEN_PATTERN', () => {
  it('is exactly the contract expression and carries no stateful flag', () => {
    expect(INVITE_TOKEN_PATTERN.source).toBe('^[A-Za-z0-9_-]{43}$');
    // A `g` or `y` flag makes `.test()` stateful across calls: a token that
    // passes once would then fail on the next, in a security check.
    expect(INVITE_TOKEN_PATTERN.flags).toBe('');
  });

  it('accepts 43 url-safe base64 characters, upper and lower case, hyphen and underscore', () => {
    expect(INVITE_TOKEN_PATTERN.test(TOKEN)).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test(MIXED_TOKEN)).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test('A'.repeat(43))).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test('-'.repeat(43))).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test('_'.repeat(43))).toBe(true);
  });

  it('is repeatable: testing the same valid token twice never flips the answer', () => {
    expect(INVITE_TOKEN_PATTERN.test(TOKEN)).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test(TOKEN)).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test(TOKEN)).toBe(true);
  });

  it('is case sensitive in what it admits: both cases are valid, neither is folded', () => {
    expect(INVITE_TOKEN_PATTERN.test(TOKEN.toUpperCase())).toBe(true);
    expect(INVITE_TOKEN_PATTERN.test(TOKEN.toLowerCase())).toBe(true);
    // Folding is not the pattern's job, and the two spellings are different tokens.
    expect(TOKEN.toUpperCase()).not.toBe(TOKEN);
  });

  it.each([
    ['42 characters', TOKEN.slice(0, 42)],
    ['44 characters', `${TOKEN}A`],
    ['empty', ''],
    ['standard base64 plus', `${TOKEN.slice(0, 42)}+`],
    ['standard base64 slash', `${TOKEN.slice(0, 42)}/`],
    ['base64 padding', `${TOKEN.slice(0, 42)}=`],
    ['a dot', `${TOKEN.slice(0, 42)}.`],
    ['an interior space', `${TOKEN.slice(0, 20)} ${TOKEN.slice(21)}`],
    ['a leading space', ` ${TOKEN.slice(1)}`],
    ['a trailing newline', `${TOKEN}\n`],
    ['a leading newline', `\n${TOKEN}`],
    ['a non-ASCII look-alike', `${TOKEN.slice(0, 42)}Α`],
    ['a percent escape', `${TOKEN.slice(0, 40)}%2F`],
  ])('refuses %s', (_label, candidate) => {
    expect(INVITE_TOKEN_PATTERN.test(candidate)).toBe(false);
  });

  it('is consistent with the byte budget: 32 bytes encode to 43 unpadded base64url characters', () => {
    expect(Math.ceil((MEMBER_INVITE_LIMITS.tokenBytes * 8) / 6)).toBe(43);
  });
});

describe('inviteIssueRequestSchema', () => {
  it('accepts exactly a member uuid', () => {
    expect(inviteIssueRequestSchema.parse({ memberId: MEMBER_ID })).toEqual({ memberId: MEMBER_ID });
  });

  it.each([
    ['an unknown key', { memberId: MEMBER_ID, tenantId: MEMBER_ID }],
    ['a smuggled token', { memberId: MEMBER_ID, token: TOKEN }],
    ['a missing member id', {}],
    ['a non-uuid member id', { memberId: 'member-1' }],
    ['a padded uuid', { memberId: ` ${MEMBER_ID} ` }],
    ['a numeric member id', { memberId: 7 }],
    ['a null member id', { memberId: null }],
    ['an array', [MEMBER_ID]],
    ['null', null],
    ['a bare string', MEMBER_ID],
  ])('refuses %s', (_label, body) => {
    expect(inviteIssueRequestSchema.safeParse(body).success).toBe(false);
  });
});

describe('inviteRevokeRequestSchema', () => {
  it('accepts exactly an invite uuid', () => {
    expect(inviteRevokeRequestSchema.parse({ inviteId: MEMBER_ID })).toEqual({ inviteId: MEMBER_ID });
  });

  it.each([
    ['an unknown key', { inviteId: MEMBER_ID, memberId: MEMBER_ID }],
    ['the issue request shape', { memberId: MEMBER_ID }],
    ['a missing invite id', {}],
    ['a non-uuid invite id', { inviteId: 'invite-1' }],
    ['a null invite id', { inviteId: null }],
    ['an array', [MEMBER_ID]],
    ['null', null],
  ])('refuses %s', (_label, body) => {
    expect(inviteRevokeRequestSchema.safeParse(body).success).toBe(false);
  });
});

describe('inviteRedeemRequestSchema', () => {
  it('accepts exactly a pattern-valid token and returns it untouched', () => {
    expect(inviteRedeemRequestSchema.parse({ token: TOKEN })).toEqual({ token: TOKEN });
    expect(inviteRedeemRequestSchema.parse({ token: MIXED_TOKEN })).toEqual({ token: MIXED_TOKEN });
  });

  it.each([
    ['an unknown key', { token: TOKEN, memberId: MEMBER_ID }],
    ['a missing token', {}],
    ['a 42-character token', { token: TOKEN.slice(0, 42) }],
    ['a 44-character token', { token: `${TOKEN}A` }],
    ['a padded token (no trimming)', { token: ` ${TOKEN} ` }],
    ['a whole invite link instead of the token', { token: `https://app.example/invite/${TOKEN}` }],
    ['a non-string token', { token: 12345 }],
    ['a null token', { token: null }],
    ['an empty token', { token: '' }],
    ['an array', [TOKEN]],
    ['null', null],
  ])('refuses %s', (_label, body) => {
    expect(inviteRedeemRequestSchema.safeParse(body).success).toBe(false);
  });
});

describe('memberUnlinkRequestSchema', () => {
  it('accepts a member uuid and a reason, returning the trimmed reason', () => {
    expect(memberUnlinkRequestSchema.parse({ memberId: MEMBER_ID, reason: 'Left the gym' })).toEqual({
      memberId: MEMBER_ID,
      reason: 'Left the gym',
    });
    expect(memberUnlinkRequestSchema.parse({ memberId: MEMBER_ID, reason: '   wrong person linked   ' })).toEqual({
      memberId: MEMBER_ID,
      reason: 'wrong person linked',
    });
  });

  it('trims before measuring: the 3 and 200 character limits apply to the trimmed text', () => {
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: 'abc' }).success).toBe(true);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: '  abc  ' }).success).toBe(true);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: 'ab' }).success).toBe(false);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: '  ab  ' }).success).toBe(false);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: '     ' }).success).toBe(false);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: '' }).success).toBe(false);

    const atLimit = 'x'.repeat(200);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: atLimit }).success).toBe(true);
    expect(memberUnlinkRequestSchema.safeParse({ memberId: MEMBER_ID, reason: `${atLimit}x` }).success).toBe(false);
    // 200 characters surrounded by whitespace is a 200-character reason.
    const padded = memberUnlinkRequestSchema.parse({ memberId: MEMBER_ID, reason: `  ${atLimit}  ` });
    expect(padded.reason).toBe(atLimit);
    expect(padded.reason).toHaveLength(200);
  });

  it.each([
    ['an unknown key', { memberId: MEMBER_ID, reason: 'Left the gym', inviteId: MEMBER_ID }],
    ['a missing reason', { memberId: MEMBER_ID }],
    ['a missing member id', { reason: 'Left the gym' }],
    ['a non-uuid member id', { memberId: 'member-1', reason: 'Left the gym' }],
    ['a non-string reason', { memberId: MEMBER_ID, reason: 42 }],
    ['a null reason', { memberId: MEMBER_ID, reason: null }],
    ['an array', [MEMBER_ID, 'Left the gym']],
    ['null', null],
  ])('refuses %s', (_label, body) => {
    expect(memberUnlinkRequestSchema.safeParse(body).success).toBe(false);
  });
});

describe('INVITE_REDEEM_OUTCOMES', () => {
  it('lists the seven outcomes in the contract order', () => {
    expect([...INVITE_REDEEM_OUTCOMES]).toEqual([
      'linked',
      'already_linked_here',
      'invite_unavailable',
      'email_mismatch',
      'identity_unverified',
      'account_already_linked',
      'rate_limited',
    ]);
  });

  it('has no duplicates', () => {
    expect(new Set(INVITE_REDEEM_OUTCOMES).size).toBe(INVITE_REDEEM_OUTCOMES.length);
  });
});

describe('INVITE_REFUSAL_COPY', () => {
  it('has exactly the five refusal outcomes as keys, and neither success outcome', () => {
    expect(Object.keys(INVITE_REFUSAL_COPY).sort()).toEqual(Object.keys(COPY).sort());
    expect(INVITE_REFUSAL_COPY).not.toHaveProperty('linked');
    expect(INVITE_REFUSAL_COPY).not.toHaveProperty('already_linked_here');
  });

  it('covers every outcome that is not a success', () => {
    const refusals = INVITE_REDEEM_OUTCOMES.filter((o) => o !== 'linked' && o !== 'already_linked_here');
    expect(refusals.sort()).toEqual(Object.keys(INVITE_REFUSAL_COPY).sort());
  });

  it.each(Object.entries(COPY))('says exactly the contract sentence for %s', (code, sentence) => {
    expect((INVITE_REFUSAL_COPY as Record<string, string>)[code]).toBe(sentence);
  });

  it('keeps unavailable causes collapsed: the sentence names no single cause and no member fact', () => {
    const unavailable = INVITE_REFUSAL_COPY.invite_unavailable;
    for (const word of ['cancelled', 'canceled', 'blocked', 'erased', 'revoked', 'redeemed', 'already used']) {
      expect(unavailable.toLowerCase()).not.toContain(word);
    }
  });
});

describe('inviteRefusalMessage', () => {
  it.each(Object.entries(COPY))('maps %s to its sentence', (code, sentence) => {
    expect(inviteRefusalMessage(code)).toBe(sentence);
  });

  it.each([
    ['an empty code', ''],
    ['an unknown code', 'something_else'],
    ['a success outcome (not a refusal)', 'linked'],
    ['the other success outcome', 'already_linked_here'],
    ['a differently-cased code', 'INVITE_UNAVAILABLE'],
    ['a padded code', ' rate_limited '],
    ['__proto__', '__proto__'],
    ['constructor', 'constructor'],
    ['prototype', 'prototype'],
    ['toString', 'toString'],
    ['hasOwnProperty', 'hasOwnProperty'],
    ['valueOf', 'valueOf'],
    ['__defineGetter__', '__defineGetter__'],
  ])('falls back to the unavailable sentence for %s', (_label, code) => {
    const message = inviteRefusalMessage(code);
    expect(typeof message).toBe('string');
    expect(message).toBe(COPY.invite_unavailable);
  });
});

describe('buildInviteLink', () => {
  it.each(['token?query=secret', 'token#fragment', 'token/extra', '../escape', '%2e%2e/escape'])(
    'INV-018 malformed token %j cannot inject URL structure',
    (candidate) => {
      let link: string;
      try { link = buildInviteLink('https://app.example', candidate); } catch { return; }
      const url = new URL(link);
      expect(url.origin).toBe('https://app.example');
      expect(url.search).toBe('');
      expect(url.hash).toBe('');
      expect(url.pathname.split('/')).toHaveLength(3);
      expect(url.pathname.split('/')[1]).toBe('invite');
    },
  );
  it('joins origin, /invite/ and the token', () => {
    expect(buildInviteLink('https://app.example', TOKEN)).toBe(`https://app.example/invite/${TOKEN}`);
    expect(buildInviteLink('http://127.0.0.1:3000', MIXED_TOKEN)).toBe(`http://127.0.0.1:3000/invite/${MIXED_TOKEN}`);
  });

  it('does not double the slash when the origin carries a trailing one', () => {
    expect(buildInviteLink('https://app.example/', TOKEN)).toBe(`https://app.example/invite/${TOKEN}`);
  });

  it('carries the token verbatim: no case folding, no encoding, no truncation', () => {
    const link = buildInviteLink('https://app.example', MIXED_TOKEN);
    expect(link.endsWith(`/invite/${MIXED_TOKEN}`)).toBe(true);
    expect(link).toContain('-_01');
    expect(link).not.toContain('%');
  });

  it('round-trips through parseInviteToken', () => {
    expect(parseInviteToken(buildInviteLink('https://app.example', TOKEN))).toBe(TOKEN);
    expect(parseInviteToken(buildInviteLink('https://app.example/', MIXED_TOKEN))).toBe(MIXED_TOKEN);
  });
});

describe('parseInviteToken', () => {
  it('accepts a bare token, with its case preserved', () => {
    expect(parseInviteToken(TOKEN)).toBe(TOKEN);
    expect(parseInviteToken(MIXED_TOKEN)).toBe(MIXED_TOKEN);
  });

  it('trims surrounding whitespace, including newlines from a pasted block', () => {
    expect(parseInviteToken(`  ${TOKEN}  `)).toBe(TOKEN);
    expect(parseInviteToken(`\n${TOKEN}\n`)).toBe(TOKEN);
    expect(parseInviteToken(`\t${TOKEN}\r\n`)).toBe(TOKEN);
    expect(parseInviteToken(`  https://app.example/invite/${TOKEN}  `)).toBe(TOKEN);
    expect(parseInviteToken(`\nfitcruxx://invite/${TOKEN}\n`)).toBe(TOKEN);
  });

  it('accepts an https invite link on any host, ignoring query and hash', () => {
    expect(parseInviteToken(`https://app.example/invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseInviteToken(`https://fitcruxx.vercel.app/invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseInviteToken(`https://app.example:8443/invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseInviteToken(`https://app.example/invite/${TOKEN}?utm_source=whatsapp`)).toBe(TOKEN);
    expect(parseInviteToken(`https://app.example/invite/${TOKEN}#section`)).toBe(TOKEN);
    expect(parseInviteToken(`https://app.example/invite/${TOKEN}?a=1&b=2#frag`)).toBe(TOKEN);
  });

  it('accepts the fitcruxx:// deep link', () => {
    expect(parseInviteToken(`fitcruxx://invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseInviteToken(`fitcruxx://invite/${MIXED_TOKEN}`)).toBe(MIXED_TOKEN);
  });

  it.each([
    ['an extra path segment after the token', `https://app.example/invite/${TOKEN}/extra`],
    ['a longer token glued on', `https://app.example/invite/${TOKEN}extra`],
    ['a different path', `https://app.example/other/${TOKEN}`],
    ['the token as a query value on the root', `https://app.example/?token=${TOKEN}`],
    ['the token as a query value on /invite', `https://app.example/invite?token=${TOKEN}`],
    ['an /invite/ link with no token', 'https://app.example/invite/'],
    ['an /invite link with no slash or token', 'https://app.example/invite'],
    ['a 42-character token in a link', `https://app.example/invite/${TOKEN.slice(0, 42)}`],
    ['a 44-character token in a link', `https://app.example/invite/${TOKEN}A`],
    ['the continue page', 'https://app.example/invite/continue'],
    ['a deep link with an extra segment', `fitcruxx://invite/${TOKEN}/extra`],
    ['a deep link with the wrong host', `fitcruxx://other/${TOKEN}`],
    ['a deep link with no token', 'fitcruxx://invite/'],
    ['a different scheme', `ftp://app.example/invite/${TOKEN}`],
    ['javascript: carrying the token', `javascript:alert('${TOKEN}')`],
  ])('returns null for %s', (_label, input) => {
    expect(parseInviteToken(input)).toBeNull();
  });

  it.each([
    ['an empty string', ''],
    ['only whitespace', '   \n  '],
    ['a word', 'hello'],
    ['a sentence', 'please use my invite'],
    ['a 42-character bare token', TOKEN.slice(0, 42)],
    ['a 44-character bare token', `${TOKEN}A`],
    ['a standard-base64 token', `${TOKEN.slice(0, 42)}+`],
    ['a token with an interior space', `${TOKEN.slice(0, 20)} ${TOKEN.slice(21)}`],
    ['a token embedded in prose', `use ${TOKEN} to join`],
    ['two tokens', `${TOKEN} ${TOKEN}`],
    ['a bare host', 'app.example/invite/'],
  ])('returns null for junk: %s', (_label, input) => {
    expect(parseInviteToken(input)).toBeNull();
  });

  it('never returns a non-token: whatever it returns satisfies the pattern', () => {
    const samples = [
      TOKEN,
      `https://app.example/invite/${TOKEN}`,
      `fitcruxx://invite/${TOKEN}`,
      'nonsense',
      '',
      `https://app.example/invite/${TOKEN}/x`,
    ];
    for (const sample of samples) {
      const parsed = parseInviteToken(sample);
      if (parsed !== null) expect(INVITE_TOKEN_PATTERN.test(parsed)).toBe(true);
    }
  });
});

describe('inviteShareMessage', () => {
  const base = {
    memberName: 'Asha Rao',
    gymName: 'Iron Box Fitness',
    email: 'asha@example.com',
    link: `https://app.example/invite/${TOKEN}`,
  };

  it('addresses the member by first name only and carries the gym, email and link', () => {
    const message = inviteShareMessage(base);
    expect(message).toContain('Asha');
    expect(message).not.toContain('Rao');
    expect(message).toContain('Iron Box Fitness');
    expect(message).toContain('asha@example.com');
    expect(message).toContain(base.link);
    expect(message).toContain('FitCruxx');
    expect(message.startsWith('Hi Asha')).toBe(true);
  });

  it('puts the link in once, unaltered', () => {
    const message = inviteShareMessage(base);
    expect(message.split(base.link)).toHaveLength(2);
  });

  it('tells the person which Google account to use, so the email match is not a surprise', () => {
    const message = inviteShareMessage(base);
    expect(message.toLowerCase()).toContain('google');
  });

  it('copes with a single-word name and with stray whitespace around a full name', () => {
    expect(inviteShareMessage({ ...base, memberName: 'Asha' })).toContain('Hi Asha');
    const spaced = inviteShareMessage({ ...base, memberName: '  Asha   Rao  ' });
    expect(spaced).toContain('Hi Asha');
    expect(spaced).not.toContain('Rao');
  });

  it('adds no personal data the input did not name', () => {
    const withExtras = { ...base, phone: '+919876543210', memberId: MEMBER_ID, lastName: 'Rao' };
    const message = inviteShareMessage(withExtras as unknown as typeof base);
    expect(message).not.toContain('+919876543210');
    expect(message).not.toContain('9876543210');
    expect(message).not.toContain(MEMBER_ID);
    expect(message).not.toContain('Rao');
  });

  it('uses the supplied values literally, even when they contain replacement-pattern characters', () => {
    const message = inviteShareMessage({ ...base, gymName: "Pump $& Co $1 $'" });
    expect(message).toContain("Pump $& Co $1 $'");
  });
});

describe('inviteNotice', () => {
  const notice = (gym: string) =>
    `By linking, you let ${gym} connect this Google account (your name and email) to your membership record. FitCruxx processes it on ${gym}'s behalf to show you your visits, payments and messages. Ask ${gym} to unlink it at any time.`;

  it('is exactly the DPDP notice from the contract', () => {
    expect(inviteNotice('Iron Box Fitness')).toBe(notice('Iron Box Fitness'));
  });

  it('names the gym at every place the notice speaks of it, and says unlink', () => {
    const text = inviteNotice('Iron Box Fitness');
    expect(text.split('Iron Box Fitness')).toHaveLength(4); // three occurrences
    expect(text).toContain('unlink');
    expect(text).toContain("Iron Box Fitness's behalf");
  });

  it('states what is processed and for what, with no invented number', () => {
    const text = inviteNotice('Iron Box Fitness');
    expect(text).toContain('your name and email');
    expect(text).toContain('visits, payments and messages');
    expect(text).not.toMatch(/\d/);
  });

  it('inserts the gym name literally, including characters that are special in a replacement string', () => {
    const gym = "Pump $& Co $1 $' $`";
    expect(inviteNotice(gym)).toBe(notice(gym));
  });

  it('does not leave a placeholder behind', () => {
    const text = inviteNotice('Iron Box Fitness');
    expect(text).not.toContain('{gym}');
    expect(text).not.toContain('{');
    expect(text).not.toContain('undefined');
  });
});

describe('MEMBER_INVITE_LIMITS and INVITE_COOKIE_NAME', () => {
  it('are the exact contract values', () => {
    expect(MEMBER_INVITE_LIMITS).toStrictEqual({
      ttlHours: 48,
      tenantIssuesPerHour: 100,
      memberIssuesPerDay: 5,
      redeemFailuresPerWindow: 10,
      redeemWindowMinutes: 15,
      tokenBytes: 32,
      cookieMaxAgeSeconds: 1800,
    });
    expect(INVITE_COOKIE_NAME).toBe('fitcruxx_invite');
  });

  it('keeps the cookie lifetime at thirty minutes (INV-021)', () => {
    expect(MEMBER_INVITE_LIMITS.cookieMaxAgeSeconds).toBe(30 * 60);
  });
});

describe('package index', () => {
  it('re-exports every INV symbol from the same definitions', () => {
    expect(barrel.INVITE_TOKEN_PATTERN).toBe(INVITE_TOKEN_PATTERN);
    expect(barrel.inviteIssueRequestSchema).toBe(inviteIssueRequestSchema);
    expect(barrel.inviteRevokeRequestSchema).toBe(inviteRevokeRequestSchema);
    expect(barrel.inviteRedeemRequestSchema).toBe(inviteRedeemRequestSchema);
    expect(barrel.memberUnlinkRequestSchema).toBe(memberUnlinkRequestSchema);
    expect(barrel.INVITE_REDEEM_OUTCOMES).toBe(INVITE_REDEEM_OUTCOMES);
    expect(barrel.INVITE_REFUSAL_COPY).toBe(INVITE_REFUSAL_COPY);
    expect(barrel.inviteRefusalMessage).toBe(inviteRefusalMessage);
    expect(barrel.buildInviteLink).toBe(buildInviteLink);
    expect(barrel.parseInviteToken).toBe(parseInviteToken);
    expect(barrel.inviteShareMessage).toBe(inviteShareMessage);
    expect(barrel.inviteNotice).toBe(inviteNotice);
    expect(barrel.MEMBER_INVITE_LIMITS).toBe(MEMBER_INVITE_LIMITS);
    expect(barrel.INVITE_COOKIE_NAME).toBe(INVITE_COOKIE_NAME);
  });

  it('exposes the functions as functions and the data as data', () => {
    for (const name of [
      'inviteRefusalMessage',
      'buildInviteLink',
      'parseInviteToken',
      'inviteShareMessage',
      'inviteNotice',
    ] as const) {
      expect(typeof barrel[name]).toBe('function');
    }
    for (const name of [
      'inviteIssueRequestSchema',
      'inviteRevokeRequestSchema',
      'inviteRedeemRequestSchema',
      'memberUnlinkRequestSchema',
    ] as const) {
      expect(typeof barrel[name].safeParse).toBe('function');
    }
    expect(barrel.INVITE_TOKEN_PATTERN).toBeInstanceOf(RegExp);
    expect(Array.isArray(barrel.INVITE_REDEEM_OUTCOMES)).toBe(true);
  });
});
