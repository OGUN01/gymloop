/**
 * HOLDOUT TypeScript suite: FitCruxx v2 feature INV (member invites and self-linking).
 *
 * Written blind from `openspec/changes/member-invites/proposal.md` (INV-001..INV-024) and
 * nothing else: no visible suite and no implementation was read. It runs under
 * `pnpm test:scripts` (`vitest run scripts supabase/tests-holdout`) from the repository root.
 *
 * Where the proposal is silent this file takes the strictest reading that is still reasonable
 * for an identity feature (a wrong answer here shows one person another person's membership).
 *
 * How the route handlers are exercised
 * - The four handlers are imported by relative path and run for real, together with the real
 *   `apps/web/lib/api.ts` and `identity-session.ts`. Only the two Supabase client factories
 *   (`lib/supabase/server`, `lib/supabase/request`) and `next/headers` are replaced, by fakes
 *   that behave like the real Auth + PostgREST surface: claims verification, `getUser`,
 *   `refreshSession`, `signOut`, `rpc` builders (await, `single`, `maybeSingle`, `throwOnError`).
 * - The fake database answers only through named RPCs. Any table access is recorded.
 * - Raw invite tokens must never be stored, logged, echoed or sent to the database. Leak checks
 *   look for the known token and hash AND for any 43+ character base64url-looking run in every
 *   surface (body, headers, console), so a leak of an unknown token is caught too.
 *
 * Runtime limitation: React pages, the client panel and the mobile screens cannot be rendered
 * from here; the page-level requirements are covered only by source-level guards at the end.
 */
import { createHash, randomBytes } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { inspect } from 'node:util'
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest'

import * as shared from '../../packages/shared/src/index'

/* ------------------------------------------------------------------------------------------ *
 * Shared fixtures and tiny helpers
 * ------------------------------------------------------------------------------------------ */

const sha256Hex = (text: string): string => createHash('sha256').update(text, 'utf8').digest('hex')
const freshToken = (): string => randomBytes(32).toString('base64url')
const count = (haystack: string, needle: string): number => (needle === '' ? 0 : haystack.split(needle).length - 1)
const readSource = (relative: string): string => readFileSync(new URL(relative, import.meta.url), 'utf8')

const TOKEN_A = 'A'.repeat(43)
const TOKEN_B = `${'Ab_-'.repeat(10)}Ab_`
const TOKEN_C = 'GbJYVuHBUMqDTP_ItZsjrb0OwDieWOsis7ZHaAmNACs'
const TOKEN_D = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQ'
const TOKEN_DASH = `-_${'x'.repeat(41)}`

/** SHA-256 known answers, computed independently of any implementation with node:crypto. */
const KNOWN_HASHES: Array<[string, string]> = [
  [TOKEN_A, '0f007385b6f9d4b7eeb2748605afe1a984a0a3bfa3f014d09e2a784ce9e5cd1a'],
  [TOKEN_B, '7297e5976b644c59b1bf568d65ffb2acc15afde2b1a48332131a7c1f98e38cc9'],
  [TOKEN_C, '0c5a210295a001efa268117d1124cc415032443ffc15719f4008ce12b900cf52'],
  [TOKEN_D, '46a2199782c8827f0ac56f503be9d39efee97f40a736b92cc7d7c5f825cfd851'],
]

const UUID_1 = '5b9e2c1a-7d34-4f1b-9a6e-0c1d2e3f4a5b'
const UUID_2 = '8c1f0d2e-3a4b-4c5d-8e6f-7a8b9c0d1e2f'

const COPY = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch:
    "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  identity_unverified: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked:
    "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const
const REFUSAL_CODES = Object.keys(COPY) as Array<keyof typeof COPY>
const ALL_OUTCOMES = ['linked', 'already_linked_here', ...REFUSAL_CODES]

const INVITE_COOKIE = 'fitcruxx_invite'
const TOKEN_RUN = /[A-Za-z0-9_-]{43}/

/* ------------------------------------------------------------------------------------------ *
 * Fake PostgREST rpc builder, shared by the route harness and the pure web libs
 * ------------------------------------------------------------------------------------------ */

type RpcOutcome = { data?: unknown; error?: unknown }
type RpcCall = { name: string; args: Record<string, unknown> }
type RpcMode = 'all' | 'single' | 'maybe'

function settleRpc(raw: RpcOutcome, mode: RpcMode): { data: unknown; error: unknown; count: null; status: number; statusText: string } {
  let data: unknown = raw.data ?? null
  let error: unknown = raw.error ?? null
  if (error === null && Array.isArray(data) && mode !== 'all') {
    const rows = data.length
    if (rows === 1) data = data[0]
    else if (rows === 0 && mode === 'maybe') data = null
    else {
      data = null
      error = { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: `The result contains ${rows} rows` }
    }
  }
  return { data, error, count: null, status: error === null ? 200 : 400, statusText: error === null ? 'OK' : 'Bad Request' }
}

function rpcBuilder(thunk: () => Promise<RpcOutcome>, mode: RpcMode = 'all', strict = false): Record<string, unknown> {
  let memo: Promise<unknown> | undefined
  const settle = (): Promise<unknown> => {
    memo ??= thunk().then((raw) => {
      const result = settleRpc(raw, mode)
      if (strict && result.error !== null) {
        throw Object.assign(new Error(String((result.error as { message?: unknown }).message ?? 'rpc failed')), result.error as object)
      }
      return result
    })
    return memo
  }
  const self: Record<string, unknown> = {
    then: (onOk?: (value: unknown) => unknown, onBad?: (reason: unknown) => unknown) => settle().then(onOk, onBad),
    catch: (onBad?: (reason: unknown) => unknown) => settle().catch(onBad),
    finally: (callback?: () => void) => settle().finally(callback),
    single: () => rpcBuilder(thunk, 'single', strict),
    maybeSingle: () => rpcBuilder(thunk, 'maybe', strict),
    throwOnError: () => rpcBuilder(thunk, mode, true),
    abortSignal: () => self,
    setHeader: () => self,
    returns: () => self,
    overrideTypes: () => self,
  }
  return self
}

/** A bare `{ rpc }` client for the pure web libs (no auth surface needed). */
function fakeRpcClient(handler: (call: RpcCall) => RpcOutcome | Promise<RpcOutcome>) {
  const calls: RpcCall[] = []
  const client = {
    rpc(name: string, args: Record<string, unknown> = {}) {
      const call = { name, args: JSON.parse(JSON.stringify(args)) as Record<string, unknown> }
      calls.push(call)
      return rpcBuilder(async () => handler(call))
    },
    from() {
      throw new Error('tables are not part of this surface')
    },
  }
  return { client, calls }
}

/* ============================================================================================ *
 * 1. Token generation and hashing  (INV-001, INV-018)
 * ============================================================================================ */

describe('INV-001/INV-018 generateInviteToken and hashInviteToken (apps/web/lib/member-invite-token)', () => {
  const load = () => import('../../apps/web/lib/member-invite-token')

  it('generates 43-character unpadded base64url tokens accepted by INVITE_TOKEN_PATTERN', async () => {
    const { generateInviteToken } = await load()
    for (let i = 0; i < 300; i += 1) {
      const token = generateInviteToken()
      expect(typeof token).toBe('string')
      expect(token).toHaveLength(43)
      expect(token).toMatch(/^[A-Za-z0-9_-]{43}$/)
      expect(token).not.toContain('=')
      expect(shared.INVITE_TOKEN_PATTERN.test(token)).toBe(true)
    }
  })

  it('encodes exactly 32 random bytes in canonical base64url (the 43rd character carries only 4 data bits)', async () => {
    const { generateInviteToken } = await load()
    const canonicalLast = new Set('048AEIMQUYcgkosw')
    for (let i = 0; i < 500; i += 1) {
      const token = generateInviteToken()
      const bytes = Buffer.from(token, 'base64url')
      expect(bytes.length).toBe(shared.MEMBER_INVITE_LIMITS.tokenBytes)
      expect(bytes.length).toBe(32)
      expect(bytes.toString('base64url')).toBe(token)
      expect(canonicalLast.has(token.slice(-1))).toBe(true)
    }
  })

  it('never repeats over 10,000 draws', async () => {
    const { generateInviteToken } = await load()
    const seen = new Set<string>()
    for (let i = 0; i < 10_000; i += 1) seen.add(generateInviteToken())
    expect(seen.size).toBe(10_000)
  })

  it('is roughly uniform: every symbol shows at the first, middle and last full positions; the last character uses 16 symbols', async () => {
    const { generateInviteToken } = await load()
    const draws = 6400
    const positions = [0, 21, 41]
    const tallies = positions.map(() => new Map<string, number>())
    const last = new Map<string, number>()
    for (let i = 0; i < draws; i += 1) {
      const token = generateInviteToken()
      positions.forEach((position, index) => {
        const char = token.charAt(position)
        tallies[index]?.set(char, (tallies[index]?.get(char) ?? 0) + 1)
      })
      last.set(token.slice(-1), (last.get(token.slice(-1)) ?? 0) + 1)
    }
    for (const tally of tallies) {
      expect(tally.size).toBe(64)
      for (const seen of tally.values()) {
        expect(seen).toBeGreaterThan(40)
        expect(seen).toBeLessThan(175)
      }
    }
    expect(last.size).toBe(16)
    for (const seen of last.values()) {
      expect(seen).toBeGreaterThan(270)
      expect(seen).toBeLessThan(530)
    }
  })

  it('does not draw from Math.random and does not depend on the clock', async () => {
    const { generateInviteToken } = await load()
    const random = vi.spyOn(Math, 'random').mockImplementation(() => {
      throw new Error('Math.random is not a secret source')
    })
    vi.useFakeTimers({ toFake: ['Date'] })
    try {
      vi.setSystemTime(0)
      const seen = new Set<string>()
      for (let i = 0; i < 200; i += 1) seen.add(generateInviteToken())
      expect(seen.size).toBe(200)
      expect(random).not.toHaveBeenCalled()
    } finally {
      vi.useRealTimers()
      random.mockRestore()
    }
  })

  it.each(KNOWN_HASHES)('hashInviteToken(%s) is the known lowercase-hex SHA-256 of the token text', async (token, expected) => {
    const { hashInviteToken } = await load()
    expect(hashInviteToken(token)).toBe(expected)
    expect(hashInviteToken(token)).toBe(sha256Hex(token))
  })

  it('hashes the token text, not the decoded bytes, with no salt, key or trimming', async () => {
    const { hashInviteToken } = await load()
    const decoded = createHash('sha256').update(Buffer.from(TOKEN_C, 'base64url')).digest('hex')
    expect(hashInviteToken(TOKEN_C)).not.toBe(decoded)
    expect(hashInviteToken(TOKEN_C)).toBe(sha256Hex(TOKEN_C))
    expect(hashInviteToken(TOKEN_C)).toBe(hashInviteToken(TOKEN_C))
  })

  it('hashes the UTF-8 text of any string without validating it (SHA-256 of "abc", "", "e-acute")', async () => {
    const { hashInviteToken } = await load()
    expect(hashInviteToken('abc')).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
    expect(hashInviteToken('')).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855')
    expect(hashInviteToken('\u00e9')).toBe('4a99557e4033c3539de2eb65472017cad5f9557f7a0625a09f1c3f6e2ba69c4c')
    expect(hashInviteToken(`${TOKEN_C} `)).not.toBe(hashInviteToken(TOKEN_C))
    expect(hashInviteToken(TOKEN_C.toLowerCase())).not.toBe(hashInviteToken(TOKEN_C))
  })

  it('property: 10,000 random tokens hash to 64 lowercase hex characters, match the independent digest and never collide', async () => {
    const { generateInviteToken, hashInviteToken } = await load()
    const hashes = new Set<string>()
    for (let i = 0; i < 10_000; i += 1) {
      const token = i % 2 === 0 ? generateInviteToken() : freshToken()
      const digest = hashInviteToken(token)
      expect(typeof digest).toBe('string')
      expect(digest).toMatch(/^[0-9a-f]{64}$/)
      expect(digest).toBe(sha256Hex(token))
      expect(digest).not.toBe(token)
      hashes.add(digest)
    }
    expect(hashes.size).toBe(10_000)
  }, 30_000)
})

/* ============================================================================================ *
 * 2. INVITE_TOKEN_PATTERN exactness  (INV-018)
 * ============================================================================================ */

describe('INV-018 INVITE_TOKEN_PATTERN is exactly 43 unpadded base64url characters', () => {
  const pattern = () => shared.INVITE_TOKEN_PATTERN

  it('is a RegExp with no global, sticky or multiline flag (a stateful or line-anchored pattern would pass hostile input)', () => {
    expect(pattern()).toBeInstanceOf(RegExp)
    expect(pattern().global).toBe(false)
    expect(pattern().sticky).toBe(false)
    expect(pattern().multiline).toBe(false)
    expect(pattern().ignoreCase).toBe(false)
  })

  it.each([
    ['all A', TOKEN_A],
    ['all lowercase', 'z'.repeat(43)],
    ['all digits', '7'.repeat(43)],
    ['all underscores', '_'.repeat(43)],
    ['all hyphens', '-'.repeat(43)],
    ['mixed', TOKEN_B],
    ['random-looking', TOKEN_C],
    ['starts with dash and underscore', TOKEN_DASH],
  ])('accepts %s', (_label, token) => {
    expect(token).toHaveLength(43)
    expect(pattern().test(token)).toBe(true)
    expect(pattern().test(token)).toBe(true)
  })

  it.each([
    ['42 characters', TOKEN_C.slice(0, 42)],
    ['44 characters', `${TOKEN_C}a`],
    ['empty', ''],
    ['43rd character is padding', `${TOKEN_C.slice(0, 42)}=`],
    ['44 characters with padding', `${TOKEN_C}=`],
    ['standard base64 plus', `${TOKEN_C.slice(0, 42)}+`],
    ['standard base64 slash', `${TOKEN_C.slice(0, 42)}/`],
    ['trailing newline', `${TOKEN_C}\n`],
    ['leading newline', `\n${TOKEN_C}`],
    ['trailing space', `${TOKEN_C} `],
    ['leading tab', `\t${TOKEN_C}`],
    ['two tokens on two lines', `${TOKEN_C}\n${TOKEN_A}`],
    ['inner space', `${TOKEN_C.slice(0, 20)} ${TOKEN_C.slice(21)}`],
    ['NUL', `${TOKEN_C.slice(0, 42)}\0`],
    ['Cyrillic a lookalike', `${'a'.repeat(42)}\u0430`],
    ['fullwidth capital A', '\uff21'.repeat(43)],
    ['fullwidth digit', '\uff11'.repeat(43)],
    ['Kelvin sign (case-folds to k under /iu)', '\u212a'.repeat(43)],
    ['long s (case-folds to s under /iu)', '\u017f'.repeat(43)],
    ['dotless i', '\u0131'.repeat(43)],
    ['combining acute accent', `${'a'.repeat(42)}\u0301`],
    ['zero-width space', `${TOKEN_C.slice(0, 42)}\u200b`],
    ['percent escape', `${TOKEN_C.slice(0, 40)}%41`],
  ])('rejects %s', (_label, value) => {
    expect(pattern().test(value)).toBe(false)
  })

  it('is stateless across repeated calls', () => {
    const outcomes = Array.from({ length: 6 }, () => pattern().test(TOKEN_C))
    expect(new Set(outcomes)).toEqual(new Set([true]))
  })
})

/* ============================================================================================ *
 * 3. parseInviteToken against hostile input  (INV-020, INV-022)
 * ============================================================================================ */

