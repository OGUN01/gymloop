import { Constants } from '@gymloop/db';
import { describe, expect, it } from 'vitest';
import * as barrel from '../../index';
import { STAFF_INVITE_COOKIE_NAME, STAFF_INVITE_LIMITS } from '../../config/constants';
import {
  buildStaffInviteLink,
  parseStaffInviteToken,
  STAFF_INVITE_REFUSAL_COPY,
  STAFF_INVITE_ROLE_LABELS,
  STAFF_INVITE_ROLES,
  staffInviteIssueRequestSchema,
  staffInviteNotice,
  staffInviteRedeemRequestSchema,
  staffInviteRefusalMessage,
  staffInviteRevokeRequestSchema,
  staffInviteShareMessage,
  staffMemberInviteRequestSchema,
  staffUnlinkRequestSchema,
} from '../staff-invites';

/**
 * Staff invites (STI-001..STI-018), shared contract. Written from
 * `openspec/changes/staff-invites/proposal.md` ("Shared") and the member-invites
 * proposal it mirrors, before `packages/shared/src/api/staff-invites.ts`
 * exists. No implementation and no other author's test was read.
 *
 * Readings chosen where the contract is silent (each is listed in the author's
 * report so the owner can overrule it):
 * - `staffInviteShareMessage` greets by FIRST NAME ONLY, like INV's
 *   `inviteShareMessage`; no surname may appear.
 * - `parseStaffInviteToken` accepts ONLY a bare token or an `https://` link on
 *   `/staff-invite/<token>`; `http://`, the member path and a deep-link scheme
 *   are all null ("null otherwise").
 * - `staffInviteRefusalMessage` looks codes up by own property, so inherited
 *   names and the two success outcomes fall back to the unavailable sentence.
 */

const TOKEN = 'Zm9vYmFyYmF6'.padEnd(43, 'Q');
const ORIGIN = 'https://app.fitcruxx.example';
const UUID = '11111111-1111-4111-8111-111111111111';
const UUID_2 = '22222222-2222-4222-8222-222222222222';