describe('INV-020/INV-022 parseInviteToken', () => {
  const parse = (input: unknown): string | null => shared.parseInviteToken(input as string)
  const hostHttps = (token: string) => `https://fitcruxx.vercel.app/invite/${token}`

  const accepted: Array<{ label: string; input: string; token: string }> = [
    { label: 'a bare token', input: TOKEN_C, token: TOKEN_C },
    { label: 'a bare token starting with dash and underscore', input: TOKEN_DASH, token: TOKEN_DASH },
    { label: 'a bare token with surrounding spaces, tabs and newlines', input: `  \n\t${TOKEN_C}\r\n `, token: TOKEN_C },
    { label: 'an https link', input: hostHttps(TOKEN_C), token: TOKEN_C },
    { label: 'an https link with a port', input: `https://gym.example.com:8443/invite/${TOKEN_B}`, token: TOKEN_B },
    { label: 'an http link (development origin)', input: `http://localhost:3000/invite/${TOKEN_C}`, token: TOKEN_C },
    { label: 'an https link with a query (ignored)', input: `${hostHttps(TOKEN_C)}?utm_source=whatsapp&x=1`, token: TOKEN_C },
    { label: 'an https link with a hash (ignored)', input: `${hostHttps(TOKEN_C)}#section`, token: TOKEN_C },
    { label: 'an https link with query and hash (ignored)', input: `${hostHttps(TOKEN_C)}?a=b#c`, token: TOKEN_C },
    { label: 'an https link wrapped in whitespace', input: `\n  ${hostHttps(TOKEN_C)}  \n`, token: TOKEN_C },
    { label: 'an uppercase host', input: `https://FITCRUXX.VERCEL.APP/invite/${TOKEN_C}`, token: TOKEN_C },
    { label: 'the fitcruxx:// deep link', input: `fitcruxx://invite/${TOKEN_C}`, token: TOKEN_C },
    { label: 'a mixed-case https scheme (keyboards capitalise)', input: `HtTpS://fitcruxx.vercel.app/invite/${TOKEN_C}`, token: TOKEN_C },
    { label: 'a mixed-case custom scheme', input: `FitCruxx://invite/${TOKEN_C}`, token: TOKEN_C },
    { label: 'a mixed-case token inside a link (case is preserved, never normalised)', input: `HTTPS://HOST.EXAMPLE/invite/${TOKEN_B}`, token: TOKEN_B },
  ]
  it.each(accepted)('accepts $label', ({ input, token }) => {
    expect(parse(input)).toBe(token)
  })

  const rejected: Array<{ label: string; input: string }> = [
    { label: 'the empty string', input: '' },
    { label: 'whitespace only', input: '   \n\t ' },
    { label: 'a 42-character token', input: TOKEN_C.slice(0, 42) },
    { label: 'a 44-character token', input: `${TOKEN_C}a` },
    { label: 'a padded token (=)', input: `${TOKEN_C}=` },
    { label: 'a doubly padded token', input: `${TOKEN_C}==` },
    { label: 'a 43-character token whose last character is padding', input: `${TOKEN_C.slice(0, 42)}=` },
    { label: 'standard base64 with +', input: `${TOKEN_C.slice(0, 42)}+` },
    { label: 'standard base64 with /', input: `${TOKEN_C.slice(0, 42)}/` },
    { label: 'a token with an inner space', input: `${TOKEN_C.slice(0, 20)} ${TOKEN_C.slice(21)}` },
    { label: 'two tokens separated by a newline', input: `${TOKEN_C}\n${TOKEN_A}` },
    { label: 'two tokens separated by a space', input: `${TOKEN_C} ${TOKEN_A}` },
    { label: 'a token followed by sentence punctuation', input: `${TOKEN_C}.` },
    { label: 'a link whose token is followed by a dot', input: `${hostHttps(TOKEN_C)}.` },
    { label: 'a quoted token', input: `"${TOKEN_C}"` },
    { label: 'an angle-bracketed token', input: `<${TOKEN_C}>` },
    { label: 'a labelled token', input: `token=${TOKEN_C}` },
    { label: 'a bearer-prefixed token', input: `Bearer ${TOKEN_C}` },
    { label: 'a zero-width space before the token', input: `\u200b${TOKEN_C}` },
    { label: 'a zero-width space after the token', input: `${TOKEN_C}\u200b` },
    { label: 'a right-to-left override before the token', input: `\u202e${TOKEN_C}` },
    { label: 'a Cyrillic lookalike letter', input: `${'a'.repeat(42)}\u0430` },
    { label: 'fullwidth letters', input: '\uff21'.repeat(43) },
    { label: 'fullwidth digits', input: '\uff11'.repeat(43) },
    { label: 'Kelvin sign letters', input: '\u212a'.repeat(43) },
    { label: 'long-s letters', input: '\u017f'.repeat(43) },
    { label: 'a combining mark after 42 letters', input: `${'a'.repeat(42)}\u0301` },
    { label: 'a NUL byte', input: `${TOKEN_C.slice(0, 42)}\0` },
    { label: 'emoji', input: '\u{1f600}'.repeat(22) },
    { label: 'a percent-encoded character in a bare token', input: `${TOKEN_C.slice(0, 40)}%41` },
    { label: 'a link with a percent-encoded token character', input: `https://h.example/invite/%41${TOKEN_C.slice(1)}` },
    { label: 'a link with an encoded slash in the path', input: `https://h.example/invite%2F${TOKEN_C}` },
    { label: 'a link whose token is followed by an encoded newline', input: `https://h.example/invite/${TOKEN_C}%0A` },
    { label: 'a token in the query only', input: `https://h.example/?invite=${TOKEN_C}` },
    { label: 'a token as a query parameter on /invite/', input: `https://h.example/invite/?token=${TOKEN_C}` },
    { label: 'a token behind a hash route', input: `https://h.example/#/invite/${TOKEN_C}` },
    { label: 'the wrong path word', input: `https://h.example/join/${TOKEN_C}` },
    { label: 'an uppercase path word', input: `https://h.example/INVITE/${TOKEN_C}` },
    { label: 'an extra path segment after the token', input: `https://h.example/invite/${TOKEN_C}/extra` },
    { label: 'an extra path segment before /invite/', input: `https://h.example/x/invite/${TOKEN_C}` },
    { label: 'a double slash before the token', input: `https://h.example/invite//${TOKEN_C}` },
    { label: 'an empty authority', input: `https:///invite/${TOKEN_C}` },
    { label: 'userinfo before the host (credential smuggling)', input: `https://evil@h.example/invite/${TOKEN_C}` },
    { label: 'userinfo with a password', input: `https://user:pw@h.example/invite/${TOKEN_C}` },
    { label: 'a javascript: URL', input: `javascript:alert(1)//invite/${TOKEN_C}` },
    { label: 'a javascript: URL in authority form', input: `javascript://h.example/invite/${TOKEN_C}` },
    { label: 'a javascript: URL with an encoded newline payload', input: `javascript://h.example/invite/${TOKEN_C}%0Aalert(1)` },
    { label: 'a data: URL', input: `data:text/html,https://h.example/invite/${TOKEN_C}` },
    { label: 'an ftp: URL', input: `ftp://h.example/invite/${TOKEN_C}` },
    { label: 'a file: URL', input: `file:///invite/${TOKEN_C}` },
    { label: 'a protocol-relative URL', input: `//h.example/invite/${TOKEN_C}` },
    { label: 'a scheme-less host and path', input: `h.example/invite/${TOKEN_C}` },
    { label: 'a bare path', input: `/invite/${TOKEN_C}` },
    { label: 'the custom scheme with the wrong host', input: `fitcruxx://evil/invite/${TOKEN_C}` },
    { label: 'another custom scheme', input: `gymloop://invite/${TOKEN_C}` },
    { label: 'a mailto: URL carrying a link', input: `mailto:a@b.example?body=https://h.example/invite/${TOKEN_C}` },
    { label: 'two links on two lines', input: `${hostHttps(TOKEN_C)}\n${hostHttps(TOKEN_A)}` },
    { label: 'text before the link', input: `Join us: ${hostHttps(TOKEN_C)}` },
    { label: 'text after the link', input: `${hostHttps(TOKEN_C)} thanks` },
    { label: 'a newline injected into the path (URL parsers strip it silently)', input: `https://h.example/inv\nite/${TOKEN_C}` },
    { label: 'a carriage return and tab injected into the path', input: `https://h.example/invite/\r\t${TOKEN_C}` },
    { label: 'a newline injected into the scheme', input: `ht\ntps://h.example/invite/${TOKEN_C}` },
    { label: 'a script payload on a second line', input: `${TOKEN_C}\njavascript:alert(1)` },
    { label: 'a 100,000-character junk string', input: 'x'.repeat(100_000) },
    { label: 'a link with a 100,000-character token', input: `https://h.example/invite/${'A'.repeat(100_000)}` },
    { label: 'a valid token with 100,000 characters appended', input: `${TOKEN_C}${'a'.repeat(100_000)}` },
  ]
  it.each(rejected)('returns null for $label', ({ input }) => {
    expect(parse(input)).toBeNull()
  })

  it.each([undefined, null, 0, 1, true, {}, [], () => TOKEN_C])(
    'returns null (never throws) for the non-string value %#',
    (value) => {
      expect(() => parse(value)).not.toThrow()
      expect(parse(value)).toBeNull()
    },
  )

  it('finishes pathological inputs quickly (no catastrophic backtracking) and still parses a wrapped valid token', () => {
    const cases: Array<[string, string | null]> = [
      [`${' '.repeat(200_000)}x`, null],
      [`https://${'a/'.repeat(100_000)}`, null],
      [`https://h.example/invite/${'A'.repeat(500_000)}`, null],
      ['/'.repeat(300_000), null],
      [`${`${'a'.repeat(5000)} `.repeat(40)}`, null],
      [`https://${'a.'.repeat(100_000)}/invite/${TOKEN_C}`, TOKEN_C],
      [`https://${'@'.repeat(100_000)}/invite/${TOKEN_C}`, null],
      [`${'\n'.repeat(100_000)}${TOKEN_C}${'\n'.repeat(100_000)}`, TOKEN_C],
      [`https://h.example/invite/${TOKEN_C}?${'q=1&'.repeat(50_000)}`, TOKEN_C],
    ]
    for (const [input, expected] of cases) {
      const started = performance.now()
      expect(parse(input)).toBe(expected)
      expect(performance.now() - started).toBeLessThan(1500)
    }
  }, 30_000)

  it('property (seeded, reproducible): a non-null result is always a valid token that literally occurs in the input', () => {
    // mulberry32: small deterministic PRNG so a failure here can be replayed exactly.
    let state = 0x9e3779b9
    const next = (): number => {
      state = (state + 0x6d2b79f5) | 0
      let t = Math.imul(state ^ (state >>> 15), 1 | state)
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
    const pick = <T>(items: readonly T[]): T => items[Math.floor(next() * items.length)] as T
    const alphabet = `${TOKEN_C}/:?#@.%=\n\t \\"'<>[]{}()$&*+;,~\`!|^invite_https://fitcruxx\u200b\u0430\u212a`
    const fragments = [
      '', ' ', '\n', '\t', '.', ',', '=', '/', '?q=1', '#f', '%41', '%0A', '@', 'x', '\u200b', 'javascript:', 'https://h.example/invite/',
      'fitcruxx://invite/', 'http://localhost:3000/invite/', '//', '../', '\\',
    ]
    let accepted = 0
    for (let i = 0; i < 4000; i += 1) {
      const length = Math.floor(next() * 140)
      let candidate = ''
      for (let c = 0; c < length; c += 1) candidate += alphabet.charAt(Math.floor(next() * alphabet.length))
      if (i % 2 === 1) candidate = `${pick(fragments)}${pick(fragments)}${TOKEN_C}${pick(fragments)}${pick(fragments)}`
      const result = parse(candidate)
      if (result !== null) {
        accepted += 1
        expect(shared.INVITE_TOKEN_PATTERN.test(result)).toBe(true)
        expect(candidate).toContain(result)
      }
    }
    expect(accepted).toBeGreaterThan(0)
  })

  it('property: parse is the identity on random bare tokens, https links and fitcruxx links', () => {
    for (let i = 0; i < 600; i += 1) {
      const token = freshToken()
      expect(parse(token)).toBe(token)
      expect(parse(` ${token}\n`)).toBe(token)
      expect(parse(`https://gym.example.co.in/invite/${token}`)).toBe(token)
      expect(parse(`fitcruxx://invite/${token}`)).toBe(token)
    }
  })
})

/* ============================================================================================ *
 * 4. buildInviteLink  (INV-018, INV-020)
 * ============================================================================================ */

describe('INV-018 buildInviteLink', () => {
  const build = (origin: string, token: string): string => shared.buildInviteLink(origin, token)

  it.each(['https://fitcruxx.vercel.app', 'http://localhost:3000', 'http://127.0.0.1:3000', 'https://gym.example.co.in:8443'])(
    'builds <origin>/invite/<token> for %s',
    (origin) => {
      expect(build(origin, TOKEN_C)).toBe(`${origin}/invite/${TOKEN_C}`)
    },
  )

  it.each(['https://fitcruxx.vercel.app/', 'https://fitcruxx.vercel.app//', 'http://localhost:3000/'])(
    'never produces a double slash even if the origin has trailing slashes (%s)',
    (origin) => {
      const link = build(origin, TOKEN_C)
      expect(link.replace(/^https?:\/\//, '')).not.toContain('//')
      expect(link).toBe(`${origin.replace(/\/+$/, '')}/invite/${TOKEN_C}`)
    },
  )

  it('never adds a query string or fragment and keeps the token as the whole last path segment', () => {
    for (let i = 0; i < 200; i += 1) {
      const token = freshToken()
      const link = build('https://fitcruxx.vercel.app', token)
      expect(link).not.toMatch(/[?#]/)
      const url = new URL(link)
      expect(url.search).toBe('')
      expect(url.hash).toBe('')
      expect(url.pathname).toBe(`/invite/${token}`)
      expect(url.username).toBe('')
    }
  })

  it('round-trips through parseInviteToken for random tokens and several origins', () => {
    const origins = ['https://fitcruxx.vercel.app', 'http://localhost:3000', 'http://127.0.0.1:3000', 'https://a.b.example.co.in']
    for (let i = 0; i < 400; i += 1) {
      const token = freshToken()
      const origin = origins[i % origins.length] as string
      expect(shared.parseInviteToken(build(origin, token))).toBe(token)
    }
  })

  it.each(['abc?x=1', 'abc#frag', 'a/b', '../x', 'a b', ''])(
    'cannot be used to inject a query, fragment or extra path segment through the token (%j)',
    (token) => {
      let link: string | null = null
      try {
        link = build('https://fitcruxx.vercel.app', token)
      } catch {
        link = null
      }
      if (link !== null) {
        const url = new URL(link)
        expect(url.search).toBe('')
        expect(url.hash).toBe('')
        expect(url.host).toBe('fitcruxx.vercel.app')
        expect(url.pathname.split('/')).toHaveLength(3)
      }
    },
  )
})

/* ============================================================================================ *
 * 5. Request schemas  (INV-018)
 * ============================================================================================ */

describe('INV-018 request schemas', () => {
  const json = (text: string): unknown => JSON.parse(text)

  describe('inviteIssueRequestSchema', () => {
    const parse = (value: unknown) => shared.inviteIssueRequestSchema.safeParse(value)
    it('accepts exactly { memberId: uuid } and returns a clean plain object', () => {
      const result = parse({ memberId: UUID_1 })
      expect(result.success).toBe(true)
      if (result.success) {
        expect(result.data).toEqual({ memberId: UUID_1 })
        expect(Object.keys(result.data)).toEqual(['memberId'])
        expect(Object.getPrototypeOf(result.data)).toBe(Object.prototype)
      }
    })
    it.each([
      ['no memberId', {}],
      ['extra key', { memberId: UUID_1, tenantId: UUID_2 }],
      ['extra key with the revoke field', { memberId: UUID_1, inviteId: UUID_2 }],
      ['the revoke field instead', { inviteId: UUID_1 }],
      ['non-uuid text', { memberId: 'not-a-uuid' }],
      ['empty string', { memberId: '' }],
      ['numeric', { memberId: 12345 }],
      ['null', { memberId: null }],
      ['array', { memberId: [UUID_1] }],
      ['object', { memberId: { toString: UUID_1 } }],
      ['uuid with surrounding space', { memberId: ` ${UUID_1} ` }],
      ['uuid without dashes', { memberId: UUID_1.replaceAll('-', '') }],
      ['braced uuid', { memberId: `{${UUID_1}}` }],
      ['uuid plus suffix', { memberId: `${UUID_1}x` }],
      ['uuid with newline', { memberId: `${UUID_1}\n` }],
      ['null body', null],
      ['array body', [{ memberId: UUID_1 }]],
      ['string body', UUID_1],
      ['undefined body', undefined],
    ])('rejects %s', (_label, value) => {
      expect(parse(value).success).toBe(false)
    })
    it('rejects prototype-pollution keys supplied through JSON.parse and never pollutes Object.prototype', () => {
      for (const text of [
        `{"memberId":"${UUID_1}","__proto__":{"polluted":true}}`,
        `{"memberId":"${UUID_1}","constructor":{"prototype":{"polluted":true}}}`,
        `{"memberId":"${UUID_1}","prototype":{"polluted":true}}`,
        `{"__proto__":{"memberId":"${UUID_1}"}}`,
      ]) {
        expect(parse(json(text)).success).toBe(false)
      }
      expect(({} as Record<string, unknown>).polluted).toBeUndefined()
    })
  })

  describe('inviteRevokeRequestSchema', () => {
    const parse = (value: unknown) => shared.inviteRevokeRequestSchema.safeParse(value)
    it('accepts exactly { inviteId: uuid }', () => {
      const result = parse({ inviteId: UUID_2 })
      expect(result.success).toBe(true)
      if (result.success) expect(result.data).toEqual({ inviteId: UUID_2 })
    })
    it.each([
      ['no inviteId', {}],
      ['memberId instead', { memberId: UUID_1 }],
      ['extra key', { inviteId: UUID_2, memberId: UUID_1 }],
      ['non-uuid', { inviteId: 'invite-1' }],
      ['uuid with space', { inviteId: `${UUID_2} ` }],
      ['null', { inviteId: null }],
      ['number', { inviteId: 7 }],
      ['null body', null],
    ])('rejects %s', (_label, value) => {
      expect(parse(value).success).toBe(false)
    })
    it('rejects prototype-pollution keys', () => {
      expect(parse(json(`{"inviteId":"${UUID_2}","__proto__":{"x":1}}`)).success).toBe(false)
      expect(parse(json(`{"inviteId":"${UUID_2}","constructor":{"x":1}}`)).success).toBe(false)
      expect(({} as Record<string, unknown>).x).toBeUndefined()
    })
  })

  describe('inviteRedeemRequestSchema', () => {
    const parse = (value: unknown) => shared.inviteRedeemRequestSchema.safeParse(value)
    it('accepts exactly { token } and does not transform it', () => {
      for (const token of [TOKEN_A, TOKEN_B, TOKEN_C, TOKEN_DASH]) {
        const result = parse({ token })
        expect(result.success).toBe(true)
        if (result.success) expect(result.data).toEqual({ token })
      }
    })
    it.each([
      ['a leading space', { token: ` ${TOKEN_C}` }],
      ['a trailing newline', { token: `${TOKEN_C}\n` }],
      ['a trailing tab', { token: `${TOKEN_C}\t` }],
      ['an inner space', { token: `${TOKEN_C.slice(0, 20)} ${TOKEN_C.slice(21)}` }],
      ['padding', { token: `${TOKEN_C}=` }],
      ['42 characters', { token: TOKEN_C.slice(0, 42) }],
      ['44 characters', { token: `${TOKEN_C}a` }],
      ['an empty token', { token: '' }],
      ['a full link instead of a bare token', { token: `https://h.example/invite/${TOKEN_C}` }],
      ['a custom-scheme link', { token: `fitcruxx://invite/${TOKEN_C}` }],
      ['a unicode lookalike', { token: `${'a'.repeat(42)}\u0430` }],
      ['a numeric token', { token: 12345 }],
      ['an array token', { token: [TOKEN_C] }],
      ['an object token with toString', { token: { toString: () => TOKEN_C } }],
      ['a missing token', {}],
      ['an extra key', { token: TOKEN_C, memberId: UUID_1 }],
      ['an extra key named like a hash', { token: TOKEN_C, tokenHash: sha256Hex(TOKEN_C) }],
      ['a null body', null],
      ['a bare string body', TOKEN_C],
    ])('rejects %s', (_label, value) => {
      expect(parse(value).success).toBe(false)
    })
    it('rejects prototype-pollution keys', () => {
      expect(parse(json(`{"token":"${TOKEN_C}","__proto__":{"admin":true}}`)).success).toBe(false)
      expect(parse(json(`{"token":"${TOKEN_C}","constructor":{"prototype":{"admin":true}}}`)).success).toBe(false)
      expect(({} as Record<string, unknown>).admin).toBeUndefined()
    })
  })

  describe('memberUnlinkRequestSchema', () => {
    const parse = (value: unknown) => shared.memberUnlinkRequestSchema.safeParse(value)
    it('accepts a uuid and a trimmed reason of 3..200 characters, and returns the trimmed reason', () => {
      const result = parse({ memberId: UUID_1, reason: '  abc  ' })
      expect(result.success).toBe(true)
      if (result.success) {
        expect(result.data).toEqual({ memberId: UUID_1, reason: 'abc' })
        expect(Object.keys(result.data).sort()).toEqual(['memberId', 'reason'])
      }
      const edge = parse({ memberId: UUID_1, reason: ` ${'r'.repeat(200)} ` })
      expect(edge.success).toBe(true)
      if (edge.success) expect(edge.data.reason).toBe('r'.repeat(200))
      expect(parse({ memberId: UUID_1, reason: 'a\tb' }).success).toBe(true)
    })
    it.each([
      ['a reason of 2 characters', { memberId: UUID_1, reason: 'ab' }],
      ['a reason that is 2 characters once trimmed', { memberId: UUID_1, reason: '   ab   ' }],
      ['a whitespace-only reason', { memberId: UUID_1, reason: '          ' }],
      ['a newline-and-tab-only reason', { memberId: UUID_1, reason: '\n\t \r\n\t' }],
      ['a no-break-space-only reason', { memberId: UUID_1, reason: '\u00a0\u00a0\u00a0\u00a0\u00a0' }],
      ['an empty reason', { memberId: UUID_1, reason: '' }],
      ['a reason of 201 characters', { memberId: UUID_1, reason: 'r'.repeat(201) }],
      ['a reason of 201 characters once trimmed', { memberId: UUID_1, reason: `  ${'r'.repeat(201)}  ` }],
      ['a missing reason', { memberId: UUID_1 }],
      ['a numeric reason', { memberId: UUID_1, reason: 123456 }],
      ['a null reason', { memberId: UUID_1, reason: null }],
      ['an array reason', { memberId: UUID_1, reason: ['because'] }],
      ['a missing memberId', { reason: 'because' }],
      ['a non-uuid memberId', { memberId: 'member', reason: 'because' }],
      ['an extra key', { memberId: UUID_1, reason: 'because', userId: UUID_2 }],
      ['an extra tenant key', { memberId: UUID_1, reason: 'because', tenantId: UUID_2 }],
      ['a null body', null],
    ])('rejects %s', (_label, value) => {
      expect(parse(value).success).toBe(false)
    })
    it('rejects prototype-pollution keys', () => {
      expect(parse(json(`{"memberId":"${UUID_1}","reason":"because","__proto__":{"p":1}}`)).success).toBe(false)
      expect(parse(json(`{"memberId":"${UUID_1}","reason":"because","constructor":{"p":1}}`)).success).toBe(false)
      expect(({} as Record<string, unknown>).p).toBeUndefined()
    })
  })
})

/* ============================================================================================ *
 * 6. Outcomes and refusal copy  (INV-008, INV-023)
 * ============================================================================================ */

describe('INV-008/INV-023 redeem outcomes and refusal copy', () => {
  it('INVITE_REDEEM_OUTCOMES is exactly the seven outcomes in the contract order', () => {
    expect([...shared.INVITE_REDEEM_OUTCOMES]).toEqual([
      'linked',
      'already_linked_here',
      'invite_unavailable',
      'email_mismatch',
      'identity_unverified',
      'account_already_linked',
      'rate_limited',
    ])
    expect(new Set(shared.INVITE_REDEEM_OUTCOMES).size).toBe(7)
  })

  it('INVITE_REFUSAL_COPY has exactly the five refusal keys and the five verbatim sentences', () => {
    expect(Object.keys(shared.INVITE_REFUSAL_COPY).sort()).toEqual([...REFUSAL_CODES].sort())
    expect(shared.INVITE_REFUSAL_COPY).toEqual(COPY)
    const refusals = shared.INVITE_REDEEM_OUTCOMES.filter((outcome) => outcome !== 'linked' && outcome !== 'already_linked_here')
    expect([...refusals].sort()).toEqual(Object.keys(shared.INVITE_REFUSAL_COPY).sort())
  })

  it.each(REFUSAL_CODES)('inviteRefusalMessage(%s) returns its sentence verbatim', (code) => {
    expect(shared.inviteRefusalMessage(code)).toBe(COPY[code])
  })

  it.each([
    '',
    ' ',
    'linked',
    'already_linked_here',
    'unknown',
    'INVITE_UNAVAILABLE',
    'Email_Mismatch',
    ' email_mismatch',
    'email_mismatch ',
    'email_mismatch\n',
    'email_mismatch\0',
    'email_mismatch.',
    'email-mismatch',
    'emailMismatch',
    'rate_limited,email_mismatch',
    '__proto__',
    'constructor',
    'prototype',
    'toString',
    'valueOf',
    'hasOwnProperty',
    'isPrototypeOf',
    'propertyIsEnumerable',
    'toLocaleString',
    '__defineGetter__',
    '__lookupGetter__',
    'x'.repeat(100_000),
  ])('inviteRefusalMessage(%j) falls back to the invite_unavailable sentence (a string, never undefined or inherited)', (code) => {
    let message: unknown
    expect(() => {
      message = shared.inviteRefusalMessage(code)
    }).not.toThrow()
    expect(typeof message).toBe('string')
    expect(message).toBe(COPY.invite_unavailable)
  })

  it.each([undefined, null, 0, 1, true, {}, []])(
    'inviteRefusalMessage never throws for the non-string value %#',
    (value) => {
      let message: unknown
      expect(() => {
        message = shared.inviteRefusalMessage(value as never)
      }).not.toThrow()
      expect(typeof message).toBe('string')
      expect(message).toBe(COPY.invite_unavailable)
    },
  )

  it('hostile lookups leave Object.prototype untouched', () => {
    for (const code of ['__proto__', 'constructor', 'toString']) shared.inviteRefusalMessage(code)
    expect(Object.keys(Object.prototype)).toEqual([])
    expect(({} as Record<string, unknown>).invite_unavailable).toBeUndefined()
  })

  describe('no refusal sentence is an existence oracle', () => {
    const nonD1 = ['invite_unavailable', 'email_mismatch', 'identity_unverified', 'rate_limited'] as const

    it.each(nonD1)('%s never says "member", "exist", "registered" or "found" and holds no e-mail address', (code) => {
      const sentence = shared.inviteRefusalMessage(code)
      expect(sentence).not.toMatch(/\bmembers?\b/i)
      expect(sentence).not.toMatch(/exist/i)
      expect(sentence).not.toMatch(/registered/i)
      expect(sentence).not.toMatch(/\bnot found\b/i)
      expect(sentence).not.toMatch(/\bfound\b/i)
      expect(sentence).not.toMatch(/[^\s@]+@[^\s@]+/)
    })

    it('only the D1 sentence mentions being joined as a member, and even it names no gym, address or number', () => {
      const d1 = shared.inviteRefusalMessage('account_already_linked')
      expect(d1).toBe(COPY.account_already_linked)
      expect(d1).toMatch(/already joined as a member/)
      expect(d1).not.toMatch(/exist/i)
      expect(d1).not.toMatch(/registered/i)
      expect(d1).not.toMatch(/found/i)
      expect(d1).not.toMatch(/[^\s@]+@[^\s@]+/)
    })

    it('no sentence holds a digit (no invented numbers) and every sentence is one trimmed, single-line, ASCII-apostrophe string', () => {
      for (const code of REFUSAL_CODES) {
        const sentence = shared.inviteRefusalMessage(code)
        expect(sentence).not.toMatch(/\d/)
        expect(sentence).toBe(sentence.trim())
        expect(sentence).not.toMatch(/[\r\n]/)
        expect(sentence).not.toMatch(/[\u2018\u2019\u201c\u201d]/)
        expect(sentence.endsWith('.')).toBe(true)
      }
      expect(new Set(REFUSAL_CODES.map((code) => shared.inviteRefusalMessage(code))).size).toBe(5)
    })

    it('the four causes that collapse into invite_unavailable are not distinguished by the copy', () => {
      const sentence = shared.inviteRefusalMessage('invite_unavailable')
      expect(sentence).not.toMatch(/revoked|cancelled|canceled|blocked|erased|replaced by|used already|redeemed/i)
    })
  })
})

/* ============================================================================================ *
 * 7. Share message and DPDP notice  (INV-020, INV-023)
 * ============================================================================================ */

describe('INV-020/INV-023 inviteShareMessage and inviteNotice', () => {
  const link = `https://fitcruxx.vercel.app/invite/${TOKEN_C}`
  const input = { memberName: 'Asha Verma', gymName: 'Iron Box Fitness', email: 'asha@example.com', link }
  const shareFor = (first: string, fields: { gymName: string; email: string; link: string }) =>
    `Hi ${first}, ${fields.gymName} invited you to join on FitCruxx. Open this link and sign in with Google using ${fields.email} so your membership connects: ${fields.link}`
  const noticeFor = (gym: string) =>
    `By linking, you let ${gym} connect this Google account (your name and email) to your membership record. FitCruxx processes it on ${gym}'s behalf to show you your visits, payments and messages. Ask ${gym} to unlink it at any time.`

  it('produces the exact example from the contract (first name only)', () => {
    expect(shared.inviteShareMessage(input)).toBe(
      `Hi Asha, Iron Box Fitness invited you to join on FitCruxx. Open this link and sign in with Google using asha@example.com so your membership connects: ${link}`,
    )
  })

  it.each([
    ['Asha', 'Asha'],
    ['Asha Verma', 'Asha'],
    ['  Asha   Verma  ', 'Asha'],
    ['Asha\tVerma', 'Asha'],
    ['Asha\nVerma', 'Asha'],
    ['Asha-Lee Verma', 'Asha-Lee'],
    ["D'Souza Rahul", "D'Souza"],
    ['\u00dcnal \u00c7elik', '\u00dcnal'],
    ['{gym} Rahul', '{gym}'],
    ['$& Rahul', '$&'],
    ['${gymName} Rahul', '${gymName}'],
    ['Madonna', 'Madonna'],
  ])('uses the first name of %j', (memberName, first) => {
    const message = shared.inviteShareMessage({ ...input, memberName })
    expect(message).toBe(shareFor(first, input))
    expect(message).not.toContain('Verma')
  })

  it.each([
    '{link}',
    '{email}',
    '{gym}',
    '{{gymName}}',
    '${gymName}',
    '${link}',
    '$&',
    "$'",
    '$`',
    '$1',
    '$$',
    'A&B <Fitness>',
    'He said "hi"',
    "O'Brien's Gym",
    'Iron\nBox',
    'Gym \u{1f600}',
    '%s %d %j',
    '\\n \\u0041',
    '</script><script>alert(1)</script>',
    'x'.repeat(10_000),
  ])('passes the gym name %j through unmodified, with the link once and the email once', (gymName) => {
    const message = shared.inviteShareMessage({ ...input, gymName })
    expect(message).toBe(shareFor('Asha', { gymName, email: input.email, link }))
    expect(count(message, link)).toBe(1)
    expect(count(message, 'asha@example.com')).toBe(1)
  })

  it.each([
    { email: 'us$&er@example.com', link },
    { email: 'a$1@example.com', link: `${link}?x=$&y` },
    { email: 'plain@example.com', link: 'https://x.test/invite/a$&b' },
    { email: 'plain@example.com', link: "https://x.test/invite/$'`$$" },
  ])('passes email and link through verbatim even with replacement-pattern characters (%j)', (fields) => {
    const message = shared.inviteShareMessage({ ...input, ...fields })
    expect(message).toBe(shareFor('Asha', { gymName: input.gymName, ...fields }))
    expect(count(message, fields.email)).toBe(1)
    expect(count(message, fields.link)).toBe(1)
  })

  it('does not invent "undefined", "null" or "NaN" for a missing or blank member name and still carries the link and email once', () => {
    for (const memberName of ['', '   ']) {
      const message = shared.inviteShareMessage({ ...input, memberName })
      expect(message).not.toMatch(/undefined|null|NaN/)
      expect(count(message, link)).toBe(1)
      expect(count(message, 'asha@example.com')).toBe(1)
    }
  })

  it('inviteNotice is the exact DPDP sentence with the gym name three times', () => {
    const notice = shared.inviteNotice('Iron Box Fitness')
    expect(notice).toBe(noticeFor('Iron Box Fitness'))
    expect(count(notice, 'Iron Box Fitness')).toBe(3)
    expect(notice).not.toMatch(/\d/)
    expect(notice).not.toMatch(/\{gym\}/)
  })

  it.each(['{gym}', '$&', "$'", '$`', '$1', '$$', '${gym}', 'A & B', "O'Brien's Gym", 'Iron\nBox', '"Quoted" Gym', '', '\u{1f600}'])(
    'inviteNotice passes the gym name %j through with no substitution mangling',
    (gym) => {
      expect(shared.inviteNotice(gym)).toBe(noticeFor(gym))
    },
  )
})

/* ============================================================================================ *
 * 8. Constants  (INV-006, INV-010, INV-021)
 * ============================================================================================ */

describe('INV-006/INV-010/INV-021 constants', () => {
  it('MEMBER_INVITE_LIMITS carries exactly the numbers in the proposal', () => {
    expect(shared.MEMBER_INVITE_LIMITS).toEqual({
      ttlHours: 48,
      tenantIssuesPerHour: 100,
      memberIssuesPerDay: 5,
      redeemFailuresPerWindow: 10,
      redeemWindowMinutes: 15,
      tokenBytes: 32,
      cookieMaxAgeSeconds: 1800,
    })
  })

  it('is internally consistent with the EARS rows (48 h expiry, 30-minute cookie, 32-byte token = 43 characters)', () => {
    const limits = shared.MEMBER_INVITE_LIMITS
    expect(limits.ttlHours * 3600).toBe(172_800)
    expect(limits.cookieMaxAgeSeconds).toBe(30 * 60)
    expect(Math.ceil((limits.tokenBytes * 8) / 6)).toBe(43)
    expect(Object.values(limits).every((value) => Number.isInteger(value) && value > 0)).toBe(true)
  })

  it('INVITE_COOKIE_NAME is fitcruxx_invite', () => {
    expect(shared.INVITE_COOKIE_NAME).toBe('fitcruxx_invite')
  })
})

/* ============================================================================================ *
 * 9. Pure web libs that talk to the database  (INV-012, INV-015)
 * ============================================================================================ */

describe('INV-012/INV-015 apps/web/lib/member-invites', () => {
  const load = () => import('../../apps/web/lib/member-invites')

  it('peekInvite sends only the SHA-256 of the token to peek_member_invite and returns { gymName }', async () => {
    const { peekInvite } = await load()
    const { client, calls } = fakeRpcClient(({ name, args }) => ({
      data: name === 'peek_member_invite' && args.p_token_hash === sha256Hex(TOKEN_C) ? [{ gym_name: 'Iron Box Fitness' }] : [],
      error: null,
    }))
    const result = await peekInvite(client as never, TOKEN_C)
    expect(result).toEqual({ gymName: 'Iron Box Fitness' })
    expect(calls).toHaveLength(1)
    expect(calls[0]).toEqual({ name: 'peek_member_invite', args: { p_token_hash: sha256Hex(TOKEN_C) } })
    expect(JSON.stringify(calls)).not.toContain(TOKEN_C)
  })

  it('peekInvite returns null for zero rows, a null result and any RPC error, and never throws', async () => {
    const { peekInvite } = await load()
    for (const outcome of [
      { data: [], error: null },
      { data: null, error: null },
      { data: null, error: { code: '22023', message: 'malformed hash' } },
      { data: null, error: { code: '42501', message: 'denied' } },
      { data: null, error: 'boom' },
    ] as RpcOutcome[]) {
      const { client } = fakeRpcClient(() => outcome)
      await expect(peekInvite(client as never, TOKEN_C)).resolves.toBeNull()
    }
    const thrown = fakeRpcClient(() => {
      throw new Error('network down')
    })
    await expect(peekInvite(thrown.client as never, TOKEN_C)).resolves.toBeNull()
  })

  it('peekInvite returns only the gym name, never other columns, and fails closed on odd rows', async () => {
    const { peekInvite } = await load()
    const wide = fakeRpcClient(() => ({
      data: [{ gym_name: 'Iron Box Fitness', member_id: UUID_1, email: 'asha@example.com', status: 'pending' }],
      error: null,
    }))
    const result = await peekInvite(wide.client as never, TOKEN_C)
    expect(result).toEqual({ gymName: 'Iron Box Fitness' })
    expect(JSON.stringify(result)).not.toMatch(/asha@example\.com|member_id|pending/)
    for (const data of [[{ gym_name: null }], [{ gym_name: '' }], [{}]]) {
      const odd = fakeRpcClient(() => ({ data, error: null }))
      await expect(peekInvite(odd.client as never, TOKEN_C)).resolves.toBeNull()
    }
  })

  it('peekInvite never forwards a raw token: for any call made, the only argument is the 64-hex hash of the exact text', async () => {
    const { peekInvite } = await load()
    for (const token of [TOKEN_A, TOKEN_B, TOKEN_D, TOKEN_DASH, 'garbage', '', `${TOKEN_C}=`]) {
      const { client, calls } = fakeRpcClient(() => ({ data: [], error: null }))
      await expect(peekInvite(client as never, token)).resolves.toBeNull()
      for (const call of calls) {
        expect(Object.keys(call.args)).toEqual(['p_token_hash'])
        expect(call.args.p_token_hash).toBe(sha256Hex(token))
        if (token.length >= 8) expect(JSON.stringify(call)).not.toContain(token)
      }
    }
  })

  it('loadMemberAppAccess calls read_member_app_access once with { p_member_id } and carries the state through', async () => {
    const { loadMemberAppAccess } = await load()
    const row = { state: 'invite_pending', invite_id: UUID_2, issued_at: '2026-10-02T10:00:00.000Z', expires_at: '2026-10-04T10:00:00.000Z', linked_at: null }
    const { client, calls } = fakeRpcClient(() => ({ data: [row], error: null }))
    const result = await loadMemberAppAccess(client as never, UUID_1)
    expect(calls).toEqual([{ name: 'read_member_app_access', args: { p_member_id: UUID_1 } }])
    expect(JSON.stringify(result)).toContain('invite_pending')
  })
})

/* ============================================================================================ *
 * 10. Route handlers  (INV-001..INV-011, INV-014, INV-018, INV-021)
 * ============================================================================================ */

type Claims = Record<string, unknown>
type RouteKey = 'issue' | 'revoke' | 'unlink' | 'redeem'
type Transport = 'cookie' | 'bearer' | 'mixed'
type CookieOp = { op: 'set' | 'delete'; name: string; value?: string; options?: Record<string, unknown> }

const IDS = {
  user: 'b1000000-0000-4000-8000-000000000001',
  otherUser: 'b1000000-0000-4000-8000-00000000000a',
  tenant: 'b1000000-0000-4000-8000-000000000002',
  staff: 'b1000000-0000-4000-8000-000000000003',
  member: 'b1000000-0000-4000-8000-000000000004',
  invite: 'b1000000-0000-4000-8000-000000000005',
  superseded: 'b1000000-0000-4000-8000-000000000006',
  linkedMember: 'b1000000-0000-4000-8000-000000000007',
  preview: 'b1000000-0000-4000-8000-000000000008',
} as const

const GYM = 'Iron Box Fitness'
const REASON = 'Member moved to a new Google account'
const LEAK = 'LEAKSENTINEL-9f3a'
const LEAK_EMAIL = 'leaked.person@example.com'
const EXPIRES = '2026-10-04T10:00:00.000Z'
const ORIGIN = 'https://gym.example'
const OAUTH_URL = 'https://project.supabase.co/auth/v1/authorize?provider=google'
const SESSION_COOKIE = 'sb-gymtest-auth-token=base64-session-value'
const BEARER = 'Bearer header.payload.signature'

const authed = { sub: IDS.user, role: 'authenticated' }
const SESSION = {
  owner: { ...authed, app_role: 'gym_owner', tenant_id: IDS.tenant, staff_id: IDS.staff },
  manager: { ...authed, app_role: 'gym_manager', tenant_id: IDS.tenant, staff_id: IDS.staff },
  frontDesk: { ...authed, app_role: 'front_desk', tenant_id: IDS.tenant, staff_id: IDS.staff },
  trainer: { ...authed, app_role: 'trainer', tenant_id: IDS.tenant, staff_id: IDS.staff },
  member: { ...authed, app_role: 'member', tenant_id: IDS.tenant, member_id: IDS.linkedMember },
  platform: { ...authed, app_role: 'super_admin' },
  preview: { ...authed, app_role: 'gym_owner', tenant_id: IDS.tenant, impersonation_session_id: IDS.preview },
  unlinked: { ...authed },
} satisfies Record<string, Claims>

const PATHS: Record<RouteKey, string> = {
  issue: '/api/member-invites',
  revoke: '/api/member-invites/revoke',
  unlink: '/api/member-identity/unlink',
  redeem: '/api/member-invites/redeem',
}
const RPC_NAME: Record<RouteKey, string> = {
  issue: 'issue_member_invite',
  revoke: 'revoke_member_invite',
  unlink: 'unlink_member_identity',
  redeem: 'redeem_member_invite',
}
const VALID_BODY: Record<RouteKey, () => Record<string, unknown>> = {
  issue: () => ({ memberId: IDS.member }),
  revoke: () => ({ inviteId: IDS.invite }),
  unlink: () => ({ memberId: IDS.member, reason: REASON }),
  redeem: () => ({ token: TOKEN_C }),
}
const SUCCESS_RPC: Record<RouteKey, RpcOutcome> = {
  issue: { data: [{ invite_id: IDS.invite, expires_at: EXPIRES, superseded_invite_id: null }], error: null },
  revoke: { data: IDS.invite, error: null },
  unlink: { data: null, error: null },
  redeem: { data: [{ outcome: 'linked', gym_name: GYM }], error: null },
}
const FRONT_OFFICE = ['gym_owner', 'gym_manager', 'front_desk']
const ROLES_FOR: Record<RouteKey, string[] | null> = {
  issue: FRONT_OFFICE,
  revoke: FRONT_OFFICE,
  unlink: ['gym_owner', 'gym_manager'],
  redeem: null,
}
const ROUTE_KEYS: RouteKey[] = ['issue', 'revoke', 'unlink', 'redeem']

function freshWorld() {
  return {
    claims: null as Claims | null,
    claimsError: null as unknown,
    postRefreshClaims: null as Claims | null,
    getUserOverride: undefined as undefined | { id: string } | null,
    exchangeError: null as unknown,
    rpc: ((call: RpcCall): RpcOutcome => ({ data: null, error: { code: 'XX000', message: `rpc not scripted: ${call.name}` } })) as (
      call: RpcCall,
    ) => RpcOutcome | Promise<RpcOutcome>,
    rpcFailure: 'none' as 'none' | 'reject' | 'throw',
    rpcFailureValue: new Error(`rpc transport failed ${LEAK}`) as unknown,
    rpcCalls: [] as RpcCall[],
    fromCalls: [] as string[],
    getSessionCalls: 0,
    getClaimsArgs: [] as unknown[],
    refreshCalls: 0,
    refreshMode: 'ok' as 'ok' | 'error' | 'throw',
    signOutCalls: [] as unknown[],
    oauthCalls: [] as unknown[],
    exchangeCalls: [] as string[],
    events: [] as string[],
    cookieOps: [] as CookieOp[],
    cookieJar: new Map<string, string>(),
    requestHeaders: new Headers(),
  }
}
let world = freshWorld()

const dbError = (code: unknown, message = `database refused ${LEAK} ${LEAK_EMAIL}`): RpcOutcome => ({
  data: null,
  error: { code, message, details: message, hint: message },
})

function makeClient() {
  const claimsResult = () =>
    world.claims === null || world.claimsError !== null
      ? { data: null, error: world.claimsError ?? { message: 'Auth session missing' } }
      : { data: { claims: world.claims, header: { alg: 'ES256' }, signature: new Uint8Array() }, error: null }
  return {
    auth: {
      getClaims: async (...args: unknown[]) => {
        world.getClaimsArgs.push(args[0])
        return claimsResult()
      },
      getUser: async () => {
        if (world.claims === null) return { data: { user: null }, error: { message: 'Auth session missing' } }
        const user = world.getUserOverride === undefined ? { id: String(world.claims.sub) } : world.getUserOverride
        return { data: { user }, error: user === null ? { message: 'User from sub claim in JWT does not exist' } : null }
      },
      getSession: () => {
        world.getSessionCalls += 1
        throw new Error('Unverified session access is not authentication')
      },
      refreshSession: async () => {
        world.refreshCalls += 1
        world.events.push('refresh')
        if (world.refreshMode === 'throw') throw new Error('refresh transport failure')
        if (world.refreshMode === 'error') return { data: { session: null, user: null }, error: { message: 'refresh refused' } }
        if (world.postRefreshClaims !== null) world.claims = world.postRefreshClaims
        return { data: { session: {}, user: {} }, error: null }
      },
      signOut: async (options?: unknown) => {
        world.signOutCalls.push(options)
        return { error: null }
      },
      signInWithOAuth: async (options: unknown) => {
        world.oauthCalls.push(options)
        world.events.push('oauth.start')
        return { data: { provider: 'google', url: OAUTH_URL }, error: null }
      },
      exchangeCodeForSession: async (code: string) => {
        world.exchangeCalls.push(code)
        return world.exchangeError === null ? { data: { session: {}, user: {} }, error: null } : { data: { session: null, user: null }, error: world.exchangeError }
      },
    },
    rpc(name: string, args: Record<string, unknown> = {}) {
      const call: RpcCall = { name, args: JSON.parse(JSON.stringify(args)) as Record<string, unknown> }
      world.rpcCalls.push(call)
      if (world.rpcFailure === 'throw') throw world.rpcFailureValue
      return rpcBuilder(async () => {
        if (world.rpcFailure === 'reject') throw world.rpcFailureValue
        return world.rpc(call)
      })
    },
    from(table: string) {
      world.fromCalls.push(table)
      const result = { data: null, error: { code: 'PGRST000', message: 'tables are not part of the invite routes' } }
      const chain: unknown = new Proxy(function inert() {}, {
        get: (_target, property) =>
          property === 'then' ? (ok: (value: unknown) => unknown, bad: (reason: unknown) => unknown) => Promise.resolve(result).then(ok, bad) : () => chain,
        apply: () => chain,
      })
      return chain
    },
  }
}

function cookieStore() {
  const entries = () => [...world.cookieJar].map(([name, value]) => ({ name, value }))
  return {
    get: (name: string) => (world.cookieJar.has(name) ? { name, value: world.cookieJar.get(name) as string } : undefined),
    getAll: (name?: string) => entries().filter((entry) => name === undefined || entry.name === name),
    has: (name: string) => world.cookieJar.has(name),
    set: (first: string | ({ name: string; value: string } & Record<string, unknown>), value?: string, options?: Record<string, unknown>) => {
      if (typeof first === 'string') world.cookieOps.push({ op: 'set', name: first, value: value ?? '', ...(options ? { options } : {}) })
      else {
        const { name, value: v, ...rest } = first
        world.cookieOps.push({ op: 'set', name, value: v, options: rest })
      }
      world.events.push(`cookie.set:${typeof first === 'string' ? first : first.name}`)
    },
    delete: (first: string | ({ name: string } & Record<string, unknown>)) => {
      world.cookieOps.push({ op: 'delete', name: typeof first === 'string' ? first : first.name })
    },
  }
}

/** Module ids for a bare specifier: the specifier itself plus its resolved file as seen from `from`. */
function moduleIds(from: string, specifier: string): string[] {
  const ids = new Set<string>([specifier])
  try {
    const resolved = createRequire(new URL(from, import.meta.url)).resolve(specifier)
    ids.add(resolved)
    ids.add(resolved.replaceAll('\\', '/'))
  } catch {
    // Not resolvable from this package: the bare specifier registration still applies.
  }
  return [...ids]
}

const SERVER_MODULE = '../../apps/web/lib/supabase/server'
const REQUEST_MODULE = '../../apps/web/lib/supabase/request'
const NEXT_HEADERS_IDS = moduleIds('../../apps/web/package.json', 'next/headers')

function registerWebMocks() {
  vi.doMock(SERVER_MODULE, () => ({ createServerSupabase: async () => makeClient() }))
  vi.doMock(REQUEST_MODULE, () => ({
    createRequestSupabase: (request: Request) => {
      const authorization = request.headers.get('authorization')
      const cookie = request.headers.get('cookie') ?? ''
      const hasCookieSession = /(?:^|;\s*)sb-[a-z0-9-]+-auth-token(?:\.\d+)?=/i.test(cookie)
      if (authorization !== null && hasCookieSession) return null
      if (authorization !== null) {
        const match = /^Bearer (\S+)$/.exec(authorization)
        if (!match?.[1]) return null
        return { supabase: makeClient(), bearer: match[1] }
      }
      return hasCookieSession ? { supabase: makeClient() } : null
    },
  }))
  for (const id of NEXT_HEADERS_IDS) {
    vi.doMock(id, () => ({ cookies: async () => cookieStore(), headers: async () => world.requestHeaders }))
  }
}

function unregisterWebMocks() {
  vi.doUnmock(SERVER_MODULE)
  vi.doUnmock(REQUEST_MODULE)
  for (const id of NEXT_HEADERS_IDS) vi.doUnmock(id)
}

type RouteModule = Record<string, unknown> & { POST: (request: Request) => Promise<Response> }
let routes = {} as Record<RouteKey, RouteModule>
let signedInSession = (async () => {
  throw new Error('web modules are not loaded yet')
}) as (request: Request) => Promise<Record<string, any>>

let consoleLines: string[] = []
function spyConsole() {
  consoleLines = []
  for (const level of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
      consoleLines.push(args.map((arg) => (typeof arg === 'string' ? arg : inspect(arg, { depth: 8, breakLength: Infinity }))).join(' '))
    })
  }
}
const consoleText = (): string => consoleLines.join('\n')

type Init = {
  json?: unknown
  raw?: string
  contentType?: string
  form?: Record<string, string>
  multipart?: Record<string, string>
  transport?: Transport
  authorization?: string
  inviteCookie?: string
  extraCookie?: string
  query?: string
}

function buildRequest(path: string, init: Init = {}): Request {
  const headers = new Headers()
  const transport = init.transport ?? 'cookie'
  const cookies: string[] = []
  if (transport === 'cookie' || transport === 'mixed') cookies.push(SESSION_COOKIE)
  if (transport === 'bearer' || transport === 'mixed') headers.set('authorization', init.authorization ?? BEARER)
  if (init.inviteCookie !== undefined) cookies.push(`${INVITE_COOKIE}=${init.inviteCookie}`)
  if (init.extraCookie !== undefined) cookies.push(init.extraCookie)
  if (cookies.length > 0) headers.set('cookie', cookies.join('; '))
  let body: BodyInit | undefined
  if (init.json !== undefined) {
    headers.set('content-type', 'application/json')
    body = JSON.stringify(init.json)
  } else if (init.raw !== undefined) {
    headers.set('content-type', init.contentType ?? 'application/json')
    body = init.raw
  } else if (init.form !== undefined) {
    headers.set('content-type', 'application/x-www-form-urlencoded')
    body = new URLSearchParams(init.form).toString()
  } else if (init.multipart !== undefined) {
    const data = new FormData()
    for (const [key, value] of Object.entries(init.multipart)) data.set(key, value)
    body = data
  }
  return new Request(`${ORIGIN}${path}${init.query ?? ''}`, { method: 'POST', headers, ...(body === undefined ? {} : { body }) })
}

async function run(route: RouteKey, init: Init = {}, prebuilt?: Request): Promise<Response> {
  const request = prebuilt ?? buildRequest(PATHS[route], init)
  if (init.inviteCookie !== undefined) world.cookieJar.set(INVITE_COOKIE, init.inviteCookie)
  world.requestHeaders = request.headers
  return routes[route].POST(request)
}

type Seen = {
  res: Response
  status: number
  text: string
  // The envelope is inspected structurally across many shapes.
  json: any
  setCookies: string[]
  location: string | null
}
async function seen(res: Response): Promise<Seen> {
  const text = await res.clone().text()
  let json: unknown = null
  try {
    json = JSON.parse(text)
  } catch {
    json = null
  }
  return { res, status: res.status, text, json, setCookies: res.headers.getSetCookie(), location: res.headers.get('location') }
}

const surfaceText = (out: Seen): string => [...out.res.headers.entries()].map(([key, value]) => `${key}: ${value}`).join('\n') + `\n${out.text}`

const NO_STORE = /(?:^|,)\s*no-store\s*(?:,|$)/i
const expectNoStore = (out: Seen) => expect(out.res.headers.get('cache-control') ?? '').toMatch(NO_STORE)

/** No secret may appear in the body, headers or console; neither may any unknown 43+ character token-looking run. */
function expectNoTokenMaterial(out: Seen, secrets: string[] = []) {
  const haystack = `${surfaceText(out)}\n${consoleText()}`
  for (const secret of secrets) expect(haystack).not.toContain(secret)
  expect(haystack).not.toMatch(TOKEN_RUN)
}

function watchBody(request: Request): () => boolean {
  const spies = (['json', 'text', 'formData', 'arrayBuffer', 'blob', 'clone'] as const).map((method) => vi.spyOn(request, method))
  return () => spies.some((spy) => spy.mock.calls.length > 0) || request.bodyUsed || (request.body?.locked ?? false)
}

function expiredAttribute(attributes: string[]): boolean {
  return attributes.some(
    (attribute) => attribute === 'max-age=0' || (attribute.startsWith('expires=') && Date.parse(attribute.slice('expires='.length)) <= Date.now()),
  )
}
function inviteCookieCleared(out: Seen): boolean {
  const viaHeader = out.setCookies.some((line) => {
    const [pair = '', ...rest] = line.split(';')
    const equals = pair.indexOf('=')
    const name = (equals === -1 ? pair : pair.slice(0, equals)).trim()
    const attributes = rest.map((attribute) => attribute.trim().toLowerCase())
    return name === INVITE_COOKIE && expiredAttribute(attributes) && attributes.includes('path=/')
  })
  const viaStore = world.cookieOps.some((op) => {
    if (op.name !== INVITE_COOKIE) return false
    const path = op.options?.path
    if (path !== undefined && path !== '/') return false
    if (op.op === 'delete') return true
    const expires = op.options?.expires
    const expired = expires instanceof Date ? expires.getTime() <= Date.now() : typeof expires === 'number' && expires <= Date.now()
    return op.options?.maxAge === 0 || expired
  })
  return viaHeader || viaStore
}
const authCookiesExpired = (out: Seen): boolean =>
  out.setCookies.some((line) => line.startsWith('sb-gymtest-auth-token=') && /max-age=0/i.test(line))

const locationUrl = (out: Seen): URL => new URL(out.location ?? '', ORIGIN)

function useSession(name: keyof typeof SESSION) {
  world.claims = SESSION[name]
  world.postRefreshClaims = name === 'unlinked' ? SESSION.member : null
}

/** A fake database for a staff-only RPC: wrong roles and impersonators get 42501, like the real definer. */
function onlyRoles(roles: string[], inner: (call: RpcCall) => RpcOutcome): (call: RpcCall) => RpcOutcome {
  return (call) => {
    const role = typeof world.claims?.app_role === 'string' ? world.claims.app_role : null
    if (role === null || !roles.includes(role) || world.claims?.impersonation_session_id != null) return dbError('42501', 'permission denied')
    return inner(call)
  }
}
function scriptSuccess(route: RouteKey) {
  const roles = ROLES_FOR[route]
  world.rpc = roles === null ? () => SUCCESS_RPC[route] : onlyRoles(roles, () => SUCCESS_RPC[route])
}
function prepare(route: RouteKey, session: keyof typeof SESSION = 'owner') {
  useSession(session)
  scriptSuccess(route)
}

/** Redeem database: knows exactly one token; every other hash is the same generic refusal. */
function dbRedeems(token: string, outcome: unknown, gym: unknown = null) {
  const known = sha256Hex(token)
  world.rpc = ({ name, args }) => {
    if (name !== 'redeem_member_invite') return dbError('42883', 'unexpected rpc')
    if (typeof args.p_token_hash !== 'string' || !/^[0-9a-f]{64}$/.test(args.p_token_hash)) return dbError('22023', 'malformed token hash')
    return args.p_token_hash === known
      ? { data: [{ outcome, gym_name: gym }], error: null }
      : { data: [{ outcome: 'invite_unavailable', gym_name: null }], error: null }
  }
}

describe('INV-018 route handlers', () => {
  beforeAll(async () => {
    vi.resetModules()
    registerWebMocks()
    routes = {
      issue: (await import('../../apps/web/app/api/member-invites/route')) as unknown as RouteModule,
      revoke: (await import('../../apps/web/app/api/member-invites/revoke/route')) as unknown as RouteModule,
      unlink: (await import('../../apps/web/app/api/member-identity/unlink/route')) as unknown as RouteModule,
      redeem: (await import('../../apps/web/app/api/member-invites/redeem/route')) as unknown as RouteModule,
    }
    const api = (await import('../../apps/web/lib/api')) as unknown as { signedInSession: (request: Request) => Promise<Record<string, any>> }
    signedInSession = api.signedInSession
  }, 120_000)

  afterAll(() => {
    unregisterWebMocks()
    vi.resetModules()
  })

  beforeEach(() => {
    world = freshWorld()
    spyConsole()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  /* ------------------------------------------------------------------ common posture ---- */

  describe('common posture of all four routes', () => {
    it.each(ROUTE_KEYS)('%s exports POST and no other method', (route) => {
      expect(typeof routes[route].POST).toBe('function')
      for (const method of ['GET', 'PUT', 'PATCH', 'DELETE']) expect(routes[route][method]).toBeUndefined()
    })

    const unauthenticated: Array<{
      label: string
      transport?: Transport
      authorization?: string
      skip?: RouteKey[]
      setup: () => void
    }> = [
      { label: 'no session at all', setup: () => { world.claims = null } },
      { label: 'claims whose signature verification failed', setup: () => { world.claims = SESSION.owner; world.claimsError = { message: 'invalid JWT' } } },
      { label: 'the public anon-key JWT (role anon, no subject)', setup: () => { world.claims = { role: 'anon' } } },
      { label: 'complete-looking app claims under a non-authenticated role (cookie session)', setup: () => { world.claims = { ...SESSION.owner, role: 'anon' } } },
      { label: 'complete-looking app claims under a non-authenticated role (bearer)', transport: 'bearer', setup: () => { world.claims = { ...SESSION.owner, role: 'service_role' } } },
      { label: 'a service-role JWT without a subject', setup: () => { world.claims = { role: 'service_role' } } },
      { label: 'role authenticated but no subject', setup: () => { world.claims = { role: 'authenticated', app_role: 'gym_owner', tenant_id: IDS.tenant, staff_id: IDS.staff } } },
      { label: 'a subject that is not a uuid (cookie session)', skip: ['redeem'], setup: () => { world.claims = { ...SESSION.owner, sub: 'not-a-uuid' } } },
      { label: 'an Auth user lookup that finds nobody (cookie session)', setup: () => { world.claims = SESSION.owner; world.getUserOverride = null } },
      { label: 'an Auth user lookup that returns a different user than the claim subject', setup: () => { world.claims = SESSION.owner; world.getUserOverride = { id: IDS.otherUser } } },
      { label: 'a cookie session AND a bearer header together (never mixed)', transport: 'mixed', setup: () => { world.claims = SESSION.owner } },
      { label: 'a non-Bearer authorization scheme', transport: 'bearer', authorization: 'Basic dXNlcjpwYXNzd29yZA==', setup: () => { world.claims = SESSION.owner } },
      { label: 'a bearer whose claims failed verification', transport: 'bearer', setup: () => { world.claims = SESSION.owner; world.claimsError = { message: 'expired' } } },
      { label: 'a bearer carrying the anon role', transport: 'bearer', setup: () => { world.claims = { role: 'anon' } } },
    ]

    for (const route of ROUTE_KEYS) {
      describe(`${route}: identifies the caller before the body is read`, () => {
        it.each(unauthenticated.filter((scenario) => !scenario.skip?.includes(route)))('401 not_signed_in for $label', async (scenario) => {
          scriptSuccess(route)
          scenario.setup()
          const request = buildRequest(PATHS[route], {
            json: VALID_BODY[route](),
            transport: scenario.transport ?? 'cookie',
            ...(scenario.authorization === undefined ? {} : { authorization: scenario.authorization }),
          })
          const bodyTouched = watchBody(request)
          const out = await seen(await run(route, {}, request))
          expect(out.status).toBe(401)
          expect(out.json).toMatchObject({ ok: false, error: { code: 'not_signed_in' } })
          expect(bodyTouched()).toBe(false)
          expect(world.rpcCalls).toHaveLength(0)
          expect(world.fromCalls).toHaveLength(0)
          expect(world.refreshCalls).toBe(0)
          expect(inviteCookieCleared(out)).toBe(false)
          expectNoStore(out)
          expectNoTokenMaterial(out, [TOKEN_C, sha256Hex(TOKEN_C)])
        })

        it('a signed-out caller with a hostile, malformed body still gets 401 (body parsing is not a side channel)', async () => {
          scriptSuccess(route)
          world.claims = null
          const request = buildRequest(PATHS[route], { raw: '{"__proto__":' })
          const bodyTouched = watchBody(request)
          const out = await seen(await run(route, {}, request))
          expect(out.status).toBe(401)
          expect(bodyTouched()).toBe(false)
          expect(world.rpcCalls).toHaveLength(0)
        })
      })
    }

    describe('signedInSession (lib/api): any verified session, unlinked included, cookie or bearer, never mixed', () => {
      const unwrap = (result: Record<string, any>): Record<string, any> => ('session' in result ? result.session : result)

      it.each(['unlinked', 'member', 'owner', 'platform', 'preview'] as const)(
        'admits a verified %s session over cookie and over bearer and returns the verified subject',
        async (name) => {
          for (const transport of ['cookie', 'bearer'] as const) {
            world = freshWorld()
            spyConsole()
            useSession(name)
            const request = buildRequest(PATHS.redeem, { json: { token: TOKEN_C }, transport })
            const bodyTouched = watchBody(request)
            const result = await signedInSession(request)
            expect([name, transport, result.failure]).toEqual([name, transport, undefined])
            const session = unwrap(result)
            expect(session.userId).toBe(IDS.user)
            expect(typeof session.supabase?.rpc).toBe('function')
            expect(bodyTouched()).toBe(false)
            expect(world.rpcCalls).toHaveLength(0)
            expect(world.getSessionCalls).toBe(0)
          }
        },
      )

      it.each(unauthenticated.filter((scenario) => !scenario.skip?.includes('redeem')))('refuses $label with a 401 not_signed_in failure', async (scenario) => {
        scenario.setup()
        const request = buildRequest(PATHS.redeem, {
          json: { token: TOKEN_C },
          transport: scenario.transport ?? 'cookie',
          ...(scenario.authorization === undefined ? {} : { authorization: scenario.authorization }),
        })
        const bodyTouched = watchBody(request)
        const result = await signedInSession(request)
        expect(result.failure).toBeInstanceOf(Response)
        const out = await seen(result.failure as Response)
        expect(out.status).toBe(401)
        expect(out.json).toMatchObject({ ok: false, error: { code: 'not_signed_in' } })
        expect(bodyTouched()).toBe(false)
        expect(world.rpcCalls).toHaveLength(0)
        expect(world.getSessionCalls).toBe(0)
      })
    })

    it.each(ROUTE_KEYS)('%s: an authenticated caller with a malformed JSON body gets 400 and the database is never called', async (route) => {
      prepare(route, route === 'redeem' ? 'unlinked' : 'owner')
      const out = await seen(await run(route, { raw: '{"memberId":' }))
      expect(out.status).toBe(400)
      expect(out.json).toMatchObject({ ok: false })
      expect(world.rpcCalls).toHaveLength(0)
      expectNoStore(out)
    })

    it.each(ROUTE_KEYS)('%s: talks to the database only through its named RPC, never a table, never an unverified session', async (route) => {
      prepare(route, route === 'redeem' ? 'unlinked' : 'owner')
      const out = await seen(await run(route, { json: VALID_BODY[route]() }))
      expect(out.status).toBeLessThan(400)
      expect(world.rpcCalls.map((call) => call.name)).toEqual([RPC_NAME[route]])
      expect(world.fromCalls).toEqual([])
      expect(world.getSessionCalls).toBe(0)
    })

    it.each(ROUTE_KEYS)('%s: rejects a body with an unexpected extra key (client-supplied tenant, staff or user ids are never accepted)', async (route) => {
      prepare(route, route === 'redeem' ? 'unlinked' : 'owner')
      for (const extra of [{ tenantId: IDS.tenant }, { staffId: IDS.staff }, { userId: IDS.user }, { p_token_hash: sha256Hex(TOKEN_C) }, { extra: 1 }]) {
        const out = await seen(await run(route, { json: { ...VALID_BODY[route](), ...extra } }))
        expect(out.status).toBe(400)
        expect(out.json).toMatchObject({ ok: false })
      }
      expect(world.rpcCalls).toHaveLength(0)
    })

    it.each(ROUTE_KEYS)('%s: rejects __proto__ / constructor keys in the JSON body and does not pollute prototypes', async (route) => {
      prepare(route, route === 'redeem' ? 'unlinked' : 'owner')
      const base = JSON.stringify(VALID_BODY[route]()).slice(0, -1)
      for (const tail of [',"__proto__":{"polluted":true}}', ',"constructor":{"prototype":{"polluted":true}}}']) {
        const out = await seen(await run(route, { raw: `${base}${tail}` }))
        expect(out.status).toBe(400)
      }
      expect(world.rpcCalls).toHaveLength(0)
      expect(({} as Record<string, unknown>).polluted).toBeUndefined()
    })

    it.each(ROUTE_KEYS)('%s: a schema failure never echoes the offending input and never reaches the database', async (route) => {
      prepare(route, route === 'redeem' ? 'unlinked' : 'owner')
      const hostile = '<script>alert("x")</script>' + LEAK_EMAIL
      const key = route === 'issue' ? 'memberId' : route === 'revoke' ? 'inviteId' : route === 'redeem' ? 'token' : 'memberId'
      const out = await seen(await run(route, { json: { ...VALID_BODY[route](), [key]: hostile } }))
      expect(out.status).toBe(400)
      expect(out.text).not.toContain('<script>')
      expect(out.text).not.toContain(LEAK_EMAIL)
      expect(consoleText()).not.toContain(LEAK_EMAIL)
      expect(world.rpcCalls).toHaveLength(0)
    })

    it('every route sets Cache-Control: no-store on success AND on every kind of error response', async () => {
      const responses: Array<[string, Seen]> = []
      for (const route of ROUTE_KEYS) {
        const session = route === 'redeem' ? 'unlinked' : 'owner'
        world = freshWorld()
        prepare(route, session)
        responses.push([`${route} success`, await seen(await run(route, { json: VALID_BODY[route]() }))])
        world = freshWorld()
        world.claims = null
        responses.push([`${route} signed out`, await seen(await run(route, { json: VALID_BODY[route]() }))])
        world = freshWorld()
        prepare(route, session)
        responses.push([`${route} malformed`, await seen(await run(route, { raw: '{' }))])
        responses.push([`${route} schema`, await seen(await run(route, { json: { nope: 1 } }))])
        world.rpc = () => dbError('XX000')
        responses.push([`${route} database failure`, await seen(await run(route, { json: VALID_BODY[route]() }))])
        world.rpcFailure = 'throw'
        responses.push([`${route} thrown failure`, await seen(await run(route, { json: VALID_BODY[route]() }))])
        world.rpcFailure = 'none'
        world.rpc = () => dbError('42501')
        responses.push([`${route} permission refusal`, await seen(await run(route, { json: VALID_BODY[route]() }))])
      }
      const bare = new Set<string>()
      for (const [label, out] of responses) if (!NO_STORE.test(out.res.headers.get('cache-control') ?? '')) bare.add(label)
      expect([...bare]).toEqual([])
    })
  })

  /* ----------------------------------------------------------------- POST member-invites ---- */

  describe('INV-001/002/003/006 POST /api/member-invites', () => {
    it.each([
      ['owner', 'owner'],
      ['manager', 'manager'],
      ['front desk', 'frontDesk'],
    ] as const)('%s issues an invite: hash-only RPC, exact envelope, link carries the token once', async (_label, session) => {
      prepare('issue', session)
      const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
      expect(out.status).toBe(200)
      expect(world.rpcCalls).toHaveLength(1)
      const call = world.rpcCalls[0] as RpcCall
      expect(call.name).toBe('issue_member_invite')
      expect(Object.keys(call.args).sort()).toEqual(['p_member_id', 'p_token_hash'])
      expect(call.args.p_member_id).toBe(IDS.member)
      expect(call.args.p_token_hash).toMatch(/^[0-9a-f]{64}$/)

      expect(out.json).toEqual({
        ok: true,
        data: { inviteId: IDS.invite, link: expect.any(String), expiresAt: EXPIRES, supersededInviteId: null },
      })
      const link = String(out.json.data.link)
      const url = new URL(link)
      expect(['http:', 'https:']).toContain(url.protocol)
      expect(url.search).toBe('')
      expect(url.hash).toBe('')
      expect(url.username).toBe('')
      expect(url.pathname).toMatch(/^\/invite\/[A-Za-z0-9_-]{43}$/)
      expect(link.replace(/^https?:\/\//, '')).not.toContain('//')
      const token = shared.parseInviteToken(link)
      expect(token).not.toBeNull()
      expect(sha256Hex(token as string)).toBe(call.args.p_token_hash)

      expect(count(out.text, token as string)).toBe(1)
      expect(out.text).not.toContain(call.args.p_token_hash as string)
      expect(JSON.stringify(call)).not.toContain(token as string)
      expect([...out.res.headers.entries()].map(([k, v]) => `${k}: ${v}`).join('\n')).not.toContain(token as string)
      expect(consoleText()).not.toContain(token as string)
      expect(consoleText()).not.toContain(call.args.p_token_hash as string)
      expectNoStore(out)
      expect(out.res.headers.get('content-type') ?? '').toMatch(/application\/json/)
    })

    it('passes a superseded invite id through (resend) and mints a fresh token and hash every time', async () => {
      prepare('issue')
      world.rpc = onlyRoles(FRONT_OFFICE, () => ({
        data: [{ invite_id: IDS.invite, expires_at: EXPIRES, superseded_invite_id: IDS.superseded }],
        error: null,
      }))
      const first = await seen(await run('issue', { json: { memberId: IDS.member } }))
      const second = await seen(await run('issue', { json: { memberId: IDS.member } }))
      expect(first.json.data.supersededInviteId).toBe(IDS.superseded)
      expect(second.json.data.supersededInviteId).toBe(IDS.superseded)
      const tokens = [first, second].map((out) => shared.parseInviteToken(String(out.json.data.link)))
      expect(tokens[0]).not.toBeNull()
      expect(tokens[1]).not.toBeNull()
      expect(tokens[0]).not.toBe(tokens[1])
      const hashes = world.rpcCalls.map((call) => call.args.p_token_hash)
      expect(new Set(hashes).size).toBe(2)
    })

    it('draws a distinct token for every one of 200 issues', async () => {
      prepare('issue')
      const hashes = new Set<unknown>()
      for (let i = 0; i < 200; i += 1) {
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect(out.status).toBe(200)
      }
      for (const call of world.rpcCalls) hashes.add(call.args.p_token_hash)
      expect(hashes.size).toBe(200)
    }, 60_000)

    it.each([
      ['trainer', 'trainer'],
      ['member', 'member'],
      ['platform user', 'platform'],
      ['support preview (impersonation)', 'preview'],
      ['unlinked account', 'unlinked'],
    ] as const)('refuses a %s: no success, no link, no token material', async (_label, session) => {
      prepare('issue', session)
      const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
      expect([401, 403, 404]).toContain(out.status)
      expect(out.json).toMatchObject({ ok: false })
      expect(out.json?.data).toBeUndefined()
      expect(out.text).not.toContain('/invite/')
      expectNoStore(out)
      expectNoTokenMaterial(out)
    })

    it('maps each documented SQLSTATE to its documented status and code, exhaustively', async () => {
      const table: Array<[string, number, string]> = [
        ['42501', 404, 'member_not_found'],
        ['GL075', 409, 'member_not_invitable'],
        ['GL076', 422, 'member_email_required'],
        ['GL077', 409, 'member_already_linked'],
        ['GL078', 429, 'invite_rate_limited'],
      ]
      for (const [sqlstate, status, code] of table) {
        world = freshWorld()
        prepare('issue')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect([sqlstate, out.status, out.json?.error?.code]).toEqual([sqlstate, status, code])
        expect(out.json).toMatchObject({ ok: false, error: { message: expect.any(String) } })
        expect(out.json.error.message.length).toBeGreaterThan(0)
        expect(out.text).not.toContain(LEAK)
        expect(out.text).not.toContain(LEAK_EMAIL)
        expect(out.text).not.toContain('/invite/')
        expectNoStore(out)
      }
    })

    it('answers 500 invite_failed for every other or hostile error code, never a mapped status and never a crash', async () => {
      const hostile: unknown[] = [
        'GL074', 'GL079', 'GL080', '22023', '23505', 'P0001', 'PGRST116', 'XX000', '', ' ', 'gl075', ' GL075', 'GL075 ', 'GL0750', '42501 ',
        '__proto__', 'constructor', 'prototype', 'toString', 'valueOf', 'hasOwnProperty', '__defineGetter__', 'isPrototypeOf',
        null, undefined, {}, true,
      ]
      for (const sqlstate of hostile) {
        world = freshWorld()
        prepare('issue')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect([String(sqlstate), out.status, out.json?.error?.code]).toEqual([String(sqlstate), 500, 'invite_failed'])
        expect(out.text).not.toContain(LEAK)
        expect(out.text).not.toContain(LEAK_EMAIL)
        expectNoStore(out)
      }
      for (const error of ['boom', true, { message: 'boom' }, { code: 'GL075x' }]) {
        world = freshWorld()
        prepare('issue')
        world.rpc = () => ({ data: null, error })
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect([out.status, out.json?.error?.code]).toEqual([500, 'invite_failed'])
      }
    })

    it('a thrown or rejected RPC is a 500 invite_failed with nothing leaked', async () => {
      for (const failure of ['throw', 'reject'] as const) {
        world = freshWorld()
        spyConsole()
        prepare('issue')
        world.rpcFailure = failure
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect([out.status, out.json?.error?.code]).toEqual([500, 'invite_failed'])
        expect(out.text).not.toContain(LEAK)
        expect(consoleText()).not.toContain(LEAK)
        expect(out.text).not.toContain('/invite/')
      }
    })

    it('never leaks the hash, an address or driver text into the response or console when the database fails', async () => {
      prepare('issue')
      world.rpc = ({ args }) =>
        dbError('23505', `duplicate key value violates unique constraint "member_invites_token_hash_key" Key (token_hash)=(${String(args.p_token_hash)}) ${LEAK_EMAIL}`)
      const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
      expect(out.status).toBe(500)
      const hash = String(world.rpcCalls[0]?.args.p_token_hash)
      expect(hash).toMatch(/^[0-9a-f]{64}$/)
      expectNoTokenMaterial(out, [hash, LEAK_EMAIL, 'member_invites_token_hash_key'])
    })

    it('zero rows, a null result or several rows is a failure with no link (a dead or ambiguous link is never handed out)', async () => {
      const row = { invite_id: IDS.invite, expires_at: EXPIRES, superseded_invite_id: null }
      for (const data of [[], null, [row, { ...row, invite_id: IDS.superseded }]]) {
        world = freshWorld()
        prepare('issue')
        world.rpc = () => ({ data, error: null })
        const out = await seen(await run('issue', { json: { memberId: IDS.member } }))
        expect(out.status).toBeGreaterThanOrEqual(400)
        expect(out.json).toMatchObject({ ok: false })
        expect(out.text).not.toContain('/invite/')
        expectNoTokenMaterial(out)
      }
    })

    it('rejects invalid bodies with 400 invalid_request and no database call', async () => {
      prepare('issue')
      const bodies: unknown[] = [{}, { memberId: 'x' }, { memberId: '' }, { memberId: null }, { memberId: 7 }, { memberId: `${IDS.member} ` }, [], [IDS.member], null, 'text', 7]
      for (const body of bodies) {
        const out = await seen(await run('issue', { json: body }))
        expect([out.status, out.json?.error?.code]).toEqual([400, 'invalid_request'])
        expectNoStore(out)
      }
      expect(world.rpcCalls).toHaveLength(0)
    })

    it('ignores any token, member or tenant smuggled through the query string', async () => {
      prepare('issue')
      const out = await seen(await run('issue', { json: { memberId: IDS.member }, query: `?memberId=${IDS.otherUser}&tenantId=${IDS.tenant}&token=${TOKEN_A}` }))
      expect(out.status).toBe(200)
      expect(world.rpcCalls[0]?.args.p_member_id).toBe(IDS.member)
      expect(world.rpcCalls[0]?.args.p_token_hash).not.toBe(sha256Hex(TOKEN_A))
    })
  })

  /* -------------------------------------------------------------------- revoke ---- */

  describe('INV-005 POST /api/member-invites/revoke', () => {
    it.each([
      ['owner', 'owner'],
      ['manager', 'manager'],
      ['front desk', 'frontDesk'],
    ] as const)('%s revokes: only the invite id goes to the database, answer is { revoked: true }', async (_label, session) => {
      prepare('revoke', session)
      const out = await seen(await run('revoke', { json: { inviteId: IDS.invite } }))
      expect(out.status).toBe(200)
      expect(out.json).toEqual({ ok: true, data: { revoked: true } })
      expect(world.rpcCalls).toEqual([{ name: 'revoke_member_invite', args: { p_invite_id: IDS.invite } }])
      expectNoStore(out)
      expectNoTokenMaterial(out)
    })

    it.each([
      ['trainer', 'trainer'],
      ['member', 'member'],
      ['platform user', 'platform'],
      ['support preview (impersonation)', 'preview'],
      ['unlinked account', 'unlinked'],
    ] as const)('refuses a %s', async (_label, session) => {
      prepare('revoke', session)
      const out = await seen(await run('revoke', { json: { inviteId: IDS.invite } }))
      expect([401, 403, 404]).toContain(out.status)
      expect(out.json).toMatchObject({ ok: false })
      expect(out.json?.data).toBeUndefined()
    })

    it('maps 42501 to 404 invite_not_found and GL079 to 409 invite_not_pending', async () => {
      for (const [sqlstate, status, code] of [['42501', 404, 'invite_not_found'], ['GL079', 409, 'invite_not_pending']] as const) {
        world = freshWorld()
        prepare('revoke')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('revoke', { json: { inviteId: IDS.invite } }))
        expect([sqlstate, out.status, out.json?.error?.code]).toEqual([sqlstate, status, code])
        expect(out.text).not.toContain(LEAK)
        expectNoStore(out)
      }
    })

    it('answers 500 for every other or hostile code, including the other routes\' states', async () => {
      const codes: unknown[] = [
        'GL074', 'GL075', 'GL076', 'GL077', 'GL078', 'GL080', '22023', '23505', 'XX000', '', 'gl079', ' GL079', 'GL0790',
        '__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', null, undefined, {}, true,
      ]
      for (const sqlstate of codes) {
        world = freshWorld()
        prepare('revoke')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('revoke', { json: { inviteId: IDS.invite } }))
        expect([String(sqlstate), out.status]).toEqual([String(sqlstate), 500])
        expect(out.json).toMatchObject({ ok: false })
        expect(out.text).not.toContain(LEAK)
        expectNoStore(out)
      }
    })

    it('a thrown or rejected RPC is a clean 500 with nothing leaked', async () => {
      for (const failure of ['throw', 'reject'] as const) {
        world = freshWorld()
        spyConsole()
        prepare('revoke')
        world.rpcFailure = failure
        const out = await seen(await run('revoke', { json: { inviteId: IDS.invite } }))
        expect(out.status).toBe(500)
        expectNoTokenMaterial(out, [LEAK])
      }
    })

    it('rejects a member id in place of an invite id and a non-uuid id with 400', async () => {
      prepare('revoke')
      for (const body of [{ memberId: IDS.member }, { inviteId: 'invite-1' }, {}, { inviteId: IDS.invite, memberId: IDS.member }]) {
        const out = await seen(await run('revoke', { json: body }))
        expect(out.status).toBe(400)
      }
      expect(world.rpcCalls).toHaveLength(0)
    })

    it('never mints or sends a token hash', async () => {
      prepare('revoke')
      await run('revoke', { json: { inviteId: IDS.invite } })
      expect(JSON.stringify(world.rpcCalls)).not.toMatch(/[0-9a-f]{64}/)
    })
  })

  /* -------------------------------------------------------------------- unlink ---- */

  describe('INV-014 POST /api/member-identity/unlink', () => {
    it.each([
      ['owner', 'owner'],
      ['manager', 'manager'],
    ] as const)('%s unlinks: trimmed reason and member id only, answer { unlinked: true }', async (_label, session) => {
      prepare('unlink', session)
      const out = await seen(await run('unlink', { json: { memberId: IDS.member, reason: `  ${REASON}  ` } }))
      expect(out.status).toBe(200)
      expect(out.json).toEqual({ ok: true, data: { unlinked: true } })
      expect(world.rpcCalls).toEqual([{ name: 'unlink_member_identity', args: { p_member_id: IDS.member, p_reason: REASON } }])
      expectNoStore(out)
    })

    it.each([
      ['front desk', 'frontDesk'],
      ['trainer', 'trainer'],
      ['member', 'member'],
      ['platform user', 'platform'],
      ['support preview (impersonation)', 'preview'],
      ['unlinked account', 'unlinked'],
    ] as const)('refuses a %s', async (_label, session) => {
      prepare('unlink', session)
      const out = await seen(await run('unlink', { json: VALID_BODY.unlink() }))
      expect([401, 403, 404]).toContain(out.status)
      expect(out.json).toMatchObject({ ok: false })
      expect(out.json?.data).toBeUndefined()
    })

    it('maps 42501 to 404 member_not_found and GL080 to 409 member_not_linked', async () => {
      for (const [sqlstate, status, code] of [['42501', 404, 'member_not_found'], ['GL080', 409, 'member_not_linked']] as const) {
        world = freshWorld()
        prepare('unlink')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('unlink', { json: VALID_BODY.unlink() }))
        expect([sqlstate, out.status, out.json?.error?.code]).toEqual([sqlstate, status, code])
        expect(out.text).not.toContain(LEAK)
        expectNoStore(out)
      }
    })

    it('answers 500 for every other or hostile code', async () => {
      const codes: unknown[] = [
        'GL074', 'GL075', 'GL076', 'GL077', 'GL078', 'GL079', '23505', 'XX000', '', 'gl080', ' GL080', 'GL0800',
        '__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', null, undefined, {}, true,
      ]
      for (const sqlstate of codes) {
        world = freshWorld()
        prepare('unlink')
        world.rpc = () => dbError(sqlstate)
        const out = await seen(await run('unlink', { json: VALID_BODY.unlink() }))
        expect([String(sqlstate), out.status]).toEqual([String(sqlstate), 500])
        expect(out.text).not.toContain(LEAK)
        expectNoStore(out)
      }
    })

    it('enforces the reason bounds before the database is touched (3..200 trimmed characters)', async () => {
      prepare('unlink')
      const tooShort = ['', 'ab', '   ab   ', '          ', '\n\t\n\t', '\u00a0\u00a0\u00a0\u00a0\u00a0']
      for (const reason of [...tooShort, 'r'.repeat(201), `  ${'r'.repeat(201)}  `]) {
        const out = await seen(await run('unlink', { json: { memberId: IDS.member, reason } }))
        expect([JSON.stringify(reason).slice(0, 12), out.status]).toEqual([JSON.stringify(reason).slice(0, 12), 400])
      }
      for (const body of [{ memberId: IDS.member }, { reason: REASON }, { memberId: 'x', reason: REASON }, { memberId: IDS.member, reason: 123456 }]) {
        expect((await seen(await run('unlink', { json: body }))).status).toBe(400)
      }
      expect(world.rpcCalls).toHaveLength(0)
      for (const reason of ['abc', 'r'.repeat(200), ` ${'r'.repeat(200)} `]) {
        const out = await seen(await run('unlink', { json: { memberId: IDS.member, reason } }))
        expect(out.status).toBe(200)
      }
      expect(world.rpcCalls.map((call) => String(call.args.p_reason).length)).toEqual([3, 200, 200])
    })

    it('keeps the free-text reason out of the response and the console', async () => {
      prepare('unlink')
      const reason = 'Asked by Priya Nair, 9876543210, priya@example.com'
      const ok = await seen(await run('unlink', { json: { memberId: IDS.member, reason } }))
      expect(ok.text).not.toContain('Priya')
      world.rpc = () => dbError('XX000')
      const failed = await seen(await run('unlink', { json: { memberId: IDS.member, reason } }))
      expect(failed.text).not.toContain('Priya')
      expect(consoleText()).not.toContain('Priya')
      expect(consoleText()).not.toContain('priya@example.com')
    })

    it('a thrown or rejected RPC is a clean 500', async () => {
      for (const failure of ['throw', 'reject'] as const) {
        world = freshWorld()
        spyConsole()
        prepare('unlink')
        world.rpcFailure = failure
        const out = await seen(await run('unlink', { json: VALID_BODY.unlink() }))
        expect(out.status).toBe(500)
        expectNoTokenMaterial(out, [LEAK])
      }
    })
  })

  /* -------------------------------------------------------------------- redeem ---- */

  describe('INV-007..INV-011 / INV-021 POST /api/member-invites/redeem', () => {
    const HASH = sha256Hex(TOKEN_C)
    const REFUSALS: Array<[keyof typeof COPY, number]> = [
      ['invite_unavailable', 404],
      ['email_mismatch', 403],
      ['identity_unverified', 403],
      ['account_already_linked', 409],
      ['rate_limited', 429],
    ]

    beforeEach(() => {
      useSession('unlinked')
    })

    /** Fail-closed expectations shared by every "this must not look like a link" scenario. */
    async function expectFailClosed(out: Seen, form: boolean) {
      expect(world.refreshCalls).toBe(0)
      expect(world.signOutCalls).toHaveLength(0)
      expect(inviteCookieCleared(out)).toBe(false)
      if (form && out.status === 303) {
        const target = locationUrl(out)
        expect(target.pathname).toBe('/invite/continue')
        expect([...target.searchParams.keys()]).toEqual(['result'])
        expect(REFUSAL_CODES as string[]).toContain(target.searchParams.get('result'))
      } else {
        expect(out.status).toBeGreaterThanOrEqual(400)
        if (!form) expect(out.json).toMatchObject({ ok: false })
      }
      expectNoStore(out)
    }

    describe('JSON path (mobile)', () => {
      it.each(['linked', 'already_linked_here'])('%s: 200 envelope, exactly one session refresh, invite cookie cleared, hash-only RPC', async (outcome) => {
        dbRedeems(TOKEN_C, outcome, GYM)
        const out = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(200)
        expect(out.json).toEqual({ ok: true, data: { outcome, gymName: GYM } })
        expect(world.refreshCalls).toBe(1)
        expect(world.signOutCalls).toHaveLength(0)
        expect(inviteCookieCleared(out)).toBe(true)
        expect(world.rpcCalls).toEqual([{ name: 'redeem_member_invite', args: { p_token_hash: HASH } }])
        expect(out.location).toBeNull()
        expectNoStore(out)
        expectNoTokenMaterial(out, [TOKEN_C, HASH])
      })

      it.each(REFUSALS)('%s: HTTP %i, code equals the outcome, the fixed sentence, no refresh, cookie kept', async (outcome, status) => {
        dbRedeems(TOKEN_C, outcome, null)
        const out = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(status)
        expect(out.json).toMatchObject({ ok: false, error: { code: outcome, message: COPY[outcome] } })
        expect(out.json.data).toBeUndefined()
        expect(world.refreshCalls).toBe(0)
        expect(world.signOutCalls).toHaveLength(0)
        expect(inviteCookieCleared(out)).toBe(false)
        expect(world.rpcCalls).toEqual([{ name: 'redeem_member_invite', args: { p_token_hash: HASH } }])
        expectNoStore(out)
        expectNoTokenMaterial(out, [TOKEN_C, HASH])
      })

      it('never forwards a gym name or any row detail on a refusal, even if the database row carries one', async () => {
        for (const [outcome] of REFUSALS) {
          world = freshWorld()
          spyConsole()
          useSession('unlinked')
          dbRedeems(TOKEN_C, outcome, 'LEAKGYM Fitness')
          const out = await seen(await run('redeem', { json: { token: TOKEN_C } }))
          expect(out.text).not.toContain('LEAKGYM')
          expect(consoleText()).not.toContain('LEAKGYM')
        }
      })

      it('an unknown token is the generic refusal (the same answer as an expired or revoked one)', async () => {
        dbRedeems(TOKEN_A, 'linked', GYM)
        const out = await seen(await run('redeem', { json: { token: TOKEN_C } }))
        expect(out.status).toBe(404)
        expect(out.json).toMatchObject({ ok: false, error: { code: 'invite_unavailable', message: COPY.invite_unavailable } })
        expect(world.refreshCalls).toBe(0)
      })

      it('reads the token only from the JSON body: an absent token with a valid cookie is a 400, and a query token is ignored', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const missing = await seen(await run('redeem', { json: {}, inviteCookie: TOKEN_C }))
        expect(missing.status).toBe(400)
        expect(world.rpcCalls).toHaveLength(0)
        const body = await seen(await run('redeem', { json: { token: TOKEN_C }, query: `?token=${TOKEN_A}`, inviteCookie: TOKEN_A }))
        expect(body.status).toBe(200)
        expect(world.rpcCalls).toEqual([{ name: 'redeem_member_invite', args: { p_token_hash: HASH } }])
      })

      it('rejects every malformed token with 400 invalid_request and never calls the database', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const bad: unknown[] = [
          '', 'short', ` ${TOKEN_C}`, `${TOKEN_C}\n`, `${TOKEN_C}=`, TOKEN_C.slice(0, 42), `${TOKEN_C}a`, `https://h.example/invite/${TOKEN_C}`,
          `${'a'.repeat(42)}\u0430`, 12345, null, [TOKEN_C], { toString: TOKEN_C },
        ]
        for (const token of bad) {
          const out = await seen(await run('redeem', { json: { token } }))
          expect([out.status, out.json?.error?.code]).toEqual([400, 'invalid_request'])
          expectNoStore(out)
        }
        expect(world.rpcCalls).toHaveLength(0)
      })

      it('accepts a charset-parameterised JSON content type', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const out = await seen(await run('redeem', { raw: JSON.stringify({ token: TOKEN_C }), contentType: 'application/json; charset=utf-8' }))
        expect(out.status).toBe(200)
      })

      it('a bearer-authenticated unlinked caller (the mobile app) can redeem; refusals never refresh', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const ok = await seen(await run('redeem', { json: { token: TOKEN_C }, transport: 'bearer' }))
        expect(ok.status).toBe(200)
        expect(ok.json).toEqual({ ok: true, data: { outcome: 'linked', gymName: GYM } })
        expect(world.refreshCalls).toBeLessThanOrEqual(1)

        world = freshWorld()
        spyConsole()
        useSession('unlinked')
        dbRedeems(TOKEN_C, 'email_mismatch')
        const refused = await seen(await run('redeem', { json: { token: TOKEN_C }, transport: 'bearer' }))
        expect(refused.status).toBe(403)
        expect(world.refreshCalls).toBe(0)
        expect(world.signOutCalls).toHaveLength(0)
      })

      it('lets an already-bound member, staff or platform session reach the database so the D1 copy can be shown', async () => {
        for (const session of ['member', 'owner', 'platform'] as const) {
          world = freshWorld()
          spyConsole()
          useSession(session)
          dbRedeems(TOKEN_C, 'account_already_linked')
          const out = await seen(await run('redeem', { json: { token: TOKEN_C } }))
          expect([session, out.status, out.json?.error?.code]).toEqual([session, 409, 'account_already_linked'])
          expect(world.rpcCalls).toHaveLength(1)
          expect(world.refreshCalls).toBe(0)
        }
      })

      it('a support-preview session is refused by the database and the handler fails closed', async () => {
        useSession('preview')
        world.rpc = () => dbError('42501', 'permission denied')
        const out = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        await expectFailClosed(out, false)
        expect(out.json?.data).toBeUndefined()
      })
    })

    describe('form path (browser, 303)', () => {
      it.each(['linked', 'already_linked_here'])('%s: 303 to the member home, one refresh, invite cookie cleared', async (outcome) => {
        dbRedeems(TOKEN_C, outcome, GYM)
        const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(303)
        const target = locationUrl(out)
        expect(target.pathname).toBe('/member')
        expect(target.search).toBe('')
        expect(world.refreshCalls).toBe(1)
        expect(inviteCookieCleared(out)).toBe(true)
        expect(world.rpcCalls).toEqual([{ name: 'redeem_member_invite', args: { p_token_hash: HASH } }])
        expectNoStore(out)
        expectNoTokenMaterial(out, [TOKEN_C, HASH])
      })

      it.each(REFUSALS)('%s: 303 to /invite/continue?result=<outcome>, no refresh, cookie kept so the person can retry with another Google account', async (outcome) => {
        dbRedeems(TOKEN_C, outcome)
        const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(303)
        const target = locationUrl(out)
        expect(target.pathname).toBe('/invite/continue')
        expect([...target.searchParams.entries()]).toEqual([['result', outcome]])
        expect(world.refreshCalls).toBe(0)
        expect(world.signOutCalls).toHaveLength(0)
        expect(inviteCookieCleared(out)).toBe(false)
        expectNoStore(out)
        expectNoTokenMaterial(out, [TOKEN_C, HASH])
      })

      it('falls back to the fitcruxx_invite cookie when the form has no token field', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const out = await seen(await run('redeem', { form: {}, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(303)
        expect(locationUrl(out).pathname).toBe('/member')
        expect(world.rpcCalls).toEqual([{ name: 'redeem_member_invite', args: { p_token_hash: HASH } }])
      })

      it('prefers the hidden form field over the cookie', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_A }))
        expect(out.status).toBe(303)
        expect(world.rpcCalls.map((call) => call.args.p_token_hash)).toEqual([HASH])
      })

      it('accepts a multipart form post as well', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const out = await seen(await run('redeem', { multipart: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        expect(out.status).toBe(303)
        expect(locationUrl(out).pathname).toBe('/member')
      })

      it('reads the cookie by exact name: look-alike cookie names are not the invite cookie', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        for (const extraCookie of [`evil_${INVITE_COOKIE}=${TOKEN_C}`, `${INVITE_COOKIE}_x=${TOKEN_C}`, `x${INVITE_COOKIE}=${TOKEN_C}`, `${INVITE_COOKIE.toUpperCase()}=${TOKEN_C}`]) {
          world = freshWorld()
          spyConsole()
          useSession('unlinked')
          dbRedeems(TOKEN_C, 'linked', GYM)
          const out = await seen(await run('redeem', { form: {}, extraCookie }))
          expect(world.rpcCalls.every((call) => call.args.p_token_hash !== HASH)).toBe(true)
          await expectFailClosed(out, true)
          expect(locationUrl(out).searchParams.get('result')).toBe('invite_unavailable')
        }
      })

      it('a missing, malformed or unusable token anywhere is the generic refusal and never a link', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        const attempts: Array<[string, Init]> = [
          ['no field and no cookie', { form: {} }],
          ['garbage cookie', { form: {}, inviteCookie: 'not-a-token' }],
          ['padded cookie', { form: {}, inviteCookie: `${TOKEN_C}=` }],
          ['garbage field', { form: { token: 'short' } }],
          ['field with a full link', { form: { token: `https://h.example/invite/${TOKEN_C}` } }],
        ]
        for (const [label, init] of attempts) {
          world.rpcCalls.length = 0
          const out = await seen(await run('redeem', init))
          await expectFailClosed(out, true)
          const result = out.status === 303 ? locationUrl(out).searchParams.get('result') : 'invite_unavailable'
          expect([label, result]).toEqual([label, 'invite_unavailable'])
          expect(world.rpcCalls.every((call) => call.args.p_token_hash !== HASH)).toBe(true)
        }
      })

      it('a signed-out form post is the 401 envelope, not a redirect, and the body is untouched', async () => {
        world.claims = null
        dbRedeems(TOKEN_C, 'linked', GYM)
        const request = buildRequest(PATHS.redeem, { form: { token: TOKEN_C }, inviteCookie: TOKEN_C })
        const bodyTouched = watchBody(request)
        const out = await seen(await run('redeem', { inviteCookie: TOKEN_C }, request))
        expect(out.status).toBe(401)
        expect(out.json).toMatchObject({ ok: false, error: { code: 'not_signed_in' } })
        expect(bodyTouched()).toBe(false)
        expect(world.rpcCalls).toHaveLength(0)
        expect(inviteCookieCleared(out)).toBe(false)
      })
    })

    describe('outcomes outside the allowlist are never a success', () => {
      const hostileOutcomes: unknown[] = [
        'LINKED', 'Linked', ' linked', 'linked ', 'linked\n', 'linked\0', 'already_linked', 'already-linked-here', 'success', 'ok', 'true', 'linked,linked',
        '', ' ', '__proto__', 'constructor', 'prototype', 'toString', 'valueOf', 'hasOwnProperty',
        'email_mismatch&next=https://evil.example', 'email_mismatch#x', '<script>', '../member',
        null, undefined, 0, 1, 42, true, false, {}, [], ['linked'], { toString: 'linked' },
      ]

      it('JSON path: fail closed, no refresh, no cookie clearing, no sign-out, no pass-through', async () => {
        for (const outcome of hostileOutcomes) {
          world = freshWorld()
          spyConsole()
          useSession('unlinked')
          dbRedeems(TOKEN_C, outcome, 'LEAKGYM Fitness')
          const out = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
          const label = JSON.stringify(outcome) ?? String(outcome)
          expect([label, out.status >= 400]).toEqual([label, true])
          expect([label, out.json?.ok]).toEqual([label, false])
          expect(out.json?.data).toBeUndefined()
          expect(world.refreshCalls).toBe(0)
          expect(inviteCookieCleared(out)).toBe(false)
          expect(out.text).not.toContain('LEAKGYM')
        }
      })

      it('form path: never to the member home, never reflects the outcome string into the redirect', async () => {
        for (const outcome of hostileOutcomes) {
          world = freshWorld()
          spyConsole()
          useSession('unlinked')
          dbRedeems(TOKEN_C, outcome, 'LEAKGYM Fitness')
          const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
          const label = JSON.stringify(outcome) ?? String(outcome)
          await expectFailClosed(out, true)
          if (out.status === 303) {
            const target = locationUrl(out)
            expect([label, target.pathname === '/member']).toEqual([label, false])
          }
          expect(out.location ?? '').not.toContain('evil.example')
          expect(out.location ?? '').not.toContain('LEAKGYM')
        }
      })
    })

    describe('unexpected database results are never a success', () => {
      const linked = { outcome: 'linked', gym_name: GYM }
      const cases: Array<[string, RpcOutcome]> = [
        ['zero rows', { data: [], error: null }],
        ['a null result', { data: null, error: null }],
        ['two identical linked rows', { data: [linked, linked], error: null }],
        ['a refusal then a linked row', { data: [{ outcome: 'email_mismatch', gym_name: null }, linked], error: null }],
        ['a linked row then a refusal', { data: [linked, { outcome: 'email_mismatch', gym_name: null }], error: null }],
        ['an empty row', { data: [{}], error: null }],
        ['a row with a null outcome', { data: [{ outcome: null, gym_name: GYM }], error: null }],
        ['a bare string result', { data: 'linked', error: null }],
        ['a bare boolean result', { data: true, error: null }],
        ['a database error object carrying a linked-looking row', { data: [linked], error: { code: 'XX000', message: 'boom' } }],
        ['an error with a hostile code', dbError('__proto__')],
        ['an error with no code', { data: null, error: { message: 'boom' } }],
        ['a permission error', dbError('42501')],
        ['a malformed-input error', dbError('22023')],
        ['a string error', { data: null, error: 'boom' }],
      ]

      it.each(cases)('JSON path, %s: fail closed', async (_label, outcome) => {
        world.rpc = () => outcome
        const out = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        await expectFailClosed(out, false)
        expect(out.json?.data).toBeUndefined()
        expect(out.text).not.toContain(LEAK)
        expectNoTokenMaterial(out, [LEAK, LEAK_EMAIL])
      })

      it.each(cases)('form path, %s: fail closed', async (_label, outcome) => {
        world.rpc = () => outcome
        const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        await expectFailClosed(out, true)
        expectNoTokenMaterial(out, [LEAK, LEAK_EMAIL])
      })

      it.each(['throw', 'reject'] as const)('a %s RPC failure is fail closed on both paths and leaks nothing', async (failure) => {
        world.rpcFailure = failure
        const json = await seen(await run('redeem', { json: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        await expectFailClosed(json, false)
        expectNoTokenMaterial(json, [LEAK, TOKEN_C, HASH])
        world.rpcCalls.length = 0
        const form = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
        await expectFailClosed(form, true)
        expectNoTokenMaterial(form, [LEAK, TOKEN_C, HASH])
      })

      it('the database error text never reaches the client or the log, even if it contains the hash and an address', async () => {
        world.rpc = ({ args }) => dbError('XX000', `could not serialize ${String(args.p_token_hash)} for ${LEAK_EMAIL}`)
        const out = await seen(await run('redeem', { json: { token: TOKEN_C } }))
        expect(out.status).toBe(500)
        expectNoTokenMaterial(out, [HASH, TOKEN_C, LEAK_EMAIL])
      })
    })

    describe('session refresh after a link (the access-token hook only runs at token issue)', () => {
      it.each([
        ['error', 'JSON'],
        ['throw', 'JSON'],
        ['error', 'form'],
        ['throw', 'form'],
      ] as const)('a refresh that fails (%s, %s path) signs the local session out and expires the auth cookies', async (mode, path) => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        world.refreshMode = mode
        const init: Init = path === 'JSON' ? { json: { token: TOKEN_C }, inviteCookie: TOKEN_C } : { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }
        const out = await seen(await run('redeem', init))
        expect(world.refreshCalls).toBe(1)
        expect(world.signOutCalls[0]).toEqual({ scope: 'local' })
        expect(authCookiesExpired(out)).toBe(true)
        if (path === 'form') {
          expect(out.status).toBe(303)
          expect(locationUrl(out).pathname).toBe('/sign-in')
        }
        expectNoStore(out)
        expectNoTokenMaterial(out, [TOKEN_C, HASH])
      })

      it('a refusal never refreshes, never signs out and never expires the session cookies', async () => {
        for (const [outcome] of REFUSALS) {
          world = freshWorld()
          spyConsole()
          useSession('unlinked')
          dbRedeems(TOKEN_C, outcome)
          const out = await seen(await run('redeem', { form: { token: TOKEN_C }, inviteCookie: TOKEN_C }))
          expect(world.refreshCalls).toBe(0)
          expect(world.signOutCalls).toHaveLength(0)
          expect(authCookiesExpired(out)).toBe(false)
        }
      })

      it('a successful link refreshes exactly once even when posted twice in a row (replay answers already_linked_here)', async () => {
        dbRedeems(TOKEN_C, 'linked', GYM)
        await run('redeem', { json: { token: TOKEN_C } })
        expect(world.refreshCalls).toBe(1)
        dbRedeems(TOKEN_C, 'already_linked_here', GYM)
        useSession('unlinked')
        const out = await seen(await run('redeem', { json: { token: TOKEN_C } }))
        expect(out.json).toEqual({ ok: true, data: { outcome: 'already_linked_here', gymName: GYM } })
        expect(world.refreshCalls).toBe(2)
      })
    })
  })
})