const COPY = {
  invite_unavailable:
    "This invite can't be used. It may have expired or been replaced. Ask your gym owner to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym owner has on file for you, or ask them to update it.",
  identity_unverified:
    "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already linked to a gym and can't be linked again. Ask your gym owner to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const;

const VALID_INVITE = { fullName: 'Rohan Mehta', email: 'rohan@example.com', role: 'front_desk' } as const;

/** Without one key of VALID_INVITE, typed loosely so a schema can be asked about the gap. */
const withoutKey = (key: keyof typeof VALID_INVITE): Record<string, unknown> => {
  const copy: Record<string, unknown> = { ...VALID_INVITE };
  delete copy[key];
  return copy;
};

const emailOfLength = (length: number): string => {
  // Four 60-character domain labels keep the local part and every label short,
  // so only the total length can be the reason a boundary case is refused.
  const domain = `${Array.from({ length: 4 }, () => 'b'.repeat(60)).join('.')}.com`;
  return `${'a'.repeat(length - domain.length - 1)}@${domain}`;
};

describe('staff invite constants', () => {
  it('lists exactly the three invitable roles, none of them the owner', () => {
    expect(STAFF_INVITE_ROLES).toEqual(['gym_manager', 'front_desk', 'trainer']);
    expect(STAFF_INVITE_ROLES).not.toContain('gym_owner');
  });

  it('draws every invitable role from the Postgres app_role enum, never a private vocabulary (AGENTS rule 5)', () => {
    for (const role of STAFF_INVITE_ROLES) expect(Constants.public.Enums.app_role).toContain(role);
  });

  it('labels each role in plain lowercase words, and labels nothing else', () => {
    expect(STAFF_INVITE_ROLE_LABELS).toEqual({
      gym_manager: 'manager',
      front_desk: 'front desk',
      trainer: 'trainer',
    });
  });

  it('pins the limits exactly, including the numbers that differ from the member invite limits', () => {
    expect(STAFF_INVITE_LIMITS).toEqual({
      ttlHours: 48,
      tenantIssuesPerHour: 30,
      staffIssuesPerDay: 5,
      redeemFailuresPerWindow: 10,
      redeemWindowMinutes: 15,
      tokenBytes: 32,
      cookieMaxAgeSeconds: 1800,
    });
  });

  it('names the invite cookie so it cannot collide with the member invite cookie', () => {
    expect(STAFF_INVITE_COOKIE_NAME).toBe('fitcruxx_staff_invite');
    expect(STAFF_INVITE_COOKIE_NAME).not.toBe('fitcruxx_invite');
  });
});

describe('request schemas that carry one id', () => {
  it.each([
    ['staffInviteIssueRequestSchema', staffInviteIssueRequestSchema, 'staffId'],
    ['staffInviteRevokeRequestSchema', staffInviteRevokeRequestSchema, 'inviteId'],
  ] as const)('%s accepts exactly one uuid and refuses everything else', (_name, schema, key) => {
    expect(schema.safeParse({ [key]: UUID }).success).toBe(true);
    expect(schema.safeParse({}).success).toBe(false);
    expect(schema.safeParse({ [key]: 'not-a-uuid' }).success).toBe(false);
    expect(schema.safeParse({ [key]: '' }).success).toBe(false);
    expect(schema.safeParse({ [key]: 7 }).success).toBe(false);
    expect(schema.safeParse({ [key]: null }).success).toBe(false);
    // Strict: a smuggled field is a refusal, not silently dropped.
    expect(schema.safeParse({ [key]: UUID, tenantId: UUID_2 }).success).toBe(false);
    expect(schema.safeParse({ [key]: UUID, userId: UUID_2 }).success).toBe(false);
    expect(schema.safeParse(null).success).toBe(false);
    expect(schema.safeParse('x').success).toBe(false);
  });

  it('keeps the two schemas apart: a staffId is not an inviteId', () => {
    expect(staffInviteIssueRequestSchema.safeParse({ inviteId: UUID }).success).toBe(false);
    expect(staffInviteRevokeRequestSchema.safeParse({ staffId: UUID }).success).toBe(false);
  });
});

describe('staffInviteRedeemRequestSchema', () => {
  it('accepts a 43-character base64url token', () => {
    expect(staffInviteRedeemRequestSchema.safeParse({ token: TOKEN }).success).toBe(true);
    expect(staffInviteRedeemRequestSchema.safeParse({ token: 'A-_'.repeat(14) + 'A' }).success).toBe(true);
  });

  it.each([
    ['empty', ''],
    ['42 characters', 'Q'.repeat(42)],
    ['44 characters', 'Q'.repeat(44)],
    ['standard-base64 plus', `${'Q'.repeat(42)}+`],
    ['standard-base64 slash', `${'Q'.repeat(42)}/`],
    ['base64 padding', `${'Q'.repeat(42)}=`],
    ['leading space', ` ${'Q'.repeat(42)}`],
    ['trailing newline', `${'Q'.repeat(42)}\n`],
    ['a full link', `${ORIGIN}/staff-invite/${TOKEN}`],
  ])('refuses a token that is %s', (_label, token) => {
    expect(staffInviteRedeemRequestSchema.safeParse({ token }).success).toBe(false);
  });

  it('refuses a missing, non-string or extra field', () => {
    expect(staffInviteRedeemRequestSchema.safeParse({}).success).toBe(false);
    expect(staffInviteRedeemRequestSchema.safeParse({ token: 43 }).success).toBe(false);
    expect(staffInviteRedeemRequestSchema.safeParse({ token: null }).success).toBe(false);
    expect(staffInviteRedeemRequestSchema.safeParse({ token: TOKEN, staffId: UUID }).success).toBe(false);
  });
});

describe('staffMemberInviteRequestSchema', () => {
  it('accepts the minimal request: name, email and an invitable role', () => {
    const parsed = staffMemberInviteRequestSchema.safeParse(VALID_INVITE);
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.fullName).toBe('Rohan Mehta');
      expect(parsed.data.email).toBe('rohan@example.com');
      expect(parsed.data.role).toBe('front_desk');
      expect(parsed.data.phone).toBeUndefined();
      expect(parsed.data.branchId).toBeUndefined();
    }
  });

  it('accepts a phone and a branch together', () => {
    const parsed = staffMemberInviteRequestSchema.safeParse({
      ...VALID_INVITE,
      role: 'trainer',
      phone: '+919876543210',
      branchId: UUID,
    });
    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.phone).toBe('+919876543210');
      expect(parsed.data.branchId).toBe(UUID);
      expect(parsed.data.role).toBe('trainer');
    }
  });

  it.each(STAFF_INVITE_ROLES)('accepts the %s role', (role) => {
    expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, role }).success).toBe(true);
  });

  it.each(['gym_owner', 'member', 'super_admin', 'platform_support', 'Manager', 'manager', 'FRONT_DESK', '', 'admin'])(
    'refuses the role %j (the owner role in particular is never invitable)',
    (role) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, role }).success).toBe(false);
    },
  );

  it('refuses an absent or non-string role', () => {
    expect(staffMemberInviteRequestSchema.safeParse(withoutKey('role')).success).toBe(false);
    expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, role: 3 }).success).toBe(false);
    expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, role: ['trainer'] }).success).toBe(false);
  });

  describe('full name', () => {
    it('is trimmed', () => {
      const parsed = staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: '  Rohan Mehta \n' });
      expect(parsed.success).toBe(true);
      if (parsed.success) expect(parsed.data.fullName).toBe('Rohan Mehta');
    });

    it.each([['empty', ''], ['spaces only', '    '], ['a tab and newline only', '\t\n']])('refuses a name that is %s', (_label, fullName) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName }).success).toBe(false);
    });

    it('allows exactly 120 characters and refuses 121', () => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: 'N'.repeat(120) }).success).toBe(true);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: 'N'.repeat(121) }).success).toBe(false);
    });

    it('measures the limit after trimming', () => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: `  ${'N'.repeat(120)}  ` }).success).toBe(true);
    });

    it('refuses a missing or non-string name', () => {
      expect(staffMemberInviteRequestSchema.safeParse(withoutKey('fullName')).success).toBe(false);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: 12 }).success).toBe(false);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, fullName: null }).success).toBe(false);
    });
  });

  describe('email', () => {
    it('is trimmed', () => {
      const parsed = staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email: '  rohan@example.com\t' });
      expect(parsed.success).toBe(true);
      if (parsed.success) expect(parsed.data.email).toBe('rohan@example.com');
    });

    it.each(['rohan@example.com', 'rohan.mehta+gym@example.co.in', 'r_m-1@sub.example.org'])('accepts %s', (email) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email }).success).toBe(true);
    });

    it.each([
      ['empty', ''],
      ['blank', '   '],
      ['no at sign', 'rohan.example.com'],
      ['no local part', '@example.com'],
      ['no domain', 'rohan@'],
      ['undotted domain', 'rohan@example'],
      ['two at signs', 'rohan@@example.com'],
      ['a space inside the local part', 'ro han@example.com'],
      ['a space inside the domain', 'rohan@exam ple.com'],
      ['a comma list', 'rohan@example.com,asha@example.com'],
    ])('refuses an email that is %s', (_label, email) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email }).success).toBe(false);
    });

    it('allows exactly 254 characters and refuses 255', () => {
      expect(emailOfLength(254)).toHaveLength(254);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email: emailOfLength(254) }).success).toBe(true);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email: emailOfLength(255) }).success).toBe(false);
    });

    it('refuses a missing or non-string email', () => {
      expect(staffMemberInviteRequestSchema.safeParse(withoutKey('email')).success).toBe(false);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email: 5 }).success).toBe(false);
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, email: null }).success).toBe(false);
    });
  });

  describe('phone', () => {
    it('treats an empty string as absent, because a blank form field submits one', () => {
      const parsed = staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, phone: '' });
      expect(parsed.success).toBe(true);
      if (parsed.success) expect(parsed.data.phone).toBeUndefined();
    });

    it.each(['+919876543210', '+12345678', '+123456789012345'])('accepts the E.164 number %s', (phone) => {
      const parsed = staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, phone });
      expect(parsed.success).toBe(true);
      if (parsed.success) expect(parsed.data.phone).toBe(phone);
    });

    it.each([
      ['no plus sign', '919876543210'],
      ['a bare ten-digit mobile', '9876543210'],
      ['a leading zero after the plus', '+0123456789'],
      ['spaces', '+91 98765 43210'],
      ['dashes', '+91-9876543210'],
      ['seven digits', '+1234567'],
      ['sixteen digits', '+1234567890123456'],
      ['letters', '+91abcdefghij'],
      ['a trailing newline', '+919876543210\n'],
    ])('refuses a phone with %s', (_label, phone) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, phone }).success).toBe(false);
    });

    it('refuses a non-string phone', () => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, phone: 919876543210 }).success).toBe(false);
    });
  });

  describe('branch', () => {
    it('is optional', () => {
      expect(staffMemberInviteRequestSchema.safeParse(VALID_INVITE).success).toBe(true);
    });

    it.each(['not-a-uuid', '1234', 'zzzzzzzz-zzzz-4zzz-8zzz-zzzzzzzzzzzz', 7])('refuses the branch %j', (branchId) => {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, branchId }).success).toBe(false);
    });
  });

  it('is strict: no field outside the contract is accepted, least of all one that names a gym or a login', () => {
    for (const extra of [
      { tenantId: UUID },
      { userId: UUID },
      { staffId: UUID },
      { isActive: true },
      { user_id: UUID },
      { password: 'x' },
    ]) {
      expect(staffMemberInviteRequestSchema.safeParse({ ...VALID_INVITE, ...extra }).success).toBe(false);
    }
  });

  it('refuses a body that is not an object', () => {
    for (const body of [null, undefined, 'Rohan', 7, [], [VALID_INVITE]]) {
      expect(staffMemberInviteRequestSchema.safeParse(body).success).toBe(false);
    }
  });
});

describe('staffUnlinkRequestSchema', () => {
  const VALID = { staffId: UUID, reason: 'Left the gym' };

  it('accepts a staff id and a reason', () => {
    const parsed = staffUnlinkRequestSchema.safeParse(VALID);
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data).toEqual(VALID);
  });

  it('trims the reason', () => {
    const parsed = staffUnlinkRequestSchema.safeParse({ ...VALID, reason: '   Left the gym \n' });
    expect(parsed.success).toBe(true);
    if (parsed.success) expect(parsed.data.reason).toBe('Left the gym');
  });

  it('requires at least three characters after trimming', () => {
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: 'abc' }).success).toBe(true);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: '  abc  ' }).success).toBe(true);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: 'ab' }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: '  ab  ' }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: '     ' }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: '' }).success).toBe(false);
  });

  it('allows exactly 200 characters and refuses 201', () => {
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: 'r'.repeat(200) }).success).toBe(true);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: 'r'.repeat(201) }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: `  ${'r'.repeat(200)}  ` }).success).toBe(true);
  });

  it('refuses a missing field, a bad id, a non-string reason and any extra field', () => {
    expect(staffUnlinkRequestSchema.safeParse({ staffId: UUID }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ reason: 'Left the gym' }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, staffId: 'nope' }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, reason: 12345 }).success).toBe(false);
    expect(staffUnlinkRequestSchema.safeParse({ ...VALID, tenantId: UUID_2 }).success).toBe(false);
  });
});