/* ============================================================================================ *
 * 11. OAuth round trip  (INV-021)
 * ============================================================================================ */

describe('INV-021 OAuth round trip: the token travels only in the fitcruxx_invite cookie', () => {
  const HOME: Array<[string, Claims, string]> = [
    ['an owner', SESSION.owner, '/dashboard'],
    ['a manager', SESSION.manager, '/dashboard'],
    ['a front-desk user', SESSION.frontDesk, '/console/check-in'],
    ['a trainer', SESSION.trainer, '/console'],
    ['a member', SESSION.member, '/member'],
    ['a platform user', SESSION.platform, '/platform'],
    ['a support preview', SESSION.preview, '/console'],
  ]

  let callback: { GET: (request: Request) => Promise<Response> }

  beforeAll(async () => {
    vi.resetModules()
    registerWebMocks()
    callback = (await import('../../apps/web/app/auth/callback/route')) as unknown as typeof callback
  }, 120_000)

  afterAll(() => {
    unregisterWebMocks()
    vi.unstubAllEnvs()
    vi.resetModules()
  })

  beforeEach(() => {
    world = freshWorld()
    spyConsole()
  })

  afterEach(() => {
    vi.restoreAllMocks()
  })

  async function callbackWith(init: { claims: Claims | null; cookie?: string | null; query?: string; exchangeError?: unknown }) {
    world.claims = init.claims
    if (init.exchangeError !== undefined) world.exchangeError = init.exchangeError
    const headers = new Headers()
    if (init.cookie !== undefined && init.cookie !== null) {
      headers.set('cookie', `${INVITE_COOKIE}=${init.cookie}`)
      world.cookieJar.set(INVITE_COOKIE, init.cookie)
    }
    const request = new Request(`${ORIGIN}/auth/callback${init.query ?? '?code=abc123'}`, { headers })
    world.requestHeaders = request.headers
    const response = await callback.GET(request)
    const target = new URL(response.headers.get('location') ?? '', ORIGIN)
    return { response, path: `${target.pathname}${target.search}`, location: response.headers.get('location') ?? '' }
  }

  it('an unlinked identity holding a valid invite cookie goes to /invite/continue', async () => {
    const out = await callbackWith({ claims: SESSION.unlinked, cookie: TOKEN_C })
    expect(out.response.status).toBe(303)
    expect(out.path).toBe('/invite/continue')
    expect(out.location).not.toContain(TOKEN_C)
    expect(world.exchangeCalls).toEqual(['abc123'])
  })

  it.each([
    ['no cookie', null],
    ['a short cookie value', 'abc'],
    ['a 42-character value', TOKEN_C.slice(0, 42)],
    ['a 44-character value', `${TOKEN_C}a`],
    ['a padded value', `${TOKEN_C.slice(0, 42)}=`],
    ['a link instead of a token', `https://h.example/invite/${TOKEN_C}`],
    ['an empty value', ''],
  ])('an unlinked identity with %s stays on /not-linked', async (_label, cookie) => {
    const out = await callbackWith({ claims: SESSION.unlinked, cookie })
    expect(out.path).toBe('/not-linked')
  })

  it.each(HOME)('%s with a valid invite cookie still goes to their own home (the cookie is honoured only in the unlinked branch)', async (_label, claims, home) => {
    const out = await callbackWith({ claims, cookie: TOKEN_C })
    expect(out.path).toBe(home)
  })

  it('every other case is unchanged: failed exchange, missing code and ignored next parameter all land where they did before', async () => {
    const failed = await callbackWith({ claims: SESSION.unlinked, cookie: TOKEN_C, exchangeError: { message: 'bad code' } })
    expect(failed.path).toBe('/sign-in?failed=1')
    world = freshWorld()
    const missing = await callbackWith({ claims: SESSION.unlinked, cookie: TOKEN_C, query: '' })
    expect(missing.path).toBe('/sign-in?failed=1')
    expect(world.exchangeCalls).toEqual([])
    world = freshWorld()
    const next = await callbackWith({ claims: SESSION.unlinked, cookie: null, query: `?code=abc&next=${encodeURIComponent('https://evil.example/steal')}` })
    expect(next.path).toBe('/not-linked')
    expect(next.location).not.toContain('evil.example')
    world = freshWorld()
    const nextWithCookie = await callbackWith({ claims: SESSION.unlinked, cookie: TOKEN_C, query: `?code=abc&next=${encodeURIComponent('//evil.example')}&redirect_to=https://evil.example` })
    expect(nextWithCookie.path).toBe('/invite/continue')
    expect(nextWithCookie.location).not.toContain('evil.example')
  })

  describe('startInviteGoogleSignIn (server action in lib/auth-actions)', () => {
    async function loadActions() {
      vi.resetModules()
      return (await import('../../apps/web/lib/auth-actions')) as unknown as { startInviteGoogleSignIn: (token: string) => Promise<void> }
    }
    async function start(token: unknown, env: string) {
      vi.stubEnv('WEB_APP_URL', env)
      const actions = await loadActions()
      const proto = env.startsWith('https') ? 'https' : 'http'
      world.requestHeaders = new Headers({ host: new URL(env).host, 'x-forwarded-proto': proto, 'x-forwarded-host': new URL(env).host })
      let thrown: unknown = null
      try {
        await actions.startInviteGoogleSignIn(token as string)
      } catch (error) {
        thrown = error
      }
      return thrown
    }
    const cookieSets = () => world.cookieOps.filter((op) => op.op === 'set' && op.name === INVITE_COOKIE)

    it('sets the HttpOnly, SameSite=Lax, Path=/ cookie for 30 minutes BEFORE it starts Google OAuth, with Secure on https', async () => {
      const thrown = await start(TOKEN_C, 'https://fitcruxx.vercel.app')
      expect(String((thrown as { digest?: string } | null)?.digest ?? thrown)).toContain('NEXT_REDIRECT')
      const sets = cookieSets()
      expect(sets).toHaveLength(1)
      const set = sets[0] as CookieOp
      expect(set.value).toBe(TOKEN_C)
      expect(set.options?.httpOnly).toBe(true)
      expect(String(set.options?.sameSite).toLowerCase()).toBe('lax')
      expect(set.options?.path).toBe('/')
      expect(set.options?.maxAge).toBe(1800)
      expect(set.options?.secure).toBe(true)
      expect(world.events.indexOf(`cookie.set:${INVITE_COOKIE}`)).toBeGreaterThanOrEqual(0)
      expect(world.events.indexOf('oauth.start')).toBeGreaterThan(world.events.indexOf(`cookie.set:${INVITE_COOKIE}`))
    })

    it('does not mark the cookie Secure on a plain-http development origin', async () => {
      await start(TOKEN_C, 'http://127.0.0.1:3000')
      const set = cookieSets()[0] as CookieOp
      expect(set.value).toBe(TOKEN_C)
      expect(Boolean(set.options?.secure)).toBe(false)
      expect(set.options?.httpOnly).toBe(true)
      expect(set.options?.path).toBe('/')
    })

    it('carries the token across OAuth only in the cookie: never in redirectTo, next, a query string, query params or the redirect', async () => {
      const thrown = await start(TOKEN_C, 'https://fitcruxx.vercel.app')
      expect(world.oauthCalls).toHaveLength(1)
      const options = (world.oauthCalls[0] as { provider: string; options: { redirectTo: string; queryParams?: unknown } }).options
      expect((world.oauthCalls[0] as { provider: string }).provider).toBe('google')
      expect(options.redirectTo).toBe('https://fitcruxx.vercel.app/auth/callback')
      expect(JSON.stringify(world.oauthCalls)).not.toContain(TOKEN_C)
      expect(JSON.stringify(world.oauthCalls)).not.toContain(sha256Hex(TOKEN_C))
      expect(String((thrown as { digest?: string } | null)?.digest ?? thrown)).not.toContain(TOKEN_C)
      expect(consoleText()).not.toContain(TOKEN_C)
    })

    it.each([
      ['an empty token', ''],
      ['a short token', 'abc'],
      ['a padded token', `${TOKEN_C}=`],
      ['a 44-character token', `${TOKEN_C}a`],
      ['a full link', `https://h.example/invite/${TOKEN_C}`],
      ['a lookalike character', `${'a'.repeat(42)}\u0430`],
      ['a number', 12345],
      ['null', null],
      ['undefined', undefined],
    ])('stores nothing and starts no OAuth for %s', async (_label, token) => {
      await start(token, 'https://fitcruxx.vercel.app')
      expect(cookieSets()).toHaveLength(0)
      expect(world.oauthCalls).toHaveLength(0)
    })
  })
})