describe('STAFF_INVITE_REFUSAL_COPY', () => {
  it('holds exactly the five staff sentences, verbatim', () => {
    expect(STAFF_INVITE_REFUSAL_COPY).toEqual(COPY);
    expect(Object.keys(STAFF_INVITE_REFUSAL_COPY).sort()).toEqual(Object.keys(COPY).sort());
  });

  it('says "gym owner" where the member copy says "gym", so a staff member is told who to ask', () => {
    for (const code of ['invite_unavailable', 'email_mismatch', 'account_already_linked'] as const) {
      expect(STAFF_INVITE_REFUSAL_COPY[code]).toContain('gym owner');
    }
  });

  it('invents no numbers', () => {
    for (const sentence of Object.values(STAFF_INVITE_REFUSAL_COPY)) expect(sentence).not.toMatch(/\d/);
  });

  it('never names a cause the person could use as an oracle (no member, no staff, no revoked)', () => {
    for (const sentence of Object.values(STAFF_INVITE_REFUSAL_COPY)) {
      expect(sentence).not.toMatch(/revoked|cancelled|blocked|deactivated|erased/i);
    }
  });
});

describe('staffInviteRefusalMessage', () => {
  it.each(Object.entries(COPY))('maps %s to its sentence', (code, sentence) => {
    expect(staffInviteRefusalMessage(code)).toBe(sentence);
  });

  it.each([
    'nope',
    '',
    ' ',
    'INVITE_UNAVAILABLE',
    'linked',
    'already_linked_here',
    '__proto__',
    'constructor',
    'prototype',
    'toString',
    'hasOwnProperty',
    'valueOf',
  ])('falls back to the unavailable sentence for %j', (code) => {
    expect(staffInviteRefusalMessage(code)).toBe(COPY.invite_unavailable);
  });

  it('never returns undefined or a function, whatever it is asked', () => {
    for (const code of ['__proto__', 'constructor', 'toString']) {
      expect(typeof staffInviteRefusalMessage(code)).toBe('string');
    }
  });
});

describe('buildStaffInviteLink', () => {
  it('joins an origin, the staff-invite path and the token', () => {
    expect(buildStaffInviteLink(ORIGIN, TOKEN)).toBe(`${ORIGIN}/staff-invite/${TOKEN}`);
    expect(buildStaffInviteLink('http://127.0.0.1:3000', TOKEN)).toBe(`http://127.0.0.1:3000/staff-invite/${TOKEN}`);
  });

  it('uses the staff-invite path, which is not the member invite path', () => {
    const link = buildStaffInviteLink(ORIGIN, TOKEN);
    expect(link).toMatch(/\/staff-invite\/[^/]+$/);
    expect(link.replace('/staff-invite/', '/')).not.toContain('/invite/');
  });

  it('round-trips through parseStaffInviteToken', () => {
    expect(parseStaffInviteToken(buildStaffInviteLink(ORIGIN, TOKEN))).toBe(TOKEN);
  });
});

describe('parseStaffInviteToken', () => {
  it('returns a bare token', () => {
    expect(parseStaffInviteToken(TOKEN)).toBe(TOKEN);
  });

  it('trims surrounding whitespace', () => {
    expect(parseStaffInviteToken(`  ${TOKEN}\n`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`\t${ORIGIN}/staff-invite/${TOKEN} `)).toBe(TOKEN);
  });

  it('reads the token out of an https staff-invite link on any host', () => {
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`https://fitcruxx.vercel.app/staff-invite/${TOKEN}`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`https://gym.example.com:8443/staff-invite/${TOKEN}`)).toBe(TOKEN);
  });

  it('ignores a query string and a fragment', () => {
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/${TOKEN}?utm_source=whatsapp`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/${TOKEN}#top`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/${TOKEN}?a=1#top`)).toBe(TOKEN);
  });

  it('takes the token from the path, never from a token-shaped query value', () => {
    const other = 'Y'.repeat(43);
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/${TOKEN}?next=${other}`)).toBe(TOKEN);
    expect(parseStaffInviteToken(`${ORIGIN}/staff-invite/?t=${other}`)).toBeNull();
  });

  it('refuses the member invite link, so a staff form cannot redeem a member token by mistake', () => {
    expect(parseStaffInviteToken(`${ORIGIN}/invite/${TOKEN}`)).toBeNull();
  });

  it('refuses http, the deep-link scheme and other schemes: staff redemption has no mobile surface', () => {
    expect(parseStaffInviteToken(`http://gym.example.com/staff-invite/${TOKEN}`)).toBeNull();
    expect(parseStaffInviteToken(`fitcruxx://staff-invite/${TOKEN}`)).toBeNull();
    expect(parseStaffInviteToken(`fitcruxx://invite/${TOKEN}`)).toBeNull();
    expect(parseStaffInviteToken(`javascript:alert(1)//${TOKEN}`)).toBeNull();
    expect(parseStaffInviteToken(`ftp://gym.example.com/staff-invite/${TOKEN}`)).toBeNull();
  });

  it.each([
    ['empty', ''],
    ['spaces', '    '],
    ['42 characters', 'Q'.repeat(42)],
    ['44 characters', 'Q'.repeat(44)],
    ['a standard-base64 character', `${'Q'.repeat(42)}+`],
    ['padding', `${'Q'.repeat(42)}=`],
    ['text around a token', `my token is ${TOKEN}`],
    ['two tokens', `${TOKEN} ${TOKEN}`],
    ['a link with no token', `${ORIGIN}/staff-invite/`],
    ['a link with no path', ORIGIN],
    ['a link with a short token', `${ORIGIN}/staff-invite/${'Q'.repeat(42)}`],
    ['a link with a long token', `${ORIGIN}/staff-invite/${'Q'.repeat(44)}`],
    ['a link with extra path after the token', `${ORIGIN}/staff-invite/${TOKEN}/extra`],
    ['a link with the token in a deeper path', `${ORIGIN}/a/staff-invite/${TOKEN}`],
    ['a link whose token is percent-encoded', `${ORIGIN}/staff-invite/%41${TOKEN.slice(1)}`],
    ['a path traversal', `${ORIGIN}/staff-invite/../${TOKEN}`],
    ['a scheme-relative link', `//gym.example.com/staff-invite/${TOKEN}`],
    ['a relative path', `/staff-invite/${TOKEN}`],
    ['HTML', `<a href="${ORIGIN}/staff-invite/${TOKEN}">x</a>`],
    ['a data URL', `data:text/plain,${TOKEN}`],
  ])('returns null for %s', (_label, input) => {
    expect(parseStaffInviteToken(input)).toBeNull();
  });
});