/* ============================================================================================ *
 * 12. Mobile entry logic  (INV-022)
 * ============================================================================================ */

describe('INV-022 mobile invite entry (apps/mobile/lib/invite)', () => {
  const secure = new Map<string, string>()
  const secureStore = {
    getItemAsync: vi.fn(async (key: string) => secure.get(key) ?? null),
    setItemAsync: vi.fn(async (key: string, value: string) => {
      secure.set(key, value)
    }),
    deleteItemAsync: vi.fn(async (key: string) => {
      secure.delete(key)
    }),
    isAvailableAsync: vi.fn(async () => true),
  }
  type Kind = 'unlinked' | 'member' | 'staff' | 'platform' | 'impersonation' | 'none'
  type Entry = { action: 'invalid_link' | 'save_and_sign_in' | 'redeem' | 'already_linked' }
  let invite: {
    PENDING_INVITE_KEY: string
    resolveInviteEntry: (input: { token: string | null; sessionPresent: boolean; identityKind: Kind }) => Entry
    inviteOutcomeMessage: (code: string) => string
    savePendingInvite: (token: string) => Promise<void>
    takePendingInvite: () => Promise<string | null>
  }

  beforeAll(async () => {
    vi.resetModules()
    for (const id of moduleIds('../../apps/mobile/package.json', 'expo-secure-store')) {
      vi.doMock(id, () => ({ ...secureStore, default: secureStore }))
    }
    invite = (await import('../../apps/mobile/lib/invite')) as unknown as typeof invite
  }, 120_000)

  afterAll(() => {
    for (const id of moduleIds('../../apps/mobile/package.json', 'expo-secure-store')) vi.doUnmock(id)
    vi.resetModules()
  })

  beforeEach(() => {
    secure.clear()
    vi.clearAllMocks()
  })

  const KINDS: Kind[] = ['unlinked', 'member', 'staff', 'platform', 'impersonation', 'none']
  const VALID_TOKENS = [TOKEN_A, TOKEN_B, TOKEN_C, TOKEN_D, TOKEN_DASH]
  const INVALID_TOKENS: Array<string | null> = [
    null,
    '',
    ' ',
    'abc',
    TOKEN_C.slice(0, 42),
    `${TOKEN_C}a`,
    `${TOKEN_C}=`,
    `${TOKEN_C.slice(0, 42)}=`,
    `${'a'.repeat(42)}\u0430`,
    `${TOKEN_C.slice(0, 20)} ${TOKEN_C.slice(21)}`,
    'undefined',
    'null',
    '__proto__',
    'x'.repeat(100_000),
  ]
  const oracle = (token: string | null, sessionPresent: boolean, kind: Kind): Entry['action'] => {
    if (token === null || !shared.INVITE_TOKEN_PATTERN.test(token)) return 'invalid_link'
    if (!sessionPresent) return 'save_and_sign_in'
    return kind === 'unlinked' ? 'redeem' : 'already_linked'
  }

  it('PENDING_INVITE_KEY is gymloop.pending-invite', () => {
    expect(invite.PENDING_INVITE_KEY).toBe('gymloop.pending-invite')
  })

  it('exhaustive truth table: valid tokens x session presence x identity kind', () => {
    for (const token of VALID_TOKENS) {
      for (const sessionPresent of [false, true]) {
        for (const identityKind of KINDS) {
          const result = invite.resolveInviteEntry({ token, sessionPresent, identityKind })
          expect([token, sessionPresent, identityKind, result]).toEqual([token, sessionPresent, identityKind, { action: oracle(token, sessionPresent, identityKind) }])
        }
      }
    }
  })

  it('a null, empty or malformed token is invalid_link whatever the session and identity say', () => {
    for (const token of INVALID_TOKENS) {
      for (const sessionPresent of [false, true]) {
        for (const identityKind of KINDS) {
          const result = invite.resolveInviteEntry({ token, sessionPresent, identityKind })
          expect([String(token).slice(0, 12), sessionPresent, identityKind, result]).toEqual([String(token).slice(0, 12), sessionPresent, identityKind, { action: 'invalid_link' }])
        }
      }
    }
  })

  it('names the four actions the contract names, each reachable', () => {
    const reached = new Set<string>()
    for (const token of [TOKEN_C, 'bad']) {
      for (const sessionPresent of [false, true]) {
        for (const identityKind of KINDS) reached.add(invite.resolveInviteEntry({ token, sessionPresent, identityKind }).action)
      }
    }
    expect([...reached].sort()).toEqual(['already_linked', 'invalid_link', 'redeem', 'save_and_sign_in'])
  })

  it('redeems only for a present session whose identity kind is exactly "unlinked"', () => {
    for (const identityKind of ['Unlinked', ' unlinked', 'unlinked\n', 'UNLINKED', '__proto__', 'constructor', '', 'toString', undefined, null] as unknown[]) {
      const result = invite.resolveInviteEntry({ token: TOKEN_C, sessionPresent: true, identityKind: identityKind as Kind })
      expect(result.action).not.toBe('redeem')
      expect(['invalid_link', 'save_and_sign_in', 'already_linked']).toContain(result.action)
    }
    expect(invite.resolveInviteEntry({ token: TOKEN_C, sessionPresent: true, identityKind: 'unlinked' })).toEqual({ action: 'redeem' })
  })

  it('is pure: it does not mutate its input, is deterministic and ignores everything but the three fields', () => {
    const input = Object.freeze({ token: TOKEN_C, sessionPresent: true, identityKind: 'unlinked' as Kind, extra: 'x' })
    const first = invite.resolveInviteEntry(input)
    const second = invite.resolveInviteEntry({ ...input })
    expect(first).toEqual(second)
    expect(first).toEqual({ action: 'redeem' })
    expect(Object.keys(first)).toEqual(['action'])
  })

  it('inviteOutcomeMessage re-uses inviteRefusalMessage for every code, including hostile ones', () => {
    for (const code of [...ALL_OUTCOMES, '', 'unknown', '__proto__', 'constructor', 'toString', 'hasOwnProperty', ' email_mismatch', 'x'.repeat(10_000)]) {
      expect(invite.inviteOutcomeMessage(code)).toBe(shared.inviteRefusalMessage(code))
    }
    for (const code of REFUSAL_CODES) expect(invite.inviteOutcomeMessage(code)).toBe(COPY[code])
    expect(invite.inviteOutcomeMessage('__proto__')).toBe(COPY.invite_unavailable)
  })

  it('savePendingInvite stores the token under PENDING_INVITE_KEY and takePendingInvite returns it once', async () => {
    await invite.savePendingInvite(TOKEN_C)
    expect(secureStore.setItemAsync.mock.calls).toHaveLength(1)
    expect(secureStore.setItemAsync.mock.calls[0]?.slice(0, 2)).toEqual([invite.PENDING_INVITE_KEY, TOKEN_C])
    expect(secure.get(invite.PENDING_INVITE_KEY)).toBe(TOKEN_C)
    await expect(invite.takePendingInvite()).resolves.toBe(TOKEN_C)
    expect(secure.has(invite.PENDING_INVITE_KEY)).toBe(false)
    await expect(invite.takePendingInvite()).resolves.toBeNull()
  })

  it('takePendingInvite never hands out a malformed stored value', async () => {
    for (const stored of ['garbage', '', ` ${TOKEN_C}`, `${TOKEN_C}\n`, `${TOKEN_C}=`, `https://h.example/invite/${TOKEN_C}`]) {
      secure.set(invite.PENDING_INVITE_KEY, stored)
      await expect(invite.takePendingInvite()).resolves.toBeNull()
    }
    secure.clear()
    await expect(invite.takePendingInvite()).resolves.toBeNull()
  })

  it('a newer pending token replaces an older one (only one is ever offered)', async () => {
    await invite.savePendingInvite(TOKEN_A)
    await invite.savePendingInvite(TOKEN_C)
    await expect(invite.takePendingInvite()).resolves.toBe(TOKEN_C)
    await expect(invite.takePendingInvite()).resolves.toBeNull()
  })
})

/* ============================================================================================ *
 * 13. Source-level guards for what cannot be rendered here
 * ============================================================================================ */

describe('platform-free shared code, no raw environment reads, no service role in request paths (hard rules 3 and 11, ADR-176)', () => {
  const ORACLE_PHRASES = /does not exist|no account|not found|no such account|invalid account/i
  /** Negative guards look at code and strings, not at prose that explains the rule. */
  const stripComments = (source: string): string =>
    source.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:'"`\\])\/\/.*$/gm, '$1')

  it('packages/shared/src/api/member-invites.ts is platform-free', () => {
    const source = stripComments(readSource('../../packages/shared/src/api/member-invites.ts'))
    expect(source).not.toMatch(/from\s+['"]node:/)
    expect(source).not.toMatch(/from\s+['"](?:next|react|react-dom)(?:\/|['"])/)
    expect(source).not.toMatch(/\brequire\s*\(/)
    expect(source).not.toMatch(/\bprocess\.env\b/)
    expect(source).not.toMatch(/\bBuffer\b/)
    expect(source).not.toMatch(/\bMath\.random\b/)
    expect(readSource('../../packages/shared/src/index.ts')).toMatch(/member-invites/)
  })

  it('the token library draws from node:crypto and not from Math.random', () => {
    const source = stripComments(readSource('../../apps/web/lib/member-invite-token.ts'))
    expect(source).toMatch(/node:crypto/)
    expect(source).not.toMatch(/\bMath\.random\b/)
    expect(source).not.toMatch(/\bprocess\.env\b/)
  })

  it.each([
    '../../apps/web/app/api/member-invites/route.ts',
    '../../apps/web/app/api/member-invites/revoke/route.ts',
    '../../apps/web/app/api/member-invites/redeem/route.ts',
    '../../apps/web/app/api/member-identity/unlink/route.ts',
    '../../apps/web/lib/member-invites.ts',
  ])('%s reads no process.env, uses no service-role client and logs nothing directly', (path) => {
    const source = stripComments(readSource(path))
    expect(source).not.toMatch(/\bprocess\.env\b/)
    expect(source).not.toMatch(/SERVICE_ROLE|service_role|serviceRole/)
    expect(source).not.toMatch(/\bconsole\.(?:log|info|debug)\b/)
  })

  it('the accept pages exist outside (console) and member, are noindex and send no referrer', () => {
    for (const path of ['../../apps/web/app/invite/[token]/page.tsx', '../../apps/web/app/invite/continue/page.tsx']) {
      const source = readSource(path)
      expect(source).toMatch(/noindex|index\s*:\s*false/)
      expect(source).toMatch(/no-referrer/)
      expect(stripComments(source)).not.toMatch(ORACLE_PHRASES)
      expect(stripComments(source)).not.toMatch(/\b(?:localStorage|sessionStorage|indexedDB)\b/)
    }
  })

  it('the console panel is a client component that renders the link as a QR code and keeps nothing in browser storage', () => {
    const source = readSource('../../apps/web/app/(console)/members/[memberId]/app-access-panel.tsx')
    expect(source).toMatch(/^\s*(?:\/\*[\s\S]*?\*\/\s*|\/\/.*\n\s*)*['"]use client['"]/)
    expect(source).toMatch(/export\s+(?:function|const)\s+AppAccessPanel\b/)
    expect(source).toMatch(/QRCodeSVG/)
    expect(source).toMatch(/qrcode\.react/)
    expect(stripComments(source)).not.toMatch(/\b(?:localStorage|sessionStorage|indexedDB)\b/)
  })

  it('the web not-linked page gains an invite sentence, still has no input and keeps its pinned strings', () => {
    const source = readSource('../../apps/web/app/not-linked/page.tsx')
    expect(source).toMatch(/invite link/i)
    expect(stripComments(source)).not.toMatch(/<input\b/i)
    expect(stripComments(source)).not.toMatch(ORACLE_PHRASES)
    expect(source).toContain('This account is not linked to a gym')
    expect(source).toContain('Sign out')
  })

  it('the mobile not-linked screen offers "Have an invite?", posts through the redeem route, refreshes, keeps its pinned strings and never queues', () => {
    const source = readSource('../../apps/mobile/app/not-linked.tsx')
    expect(source).toContain('Have an invite?')
    expect(source).toContain('Link my membership')
    expect(source).toContain('/api/member-invites/redeem')
    expect(source).toMatch(/refreshSession\s*\(/)
    expect(source).toContain('Not linked to a gym yet')
    expect(source).toContain('Use a different account')
    expect(source).toContain('Sign out')
    expect(stripComments(source)).not.toMatch(ORACLE_PHRASES)
    expect(stripComments(source)).not.toMatch(/from\s+['"][^'"]*offline-check-in['"]/)
    expect(stripComments(source)).not.toMatch(/\benqueue\w*\s*\(/i)
  })

  it('the mobile deep-link route exists for fitcruxx://invite/<token>', () => {
    const source = readSource('../../apps/mobile/app/invite/[token].tsx')
    expect(source).toMatch(/resolveInviteEntry/)
    expect(stripComments(source)).not.toMatch(ORACLE_PHRASES)
  })
})