describe('staffInviteShareMessage', () => {
  const INPUT = {
    staffName: 'Rohan Mehta',
    gymName: 'Iron Box Fitness',
    roleLabel: 'front desk',
    email: 'rohan@example.com',
    link: `${ORIGIN}/staff-invite/${TOKEN}`,
  };

  it('names the person by first name, the gym, the role, the email to use and the link', () => {
    const message = staffInviteShareMessage(INPUT);
    expect(message).toContain('Rohan');
    expect(message).toContain('Iron Box Fitness');
    expect(message).toContain('front desk');
    expect(message).toContain('rohan@example.com');
    expect(message).toContain(INPUT.link);
  });

  it('uses the first name only: a surname is never put into a forwarded message', () => {
    expect(staffInviteShareMessage(INPUT)).not.toContain('Mehta');
    expect(staffInviteShareMessage({ ...INPUT, staffName: '  Rohan   Kumar Mehta ' })).not.toContain('Mehta');
    expect(staffInviteShareMessage({ ...INPUT, staffName: '  Rohan   Kumar Mehta ' })).not.toContain('Kumar');
  });

  it('works for a single-word name', () => {
    expect(staffInviteShareMessage({ ...INPUT, staffName: 'Rohan' })).toContain('Rohan');
  });

  it('puts the link in once, so a recipient does not see two different-looking links', () => {
    expect(staffInviteShareMessage(INPUT).split(INPUT.link)).toHaveLength(2);
  });

  it('is plain text with no placeholder left in it', () => {
    const message = staffInviteShareMessage(INPUT);
    expect(message).not.toMatch(/undefined|null|\{|\}|\[object/);
    expect(message.trim()).toBe(message);
  });

  it('says the role the person is being invited as, using the label it was given', () => {
    expect(staffInviteShareMessage({ ...INPUT, roleLabel: 'trainer' })).toContain('trainer');
    expect(staffInviteShareMessage({ ...INPUT, roleLabel: 'manager' })).toContain('manager');
  });

  it('is deterministic', () => {
    expect(staffInviteShareMessage(INPUT)).toBe(staffInviteShareMessage({ ...INPUT }));
  });
});

describe('staffInviteNotice', () => {
  it('is the exact staff notice with the gym and the role filled in', () => {
    expect(staffInviteNotice('Iron Box Fitness', 'front desk')).toBe(
      "By linking, you let Iron Box Fitness connect this Google account (your name and email) to your staff profile as front desk. FitCruxx processes it on Iron Box Fitness's behalf so you can sign in and do your work. Ask Iron Box Fitness's owner to unlink it at any time.",
    );
  });

  it('fills every placeholder for every invitable role', () => {
    for (const role of STAFF_INVITE_ROLES) {
      const notice = staffInviteNotice('Test Gym', STAFF_INVITE_ROLE_LABELS[role]);
      expect(notice).toContain(`to your staff profile as ${STAFF_INVITE_ROLE_LABELS[role]}.`);
      expect(notice.split('Test Gym')).toHaveLength(4);
    }
  });

  it('names the role and the data processed, and states no number', () => {
    const notice = staffInviteNotice('Test Gym', 'manager');
    expect(notice).toContain('your name and email');
    expect(notice).toContain('as manager');
    expect(notice).not.toMatch(/\d/);
    expect(notice).not.toMatch(/compliant|DPDP/i);
  });
});

describe('the package barrel', () => {
  it('re-exports every staff invite symbol, as the very same values', () => {
    expect(barrel.STAFF_INVITE_ROLES).toBe(STAFF_INVITE_ROLES);
    expect(barrel.STAFF_INVITE_ROLE_LABELS).toBe(STAFF_INVITE_ROLE_LABELS);
    expect(barrel.staffInviteIssueRequestSchema).toBe(staffInviteIssueRequestSchema);
    expect(barrel.staffInviteRevokeRequestSchema).toBe(staffInviteRevokeRequestSchema);
    expect(barrel.staffInviteRedeemRequestSchema).toBe(staffInviteRedeemRequestSchema);
    expect(barrel.staffMemberInviteRequestSchema).toBe(staffMemberInviteRequestSchema);
    expect(barrel.staffUnlinkRequestSchema).toBe(staffUnlinkRequestSchema);
    expect(barrel.STAFF_INVITE_REFUSAL_COPY).toBe(STAFF_INVITE_REFUSAL_COPY);
    expect(barrel.staffInviteRefusalMessage).toBe(staffInviteRefusalMessage);
    expect(barrel.buildStaffInviteLink).toBe(buildStaffInviteLink);
    expect(barrel.parseStaffInviteToken).toBe(parseStaffInviteToken);
    expect(barrel.staffInviteShareMessage).toBe(staffInviteShareMessage);
    expect(barrel.staffInviteNotice).toBe(staffInviteNotice);
  });

  it('re-exports the two constants from config/constants', () => {
    expect(barrel.STAFF_INVITE_LIMITS).toBe(STAFF_INVITE_LIMITS);
    expect(barrel.STAFF_INVITE_COOKIE_NAME).toBe(STAFF_INVITE_COOKIE_NAME);
  });
});
