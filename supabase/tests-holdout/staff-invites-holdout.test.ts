/**
 * HOLDOUT TypeScript suite for v2 feature STI (staff invites), batched with INV.
 *
 * Written blind from `openspec/changes/staff-invites/proposal.md` (the sole
 * source of truth for STI) and the INV contract it builds on
 * (`openspec/changes/member-invites/proposal.md`, ADR-176). The author read no
 * visible suite and no implementation. Every module is imported lazily so that
 * a missing or wrong module fails the tests that need it and nothing else.
 *
 * Modules under test, by the names the proposal fixes:
 *   packages/shared/src/api/staff-invites.ts          (+ api/member-invites.ts for INV's names)
 *   packages/shared/src/config/constants.ts           (STAFF_INVITE_LIMITS, STAFF_INVITE_COOKIE_NAME)
 *   apps/web/lib/staff-invites.ts                     (loadStaffAppAccess, peekStaffInvite)
 *   apps/web/app/api/staff-members/route.ts           POST /api/staff-members
 *   apps/web/app/api/staff-invites/route.ts           POST /api/staff-invites
 *   apps/web/app/api/staff-invites/revoke/route.ts    POST /api/staff-invites/revoke
 *   apps/web/app/api/staff-invites/redeem/route.ts    POST /api/staff-invites/redeem
 *   apps/web/app/api/staff-identity/unlink/route.ts   POST /api/staff-identity/unlink
 *   apps/web/app/auth/callback/route.ts               GET  /auth/callback  (staff branch)
 *   apps/web/lib/auth-actions.ts                      startStaffInviteGoogleSignIn
 *   apps/web/app/sign-in/page.tsx                     "?linked=staff" notice
 *
 * Boundary mocks (the only ones): the Supabase client factories
 * (`lib/supabase/server`, `lib/supabase/request`) and Next's request-scoped
 * modules (`next/headers`, `next/navigation`, `next/cache`). Everything else
 * (lib/api.ts, identity-session.ts, shared schemas, the route handlers
 * themselves) runs for real, so the owner-only gate, the envelope and the
 * cookie helpers are exercised exactly as production wires them.
 *
 * The fake Supabase client mirrors PostgREST faithfully where it matters:
 * `.rpc()` is awaitable AND chainable with `.single()` / `.maybeSingle()`
 * (zero or many rows -> PGRST116 error), and arguments are JSON round-tripped
 * so an `undefined` argument disappears exactly as it would on the wire.
 *
 * Decisions on points the proposal leaves open are collected in the report
 * that accompanies this file; each is marked with an "AMBIGUITY n" tag below
 * so a reviewer can find the assertion that depends on it.
 */
import { createHash } from 'node:crypto'
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

// ---------------------------------------------------------------------------
// Boundary harness (hoisted: vi.mock factories run before any import)
// ---------------------------------------------------------------------------
const h = vi.hoisted(() => {
  type Plan = (args: unknown) => { data?: unknown; error?: unknown; throws?: unknown }
  type JarCookie = { name: string; value: string; options: Record<string, unknown> }
  const state = {
    claims: null as Record<string, unknown> | null,
    getUserFails: false,
    plans: {} as Record<string, Plan>,
    rpcCalls: [] as Array<{ fn: string; args: unknown }>,
    tableCalls: [] as Array<{ table: string; method: string }>,
    authCalls: [] as string[],
    events: [] as string[],
    cookieHeader: '',
    cookieSets: [] as JarCookie[],
    cookieDeletes: [] as string[],
    redirects: [] as string[],
    oauthCalls: [] as Array<Record<string, unknown>>,
    oauthFails: false,
    exchangeFails: false,
    exchangedCodes: [] as string[],
  }
  const GOOGLE_URL = 'https://accounts.google.example/o/oauth2/v2/auth?client_id=holdout'

  const reset = () => {
    state.claims = null
    state.getUserFails = false
    state.plans = {}
    state.rpcCalls = []
    state.tableCalls = []
    state.authCalls = []
    state.events = []
    state.cookieHeader = ''
    state.cookieSets = []
    state.cookieDeletes = []
    state.redirects = []
    state.oauthCalls = []
    state.oauthFails = false
    state.exchangeFails = false
    state.exchangedCodes = []
  }

  const wire = (value: unknown) => (value === undefined ? undefined : JSON.parse(JSON.stringify(value)))
  const asRows = (data: unknown): unknown[] => (Array.isArray(data) ? data : data === null || data === undefined ? [] : [data])
  const tooManyOrNone = { code: 'PGRST116', message: 'JSON object requested, multiple (or no) rows returned', details: null, hint: null }

  const rpc = (fn: string, args?: unknown) => {
    state.rpcCalls.push({ fn, args: wire(args) })
    state.events.push(`rpc:${fn}`)
    const run = () => {
      const plan = state.plans[fn]
      if (plan === undefined) return { data: null, error: { code: 'PGRST202', message: `Could not find the function public.${fn}`, details: null, hint: null } }
      const out = plan(wire(args))
      if ('throws' in out) throw out.throws
      return { data: out.data ?? null, error: out.error ?? null }
    }
    return {
      then: (onFulfilled?: (value: unknown) => unknown, onRejected?: (reason: unknown) => unknown) =>
        Promise.resolve().then(run).then(onFulfilled, onRejected),
      single: () =>
        Promise.resolve().then(run).then((result) => {
          if (result.error) return { data: null, error: result.error }
          const rows = asRows(result.data)
          return rows.length === 1 ? { data: rows[0], error: null } : { data: null, error: tooManyOrNone }
        }),
      maybeSingle: () =>
        Promise.resolve().then(run).then((result) => {
          if (result.error) return { data: null, error: result.error }
          const rows = asRows(result.data)
          if (rows.length === 0) return { data: null, error: null }
          return rows.length === 1 ? { data: rows[0], error: null } : { data: null, error: tooManyOrNone }
        }),
    }
  }

  const from = (table: string) => {
    const chain: Record<string, unknown> = {}
    const names = ['select', 'insert', 'update', 'upsert', 'delete', 'eq', 'neq', 'in', 'is', 'order', 'limit',
      'single', 'maybeSingle', 'match', 'filter', 'or', 'not', 'gte', 'lte', 'gt', 'lt', 'range', 'returns']
    for (const method of names) {
      chain[method] = () => {
        state.tableCalls.push({ table, method })
        return chain
      }
    }
    chain.then = (onFulfilled?: (value: unknown) => unknown, onRejected?: (reason: unknown) => unknown) =>
      Promise.resolve({ data: null, error: null }).then(onFulfilled, onRejected)
    return chain
  }

  const auth = {
    getClaims: async () =>
      state.claims === null
        ? { data: null, error: { message: 'Auth session missing' } }
        : { data: { claims: state.claims, header: {}, signature: new Uint8Array() }, error: null },
    getUser: async () =>
      state.claims === null || state.getUserFails
        ? { data: { user: null }, error: { message: 'Auth session missing' } }
        : { data: { user: { id: state.claims.sub } }, error: null },
    refreshSession: async () => {
      state.authCalls.push('refreshSession')
      return { data: { session: null, user: null }, error: null }
    },
    setSession: async () => {
      state.authCalls.push('setSession')
      return { data: { session: null, user: null }, error: null }
    },
    signOut: async () => {
      state.authCalls.push('signOut')
      return { error: null }
    },
    exchangeCodeForSession: async (code: string) => {
      state.authCalls.push('exchangeCodeForSession')
      state.exchangedCodes.push(code)
      return state.exchangeFails
        ? { data: { session: null, user: null }, error: { message: 'exchange failed' } }
        : { data: { session: {}, user: {} }, error: null }
    },
    signInWithOAuth: async (args: Record<string, unknown>) => {
      state.authCalls.push('signInWithOAuth')
      state.events.push('oauth:start')
      state.oauthCalls.push(wire(args))
      return state.oauthFails
        ? { data: { url: null, provider: 'google' }, error: { message: 'oauth unavailable' } }
        : { data: { url: GOOGLE_URL, provider: 'google' }, error: null }
    },
  }

  const makeClient = () => ({ auth, rpc, from })

  const SB_COOKIE = /(?:^|;\s*)sb-[a-z0-9-]+-auth-token(?:\.\d+)?=/i
  const requestClient = (request: Request) => {
    const authorization = request.headers.get('authorization')
    const hasCookieSession = SB_COOKIE.test(request.headers.get('cookie') ?? '')
    if (authorization !== null && hasCookieSession) return null
    if (authorization !== null) {
      const match = /^Bearer (\S+)$/.exec(authorization)
      return match?.[1] ? { supabase: makeClient(), bearer: match[1] } : null
    }
    return hasCookieSession ? { supabase: makeClient() } : null
  }

  const parseCookieHeader = (header: string) =>
    header.split(';').map((part) => part.trim()).filter((part) => part !== '').map((part) => {
      const i = part.indexOf('=')
      return i === -1 ? { name: part, value: '' } : { name: part.slice(0, i), value: part.slice(i + 1) }
    })

  const cookieJar = () => ({
    get: (name: string) => parseCookieHeader(state.cookieHeader).find((c) => c.name === name),
    getAll: (name?: string) => parseCookieHeader(state.cookieHeader).filter((c) => name === undefined || c.name === name),
    has: (name: string) => parseCookieHeader(state.cookieHeader).some((c) => c.name === name),
    set: (first: unknown, value?: unknown, options?: Record<string, unknown>) => {
      state.events.push('cookie:set')
      if (typeof first === 'object' && first !== null) {
        const { name, value: v, ...rest } = first as { name: string; value: string } & Record<string, unknown>
        state.cookieSets.push({ name, value: v, options: rest })
      } else {
        state.cookieSets.push({ name: String(first), value: String(value ?? ''), options: options ?? {} })
      }
    },
    delete: (first: unknown) => {
      state.events.push('cookie:delete')
      state.cookieDeletes.push(typeof first === 'string' ? first : String((first as { name: string }).name))
    },
  })

  const redirect = (url: string) => {
    state.redirects.push(String(url))
    state.events.push('redirect')
    throw Object.assign(new Error('NEXT_REDIRECT'), { digest: `NEXT_REDIRECT;replace;${url};307;` })
  }

  return { state, GOOGLE_URL, reset, makeClient, requestClient, cookieJar, redirect }
})

vi.mock('../../apps/web/lib/supabase/server', () => ({
  createServerSupabase: async () => h.makeClient(),
}))
vi.mock('../../apps/web/lib/supabase/request', () => ({
  createRequestSupabase: (request: Request) => h.requestClient(request),
}))
vi.mock('../../apps/web/node_modules/next/headers', () => ({
  cookies: async () => h.cookieJar(),
  headers: async () => new Headers({ cookie: h.state.cookieHeader }),
}))
vi.mock('../../apps/web/node_modules/next/navigation', () => ({
  redirect: (url: string) => h.redirect(url),
  permanentRedirect: (url: string) => h.redirect(url),
  notFound: () => {
    throw Object.assign(new Error('NEXT_NOT_FOUND'), { digest: 'NEXT_NOT_FOUND' })
  },
  useRouter: () => ({}),
  usePathname: () => '/',
  useSearchParams: () => new URLSearchParams(),
}))
vi.mock('../../apps/web/node_modules/next/cache', () => ({
  revalidatePath: () => undefined,
  revalidateTag: () => undefined,
}))

// ---------------------------------------------------------------------------
// Lazy module loaders (literal specifiers; a missing module fails only its test)
// ---------------------------------------------------------------------------
const staff = () => import('../../packages/shared/src/api/staff-invites')
const member = () => import('../../packages/shared/src/api/member-invites')
const constants = () => import('../../packages/shared/src/config/constants')
const barrel = () => import('../../packages/shared/src/index')
const staffLib = () => import('../../apps/web/lib/staff-invites')
const authActions = () => import('../../apps/web/lib/auth-actions')
const callbackRoute = () => import('../../apps/web/app/auth/callback/route')

type RouteKey = 'create' | 'issue' | 'revoke' | 'redeem' | 'unlink'
type RouteModule = { POST: (request: Request) => Promise<Response> } & Record<string, unknown>
const ROUTES: Record<RouteKey, { path: string; load: () => Promise<unknown> }> = {
  create: { path: '/api/staff-members', load: () => import('../../apps/web/app/api/staff-members/route') },
  issue: { path: '/api/staff-invites', load: () => import('../../apps/web/app/api/staff-invites/route') },
  revoke: { path: '/api/staff-invites/revoke', load: () => import('../../apps/web/app/api/staff-invites/revoke/route') },
  redeem: { path: '/api/staff-invites/redeem', load: () => import('../../apps/web/app/api/staff-invites/redeem/route') },
  unlink: { path: '/api/staff-identity/unlink', load: () => import('../../apps/web/app/api/staff-identity/unlink/route') },
}
const routeModule = async (key: RouteKey): Promise<RouteModule> => (await ROUTES[key].load()) as RouteModule

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------
const ORIGIN = 'https://gym.example'
const WEB_APP_URL = 'https://app.fitcruxx.example'
const STAFF_COOKIE = 'fitcruxx_staff_invite'
const MEMBER_COOKIE = 'fitcruxx_invite'
const SB_COOKIES = 'sb-testproj-auth-token.0=base64-AAAAAAAAAAAA; sb-testproj-auth-token.1=BBBBBBBBBBBB'
const SB_NAME = /^sb-[a-z0-9-]+-auth-token(?:\.\d+)?$/i

const TENANT_ID = 'a1000000-0000-4000-8000-000000000001'
const OWNER_USER = 'a2000000-0000-4000-8000-000000000001'
const OWNER_STAFF = 'a3000000-0000-4000-8000-000000000001'
const MANAGER_USER = 'a2000000-0000-4000-8000-000000000002'
const MANAGER_STAFF = 'a3000000-0000-4000-8000-000000000002'
const DESK_USER = 'a2000000-0000-4000-8000-000000000003'
const DESK_STAFF = 'a3000000-0000-4000-8000-000000000003'
const TRAINER_USER = 'a2000000-0000-4000-8000-000000000004'
const TRAINER_STAFF = 'a3000000-0000-4000-8000-000000000004'
const MEMBER_USER = 'a2000000-0000-4000-8000-000000000005'
const MEMBER_ID = 'a3000000-0000-4000-8000-000000000005'
const PLATFORM_USER = 'a2000000-0000-4000-8000-000000000006'
const NEW_USER = 'a2000000-0000-4000-8000-000000000007'
const PREVIEW_ID = 'a4000000-0000-4000-8000-000000000001'
const STAFF_ID = 'b1000000-0000-4000-8000-000000000001'
const INVITE_ID = 'b2000000-0000-4000-8000-000000000001'
const SUPERSEDED_ID = 'b3000000-0000-4000-8000-000000000001'
const BRANCH_ID = 'b4000000-0000-4000-8000-000000000001'
const EXPIRES_AT = '2031-01-02T03:04:05.000Z'

const authenticated = (extra: Record<string, unknown>) => ({ role: 'authenticated', aud: 'authenticated', ...extra })
const OWNER = authenticated({ sub: OWNER_USER, app_role: 'gym_owner', tenant_id: TENANT_ID, staff_id: OWNER_STAFF })
const MANAGER = authenticated({ sub: MANAGER_USER, app_role: 'gym_manager', tenant_id: TENANT_ID, staff_id: MANAGER_STAFF })
const FRONT_DESK = authenticated({ sub: DESK_USER, app_role: 'front_desk', tenant_id: TENANT_ID, staff_id: DESK_STAFF })
const TRAINER = authenticated({ sub: TRAINER_USER, app_role: 'trainer', tenant_id: TENANT_ID, staff_id: TRAINER_STAFF })
const MEMBER = authenticated({ sub: MEMBER_USER, app_role: 'member', tenant_id: TENANT_ID, member_id: MEMBER_ID })
const SUPER_ADMIN = authenticated({ sub: PLATFORM_USER, app_role: 'super_admin' })
const PLATFORM_SUPPORT = authenticated({ sub: PLATFORM_USER, app_role: 'platform_support' })
const IMPERSONATOR = authenticated({
  sub: OWNER_USER, app_role: 'gym_owner', tenant_id: TENANT_ID, impersonation_session_id: PREVIEW_ID,
})
const UNLINKED = authenticated({ sub: NEW_USER, email: 'new.person@example.com' })
const ANON_KEY_JWT = { sub: NEW_USER, role: 'anon', aud: 'anon' }

const tokenFrom = (seed: number) =>
  Buffer.from(Array.from({ length: 32 }, (_, i) => (i * 73 + seed * 31 + 5) % 256)).toString('base64url')
const TOKEN = tokenFrom(2)
const TOKEN_B = tokenFrom(5)
const MEMBER_TOKEN = tokenFrom(9)
const sha256 = (text: string) => createHash('sha256').update(text, 'utf8').digest('hex')
const HASH = sha256(TOKEN)
const TOKEN_RE = /^[A-Za-z0-9_-]{43}$/
const TOKEN_RUN = /[A-Za-z0-9_-]{43,}/
const HEX64_RUN = /[0-9a-f]{64}/

const LEAK = 'RAW-DB-MESSAGE-do-not-surface-7f3a'
const dbError = (code: unknown) => ({
  error: {
    code,
    message: `${LEAK} duplicate key value violates (email)=(ravi.kumar@example.com)`,
    details: `Key (token_hash)=(${'f'.repeat(64)}) already exists.`,
    hint: null,
  },
})

const createBody = (over: Record<string, unknown> = {}): Record<string, unknown> => ({
  fullName: 'Ravi Kumar',
  email: 'ravi.kumar@example.com',
  phone: '+919876543210',
  role: 'front_desk',
  branchId: BRANCH_ID,
  ...over,
})

const defaultPlans = () => ({
  invite_staff_member: () => ({ data: [{ staff_id: STAFF_ID, invite_id: INVITE_ID, expires_at: EXPIRES_AT }] }),
  issue_staff_invite: () => ({ data: [{ invite_id: INVITE_ID, expires_at: EXPIRES_AT, superseded_invite_id: null }] }),
  revoke_staff_invite: () => ({ data: INVITE_ID }),
  unlink_staff_identity: () => ({ data: null }),
  redeem_staff_invite: () => ({ data: [{ outcome: 'linked', gym_name: 'Iron Box Fitness', staff_role: 'front_desk' }] }),
  peek_staff_invite: () => ({ data: [] }),
  read_staff_app_access: () => ({ data: [] }),
})
const planRpc = (fn: string, plan: (args: unknown) => { data?: unknown; error?: unknown; throws?: unknown }) => {
  h.state.plans[fn] = plan
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const HERE = import.meta.dirname ?? fileURLToPath(new URL('.', import.meta.url))
const repoFile = (relative: string) => resolve(HERE, '../..', relative)
const readRepo = (relative: string) => readFileSync(repoFile(relative), 'utf8')

/** `it.each` spreads array rows into arguments; wrap every value so arrays and objects are passed whole. */
const each = <T>(values: readonly T[]): Array<[T]> => values.map((value) => [value])

const consoleLines: string[] = []
const stringify = (value: unknown): string => {
  try {
    return JSON.stringify(value, (_key, item) =>
      item instanceof Error ? { name: item.name, message: item.message, stack: item.stack } : typeof item === 'bigint' ? String(item) : item) ?? String(value)
  } catch {
    return String(value)
  }
}

type RequestInitLite = {
  json?: unknown
  raw?: string
  rawType?: string
  form?: Record<string, string>
  multipart?: Record<string, string>
  cookie?: string
  headers?: Record<string, string>
}
function req(path: string, init: RequestInitLite = {}): Request {
  const headers = new Headers(init.headers)
  let body: BodyInit | undefined
  if (init.json !== undefined) {
    body = JSON.stringify(init.json)
    headers.set('content-type', 'application/json')
  } else if (init.raw !== undefined) {
    body = init.raw
    headers.set('content-type', init.rawType ?? 'application/json')
  } else if (init.form !== undefined) {
    body = new URLSearchParams(init.form).toString()
    headers.set('content-type', 'application/x-www-form-urlencoded')
  } else if (init.multipart !== undefined) {
    const data = new FormData()
    for (const [key, value] of Object.entries(init.multipart)) data.append(key, value)
    body = data
  }
  const cookie = init.cookie ?? SB_COOKIES
  if (cookie !== '') headers.set('cookie', cookie)
  h.state.cookieHeader = cookie
  return new Request(`${ORIGIN}${path}`, { method: 'POST', headers, body })
}

/** Detects every way a handler can touch the body before it is allowed to. */
function watchBody(request: Request): string[] {
  const reads: string[] = []
  for (const method of ['json', 'text', 'formData', 'arrayBuffer', 'blob', 'clone'] as const) {
    const original = (request[method] as (...args: unknown[]) => unknown).bind(request)
    Object.defineProperty(request, method, {
      configurable: true,
      value: (...args: unknown[]) => {
        reads.push(method)
        return original(...args)
      },
    })
  }
  return reads
}

async function readEnvelope(response: Response): Promise<{ text: string; body: any }> {
  const text = await response.text()
  try {
    return { text, body: JSON.parse(text) }
  } catch {
    return { text, body: null }
  }
}
const noStore = (response: Response) => expect(response.headers.get('cache-control') ?? '').toMatch(/(^|[\s,])no-store($|[\s,;])/i)

async function expectFailure(response: Response, status: number, code: string) {
  const { text, body } = await readEnvelope(response)
  expect(response.status).toBe(status)
  noStore(response)
  expect(response.headers.get('content-type') ?? '').toMatch(/application\/json/i)
  expect(body).not.toBeNull()
  expect(body.ok).toBe(false)
  expect(Object.keys(body).sort()).toEqual(['error', 'ok'])
  expect(body.error.code).toBe(code)
  expect(typeof body.error.message).toBe('string')
  expect(body.error.message.trim().length).toBeGreaterThan(0)
  expect(text).not.toContain(LEAK)
  expect(text).not.toMatch(/\bGL0\d\d\b/)
  expect(text).not.toMatch(HEX64_RUN)
  return body
}
async function expectAnyFailure(response: Response) {
  const { text, body } = await readEnvelope(response)
  expect(response.status).toBeGreaterThanOrEqual(400)
  noStore(response)
  expect(body).not.toBeNull()
  expect(body.ok).toBe(false)
  expect(typeof body.error.code).toBe('string')
  expect(text).not.toContain(LEAK)
  return body
}
async function expectSuccess(response: Response) {
  const { body } = await readEnvelope(response)
  expect([200, 201]).toContain(response.status)
  noStore(response)
  expect(response.headers.get('content-type') ?? '').toMatch(/application\/json/i)
  expect(body).not.toBeNull()
  expect(body.ok).toBe(true)
  expect(Object.keys(body).sort()).toEqual(['data', 'ok'])
  return body.data
}

function parseSetCookie(raw: string) {
  const [pair = '', ...attributeParts] = raw.split(';').map((part) => part.trim())
  const eq = pair.indexOf('=')
  const attrs = new Map<string, string>()
  for (const part of attributeParts) {
    const i = part.indexOf('=')
    attrs.set((i === -1 ? part : part.slice(0, i)).toLowerCase(), i === -1 ? '' : part.slice(i + 1))
  }
  return { raw, name: eq === -1 ? pair : pair.slice(0, eq), value: eq === -1 ? '' : pair.slice(eq + 1), attrs }
}
type SetCookie = ReturnType<typeof parseSetCookie>
const setCookies = (response: Response): SetCookie[] => response.headers.getSetCookie().map(parseSetCookie)
const isExpiring = (cookie: SetCookie) =>
  cookie.value === '' &&
  ((cookie.attrs.has('max-age') && Number(cookie.attrs.get('max-age')) <= 0) ||
    (cookie.attrs.has('expires') && Date.parse(cookie.attrs.get('expires') ?? '') <= Date.now()))
const sbNamesIn = (cookieHeader: string) =>
  cookieHeader.split(';').map((part) => part.split('=')[0]?.trim() ?? '').filter((name) => SB_NAME.test(name))

/** The invite cookie is cleared either by a Set-Cookie expiry or by the Next cookie jar. */
function inviteCookieCleared(response: Response, name = STAFF_COOKIE): boolean {
  return (
    setCookies(response).some((cookie) => cookie.name === name && isExpiring(cookie)) ||
    h.state.cookieDeletes.includes(name) ||
    h.state.cookieSets.some((set) => set.name === name && set.value === '' &&
      (Number(set.options.maxAge ?? 1) <= 0 || (set.options.expires instanceof Date && set.options.expires.getTime() <= Date.now())))
  )
}
function inviteCookieTouched(response: Response, name = STAFF_COOKIE): boolean {
  return (
    setCookies(response).some((cookie) => cookie.name === name) ||
    h.state.cookieDeletes.includes(name) ||
    h.state.cookieSets.some((set) => set.name === name)
  )
}
function expectAuthCookiesExpired(response: Response, requestCookieHeader: string) {
  const cookies = setCookies(response)
  const expired = new Set(cookies.filter(isExpiring).map((cookie) => cookie.name))
  for (const name of sbNamesIn(requestCookieHeader)) expect(expired.has(name), `${name} must be expired`).toBe(true)
  for (const cookie of cookies.filter((c) => SB_NAME.test(c.name))) {
    expect(isExpiring(cookie), `${cookie.name} must only ever be expired, never (re)issued`).toBe(true)
    expect(cookie.attrs.get('path')).toBe('/')
  }
}
function expectNoCookieChanges(response: Response) {
  const touched = setCookies(response).filter((cookie) => SB_NAME.test(cookie.name) || cookie.name === STAFF_COOKIE)
  expect(touched).toEqual([])
  expect(inviteCookieTouched(response)).toBe(false)
}

const location = (response: Response): string | null => {
  const raw = response.headers.get('location')
  if (raw === null) return null
  const url = new URL(raw, ORIGIN)
  return url.pathname + url.search
}
const rpcOf = (fn: string) => h.state.rpcCalls.filter((call) => call.fn === fn)
const consoleText = () => consoleLines.join('\n')

async function settle(run: () => Promise<Response>): Promise<{ response?: Response; thrown?: unknown }> {
  try {
    return { response: await run() }
  } catch (thrown) {
    return { thrown }
  }
}
async function post(key: RouteKey, request: Request): Promise<Response> {
  return (await routeModule(key)).POST(request)
}

beforeEach(() => {
  h.reset()
  h.state.claims = OWNER
  Object.assign(h.state.plans, defaultPlans())
  consoleLines.length = 0
  for (const level of ['log', 'info', 'warn', 'error', 'debug'] as const) {
    vi.spyOn(console, level).mockImplementation((...args: unknown[]) => {
      consoleLines.push(stringify(args))
    })
  }
  vi.stubEnv('WEB_APP_URL', WEB_APP_URL)
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_URL', 'https://abc.supabase.example')
  vi.stubEnv('NEXT_PUBLIC_SUPABASE_ANON_KEY', 'anon-key-for-holdout')
})
afterEach(() => {
  vi.restoreAllMocks()
  vi.unstubAllEnvs()
})

// ===========================================================================
// Fixture sanity (a bug in this file must not masquerade as an implementation bug)
// ===========================================================================
describe('holdout fixtures', () => {
  it('uses valid, distinct 43-character base64url tokens that exercise "-" and "_"', () => {
    for (const token of [TOKEN, TOKEN_B, MEMBER_TOKEN]) expect(token).toMatch(TOKEN_RE)
    expect(new Set([TOKEN, TOKEN_B, MEMBER_TOKEN]).size).toBe(3)
    expect(TOKEN + TOKEN_B).toMatch(/[-]/)
    expect(TOKEN + TOKEN_B).toMatch(/[_]/)
    expect(HASH).toMatch(/^[0-9a-f]{64}$/)
  })
})

// ===========================================================================
// STI-005 / STI-001: roles, labels
// ===========================================================================
describe('STI-005 invitable roles and labels', () => {
  it('lists exactly manager, front desk, trainer, in that order', async () => {
    const { STAFF_INVITE_ROLES } = await staff()
    expect([...STAFF_INVITE_ROLES]).toEqual(['gym_manager', 'front_desk', 'trainer'])
  })

  it('never admits an owner, platform or member role', async () => {
    const { STAFF_INVITE_ROLES } = await staff()
    for (const forbidden of ['gym_owner', 'super_admin', 'platform_support', 'member']) {
      expect(([...STAFF_INVITE_ROLES] as string[]).includes(forbidden)).toBe(false)
    }
  })

  it('labels exactly the three roles with the spec wording and nothing else', async () => {
    const { STAFF_INVITE_ROLE_LABELS, STAFF_INVITE_ROLES } = await staff()
    expect({ ...STAFF_INVITE_ROLE_LABELS }).toEqual({ gym_manager: 'manager', front_desk: 'front desk', trainer: 'trainer' })
    expect(Object.keys(STAFF_INVITE_ROLE_LABELS).sort()).toEqual([...STAFF_INVITE_ROLES].sort())
  })

  it.each(['gym_owner', 'super_admin', 'member', '__proto__', 'constructor', 'toString'])(
    'has no own label for %s (lookups by role must not fall through the prototype)',
    async (role) => {
      const { STAFF_INVITE_ROLE_LABELS } = await staff()
      expect(Object.hasOwn(STAFF_INVITE_ROLE_LABELS, role)).toBe(false)
    },
  )
})

// ===========================================================================
// Schemas (STI-001, STI-002, STI-004, STI-008, STI-012)
// ===========================================================================
describe('STI-001 staffMemberInviteRequestSchema', () => {
  const parse = async (input: unknown) => (await staff()).staffMemberInviteRequestSchema.safeParse(input)

  it('accepts a complete request and keeps every field as given', async () => {
    const result = await parse(createBody())
    expect(result.success).toBe(true)
    expect((result as any).data).toEqual(createBody())
  })

  it('accepts the minimum (name, email, role) and leaves phone and branch undefined', async () => {
    const result = await parse({ fullName: 'Asha Nair', email: 'asha@example.com', role: 'trainer' })
    expect(result.success).toBe(true)
    expect((result as any).data.phone).toBeUndefined()
    expect((result as any).data.branchId).toBeUndefined()
  })

  it('accepts each of the three invitable roles', async () => {
    for (const role of ['gym_manager', 'front_desk', 'trainer']) {
      expect((await parse(createBody({ role }))).success, role).toBe(true)
    }
  })

  it('trims the name and the email, and does not otherwise rewrite them (AMBIGUITY 7: case is preserved)', async () => {
    const result = await parse(createBody({ fullName: '  Ravi Kumar \n', email: '\t Ravi.Kumar@Example.COM  ' }))
    expect(result.success).toBe(true)
    expect((result as any).data.fullName).toBe('Ravi Kumar')
    expect((result as any).data.email).toBe('Ravi.Kumar@Example.COM')
  })

  it('turns an empty-string phone into "no phone"', async () => {
    const result = await parse(createBody({ phone: '' }))
    expect(result.success).toBe(true)
    expect((result as any).data.phone).toBeUndefined()
  })

  it.each(each([
    'gym_owner', 'super_admin', 'platform_support', 'member', 'Gym_Manager', 'GYM_MANAGER', 'Trainer', 'TRAINER',
    'Front_Desk', 'front-desk', 'front desk', 'manager', 'owner', 'gym_manager ', ' trainer', 'trainer\n', '',
    '__proto__', 'constructor', null, undefined, 0, 1, true, ['trainer'], { role: 'trainer' },
  ]))('rejects role %j', async (role) => {
    expect((await parse(createBody({ role }))).success).toBe(false)
  })

  it('rejects a request with no role at all', async () => {
    const { role: _dropped, ...rest } = createBody()
    expect((await parse(rest)).success).toBe(false)
  })

  it.each([
    ['tenantId', TENANT_ID], ['tenant_id', TENANT_ID], ['userId', NEW_USER], ['user_id', NEW_USER], ['isActive', false],
    ['is_active', false], ['staffId', STAFF_ID], ['id', STAFF_ID], ['status', 'active'], ['extra', 1],
    ['constructor', { prototype: { admin: true } }], ['prototype', {}], ['role2', 'gym_owner'],
  ])('is strict: rejects the unknown key %s', async (key, value) => {
    expect((await parse({ ...createBody(), [key]: value })).success).toBe(false)
  })

  it('rejects a JSON-sourced "__proto__" key without polluting anything', async () => {
    const hostile = JSON.parse(
      '{"fullName":"Ravi Kumar","email":"r@example.com","role":"trainer","__proto__":{"role":"gym_owner","polluted":true}}',
    )
    expect((await parse(hostile)).success).toBe(false)
    expect(({} as Record<string, unknown>).polluted).toBeUndefined()
    expect(({} as Record<string, unknown>).role).toBeUndefined()
  })

  it('rejects an own "__proto__" property defined directly on the object', async () => {
    const hostile: Record<string, unknown> = createBody()
    Object.defineProperty(hostile, '__proto__', { value: { role: 'gym_owner' }, enumerable: true, configurable: true })
    expect((await parse(hostile)).success).toBe(false)
  })

  it.each(each([null, undefined, 'text', 42, true, [], [createBody()]]))('rejects the non-object input %j', async (input) => {
    expect((await parse(input)).success).toBe(false)
  })

  describe('fullName', () => {
    it.each([['empty', ''], ['spaces only', '    '], ['whitespace controls only', ' \n\t\r '], ['121 characters', 'x'.repeat(121)]])(
      'rejects %s',
      async (_label, fullName) => {
        expect((await parse(createBody({ fullName }))).success).toBe(false)
      },
    )
    it.each(each([123, null, undefined, [], {}, true]))('rejects the non-string name %j', async (fullName) => {
      expect((await parse(createBody({ fullName }))).success).toBe(false)
    })
    it('accepts exactly 120 characters, and measures after trimming', async () => {
      expect((await parse(createBody({ fullName: 'x'.repeat(120) }))).success).toBe(true)
      expect((await parse(createBody({ fullName: `  ${'x'.repeat(120)}  ` }))).success).toBe(true)
    })
    it('accepts a single character', async () => {
      expect((await parse(createBody({ fullName: 'A' }))).success).toBe(true)
    })
    it.each(['आशा शर्मा', 'José Núñez', "Robert'); DROP TABLE staff;--", 'O\'Brien <b>x</b>'])(
      'accepts and does not rewrite the real-world or hostile-looking name %s',
      async (fullName) => {
        const result = await parse(createBody({ fullName }))
        expect(result.success).toBe(true)
        expect((result as any).data.fullName).toBe(fullName)
      },
    )
  })

  describe('email', () => {
    it.each(['asha@example.com', 'Asha.Sharma+gym@Example.COM', 'a.b-c_d@sub.example.co.in', 'a@b.co'])(
      'accepts %s',
      async (email) => {
        expect((await parse(createBody({ email }))).success).toBe(true)
      },
    )
    it.each([
      ['empty', ''], ['spaces', '   '], ['no at sign', 'plainaddress'], ['empty local part', '@example.com'],
      ['empty domain', 'asha@'], ['undotted domain', 'asha@example'], ['double at', 'asha@@example.com'],
      ['two addresses with two ats', 'a@b.co@c.co'], ['space in local part', 'as ha@example.com'],
      ['space in domain', 'asha@exa mple.com'], ['internal newline', 'asha@example.com\nbcc:evil@example.com'],
      ['internal CRLF header injection', 'asha@example.com\r\nBcc: v@example.com'], ['internal tab', 'asha@exa\tmple.com'],
      ['internal no-break space', 'as\u00a0ha@example.com'], ['internal line separator', 'as\u2028ha@example.com'],
      ['fullwidth at sign look-alike', 'asha\uff20example.com'], ['ideographic full stop look-alike', 'asha@example\u3002com'],
      ['comma instead of dot', 'asha@example,com'], ['trailing dot only domain', 'asha@example.'], ['leading dot domain', 'asha@.com'],
    ])('rejects %s', async (_label, email) => {
      expect((await parse(createBody({ email }))).success).toBe(false)
    })
    it('trims a surrounding newline instead of keeping or rejecting it', async () => {
      const result = await parse(createBody({ email: 'asha@example.com\n' }))
      expect(result.success).toBe(true)
      expect((result as any).data.email).toBe('asha@example.com')
    })
    it('accepts exactly 254 characters and rejects 255 (AMBIGUITY 8: boundary on a syntactically plain address)', async () => {
      const domain = '@example.com'
      expect((await parse(createBody({ email: `${'a'.repeat(254 - domain.length)}${domain}` }))).success).toBe(true)
      expect((await parse(createBody({ email: `${'a'.repeat(255 - domain.length)}${domain}` }))).success).toBe(false)
      expect((await parse(createBody({ email: `${'a'.repeat(300)}${domain}` }))).success).toBe(false)
    })
    it.each(each([123, null, undefined, [], {}, true]))('rejects the non-string email %j', async (email) => {
      expect((await parse(createBody({ email }))).success).toBe(false)
    })
  })

  describe('phone', () => {
    it.each(['+919876543210', '+14155552671', '+12345678', '+123456789012345', '+447911123456'])('accepts %s', async (phone) => {
      const result = await parse(createBody({ phone }))
      expect(result.success).toBe(true)
      expect((result as any).data.phone).toBe(phone)
    })
    it.each([
      ['no plus', '919876543210'], ['leading zero after plus', '+0123456789'], ['spaces', '+91 98765 43210'],
      ['dashes', '+91-9876543210'], ['brackets', '(+91)9876543210'], ['seven digits', '+1234567'],
      ['sixteen digits', '+1234567890123456'], ['letters', '+91abcdefghij'], ['fullwidth digits', '+\uff19\uff11\uff19\uff18\uff17\uff16\uff15\uff14\uff13\uff12\uff11\uff10'],
      ['trailing newline', '+919876543210\n'], ['double plus', '++919876543210'], ['plus only', '+'], ['local number', '09876543210'],
      ['embedded newline', '+91987654\n3210'],
    ])('rejects %s', async (_label, phone) => {
      expect((await parse(createBody({ phone }))).success).toBe(false)
    })
    it.each(each([123, [], {}, true, 919876543210]))('rejects the non-string phone %j', async (phone) => {
      expect((await parse(createBody({ phone }))).success).toBe(false)
    })
  })

  describe('branchId', () => {
    it.each(each([
      'not-a-uuid', `${BRANCH_ID}\n`, ` ${BRANCH_ID}`, BRANCH_ID.replaceAll('-', ''), `{${BRANCH_ID}}`, `${BRANCH_ID}x`,
      'zzzzzzzz-zzzz-4zzz-8zzz-zzzzzzzzzzzz', 123, [], {},
    ]))('rejects %j', async (branchId) => {
      expect((await parse(createBody({ branchId }))).success).toBe(false)
    })
  })
})

describe('STI-002 staffInviteIssueRequestSchema and staffInviteRevokeRequestSchema', () => {
  const issue = async (input: unknown) => (await staff()).staffInviteIssueRequestSchema.safeParse(input)
  const revoke = async (input: unknown) => (await staff()).staffInviteRevokeRequestSchema.safeParse(input)

  it('accept exactly one uuid key each', async () => {
    expect((await issue({ staffId: STAFF_ID })).success).toBe(true)
    expect((await revoke({ inviteId: INVITE_ID })).success).toBe(true)
  })

  it('refuse each other\'s key and the member family\'s keys', async () => {
    expect((await issue({ inviteId: INVITE_ID })).success).toBe(false)
    expect((await revoke({ staffId: STAFF_ID })).success).toBe(false)
    expect((await issue({ memberId: STAFF_ID })).success).toBe(false)
    expect((await revoke({ memberId: INVITE_ID })).success).toBe(false)
  })

  it.each([
    ['extra role', { role: 'gym_owner' }], ['extra tenantId', { tenantId: TENANT_ID }], ['extra email', { email: 'x@example.com' }],
    ['extra constructor', { constructor: { prototype: {} } }],
  ])('are strict: %s is rejected', async (_label, extra) => {
    expect((await issue({ staffId: STAFF_ID, ...extra })).success).toBe(false)
    expect((await revoke({ inviteId: INVITE_ID, ...extra })).success).toBe(false)
  })

  it('reject a JSON "__proto__" smuggled next to a valid id', async () => {
    expect((await issue(JSON.parse(`{"staffId":"${STAFF_ID}","__proto__":{"role":"gym_owner"}}`))).success).toBe(false)
    expect((await revoke(JSON.parse(`{"inviteId":"${INVITE_ID}","__proto__":{"x":1}}`))).success).toBe(false)
  })

  it.each(each([
    '', 'not-a-uuid', `${STAFF_ID}\n`, ` ${STAFF_ID}`, STAFF_ID.replaceAll('-', ''), `{${STAFF_ID}}`, `${STAFF_ID}x`, 123, null, undefined, [], {},
  ]))('reject the id %j', async (id) => {
    expect((await issue({ staffId: id })).success).toBe(false)
    expect((await revoke({ inviteId: id })).success).toBe(false)
  })

  it.each(each([null, undefined, 'text', 42, [], [{ staffId: STAFF_ID }]]))('reject the non-object input %j', async (input) => {
    expect((await issue(input)).success).toBe(false)
    expect((await revoke(input)).success).toBe(false)
  })
})

describe('STI-004 staffInviteRedeemRequestSchema', () => {
  const redeem = async (input: unknown) => (await staff()).staffInviteRedeemRequestSchema.safeParse(input)

  it('accepts exactly a 43-character base64url token and nothing else', async () => {
    expect((await redeem({ token: TOKEN })).success).toBe(true)
    expect((await redeem({ token: TOKEN_B })).success).toBe(true)
    expect((await redeem({ token: 'A'.repeat(43) })).success).toBe(true)
  })

  it.each([
    ['empty', ''], ['42 characters', TOKEN.slice(1)], ['44 characters', `${TOKEN}A`], ['base64 padding', `${TOKEN.slice(0, 42)}=`],
    ['standard-alphabet plus', `${TOKEN.slice(0, 20)}+${TOKEN.slice(21)}`], ['standard-alphabet slash', `${TOKEN.slice(0, 20)}/${TOKEN.slice(21)}`],
    ['trailing newline', `${TOKEN}\n`], ['leading space', ` ${TOKEN}`], ['trailing space', `${TOKEN} `],
    ['internal space', `${TOKEN.slice(0, 20)} ${TOKEN.slice(21)}`], ['internal newline', `${TOKEN.slice(0, 20)}\n${TOKEN.slice(21)}`],
    ['Cyrillic a look-alike', `\u0430${TOKEN.slice(1)}`], ['fullwidth letter', `\uff21${TOKEN.slice(1)}`],
    ['zero-width space', `${TOKEN.slice(0, 20)}\u200b${TOKEN.slice(20, 42)}`], ['NUL byte', `${TOKEN.slice(0, 42)}\u0000`],
    ['percent-encoding', `%41${TOKEN.slice(3)}`], ['a whole link', `https://app.example/staff-invite/${TOKEN}`],
    ['a member link', `https://app.example/invite/${TOKEN}`], ['two tokens', `${TOKEN}${TOKEN_B}`], ['quoted', `"${TOKEN.slice(1, 42)}"`],
  ])('rejects a token that is %s', async (_label, token) => {
    expect((await redeem({ token })).success).toBe(false)
  })

  it.each(each([123, null, undefined, [TOKEN], { value: TOKEN }, true]))('rejects the non-string token %j', async (token) => {
    expect((await redeem({ token })).success).toBe(false)
  })

  it.each([
    ['role', 'gym_owner'], ['staffId', STAFF_ID], ['tenantId', TENANT_ID], ['gymId', TENANT_ID], ['memberId', MEMBER_ID], ['email', 'a@b.co'],
  ])('is strict: the invitee cannot add %s (the role is the owner\'s alone)', async (key, value) => {
    expect((await redeem({ token: TOKEN, [key]: value })).success).toBe(false)
  })

  it('rejects a body with no token', async () => {
    expect((await redeem({})).success).toBe(false)
  })
})

describe('STI-008 staffUnlinkRequestSchema', () => {
  const unlink = async (input: unknown) => (await staff()).staffUnlinkRequestSchema.safeParse(input)

  it('accepts a uuid and a reason of 3 to 200 trimmed characters, and trims it', async () => {
    const result = await unlink({ staffId: STAFF_ID, reason: '  Left the gym \n' })
    expect(result.success).toBe(true)
    expect((result as any).data).toEqual({ staffId: STAFF_ID, reason: 'Left the gym' })
  })

  it.each([['exactly 3', 'abc', true], ['exactly 200', 'r'.repeat(200), true], ['200 after trimming', `  ${'r'.repeat(200)}  `, true],
    ['2 characters', 'ab', false], ['2 after trimming', '   ab   ', false], ['201 characters', 'r'.repeat(201), false],
    ['empty', '', false], ['whitespace only', '     ', false]])('reason %s -> %s', async (_label, reason, ok) => {
    expect((await unlink({ staffId: STAFF_ID, reason })).success).toBe(ok)
  })

  it('rejects a missing reason, a non-string reason, a missing staffId and the member family\'s key', async () => {
    expect((await unlink({ staffId: STAFF_ID })).success).toBe(false)
    expect((await unlink({ staffId: STAFF_ID, reason: 12345 })).success).toBe(false)
    expect((await unlink({ staffId: STAFF_ID, reason: null })).success).toBe(false)
    expect((await unlink({ reason: 'Left the gym' })).success).toBe(false)
    expect((await unlink({ memberId: STAFF_ID, reason: 'Left the gym' })).success).toBe(false)
  })

  it('is strict about extra and prototype keys', async () => {
    expect((await unlink({ staffId: STAFF_ID, reason: 'Left the gym', role: 'gym_owner' })).success).toBe(false)
    expect((await unlink(JSON.parse(`{"staffId":"${STAFF_ID}","reason":"Left","__proto__":{"x":1}}`))).success).toBe(false)
  })
})

// ===========================================================================
// STI-016: refusal copy, notice, share message
// ===========================================================================
const STAFF_COPY = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym owner to send a new one.",
  email_mismatch: "This invite wasn't sent to this Google account. Sign in with the email your gym owner has on file for you, or ask them to update it.",
  identity_unverified: "Sign in with Google to use this invite. This account wasn't created with a verified Google sign-in.",
  account_already_linked: "This account is already linked to a gym and can't be linked again. Ask your gym owner to send the invite to a different email.",
  rate_limited: 'Too many attempts. Wait a few minutes, then try again.',
} as const
const MEMBER_COPY = {
  invite_unavailable: "This invite can't be used. It may have expired or been replaced. Ask your gym to send a new one.",
  email_mismatch: "This invite wasn't sent to this Google account. Sign in with the email your gym has on file for you, or ask them to update it.",
  account_already_linked: "This account is already joined as a member and can't be linked again. Ask your gym to send the invite to a different email.",
} as const
const OUTCOMES = Object.keys(STAFF_COPY) as Array<keyof typeof STAFF_COPY>

describe('STI-016 staff refusal copy', () => {
  it('is exactly the five staff sentences, verbatim, with no other keys', async () => {
    const { STAFF_INVITE_REFUSAL_COPY } = await staff()
    expect({ ...STAFF_INVITE_REFUSAL_COPY }).toEqual(STAFF_COPY)
    expect(Object.keys(STAFF_INVITE_REFUSAL_COPY).sort()).toEqual([...OUTCOMES].sort())
  })

  it('covers exactly the refusal outcomes of the shared INV vocabulary', async () => {
    const { INVITE_REDEEM_OUTCOMES } = await member()
    const { STAFF_INVITE_REFUSAL_COPY } = await staff()
    const refusals = [...INVITE_REDEEM_OUTCOMES].filter((o: string) => o !== 'linked' && o !== 'already_linked_here')
    expect(Object.keys(STAFF_INVITE_REFUSAL_COPY).sort()).toEqual(refusals.sort())
  })

  it.each(OUTCOMES)('%s: staffInviteRefusalMessage returns the staff sentence verbatim', async (code) => {
    const { staffInviteRefusalMessage } = await staff()
    expect(staffInviteRefusalMessage(code)).toBe(STAFF_COPY[code])
  })

  it.each(Object.keys(MEMBER_COPY) as Array<keyof typeof MEMBER_COPY>)(
    '%s differs from the member sentence (the staff copy names the gym owner)',
    async (code) => {
      const { STAFF_INVITE_REFUSAL_COPY } = await staff()
      expect(STAFF_INVITE_REFUSAL_COPY[code]).not.toBe(MEMBER_COPY[code])
      expect(STAFF_INVITE_REFUSAL_COPY[code]).not.toMatch(/joined as a member/i)
    },
  )

  it.each(OUTCOMES)('%s contains no email-like text, no digits, no placeholders and ends with a full stop', async (code) => {
    const { staffInviteRefusalMessage } = await staff()
    const text = staffInviteRefusalMessage(code)
    expect(text).not.toMatch(/@/)
    expect(text).not.toMatch(/\S+@\S+/)
    expect(text).not.toMatch(/\d/)
    expect(text).not.toMatch(/[{}$<>]|undefined|null|NaN|\[object/)
    expect(text.endsWith('.')).toBe(true)
  })

  it.each([
    '__proto__', 'constructor', 'toString', 'valueOf', 'hasOwnProperty', 'prototype', '', ' ', 'linked', 'already_linked_here',
    'EMAIL_MISMATCH', 'Email_Mismatch', 'email_mismatch ', ' email_mismatch', 'rate_limited\n', 'rate-limited', 'unknown', '0', 'null', 'undefined',
    'email_mismatch\u0000', 'e\u0301mail_mismatch', '\u{1f600}',
  ])('falls back to the invite_unavailable sentence for the unknown code %j and never throws', async (code) => {
    const { staffInviteRefusalMessage } = await staff()
    let text: unknown
    expect(() => {
      text = staffInviteRefusalMessage(code)
    }).not.toThrow()
    expect(text).toBe(STAFF_COPY.invite_unavailable)
  })

  it('resolves codes by own property only (a polluted Object.prototype cannot inject copy)', async () => {
    const { staffInviteRefusalMessage } = await staff()
    Object.defineProperty(Object.prototype, 'polluted_outcome', { value: 'PWNED', configurable: true, enumerable: false, writable: true })
    try {
      expect(staffInviteRefusalMessage('polluted_outcome')).toBe(STAFF_COPY.invite_unavailable)
    } finally {
      delete (Object.prototype as unknown as Record<string, unknown>).polluted_outcome
    }
  })
})

describe('STI-016 staffInviteNotice', () => {
  const expected = (gym: string, role: string) =>
    `By linking, you let ${gym} connect this Google account (your name and email) to your staff profile as ${role}. FitCruxx processes it on ${gym}'s behalf so you can sign in and do your work. Ask ${gym}'s owner to unlink it at any time.`

  it('matches the proposal wording exactly', async () => {
    const { staffInviteNotice } = await staff()
    expect(staffInviteNotice('Iron Box Fitness', 'front desk')).toBe(expected('Iron Box Fitness', 'front desk'))
    expect(staffInviteNotice('Iron Box Fitness', 'manager')).toBe(expected('Iron Box Fitness', 'manager'))
  })

  it('names the role and the data processed, and is not the member notice', async () => {
    const { staffInviteNotice } = await staff()
    const text = staffInviteNotice('Iron Box Fitness', 'trainer')
    expect(text).toContain('staff profile as trainer')
    expect(text).toContain('your name and email')
    expect(text).not.toMatch(/membership record|visits, payments and messages/)
    expect(text).not.toMatch(/\d/)
  })

  it.each([
    ['Iron Box Fitness', 'front desk'],
    ['A$&B', '$1'], ["Gym $' and $` here", 'tra$&iner'], ['$$', '$$'], ['{role}', 'trainer'], ['{gym}', 'manager'],
    ['Gym {role}', '{gym}'], ['%s %d %%', 'x'], ['<script>alert(1)</script>', '<img src=x onerror=alert(1)>'],
    ['Line\nBreak Gym', 'front\ndesk'], ["'; DROP TABLE staff; --", 'manager'], ['\u{1f600} Gym', 'trainer'], ['\\', '\\\\'],
    ['${role}', '${gym}'], ['__proto__', 'constructor'],
  ])('inserts the hostile gym %j and role %j literally, once per placeholder, and never re-expands inserted text', async (gym, role) => {
    const { staffInviteNotice } = await staff()
    expect(staffInviteNotice(gym, role)).toBe(expected(gym, role))
  })
})

describe('STI-016 staffInviteShareMessage', () => {
  const LINK = `${WEB_APP_URL}/staff-invite/${TOKEN}`
  const input = (over: Record<string, string> = {}) => ({
    staffName: 'Asha Sharma', gymName: 'Iron Box Fitness', roleLabel: 'front desk', email: 'asha@example.com', link: LINK, ...over,
  })
  const count = (haystack: string, needle: string) => (needle === '' ? 0 : haystack.split(needle).length - 1)

  it('greets by first name only and carries the gym, the role, the Google email and the link', async () => {
    const { staffInviteShareMessage } = await staff()
    const text = staffInviteShareMessage(input())
    expect(text).toContain('Asha')
    expect(text).not.toContain('Sharma')
    expect(text).toContain('Iron Box Fitness')
    expect(text).toContain('front desk')
    expect(text).toContain('asha@example.com')
    expect(count(text, LINK)).toBe(1)
    expect(text).not.toMatch(/undefined|null|NaN|\[object/)
  })

  it('is staff wording, not the member message', async () => {
    const { staffInviteShareMessage } = await staff()
    expect(staffInviteShareMessage(input())).not.toMatch(/membership/i)
  })

  it('does not put the raw token anywhere but inside the link', async () => {
    const { staffInviteShareMessage } = await staff()
    expect(count(staffInviteShareMessage(input()), TOKEN)).toBe(1)
  })

  it.each([
    ['leading and trailing spaces', '  Asha   Sharma  ', 'Asha'], ['a tab separator', 'Asha\tSharma', 'Asha'], ['a newline then a URL', 'Asha\nhttps://evil.example/x', 'Asha'],
    ['a single name', 'Asha', 'Asha'],
  ])('takes the first name only for %s', async (_label, staffName, first) => {
    const { staffInviteShareMessage } = await staff()
    const text = staffInviteShareMessage(input({ staffName }))
    expect(text).toContain(first)
    expect(text).not.toContain('Sharma')
    expect(text).not.toContain('evil.example')
  })

  it.each([
    ['staffName', '{link} Kumar'], ['staffName', '$& Kumar'], ['gymName', '{link}'], ['gymName', '{email}'], ['gymName', '$&$1'],
    ['roleLabel', '{gym}'], ['roleLabel', '$`'], ['gymName', '{staffName}'],
  ])('keeps hostile %s %j literal and never lets it duplicate the link or the email', async (field, value) => {
    const { staffInviteShareMessage } = await staff()
    const baseline = staffInviteShareMessage(input())
    const text = staffInviteShareMessage(input({ [field]: value }))
    expect(text).toContain(value.split(' ')[0] as string)
    expect(count(text, LINK)).toBe(count(baseline, LINK))
    expect(count(text, 'asha@example.com')).toBe(count(baseline, 'asha@example.com'))
  })

  it('survives a blank name without printing placeholder garbage', async () => {
    const { staffInviteShareMessage } = await staff()
    for (const staffName of ['', '   ']) {
      const text = staffInviteShareMessage(input({ staffName }))
      expect(text).toContain(LINK)
      expect(text).toContain('Iron Box Fitness')
      expect(text).not.toMatch(/undefined|null|NaN|\[object/)
    }
  })
})

// ===========================================================================
// STI-014: link building and parsing
// ===========================================================================
describe('STI-014 buildStaffInviteLink', () => {
  it('is origin + /staff-invite/ + token, exactly', async () => {
    const { buildStaffInviteLink } = await staff()
    expect(buildStaffInviteLink('https://app.fitcruxx.example', TOKEN)).toBe(`https://app.fitcruxx.example/staff-invite/${TOKEN}`)
    expect(buildStaffInviteLink('http://127.0.0.1:3000', TOKEN_B)).toBe(`http://127.0.0.1:3000/staff-invite/${TOKEN_B}`)
  })

  it('has no query, no hash and is not the member path', async () => {
    const { buildStaffInviteLink } = await staff()
    const link = buildStaffInviteLink(WEB_APP_URL, TOKEN)
    expect(link).not.toMatch(/[?#]/)
    expect(new URL(link).pathname).toBe(`/staff-invite/${TOKEN}`)
    expect(link).not.toContain('/invite/' + TOKEN)
  })

  it('round-trips through parseStaffInviteToken and is not a member link', async () => {
    const { buildStaffInviteLink, parseStaffInviteToken } = await staff()
    const { parseInviteToken } = await member()
    const link = buildStaffInviteLink(WEB_APP_URL, TOKEN)
    expect(parseStaffInviteToken(link)).toBe(TOKEN)
    expect(parseInviteToken(link)).toBeNull()
  })
})

describe('STI-014 parseStaffInviteToken', () => {
  const HOST = 'app.fitcruxx.example'
  const link = (token: string, host = HOST) => `https://${host}/staff-invite/${token}`
  const parse = async (input: string) => (await staff()).parseStaffInviteToken(input)

  it.each<[string, string]>([
    ['a bare token', TOKEN],
    ['a bare token with surrounding whitespace', `  \n\t${TOKEN}\r\n `],
    ['an https staff link', link(TOKEN)],
    ['an https staff link on a nested host', link(TOKEN, 'a.b.c.example.co.in')],
    ['a link with a query', `${link(TOKEN)}?utm_source=whatsapp&x=1`],
    ['a link with a fragment', `${link(TOKEN)}#frag`],
    ['a link with query and fragment', `${link(TOKEN)}?x=1#y`],
    ['a link with surrounding whitespace', `  ${link(TOKEN)}\n`],
    ['a link whose query smuggles another staff link', `${link(TOKEN)}?next=${encodeURIComponent(link(TOKEN_B))}`],
    ['a link whose fragment smuggles another staff path', `${link(TOKEN)}#/staff-invite/${TOKEN_B}`],
  ])('accepts %s', async (_label, input) => {
    expect(await parse(input)).toBe(TOKEN)
  })

  it.each<[string, string]>([
    ['the empty string', ''],
    ['whitespace only', ' \n\t '],
    ['a 42-character token', TOKEN.slice(1)],
    ['a 44-character token', `${TOKEN}A`],
    ['a padded token', `${TOKEN.slice(0, 42)}=`],
    ['a standard-alphabet token', `${TOKEN.slice(0, 20)}+${TOKEN.slice(21)}`],
    ['a token with an internal space', `${TOKEN.slice(0, 20)} ${TOKEN.slice(21)}`],
    ['a token with an internal newline', `${TOKEN.slice(0, 20)}\n${TOKEN.slice(21)}`],
    ['a token with a Cyrillic look-alike', `\u0430${TOKEN.slice(1)}`],
    ['a token with a fullwidth letter', `\uff21${TOKEN.slice(1)}`],
    ['a token with a zero-width space', `${TOKEN.slice(0, 20)}\u200b${TOKEN.slice(20, 42)}`],
    ['a percent-encoded token character', `%41${TOKEN.slice(3)}`],
    ['two tokens', `${TOKEN} ${TOKEN_B}`],
    ['two tokens run together', `${TOKEN}${TOKEN_B}`],
    ['a quoted token', `"${TOKEN}"`],
    ['a token with a key prefix', `token=${TOKEN}`],
    ['a bearer prefix', `Bearer ${TOKEN}`],
    ['the member invite link (cross-family)', `https://${HOST}/invite/${TOKEN}`],
    ['the member deep link (cross-family)', `fitcruxx://invite/${TOKEN}`],
    ['a staff deep link (staff has no mobile surface)', `fitcruxx://staff-invite/${TOKEN}`],
    ['a staff link with a trailing path segment', `${link(TOKEN)}/extra`],
    ['a staff link with a token one character short', link(TOKEN.slice(1))],
    ['a staff link with a token one character long', link(`${TOKEN}A`)],
    ['a staff link with no token', `https://${HOST}/staff-invite/`],
    ['a staff path with no trailing slash', `https://${HOST}/staff-invite`],
    ['a staff path under another prefix', `https://${HOST}/x/staff-invite/${TOKEN}`],
    ['a staff path with a doubled slash', `https://${HOST}//staff-invite/${TOKEN}`],
    ['an upper-cased path', `https://${HOST}/STAFF-INVITE/${TOKEN}`],
    ['a percent-encoded token in a link', `https://${HOST}/staff-invite/%41${TOKEN.slice(3)}`],
    ['a percent-encoded slash inside a link token', `https://${HOST}/staff-invite/${TOKEN.slice(0, 20)}%2F${TOKEN.slice(23)}`],
    ['a token only in a query string', `https://${HOST}/?redirect=/staff-invite/${TOKEN}`],
    ['a token only in a fragment', `https://${HOST}/#/staff-invite/${TOKEN}`],
    ['a login page carrying the path in a query', `https://${HOST}/login?u=/staff-invite/${TOKEN}`],
    ['a javascript: URL', `javascript:alert(1)//https://${HOST}/staff-invite/${TOKEN}`],
    ['a javascript: URL with an authority', `javascript://${HOST}/staff-invite/${TOKEN}`],
    ['a data: URL', `data:text/html,https://${HOST}/staff-invite/${TOKEN}`],
    ['an ftp URL', `ftp://${HOST}/staff-invite/${TOKEN}`],
    ['a file URL', `file:///staff-invite/${TOKEN}`],
    ['a protocol-relative URL', `//${HOST}/staff-invite/${TOKEN}`],
    ['a schemeless URL', `${HOST}/staff-invite/${TOKEN}`],
    ['a bare path', `/staff-invite/${TOKEN}`],
    ['an embedded newline in the path', `https://${HOST}/staff-\ninvite/${TOKEN}`],
    ['an embedded tab inside the token', `https://${HOST}/staff-invite/${TOKEN.slice(0, 10)}\t${TOKEN.slice(10)}`],
    ['an embedded carriage return inside the host', `https://${HOST.slice(0, 5)}\r${HOST.slice(5)}/staff-invite/${TOKEN}`],
    ['a look-alike hyphen in the path', `https://${HOST}/staff\u2010invite/${TOKEN}`],
    ['a Cyrillic s in the path', `https://${HOST}/\u0455taff-invite/${TOKEN}`],
    ['fullwidth slashes', `https://${HOST}\uff0fstaff-invite\uff0f${TOKEN}`],
    ['a 1 MiB blob', 'A'.repeat(1_048_576)],
    ['a 1 MiB link', `https://${HOST}/staff-invite/${'A'.repeat(1_048_576)}`],
  ])('returns null for %s', async (_label, input) => {
    expect(await parse(input)).toBeNull()
  })

  // AMBIGUITY 5: the proposal says "https://<host>/staff-invite/<token>; null otherwise". Scheme case, plain http,
  // userinfo, ports, trailing slash and backslashes are not spelled out. Whatever an implementation chooses, it must
  // never return a different string than the staff token that sits in the path.
  it.each<[string, string]>([
    ['an upper-case scheme', `HTTPS://${HOST}/staff-invite/${TOKEN}`],
    ['a mixed-case scheme', `Https://${HOST}/staff-invite/${TOKEN}`],
    ['a plain http link', `http://${HOST}/staff-invite/${TOKEN}`],
    ['a link with a port', `https://${HOST}:8443/staff-invite/${TOKEN}`],
    ['a link with a trailing slash', `https://${HOST}/staff-invite/${TOKEN}/`],
    ['userinfo before the host', `https://evil.example@${HOST}/staff-invite/${TOKEN}`],
    ['a token-shaped userinfo before the host', `https://${TOKEN_B}@${HOST}/staff-invite/${TOKEN}`],
    ['a token-shaped userinfo with a password', `https://${TOKEN_B}:${TOKEN_B}@${HOST}/staff-invite/${TOKEN}`],
    ['a token-shaped subdomain', `https://${TOKEN_B.toLowerCase()}.example/staff-invite/${TOKEN}`],
    ['backslashes for slashes', `https://${HOST}\\staff-invite\\${TOKEN}`],
    ['a look-alike host', `https://\u0430pp.fitcruxx.example/staff-invite/${TOKEN}`],
    ['a staff link whose query carries a member link', `${link(TOKEN)}?next=https://${HOST}/invite/${TOKEN_B}`],
  ])('never returns a token other than the path token for %s', async (_label, input) => {
    const result = await parse(input)
    expect([TOKEN, null]).toContain(result)
  })

  it('never returns the token of a member-family path embedded in a staff-looking input', async () => {
    expect(await parse(`https://${HOST}/invite/${MEMBER_TOKEN}`)).toBeNull()
    expect(await parse(`fitcruxx://invite/${MEMBER_TOKEN}`)).toBeNull()
  })

  it('does not throw on any of the hostile inputs it is given', async () => {
    const { parseStaffInviteToken } = await staff()
    for (const input of ['\u0000', '%', '%zz', 'https://', 'https://[', 'https://%', 'http://[::1', '\uD800', 'https://a b/staff-invite/x', '\u{1f600}'.repeat(50)]) {
      expect(() => parseStaffInviteToken(input)).not.toThrow()
      expect(parseStaffInviteToken(input)).toBeNull()
    }
  })
})

// ===========================================================================
// STI-003: limits and cookie names
// ===========================================================================
describe('STI-003 STAFF_INVITE_LIMITS and the cookie names', () => {
  it('matches the proposal value for value and has no other keys', async () => {
    const { STAFF_INVITE_LIMITS } = await constants()
    expect({ ...STAFF_INVITE_LIMITS }).toEqual({
      ttlHours: 48,
      tenantIssuesPerHour: 30,
      staffIssuesPerDay: 5,
      redeemFailuresPerWindow: 10,
      redeemWindowMinutes: 15,
      tokenBytes: 32,
      cookieMaxAgeSeconds: 1800,
    })
  })

  it('shares the identity-critical limits with INV and differs exactly where the proposal says', async () => {
    const { STAFF_INVITE_LIMITS, MEMBER_INVITE_LIMITS } = await constants()
    for (const key of ['ttlHours', 'redeemFailuresPerWindow', 'redeemWindowMinutes', 'tokenBytes', 'cookieMaxAgeSeconds'] as const) {
      expect(STAFF_INVITE_LIMITS[key], key).toBe(MEMBER_INVITE_LIMITS[key])
    }
    expect(STAFF_INVITE_LIMITS.tenantIssuesPerHour).toBeLessThan(MEMBER_INVITE_LIMITS.tenantIssuesPerHour)
    expect(Object.hasOwn(STAFF_INVITE_LIMITS, 'memberIssuesPerDay')).toBe(false)
    expect(Object.hasOwn(MEMBER_INVITE_LIMITS, 'staffIssuesPerDay')).toBe(false)
  })

  it('has a token size that yields exactly the 43-character token pattern', async () => {
    const { STAFF_INVITE_LIMITS } = await constants()
    expect(Math.ceil((STAFF_INVITE_LIMITS.tokenBytes * 8) / 6)).toBe(43)
    expect(Buffer.alloc(STAFF_INVITE_LIMITS.tokenBytes).toString('base64url')).toHaveLength(43)
  })

  it('keeps the invite cookie alive for thirty minutes (INV-021), twice the refusal window', async () => {
    const { STAFF_INVITE_LIMITS } = await constants()
    expect(STAFF_INVITE_LIMITS.cookieMaxAgeSeconds).toBe(30 * 60)
    expect(STAFF_INVITE_LIMITS.cookieMaxAgeSeconds).toBe(STAFF_INVITE_LIMITS.redeemWindowMinutes * 2 * 60)
  })

  it('names the staff cookie fitcruxx_staff_invite, distinct from INV\'s fitcruxx_invite', async () => {
    const { STAFF_INVITE_COOKIE_NAME, INVITE_COOKIE_NAME } = await constants()
    expect(STAFF_INVITE_COOKIE_NAME).toBe('fitcruxx_staff_invite')
    expect(INVITE_COOKIE_NAME).toBe('fitcruxx_invite')
    expect(STAFF_INVITE_COOKIE_NAME).not.toBe(INVITE_COOKIE_NAME)
    expect(STAFF_INVITE_COOKIE_NAME.includes(INVITE_COOKIE_NAME)).toBe(false)
    expect(INVITE_COOKIE_NAME.includes(STAFF_INVITE_COOKIE_NAME)).toBe(false)
    expect(STAFF_INVITE_COOKIE_NAME).toMatch(/^[A-Za-z0-9_-]+$/)
  })
})

describe('STI shared barrel and platform-free rules', () => {
  const NAMES = [
    'STAFF_INVITE_ROLES', 'STAFF_INVITE_ROLE_LABELS', 'staffInviteIssueRequestSchema', 'staffInviteRevokeRequestSchema',
    'staffInviteRedeemRequestSchema', 'staffMemberInviteRequestSchema', 'staffUnlinkRequestSchema', 'STAFF_INVITE_REFUSAL_COPY',
    'staffInviteRefusalMessage', 'buildStaffInviteLink', 'parseStaffInviteToken', 'staffInviteShareMessage', 'staffInviteNotice',
  ] as const

  it.each(NAMES)('re-exports %s from the package barrel as the very same value', async (name) => {
    const module = (await staff()) as Record<string, unknown>
    const index = (await barrel()) as Record<string, unknown>
    expect(module[name]).toBeDefined()
    expect(index[name]).toBe(module[name])
  })

  it('re-exports the staff constants from the package barrel', async () => {
    const index = (await barrel()) as Record<string, unknown>
    const c = (await constants()) as Record<string, unknown>
    expect(c.STAFF_INVITE_LIMITS).toBeDefined()
    expect(c.STAFF_INVITE_COOKIE_NAME).toBeDefined()
    expect(index.STAFF_INVITE_LIMITS).toBe(c.STAFF_INVITE_LIMITS)
    expect(index.STAFF_INVITE_COOKIE_NAME).toBe(c.STAFF_INVITE_COOKIE_NAME)
  })

  it('leaves INV\'s names untouched (no regression in the shared vocabulary)', async () => {
    const { INVITE_REDEEM_OUTCOMES, INVITE_TOKEN_PATTERN } = await member()
    expect([...INVITE_REDEEM_OUTCOMES]).toEqual(
      ['linked', 'already_linked_here', 'invite_unavailable', 'email_mismatch', 'identity_unverified', 'account_already_linked', 'rate_limited'],
    )
    expect(INVITE_TOKEN_PATTERN.test(TOKEN)).toBe(true)
  })

  it('keeps packages/shared platform-free: no next, react-dom, node: or process.env, and only relative/zod/db imports', () => {
    const source = readRepo('packages/shared/src/api/staff-invites.ts')
    const specifiers = [...source.matchAll(/(?:from|import)\s*\(?\s*['"]([^'"]+)['"]/g)].map((m) => m[1] as string)
    for (const specifier of specifiers) {
      const allowed = specifier.startsWith('./') || specifier.startsWith('../') || specifier === 'zod' || specifier === '@gymloop/db'
      expect(allowed, `unexpected import "${specifier}"`).toBe(true)
    }
    expect(source).not.toMatch(/process\.env/)
    expect(source).not.toMatch(/\b(?:window|document|localStorage)\b/)
    expect(source).not.toMatch(/node:/)
  })
})

// ===========================================================================
// STI-007 / STI-009: web lib helpers
// ===========================================================================
describe('STI-007 peekStaffInvite', () => {
  const arrange = () =>
    planRpc('peek_staff_invite', (args) =>
      (args as { p_token_hash?: string }).p_token_hash === HASH
        ? { data: [{ gym_name: 'Iron Box Fitness', staff_role: 'front_desk' }] }
        : { data: [] })

  it('returns { gymName, staffRole } for a known token and calls peek_staff_invite with the hash only', async () => {
    arrange()
    const { peekStaffInvite } = await staffLib()
    expect(await peekStaffInvite(h.makeClient() as never, TOKEN)).toEqual({ gymName: 'Iron Box Fitness', staffRole: 'front_desk' })
    expect(h.state.rpcCalls).toEqual([{ fn: 'peek_staff_invite', args: { p_token_hash: HASH } }])
    expect(stringify(h.state.rpcCalls)).not.toContain(TOKEN)
    expect(h.state.tableCalls).toEqual([])
  })

  it('returns null for an unknown token', async () => {
    arrange()
    const { peekStaffInvite } = await staffLib()
    expect(await peekStaffInvite(h.makeClient() as never, TOKEN_B)).toBeNull()
  })

  it('hands the database nothing but a lowercase 64-hex hash, whatever the URL parameter was', async () => {
    arrange()
    const { peekStaffInvite } = await staffLib()
    const hostile = ['', ' ', 'x', `${TOKEN} `, `${TOKEN}\n`, `https://a.example/staff-invite/${TOKEN}`, 'A'.repeat(10_000), '\u0430'.repeat(43), '\u{1f600}', '%00', `../${TOKEN}`]
    for (const token of hostile) {
      expect(await peekStaffInvite(h.makeClient() as never, token)).toBeNull()
    }
    for (const call of h.state.rpcCalls) {
      expect(call.fn).toBe('peek_staff_invite')
      expect(Object.keys(call.args as object)).toEqual(['p_token_hash'])
      expect((call.args as { p_token_hash: string }).p_token_hash).toMatch(/^[0-9a-f]{64}$/)
    }
    expect(stringify(h.state.rpcCalls)).not.toContain(TOKEN)
  })

  it('exposes only the gym name and the role, whatever else the row carries', async () => {
    planRpc('peek_staff_invite', () => ({
      data: [{ gym_name: 'Iron Box Fitness', staff_role: 'trainer', staff_id: STAFF_ID, email: 'secret.person@example.com', full_name: 'Secret Person', tenant_id: TENANT_ID }],
    }))
    const { peekStaffInvite } = await staffLib()
    const result = await peekStaffInvite(h.makeClient() as never, TOKEN)
    expect(result).toEqual({ gymName: 'Iron Box Fitness', staffRole: 'trainer' })
    expect(Object.keys(result as object).sort()).toEqual(['gymName', 'staffRole'])
    expect(stringify(result)).not.toMatch(/Secret|secret\.person|tenant/)
  })

  it('never returns a result for a database error, an exception or an ambiguous answer', async () => {
    const { peekStaffInvite } = await staffLib()
    const scenarios: Array<() => { data?: unknown; error?: unknown; throws?: unknown }> = [
      () => dbError('22023'),
      () => dbError('42501'),
      () => ({ throws: new Error('socket hang up') }),
      () => ({ data: [{ gym_name: 'A', staff_role: 'trainer' }, { gym_name: 'B', staff_role: 'gym_manager' }] }),
    ]
    for (const scenario of scenarios) {
      planRpc('peek_staff_invite', scenario)
      const outcome = await peekStaffInvite(h.makeClient() as never, TOKEN).then((value) => ({ value }), (error) => ({ error }))
      expect('error' in outcome || outcome.value === null).toBe(true)
    }
  })

  it('does not consult the member peek function', async () => {
    arrange()
    const { peekStaffInvite } = await staffLib()
    await peekStaffInvite(h.makeClient() as never, TOKEN)
    expect(rpcOf('peek_member_invite')).toEqual([])
  })
})

describe('STI-009 loadStaffAppAccess', () => {
  it('calls read_staff_app_access with the staff id and nothing else', async () => {
    planRpc('read_staff_app_access', () => ({ data: [{ state: 'not_invited', invite_id: null, issued_at: null, expires_at: null, linked_at: null }] }))
    const { loadStaffAppAccess } = await staffLib()
    await loadStaffAppAccess(h.makeClient() as never, STAFF_ID)
    expect(h.state.rpcCalls).toEqual([{ fn: 'read_staff_app_access', args: { p_staff_id: STAFF_ID } }])
    expect(rpcOf('read_member_app_access')).toEqual([])
    expect(h.state.tableCalls).toEqual([])
  })

  it.each(['linked', 'invite_pending', 'invite_expired', 'not_invited', 'unavailable'])('surfaces the %s state to the caller', async (state) => {
    planRpc('read_staff_app_access', () => ({
      data: [{ state, invite_id: INVITE_ID, issued_at: '2031-01-01T00:00:00.000Z', expires_at: EXPIRES_AT, linked_at: null }],
    }))
    const { loadStaffAppAccess } = await staffLib()
    const result = await loadStaffAppAccess(h.makeClient() as never, STAFF_ID)
    expect(stringify(result)).toContain(state)
  })

  it('does not report a pending invite when the database reports a permission failure', async () => {
    planRpc('read_staff_app_access', () => dbError('42501'))
    const { loadStaffAppAccess } = await staffLib()
    const outcome = await loadStaffAppAccess(h.makeClient() as never, STAFF_ID).then((value) => ({ value }), (error) => ({ error }))
    expect(stringify(outcome)).not.toMatch(/invite_pending|"linked"/)
  })
})

// ===========================================================================
// STI-012 / STI-001 / STI-002 / STI-008: owner-only routes
// ===========================================================================
type MappedRow = readonly [code: string, status: number, apiCode: string]
type OwnerSpec = {
  label: string
  key: Exclude<RouteKey, 'redeem'>
  fn: string
  body: () => Record<string, unknown>
  mapped: readonly MappedRow[]
  otherCode: string | null
}
const ALL_SQLSTATES = ['42501', '22023', 'GL074', 'GL075', 'GL076', 'GL077', 'GL078', 'GL079', 'GL080', 'GL081', 'GL082']
const OWNER_SPECS: readonly OwnerSpec[] = [
  {
    label: 'POST /api/staff-members', key: 'create', fn: 'invite_staff_member', body: () => createBody(),
    mapped: [
      ['GL076', 422, 'staff_email_required'], ['GL081', 409, 'staff_email_taken'], ['GL082', 422, 'staff_role_not_invitable'],
      ['GL078', 429, 'invite_rate_limited'], ['42501', 404, 'branch_not_found'],
    ],
    otherCode: 'invite_failed',
  },
  {
    label: 'POST /api/staff-invites', key: 'issue', fn: 'issue_staff_invite', body: () => ({ staffId: STAFF_ID }),
    mapped: [
      ['42501', 404, 'staff_not_found'], ['GL075', 409, 'staff_not_invitable'], ['GL076', 422, 'staff_email_required'],
      ['GL077', 409, 'staff_already_linked'], ['GL078', 429, 'invite_rate_limited'],
    ],
    otherCode: 'invite_failed',
  },
  {
    label: 'POST /api/staff-invites/revoke', key: 'revoke', fn: 'revoke_staff_invite', body: () => ({ inviteId: INVITE_ID }),
    mapped: [['42501', 404, 'invite_not_found'], ['GL079', 409, 'invite_not_pending']],
    otherCode: null,
  },
  {
    label: 'POST /api/staff-identity/unlink', key: 'unlink', fn: 'unlink_staff_identity', body: () => ({ staffId: STAFF_ID, reason: 'Left the gym' }),
    mapped: [['42501', 404, 'staff_not_found'], ['GL080', 409, 'staff_not_linked'], ['22023', 400, 'invalid_request']],
    otherCode: null,
  },
]
const HOSTILE_CODES: unknown[] = [
  '__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', 'prototype', '', ' ', ' 42501', '42501 ', '42501\n', 'gl081', 'Gl081',
  'GL081 ', 'GL0811', 'GL08', 'XX000', '08006', '23505', '23503', 'PGRST116', 'PGRST202', 'PGRST301', 'P0001', '57014', '40001', '55P03', '53300',
  null, undefined,
]

describe.each(OWNER_SPECS)('$label (owner-only mutation)', (spec) => {
  const send = (init: RequestInitLite = {}) => post(spec.key, req(ROUTES[spec.key].path, { json: spec.body(), ...init }))

  it('succeeds for a real gym owner and makes exactly one RPC to the right function, with no direct table writes', async () => {
    const response = await send()
    await expectSuccess(response)
    expect(h.state.rpcCalls.map((call) => call.fn)).toEqual([spec.fn])
    expect(h.state.tableCalls.filter((call) => ['insert', 'update', 'upsert', 'delete'].includes(call.method))).toEqual([])
    expect(h.state.authCalls).not.toContain('refreshSession')
  })

  it('exports POST and no other HTTP method (a state-changing GET would be a CSRF door)', async () => {
    const module = await routeModule(spec.key)
    expect(typeof module.POST).toBe('function')
    for (const verb of ['GET', 'PUT', 'PATCH', 'DELETE']) expect(module[verb], verb).toBeUndefined()
  })

  describe('caller gate (session before body)', () => {
    // AMBIGUITY 2: "owner-only" does not fix the refusal status. Staff of another role are 403 (lib/api.ts forbidden); an identity
    // that is not staff at all is 401 or 403 (staffSession answers 401 not_signed_in for it).
    const refused: Array<[string, Record<string, unknown>, number[]]> = [
      ['manager', MANAGER, [403]], ['front desk', FRONT_DESK, [403]], ['trainer', TRAINER, [403]],
      ['member', MEMBER, [401, 403]], ['super admin', SUPER_ADMIN, [401, 403]], ['platform support', PLATFORM_SUPPORT, [401, 403]],
      ['owner impersonating in a support preview', IMPERSONATOR, [401, 403]], ['signed-in but unlinked account', UNLINKED, [401, 403]],
    ]
    it.each(refused)('refuses %s before reading the body, calls nothing and says no-store', async (_label, claims, statuses) => {
      h.state.claims = claims
      const request = req(ROUTES[spec.key].path, { json: spec.body() })
      const reads = watchBody(request)
      const response = await (await routeModule(spec.key)).POST(request)
      expect(statuses).toContain(response.status)
      noStore(response)
      const { body } = await readEnvelope(response)
      expect(body.ok).toBe(false)
      expect(reads).toEqual([])
      expect(request.bodyUsed).toBe(false)
      expect(h.state.rpcCalls).toEqual([])
      expect(h.state.tableCalls).toEqual([])
    })

    it('refuses a signed-out caller with 401 not_signed_in before reading the body', async () => {
      h.state.claims = null
      const request = req(ROUTES[spec.key].path, { json: spec.body() })
      const reads = watchBody(request)
      const response = await (await routeModule(spec.key)).POST(request)
      await expectFailure(response, 401, 'not_signed_in')
      expect(reads).toEqual([])
      expect(request.bodyUsed).toBe(false)
      expect(h.state.rpcCalls).toEqual([])
    })

    it('does not treat an anon-key JWT as a session', async () => {
      h.state.claims = ANON_KEY_JWT
      const response = await send()
      expect([401, 403]).toContain(response.status)
      expect(h.state.rpcCalls).toEqual([])
    })

    it.each([
      ['malformed JSON', '{"staffId":'], ['an empty body', ''], ['plain text', 'hello'],
    ])('answers a non-owner with %s by identity first (403), never by body (400)', async (_label, raw) => {
      h.state.claims = MANAGER
      const response = await send({ json: undefined, raw })
      expect(response.status).toBe(403)
      expect(h.state.rpcCalls).toEqual([])
    })

    it('answers a signed-out caller with malformed JSON by identity first (401)', async () => {
      h.state.claims = null
      const response = await send({ json: undefined, raw: '{"x":' })
      expect(response.status).toBe(401)
    })

    it('accepts a bearer-authenticated owner (mobile or script transport)', async () => {
      const response = await send({ cookie: '', headers: { authorization: 'Bearer aaaa.bbbb.cccc' } })
      await expectSuccess(response)
      expect(h.state.rpcCalls.map((call) => call.fn)).toEqual([spec.fn])
    })

    it('refuses a request that presents both a cookie session and a bearer token, before the body and the database', async () => {
      const request = req(ROUTES[spec.key].path, { json: spec.body(), headers: { authorization: 'Bearer aaaa.bbbb.cccc' } })
      const reads = watchBody(request)
      const response = await (await routeModule(spec.key)).POST(request)
      expect([400, 401, 403]).toContain(response.status)
      expect(reads).toEqual([])
      expect(h.state.rpcCalls).toEqual([])
    })

    it('refuses a bearer-authenticated non-owner', async () => {
      h.state.claims = TRAINER
      const response = await send({ cookie: '', headers: { authorization: 'Bearer aaaa.bbbb.cccc' } })
      expect(response.status).toBe(403)
      expect(h.state.rpcCalls).toEqual([])
    })
  })

  describe('body handling after the gate', () => {
    it.each([
      ['malformed JSON', '{"x":', 'application/json'], ['an empty body', '', 'application/json'], ['plain text', 'hello', 'text/plain'],
      ['a form body', `a=${encodeURIComponent('b')}`, 'application/x-www-form-urlencoded'],
    ])('answers an owner sending %s with 400 and no database call', async (_label, raw, rawType) => {
      const response = await send({ json: undefined, raw, rawType })
      expect(response.status).toBe(400)
      noStore(response)
      const { body } = await readEnvelope(response)
      expect(body.ok).toBe(false)
      expect(typeof body.error.code).toBe('string')
      expect(h.state.rpcCalls).toEqual([])
    })

    it.each([['an array', '[]'], ['null', 'null'], ['a string', '"x"'], ['a number', '42'], ['an empty object', '{}']])(
      'answers a JSON body that is %s with 400 invalid_request and no database call',
      async (_label, raw) => {
        const response = await send({ json: undefined, raw })
        await expectFailure(response, 400, 'invalid_request')
        expect(h.state.rpcCalls).toEqual([])
      },
    )

    it('rejects extra keys (mass assignment) and a JSON "__proto__" with 400 invalid_request and no database call', async () => {
      for (const extra of [{ tenantId: TENANT_ID }, { tenant_id: TENANT_ID }, { userId: NEW_USER }, { isActive: true }, { role2: 'gym_owner' }]) {
        h.state.rpcCalls = []
        const response = await send({ json: { ...spec.body(), ...extra } })
        await expectFailure(response, 400, 'invalid_request')
        expect(h.state.rpcCalls).toEqual([])
      }
      const base = JSON.stringify(spec.body())
      const response = await send({ json: undefined, raw: `${base.slice(0, -1)},"__proto__":{"role":"gym_owner"}}` })
      await expectFailure(response, 400, 'invalid_request')
      expect(h.state.rpcCalls).toEqual([])
    })
  })

  describe('SQLSTATE mapping', () => {
    it.each(spec.mapped)('maps %s to %i %s, with a safe message', async (code, status, apiCode) => {
      planRpc(spec.fn, () => dbError(code))
      const response = await send()
      const body = await expectFailure(response, status, apiCode)
      expect(body.error.message).not.toContain('@')
      expect(h.state.rpcCalls).toHaveLength(1)
    })

    const mappedCodes = new Set(spec.mapped.map(([code]) => code))
    const unlisted = ALL_SQLSTATES.filter((code) => !mappedCodes.has(code))
    // AMBIGUITY 4: the proposal lists only the codes above for this route. Any other documented code is a failure, but
    // whether a handler adds a friendlier mapping for it is its own choice, so only "not a success, not a leak" is pinned.
    it.each(unlisted)('treats the unlisted %s as a failure that leaks nothing', async (code) => {
      planRpc(spec.fn, () => dbError(code))
      const response = await send()
      const body = await expectAnyFailure(response)
      expect(stringify(body)).not.toMatch(/ravi\.kumar|GL0\d\d/)
      expect(h.state.rpcCalls).toHaveLength(1)
    })

    it.each(HOSTILE_CODES)('answers the hostile or unknown error code %j with 500 (looked up by own property, never by prototype)', async (code) => {
      planRpc(spec.fn, () => dbError(code))
      const response = await send()
      expect(response.status).toBe(500)
      const body = await expectAnyFailure(response)
      if (spec.otherCode !== null) expect(body.error.code).toBe(spec.otherCode)
      for (const [, , apiCode] of spec.mapped) expect(body.error.code).not.toBe(apiCode)
      expect(h.state.rpcCalls).toHaveLength(1)
    })

    it('never classifies by error message text (a message that merely mentions a code is still a 500)', async () => {
      planRpc(spec.fn, () => ({ error: { code: 'P0001', message: 'GL081 GL082 GL078 staff email already used', details: 'GL076', hint: null } }))
      const response = await send()
      expect(response.status).toBe(500)
    })

    it('answers an error object with no code at all with 500', async () => {
      planRpc(spec.fn, () => ({ error: { message: 'fetch failed' } }))
      expect((await send()).status).toBe(500)
    })

    it('answers a thrown RPC exception with a 500 envelope instead of letting it escape or succeed', async () => {
      planRpc(spec.fn, () => ({ throws: new Error('connect ECONNRESET db.internal.example:5432') }))
      const outcome = await settle(() => send())
      expect(outcome.thrown, 'the handler must catch an RPC rejection').toBeUndefined()
      const body = await expectAnyFailure(outcome.response as Response)
      expect(outcome.response?.status).toBe(500)
      expect(stringify(body)).not.toMatch(/ECONNRESET|db\.internal/)
    })

    it('does not retry a failed RPC (a retry would double-issue and double-count the limits)', async () => {
      planRpc(spec.fn, () => dbError('XX000'))
      await send()
      expect(h.state.rpcCalls).toHaveLength(1)
    })

    it('says no-store on every error status it can produce', async () => {
      const seen = new Set<number>()
      for (const [code] of spec.mapped) {
        planRpc(spec.fn, () => dbError(code))
        const response = await send()
        seen.add(response.status)
        noStore(response)
      }
      planRpc(spec.fn, () => dbError('XX000'))
      const response = await send()
      noStore(response)
      expect(seen.size).toBeGreaterThan(0)
    })
  })

  describe('secrecy', () => {
    it('writes nothing about the token, its hash, the address or the name to the console, on success and on every failure', async () => {
      const outcomes: Array<() => { data?: unknown; error?: unknown; throws?: unknown }> = [
        () => defaultPlans()[spec.fn as keyof ReturnType<typeof defaultPlans>](),
        () => dbError('XX000'),
        () => dbError('GL081'),
        () => ({ throws: new Error('boom') }),
      ]
      for (const outcome of outcomes) {
        planRpc(spec.fn, outcome)
        await send()
      }
      const text = consoleText()
      expect(text).not.toMatch(TOKEN_RUN)
      expect(text).not.toMatch(HEX64_RUN)
      expect(text).not.toMatch(/ravi\.kumar@example\.com|Ravi Kumar|\+919876543210/)
      expect(text).not.toContain(LEAK)
    })
  })
})

// ---------------------------------------------------------------------------
// Create and invite: the invite-specific contract
// ---------------------------------------------------------------------------
const LINK_RE = /^(https?:\/\/[^/\s?#]+)\/staff-invite\/([A-Za-z0-9_-]{43})$/

describe('STI-001 POST /api/staff-members: the create-and-invite contract', () => {
  const send = (over: Record<string, unknown> = {}, init: RequestInitLite = {}) =>
    post('create', req(ROUTES.create.path, { json: createBody(over), ...init }))
  const rpcArgs = () => h.state.rpcCalls[0]?.args as Record<string, unknown>

  it('answers with exactly { staffId, inviteId, link, expiresAt }, all from the database row', async () => {
    const data = await expectSuccess(await send())
    expect(Object.keys(data).sort()).toEqual(['expiresAt', 'inviteId', 'link', 'staffId'])
    expect(data.staffId).toBe(STAFF_ID)
    expect(data.inviteId).toBe(INVITE_ID)
    expect(Date.parse(data.expiresAt)).toBe(Date.parse(EXPIRES_AT))
    expect(data.link).toMatch(LINK_RE)
  })

  it('calls invite_staff_member with exactly the six named arguments, the token only as its SHA-256 hash', async () => {
    const data = await expectSuccess(await send())
    const token = LINK_RE.exec(data.link)?.[2] as string
    expect(token).toMatch(TOKEN_RE)
    expect(rpcArgs()).toEqual({
      p_full_name: 'Ravi Kumar',
      p_email: 'ravi.kumar@example.com',
      p_phone: '+919876543210',
      p_role: 'front_desk',
      p_branch_id: BRANCH_ID,
      p_token_hash: sha256(token),
    })
    expect(stringify(h.state.rpcCalls)).not.toContain(token)
  })

  it('sends an explicit null for an omitted phone and branch (AMBIGUITY 3: the function has no defaults, so a dropped key would not resolve)', async () => {
    const { phone: _p, branchId: _b, ...minimal } = createBody()
    await expectSuccess(await post('create', req(ROUTES.create.path, { json: minimal })))
    expect(Object.keys(rpcArgs()).sort()).toEqual(['p_branch_id', 'p_email', 'p_full_name', 'p_phone', 'p_role', 'p_token_hash'])
    expect(rpcArgs().p_phone).toBeNull()
    expect(rpcArgs().p_branch_id).toBeNull()
  })

  it('sends null for an empty-string phone', async () => {
    await expectSuccess(await send({ phone: '' }))
    expect(rpcArgs().p_phone).toBeNull()
  })

  it('passes the trimmed values and the owner-chosen role through, byte for byte', async () => {
    await expectSuccess(await send({ fullName: "  Robert'); DROP TABLE staff;--  ", email: '  Ravi.Kumar@Example.com  ', role: 'trainer' }))
    expect(rpcArgs().p_full_name).toBe("Robert'); DROP TABLE staff;--")
    expect(rpcArgs().p_email).toBe('Ravi.Kumar@Example.com')
    expect(rpcArgs().p_role).toBe('trainer')
  })

  it.each(['gym_manager', 'front_desk', 'trainer'])('passes the role %s through unchanged', async (role) => {
    await expectSuccess(await send({ role }))
    expect(rpcArgs().p_role).toBe(role)
  })

  it('puts the raw token in the link and nowhere else: no header carries it', async () => {
    const response = await send()
    const token = LINK_RE.exec((await readEnvelope(response.clone())).body.data.link)?.[2] as string
    expect(token).toMatch(TOKEN_RE)
    for (const [name, value] of response.headers.entries()) {
      expect(`${name}: ${value}`).not.toContain(token)
      expect(`${name}: ${value}`).not.toContain(sha256(token))
    }
    expect(setCookies(response)).toEqual([])
  })

  it('issues a fresh random token on every call', async () => {
    const first = await expectSuccess(await send())
    const second = await expectSuccess(await send())
    expect(LINK_RE.exec(first.link)?.[2]).not.toBe(LINK_RE.exec(second.link)?.[2])
    expect((h.state.rpcCalls[0]?.args as any).p_token_hash).not.toBe((h.state.rpcCalls[1]?.args as any).p_token_hash)
  })

  it('builds the link from a trusted origin: not from forwarded or host headers an attacker controls', async () => {
    const data = await expectSuccess(await send({}, { headers: { host: 'evil.example', 'x-forwarded-host': 'evil.example', 'x-forwarded-proto': 'http', origin: 'https://evil.example', referer: 'https://evil.example/x', forwarded: 'host=evil.example;proto=http' } }))
    const origin = LINK_RE.exec(data.link)?.[1]
    expect(origin).toBeDefined()
    expect([ORIGIN, WEB_APP_URL]).toContain(origin)
    expect(data.link).not.toContain('evil.example')
  })

  it('takes the expiry from the database, not from a clock of its own', async () => {
    planRpc('invite_staff_member', () => ({ data: [{ staff_id: STAFF_ID, invite_id: INVITE_ID, expires_at: '2044-05-06T07:08:09+00:00' }] }))
    const data = await expectSuccess(await send())
    expect(Date.parse(data.expiresAt)).toBe(Date.parse('2044-05-06T07:08:09Z'))
  })

  it.each([
    ['role gym_owner', { role: 'gym_owner' }], ['role super_admin', { role: 'super_admin' }], ['role member', { role: 'member' }],
    ['upper-case role', { role: 'TRAINER' }], ['label instead of role', { role: 'front desk' }], ['blank name', { fullName: '   ' }],
    ['over-long name', { fullName: 'n'.repeat(121) }], ['email without at', { email: 'ravi.kumar.example.com' }],
    ['email with two ats', { email: 'a@b@example.com' }], ['email with a space', { email: 'ravi kumar@example.com' }],
    ['email over 254', { email: `${'a'.repeat(260)}@example.com` }], ['phone without plus', { phone: '919876543210' }],
    ['phone with spaces', { phone: '+91 98765 43210' }], ['phone with leading zero', { phone: '+0123456789' }],
    ['branch that is not a uuid', { branchId: 'main-branch' }],
  ])('rejects %s with 400 invalid_request and never reaches the database', async (_label, over) => {
    await expectFailure(await send(over), 400, 'invalid_request')
    expect(h.state.rpcCalls).toEqual([])
  })

  it('does not echo the submitted email or name in any error body', async () => {
    planRpc('invite_staff_member', () => dbError('GL081'))
    const { text } = await readEnvelope(await send())
    expect(text).not.toMatch(/ravi\.kumar|Ravi Kumar|\+919876543210/)
  })

  it('does not accept a missing role by defaulting one (the owner chooses, the invitee never does)', async () => {
    const { role: _r, ...noRole } = createBody()
    await expectFailure(await post('create', req(ROUTES.create.path, { json: noRole })), 400, 'invalid_request')
    expect(h.state.rpcCalls).toEqual([])
  })

  it('treats an RPC that returns no row, several rows or a null as a failure, never as a created invite', async () => {
    for (const data of [[], null, [{ staff_id: STAFF_ID, invite_id: INVITE_ID, expires_at: EXPIRES_AT }, { staff_id: STAFF_ID, invite_id: INVITE_ID, expires_at: EXPIRES_AT }]]) {
      planRpc('invite_staff_member', () => ({ data }))
      const response = await send()
      expect(response.status).toBeGreaterThanOrEqual(400)
      const { body, text } = await readEnvelope(response)
      expect(body.ok).toBe(false)
      expect(text).not.toMatch(/staff-invite\//)
    }
  })
})

describe('STI-002 POST /api/staff-invites: the issue / resend contract', () => {
  const send = (body: unknown = { staffId: STAFF_ID }) => post('issue', req(ROUTES.issue.path, { json: body }))

  it('answers with exactly { inviteId, link, expiresAt, supersededInviteId } and no other field', async () => {
    const data = await expectSuccess(await send())
    expect(Object.keys(data).sort()).toEqual(['expiresAt', 'inviteId', 'link', 'supersededInviteId'])
    expect(data.inviteId).toBe(INVITE_ID)
    expect(data.supersededInviteId).toBeNull()
    expect(Date.parse(data.expiresAt)).toBe(Date.parse(EXPIRES_AT))
    expect(data.link).toMatch(LINK_RE)
  })

  it('reports the invite it replaced when the database superseded one', async () => {
    planRpc('issue_staff_invite', () => ({ data: [{ invite_id: INVITE_ID, expires_at: EXPIRES_AT, superseded_invite_id: SUPERSEDED_ID }] }))
    const data = await expectSuccess(await send())
    expect(data.supersededInviteId).toBe(SUPERSEDED_ID)
  })

  it('calls issue_staff_invite with exactly { p_staff_id, p_token_hash } and the hash matches the link\'s token', async () => {
    const data = await expectSuccess(await send())
    const token = LINK_RE.exec(data.link)?.[2] as string
    expect(h.state.rpcCalls).toEqual([{ fn: 'issue_staff_invite', args: { p_staff_id: STAFF_ID, p_token_hash: sha256(token) } }])
    expect(stringify(h.state.rpcCalls)).not.toContain(token)
  })

  it('does not call the member issue function or the create function', async () => {
    await expectSuccess(await send())
    expect(rpcOf('issue_member_invite')).toEqual([])
    expect(rpcOf('invite_staff_member')).toEqual([])
  })

  it('puts the raw token in the link and nowhere else: no header carries it', async () => {
    const response = await send()
    const token = LINK_RE.exec((await readEnvelope(response.clone())).body.data.link)?.[2] as string
    expect(token).toMatch(TOKEN_RE)
    for (const [name, value] of response.headers.entries()) {
      expect(`${name}: ${value}`).not.toContain(token)
      expect(`${name}: ${value}`).not.toContain(sha256(token))
    }
    expect(setCookies(response)).toEqual([])
  })

  it('lets a resend produce a different link every time', async () => {
    const first = await expectSuccess(await send())
    const second = await expectSuccess(await send())
    expect(first.link).not.toBe(second.link)
  })

  it.each([
    ['a member id key', { memberId: STAFF_ID }], ['no key', {}], ['a non-uuid', { staffId: 'abc' }], ['a numeric id', { staffId: 7 }],
    ['an extra email', { staffId: STAFF_ID, email: 'a@b.co' }], ['an extra role', { staffId: STAFF_ID, role: 'gym_owner' }],
  ])('rejects %s with 400 invalid_request', async (_label, body) => {
    await expectFailure(await send(body), 400, 'invalid_request')
    expect(h.state.rpcCalls).toEqual([])
  })

  it('treats no row, many rows and null as a failure', async () => {
    for (const data of [[], null, [{ invite_id: INVITE_ID, expires_at: EXPIRES_AT, superseded_invite_id: null }, { invite_id: SUPERSEDED_ID, expires_at: EXPIRES_AT, superseded_invite_id: null }]]) {
      planRpc('issue_staff_invite', () => ({ data }))
      const response = await send()
      expect(response.status).toBeGreaterThanOrEqual(400)
      expect((await readEnvelope(response)).body.ok).toBe(false)
    }
  })
})

describe('STI-002 POST /api/staff-invites/revoke', () => {
  const send = (body: unknown = { inviteId: INVITE_ID }) => post('revoke', req(ROUTES.revoke.path, { json: body }))

  it('answers exactly { revoked: true } and calls revoke_staff_invite with { p_invite_id } alone', async () => {
    expect(await expectSuccess(await send())).toEqual({ revoked: true })
    expect(h.state.rpcCalls).toEqual([{ fn: 'revoke_staff_invite', args: { p_invite_id: INVITE_ID } }])
    expect(rpcOf('revoke_member_invite')).toEqual([])
  })

  it.each([
    ['a staff id instead', { staffId: INVITE_ID }], ['a member-family key', { memberId: INVITE_ID }], ['no key', {}], ['a non-uuid', { inviteId: 'x' }],
    ['an extra key', { inviteId: INVITE_ID, staffId: STAFF_ID }],
  ])('rejects %s with 400 invalid_request', async (_label, body) => {
    await expectFailure(await send(body), 400, 'invalid_request')
    expect(h.state.rpcCalls).toEqual([])
  })
})

describe('STI-008 POST /api/staff-identity/unlink', () => {
  const send = (body: unknown = { staffId: STAFF_ID, reason: 'Left the gym' }) => post('unlink', req(ROUTES.unlink.path, { json: body }))

  it('answers exactly { unlinked: true } and calls unlink_staff_identity with the id and the trimmed reason only', async () => {
    expect(await expectSuccess(await send({ staffId: STAFF_ID, reason: '  Left the gym \n' }))).toEqual({ unlinked: true })
    expect(h.state.rpcCalls).toEqual([{ fn: 'unlink_staff_identity', args: { p_staff_id: STAFF_ID, p_reason: 'Left the gym' } }])
    expect(rpcOf('unlink_member_identity')).toEqual([])
  })

  it.each([
    ['a missing reason', { staffId: STAFF_ID }], ['a two-character reason', { staffId: STAFF_ID, reason: 'ab' }],
    ['a whitespace reason', { staffId: STAFF_ID, reason: '     ' }], ['a 201-character reason', { staffId: STAFF_ID, reason: 'r'.repeat(201) }],
    ['a numeric reason', { staffId: STAFF_ID, reason: 12345 }], ['the member key', { memberId: STAFF_ID, reason: 'Left the gym' }],
    ['a non-uuid id', { staffId: 'x', reason: 'Left the gym' }], ['an extra key', { staffId: STAFF_ID, reason: 'Left the gym', role: 'gym_owner' }],
  ])('rejects %s with 400 invalid_request and never unlinks anything', async (_label, body) => {
    await expectFailure(await send(body), 400, 'invalid_request')
    expect(h.state.rpcCalls).toEqual([])
  })

  it('accepts the reason boundaries 3 and 200', async () => {
    await expectSuccess(await send({ staffId: STAFF_ID, reason: 'abc' }))
    await expectSuccess(await send({ staffId: STAFF_ID, reason: 'r'.repeat(200) }))
    expect(h.state.rpcCalls).toHaveLength(2)
  })

  it('does not put the reason in any error body or console line', async () => {
    planRpc('unlink_staff_identity', () => dbError('GL080'))
    const { text } = await readEnvelope(await send({ staffId: STAFF_ID, reason: 'confidential personal reason' }))
    expect(text).not.toContain('confidential personal reason')
    expect(consoleText()).not.toContain('confidential personal reason')
  })
})

// ===========================================================================
// STI-004 / STI-013 / STI-014: redeem
// ===========================================================================
const REFUSAL_STATUS: Record<keyof typeof STAFF_COPY, number> = {
  invite_unavailable: 404, email_mismatch: 403, identity_unverified: 403, account_already_linked: 409, rate_limited: 429,
}
const withStaffCookie = (token: string = TOKEN) => `${SB_COOKIES}; ${STAFF_COOKIE}=${token}`
const redeemPlan = (row: Record<string, unknown> | null) => planRpc('redeem_staff_invite', () => ({ data: row === null ? [] : [row] }))
const linkedRow = (over: Record<string, unknown> = {}) => ({ outcome: 'linked', gym_name: 'Iron Box Fitness', staff_role: 'front_desk', ...over })
const refusalRow = (outcome: string, over: Record<string, unknown> = {}) => ({ outcome, gym_name: null, staff_role: null, ...over })

describe('STI-004 POST /api/staff-invites/redeem: caller gate', () => {
  const json = (init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { json: { token: TOKEN }, ...init }))

  it('refuses a signed-out caller with 401 not_signed_in before reading the body and before any RPC', async () => {
    h.state.claims = null
    const request = req(ROUTES.redeem.path, { json: { token: TOKEN } })
    const reads = watchBody(request)
    await expectFailure(await (await routeModule('redeem')).POST(request), 401, 'not_signed_in')
    expect(reads).toEqual([])
    expect(request.bodyUsed).toBe(false)
    expect(h.state.rpcCalls).toEqual([])
  })

  it('refuses a signed-out form post the same way', async () => {
    h.state.claims = null
    const request = req(ROUTES.redeem.path, { form: { token: TOKEN }, cookie: withStaffCookie() })
    const reads = watchBody(request)
    await expectFailure(await (await routeModule('redeem')).POST(request), 401, 'not_signed_in')
    expect(reads).toEqual([])
    expect(h.state.rpcCalls).toEqual([])
  })

  it('does not treat an anon-key JWT as a session', async () => {
    h.state.claims = ANON_KEY_JWT
    const response = await json()
    expect(response.status).toBe(401)
    expect(h.state.rpcCalls).toEqual([])
  })

  it('refuses mixed cookie and bearer credentials before the body and the database', async () => {
    const request = req(ROUTES.redeem.path, { json: { token: TOKEN }, headers: { authorization: 'Bearer aaaa.bbbb.cccc' } })
    const reads = watchBody(request)
    const response = await (await routeModule('redeem')).POST(request)
    expect([400, 401, 403]).toContain(response.status)
    expect(reads).toEqual([])
    expect(h.state.rpcCalls).toEqual([])
  })

  it('accepts a bearer-authenticated unlinked account (the one session an ordinary staff route would reject)', async () => {
    h.state.claims = UNLINKED
    const response = await json({ cookie: '', headers: { authorization: 'Bearer aaaa.bbbb.cccc' } })
    const data = await expectSuccess(response)
    expect(data.outcome).toBe('linked')
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: HASH } }])
  })

  it.each([
    ['an unlinked account', UNLINKED], ['an existing staff member', FRONT_DESK], ['an existing owner', OWNER], ['an existing member', MEMBER],
    ['a platform administrator', SUPER_ADMIN], ['a support preview', IMPERSONATOR],
  ])('lets %s reach the database so the refusal is audited and throttled there (the gate is not in the handler)', async (_label, claims) => {
    h.state.claims = claims
    redeemPlan(refusalRow('account_already_linked'))
    const response = await json()
    expect(rpcOf('redeem_staff_invite')).toHaveLength(1)
    expect(response.status).toBe(409)
  })

  it('treats a support preview that the database rejects with 42501 as a failure with no cookie changes', async () => {
    h.state.claims = IMPERSONATOR
    planRpc('redeem_staff_invite', () => dbError('42501'))
    const response = await json({ cookie: withStaffCookie() })
    expect(response.status).toBeGreaterThanOrEqual(400)
    expect(response.status).not.toBe(200)
    expectNoCookieChanges(response)
    expect(h.state.authCalls).not.toContain('refreshSession')
  })

  it('exports POST and no other method', async () => {
    const module = await routeModule('redeem')
    expect(typeof module.POST).toBe('function')
    for (const verb of ['GET', 'PUT', 'PATCH', 'DELETE']) expect(module[verb], verb).toBeUndefined()
  })
})

describe('STI-004 / STI-013 redeem: JSON success (linked and already_linked_here)', () => {
  const jsonRedeem = (init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { json: { token: TOKEN }, cookie: withStaffCookie(), ...init }))

  it.each(['linked', 'already_linked_here'])('%s: answers { outcome, gymName, role, signInAgain: true } and nothing else', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ outcome }))
    const response = await jsonRedeem()
    expect(await expectSuccess(response)).toEqual({ outcome, gymName: 'Iron Box Fitness', role: 'front_desk', signInAgain: true })
  })

  it.each(['gym_manager', 'front_desk', 'trainer'])('passes the owner-assigned role %s through (AMBIGUITY 1: the machine value, not the label)', async (role) => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ staff_role: role }))
    const data = await expectSuccess(await jsonRedeem())
    expect(data.role).toBe(role)
  })

  it('never claims the workspace is open: signInAgain is the boolean true, not a session', async () => {
    h.state.claims = UNLINKED
    const data = await expectSuccess(await jsonRedeem())
    expect(data.signInAgain).toBe(true)
    expect(Object.keys(data).sort()).toEqual(['gymName', 'outcome', 'role', 'signInAgain'])
  })

  it('hashes the token before the database call: the RPC gets { p_token_hash } and nothing else', async () => {
    h.state.claims = UNLINKED
    await jsonRedeem()
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: HASH } }])
    expect(stringify(h.state.rpcCalls)).not.toContain(TOKEN)
  })

  it.each(['linked', 'already_linked_here'])('%s: NEVER calls refreshSession (the trigger already deleted the sessions)', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ outcome }))
    await jsonRedeem()
    expect(h.state.authCalls).not.toContain('refreshSession')
    expect(h.state.authCalls).not.toContain('setSession')
  })

  it.each(['linked', 'already_linked_here'])('%s: expires every auth cookie chunk and the staff invite cookie, and issues no live cookie', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ outcome }))
    const cookie = withStaffCookie()
    const response = await jsonRedeem({ cookie })
    expectAuthCookiesExpired(response, cookie)
    expect(inviteCookieCleared(response)).toBe(true)
    for (const set of setCookies(response).filter((c) => c.name === STAFF_COOKIE)) expect(set.attrs.get('path')).toBe('/')
    for (const set of setCookies(response)) expect(isExpiring(set), `${set.name} must be an expiry`).toBe(true)
  })

  it('does not echo the token or its hash anywhere in the response or headers', async () => {
    h.state.claims = UNLINKED
    const response = await jsonRedeem()
    const everything = `${await response.clone().text()}\n${[...response.headers.entries()].map(([k, v]) => `${k}: ${v}`).join('\n')}`
    expect(everything).not.toContain(TOKEN)
    expect(everything).not.toContain(HASH)
  })

  it('passes the gym name through verbatim as data, with no markup interpretation', async () => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ gym_name: '<img src=x onerror=alert(1)> & Co' }))
    expect((await expectSuccess(await jsonRedeem())).gymName).toBe('<img src=x onerror=alert(1)> & Co')
  })

  it('writes nothing sensitive to the console', async () => {
    h.state.claims = UNLINKED
    await jsonRedeem()
    expect(consoleText()).not.toMatch(TOKEN_RUN)
    expect(consoleText()).not.toContain(HASH)
  })
})

describe('STI-004 / STI-013 redeem: form success', () => {
  const formRedeem = (init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { form: { token: TOKEN }, cookie: withStaffCookie(), ...init }))

  it.each(['linked', 'already_linked_here'])('%s: 303 to /sign-in?linked=staff with no body, no refresh and every cookie expired', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(linkedRow({ outcome }))
    const cookie = withStaffCookie()
    const response = await formRedeem({ cookie })
    expect(response.status).toBe(303)
    expect(location(response)).toBe('/sign-in?linked=staff')
    noStore(response)
    expect(await response.text()).toBe('')
    expect(h.state.authCalls).not.toContain('refreshSession')
    expectAuthCookiesExpired(response, cookie)
    expect(inviteCookieCleared(response)).toBe(true)
  })

  it('works the same for a multipart post', async () => {
    h.state.claims = UNLINKED
    const response = await post('redeem', req(ROUTES.redeem.path, { multipart: { token: TOKEN }, cookie: withStaffCookie() }))
    expect(response.status).toBe(303)
    expect(location(response)).toBe('/sign-in?linked=staff')
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: HASH } }])
  })

  it('never puts the token, its hash, the gym or the role in the redirect', async () => {
    h.state.claims = UNLINKED
    const response = await formRedeem()
    const target = response.headers.get('location') ?? ''
    expect(target).not.toContain(TOKEN)
    expect(target).not.toContain(HASH)
    expect(target).not.toMatch(/Iron|front_desk|front%20desk/)
  })

  it('uses the hidden field over the cookie when both are present and differ', async () => {
    h.state.claims = UNLINKED
    await formRedeem({ form: { token: TOKEN_B }, cookie: withStaffCookie(TOKEN) })
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN_B) } }])
  })

  it('falls back to the staff invite cookie when the field is absent', async () => {
    h.state.claims = UNLINKED
    const response = await formRedeem({ form: {}, cookie: withStaffCookie(TOKEN_B) })
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN_B) } }])
    expect(response.status).toBe(303)
  })

  it('ignores every other form field (the role and the tenant are not the invitee\'s to supply)', async () => {
    h.state.claims = UNLINKED
    await formRedeem({ form: { token: TOKEN, role: 'gym_owner', staffId: STAFF_ID, tenant_id: TENANT_ID, p_role: 'gym_owner' } })
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: HASH } }])
  })
})

describe('STI-004 redeem: refusals', () => {
  const json = (init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { json: { token: TOKEN }, cookie: withStaffCookie(), ...init }))
  const form = (init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { form: { token: TOKEN }, cookie: withStaffCookie(), ...init }))

  it.each(OUTCOMES)('JSON %s: the mapped status, code = outcome, the staff sentence verbatim, and no other field', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(refusalRow(outcome))
    const response = await json()
    const body = await expectFailure(response, REFUSAL_STATUS[outcome], outcome)
    expect(body.error.message).toBe(STAFF_COPY[outcome])
    expect(Object.keys(body.error).sort()).toEqual(['code', 'message'])
  })

  it.each(OUTCOMES)('form %s: 303 to /staff-invite/continue?result=%s, nothing else in the URL', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(refusalRow(outcome))
    const response = await form()
    expect(response.status).toBe(303)
    expect(location(response)).toBe(`/staff-invite/continue?result=${outcome}`)
    noStore(response)
    expect(response.headers.get('location')).not.toContain(TOKEN)
  })

  it.each(OUTCOMES)('%s: keeps the cookie and the session so the person can switch Google account and retry', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(refusalRow(outcome))
    for (const response of [await json(), await form()]) {
      expectNoCookieChanges(response)
    }
    expect(h.state.authCalls).not.toContain('refreshSession')
    expect(h.state.authCalls).not.toContain('signOut')
  })

  it.each(OUTCOMES)('%s: never leaks a gym, a role or the token even if the row carries them', async (outcome) => {
    h.state.claims = UNLINKED
    redeemPlan(refusalRow(outcome, { gym_name: 'Leaky Gym Name', staff_role: 'gym_manager', member_name: 'Leaky Person', email: 'leaky@example.com' }))
    const response = await json()
    const { text, body } = await readEnvelope(response)
    expect(text).not.toMatch(/Leaky|gym_manager|leaky@example\.com/)
    expect(body.ok).toBe(false)
    expect(text).not.toContain(TOKEN)
    expect(text).not.toContain(HASH)
  })

  it('uses the staff sentence for account_already_linked, never the member one', async () => {
    h.state.claims = FRONT_DESK
    redeemPlan(refusalRow('account_already_linked'))
    const body = await expectFailure(await json(), 409, 'account_already_linked')
    expect(body.error.message).toBe(STAFF_COPY.account_already_linked)
    expect(body.error.message).not.toBe(MEMBER_COPY.account_already_linked)
  })

  it('calls the staff redeem function exactly once and never the member one', async () => {
    h.state.claims = UNLINKED
    redeemPlan(refusalRow('email_mismatch'))
    await json()
    await form()
    expect(rpcOf('redeem_member_invite')).toEqual([])
    expect(rpcOf('redeem_staff_invite')).toHaveLength(2)
  })

  // The route maps outcomes with Object.hasOwn, so none of these can pick up a prototype value, throw, or look like success.
  it.each(['weird', 'LINKED', 'Linked', 'linked ', ' linked', 'linked\n', 'already_linked_here ', '__proto__', 'constructor', 'toString', 'hasOwnProperty', 'valueOf', '', ' ', '0', 'true', 'null', 'invite_unavailable '])(
    'treats the unknown or hostile outcome %j as a failure: no success shape, no cookie expiry, no refresh, nothing reflected',
    async (outcome) => {
      h.state.claims = UNLINKED
      redeemPlan(refusalRow(outcome, { gym_name: 'Hostile Gym', staff_role: 'front_desk' }))
      const cookie = withStaffCookie()
      const asJson = await settle(() => json({ cookie }))
      expect(asJson.thrown, 'the handler must answer, not throw').toBeUndefined()
      const jsonResponse = asJson.response as Response
      const { body, text } = await readEnvelope(jsonResponse)
      expect(jsonResponse.status).toBeGreaterThanOrEqual(400)
      expect(body.ok).toBe(false)
      expect(text).not.toMatch(/signInAgain|Hostile Gym/)
      expectNoCookieChanges(jsonResponse)

      const asForm = await settle(() => form({ cookie }))
      expect(asForm.thrown, 'the handler must answer, not throw').toBeUndefined()
      const formResponse = asForm.response as Response
      expect(location(formResponse) ?? '').not.toMatch(/linked=staff/)
      const reflected = outcome.trim()
      if (reflected !== '' && !(OUTCOMES as string[]).includes(reflected)) {
        expect(formResponse.headers.get('location') ?? '').not.toContain(encodeURIComponent(reflected))
      }
      expectNoCookieChanges(formResponse)
      expect(h.state.authCalls).not.toContain('refreshSession')
    },
  )

  it('treats an unknown outcome on a row with a role as if there were no row at all (no leak of the role)', async () => {
    h.state.claims = UNLINKED
    redeemPlan({ outcome: 'surprise', gym_name: 'Iron Box Fitness', staff_role: 'front_desk' })
    const response = await json()
    expect(response.status).toBeGreaterThanOrEqual(400)
    expect((await readEnvelope(response)).text).not.toMatch(/Iron Box|front_desk/)
  })

  it('never produces success from zero rows, from two rows (even two linked rows) or from null data', async () => {
    h.state.claims = UNLINKED
    const scenarios: unknown[] = [[], null, [linkedRow(), linkedRow()], [linkedRow(), refusalRow('email_mismatch')], [refusalRow('rate_limited'), linkedRow()]]
    for (const data of scenarios) {
      h.state.authCalls = []
      planRpc('redeem_staff_invite', () => ({ data }))
      for (const send of [json, form]) {
        const response = await send()
        expect(response.status === 200 && (await response.clone().text()).includes('signInAgain')).toBe(false)
        expect(location(response) ?? '').not.toMatch(/linked=staff/)
        expectNoCookieChanges(response)
      }
      expect(h.state.authCalls).not.toContain('refreshSession')
    }
  })

  it.each(['22023', '42501', 'GL074', 'GL075', 'GL077', 'XX000', '08006', 'PGRST116', 'PGRST202', '__proto__', 'constructor', '', null, undefined])(
    'treats the database error %j as a failure with no success, no cookie change, no refresh and no leaked message',
    async (code) => {
      h.state.claims = UNLINKED
      planRpc('redeem_staff_invite', () => dbError(code))
      for (const send of [json, form]) {
        const response = await send()
        expect(response.status === 200 && (await response.clone().text()).includes('signInAgain')).toBe(false)
        expect(location(response) ?? '').not.toMatch(/linked=staff/)
        expect(await response.clone().text()).not.toContain(LEAK)
        expectNoCookieChanges(response)
      }
      expect(h.state.authCalls).not.toContain('refreshSession')
    },
  )

  it('treats a thrown RPC as a failure that neither escapes nor succeeds nor touches a cookie', async () => {
    h.state.claims = UNLINKED
    planRpc('redeem_staff_invite', () => ({ throws: new Error('connect ECONNREFUSED 10.0.0.9:5432') }))
    for (const send of [json, form]) {
      const outcome = await settle(() => send())
      expect(outcome.thrown, 'the handler must catch an RPC rejection').toBeUndefined()
      const response = outcome.response as Response
      expect(response.status === 200 && (await response.clone().text()).includes('signInAgain')).toBe(false)
      expect(location(response) ?? '').not.toMatch(/linked=staff/)
      expect(await response.clone().text()).not.toMatch(/ECONNREFUSED|10\.0\.0\.9/)
      expectNoCookieChanges(response)
    }
    expect(h.state.authCalls).not.toContain('refreshSession')
  })

  it('does not retry a failed redeem (a single-use token must not be replayed by the server)', async () => {
    h.state.claims = UNLINKED
    planRpc('redeem_staff_invite', () => dbError('XX000'))
    await json()
    expect(rpcOf('redeem_staff_invite')).toHaveLength(1)
  })

  it('writes the token and its hash nowhere on any refusal or failure path', async () => {
    h.state.claims = UNLINKED
    for (const row of [...OUTCOMES.map((o) => refusalRow(o)), refusalRow('weird')]) {
      redeemPlan(row)
      await json()
      await form()
    }
    planRpc('redeem_staff_invite', () => dbError('XX000'))
    await json()
    planRpc('redeem_staff_invite', () => ({ throws: new Error('boom') }))
    await json()
    expect(consoleText()).not.toContain(TOKEN)
    expect(consoleText()).not.toContain(HASH)
    expect(consoleText()).not.toMatch(TOKEN_RUN)
  })
})

describe('STI-014 redeem: where the token may come from', () => {
  const json = (body: unknown, init: RequestInitLite = {}) => post('redeem', req(ROUTES.redeem.path, { json: body, cookie: SB_COOKIES, ...init }))
  const form = (fields: Record<string, string>, cookie: string) => post('redeem', req(ROUTES.redeem.path, { form: fields, cookie }))
  const noCall = () => expect(rpcOf('redeem_staff_invite')).toEqual([])

  beforeEach(() => {
    h.state.claims = UNLINKED
  })

  it.each([
    ['empty', ''], ['one character short', TOKEN.slice(1)], ['one character long', `${TOKEN}A`], ['padded', `${TOKEN.slice(0, 42)}=`],
    ['with a trailing newline', `${TOKEN}\n`], ['with a leading space', ` ${TOKEN}`], ['a whole staff link', `https://app.example/staff-invite/${TOKEN}`],
    ['a member link', `https://app.example/invite/${TOKEN}`], ['Cyrillic look-alike', `\u0430${TOKEN.slice(1)}`], ['percent-encoded', `%41${TOKEN.slice(3)}`],
  ])('JSON: a token that is %s is a 400 invalid_request and never reaches the database', async (_label, token) => {
    await expectFailure(await json({ token }), 400, 'invalid_request')
    noCall()
  })

  it.each([
    ['a number', 123], ['null', null], ['an array', [TOKEN]], ['an object', { value: TOKEN }], ['a boolean', true],
  ])('JSON: a token that is %s is a 400 invalid_request', async (_label, token) => {
    await expectFailure(await json({ token }), 400, 'invalid_request')
    noCall()
  })

  it.each([
    ['role', 'gym_owner'], ['staffId', STAFF_ID], ['tenantId', TENANT_ID], ['memberId', MEMBER_ID], ['email', 'a@b.co'],
  ])('JSON: an extra %s key is a 400 invalid_request (the invitee never chooses anything)', async (key, value) => {
    await expectFailure(await json({ token: TOKEN, [key]: value }), 400, 'invalid_request')
    noCall()
  })

  it('JSON: a "__proto__" key next to a good token is a 400', async () => {
    const response = await post('redeem', req(ROUTES.redeem.path, { raw: `{"token":"${TOKEN}","__proto__":{"role":"gym_owner"}}` }))
    await expectFailure(response, 400, 'invalid_request')
    noCall()
  })

  it('JSON: a missing token is a 400 even when the staff cookie holds a valid one (AMBIGUITY 12: the cookie fallback is for form posts only)', async () => {
    await expectFailure(await json({}, { cookie: withStaffCookie() }), 400, 'invalid_request')
    noCall()
  })

  it('JSON: malformed JSON and non-JSON text are 400s', async () => {
    for (const init of [{ raw: '{"token":' }, { raw: '' }, { raw: 'hello', rawType: 'text/plain' }]) {
      const response = await post('redeem', req(ROUTES.redeem.path, { cookie: SB_COOKIES, ...init }))
      expect(response.status).toBe(400)
    }
    noCall()
  })

  it('JSON: the body token wins over a cookie token that differs', async () => {
    await json({ token: TOKEN_B }, { cookie: withStaffCookie(TOKEN) })
    expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: sha256(TOKEN_B) } }])
  })

  describe('form posts must not accept the member family\'s cookie in place of the staff cookie', () => {
    const expectNoRedemption = async (response: Response) => {
      noCall()
      expect(location(response) ?? '').not.toMatch(/linked=staff/)
      if (response.status === 303) {
        // AMBIGUITY 10: with no usable token anywhere the proposal does not name the target; the unavailable state is
        // `result=invite_unavailable` or no result at all (INV-020: "no cookie -> the unavailable state"), never a success.
        const target = new URL(response.headers.get('location') as string, ORIGIN)
        expect(target.pathname).toBe('/staff-invite/continue')
        expect([null, 'invite_unavailable']).toContain(target.searchParams.get('result'))
      } else {
        expect(response.status).toBeGreaterThanOrEqual(400)
        expect(response.status).toBeLessThan(500)
      }
      expectNoCookieChanges(response)
      expect(h.state.authCalls).not.toContain('refreshSession')
    }

    it('no field and no cookie at all: nothing is redeemed', async () => {
      await expectNoRedemption(await form({}, SB_COOKIES))
    })

    it('a valid MEMBER invite cookie alone is not a staff token', async () => {
      await expectNoRedemption(await form({}, `${SB_COOKIES}; ${MEMBER_COOKIE}=${MEMBER_TOKEN}`))
    })

    it('a valid MEMBER invite cookie does not rescue an empty staff field', async () => {
      await expectNoRedemption(await form({ token: '' }, `${SB_COOKIES}; ${MEMBER_COOKIE}=${MEMBER_TOKEN}`))
    })

    it.each([
      ['a prefixed name', `x-${STAFF_COOKIE}`], ['a suffixed name', `${STAFF_COOKIE}_x`], ['an upper-cased name', STAFF_COOKIE.toUpperCase()],
      ['a title-cased name', 'Fitcruxx_Staff_Invite'], ['a dashed name', 'fitcruxx-staff-invite'], ['a __Host- prefixed name', `__Host-${STAFF_COOKIE}`],
      ['a name with a trailing dot', `${STAFF_COOKIE}.`], ['the member name with a staff-looking suffix', `${MEMBER_COOKIE}_staff`],
    ])('a look-alike cookie name (%s) is not the staff invite cookie', async (_label, name) => {
      await expectNoRedemption(await form({}, `${SB_COOKIES}; ${name}=${TOKEN}`))
    })

    it('a malformed staff cookie value is not redeemed even though a valid member cookie sits beside it', async () => {
      for (const bad of [TOKEN.slice(1), `${TOKEN}A`, `${TOKEN.slice(0, 42)}=`, '', 'garbage']) {
        h.state.rpcCalls = []
        await form({}, `${SB_COOKIES}; ${STAFF_COOKIE}=${bad}; ${MEMBER_COOKIE}=${MEMBER_TOKEN}`)
        noCall()
      }
    })

    it('with both cookies valid, only the staff token is ever hashed (the member token is never sent to the staff function)', async () => {
      await form({}, `${SB_COOKIES}; ${MEMBER_COOKIE}=${MEMBER_TOKEN}; ${STAFF_COOKIE}=${TOKEN}`)
      expect(h.state.rpcCalls).toEqual([{ fn: 'redeem_staff_invite', args: { p_token_hash: HASH } }])
      expect(stringify(h.state.rpcCalls)).not.toContain(sha256(MEMBER_TOKEN))
    })

    it('a malformed field never reaches the database as its own hash (AMBIGUITY 6: fall back to the cookie or refuse, but never hash garbage)', async () => {
      for (const bad of [TOKEN.slice(1), `${TOKEN}\n`, 'x', `https://a.example/staff-invite/${TOKEN}`]) {
        h.state.rpcCalls = []
        await form({ token: bad }, withStaffCookie(TOKEN_B))
        for (const call of h.state.rpcCalls) {
          expect([sha256(TOKEN_B)]).toContain((call.args as { p_token_hash: string }).p_token_hash)
        }
      }
    })
  })
})

// ===========================================================================
// STI-014: OAuth callback honours the staff cookie only in the unlinked branch
// ===========================================================================
describe('STI-014 GET /auth/callback: staff invite branch', () => {
  const callback = async (cookie: string, query = 'code=abc123') => {
    h.state.cookieHeader = cookie
    const request = new Request(`${ORIGIN}/auth/callback?${query}`, { method: 'GET', headers: cookie === '' ? {} : { cookie } })
    return (await callbackRoute()).GET(request)
  }
  const staffCookie = (token = TOKEN) => `${STAFF_COOKIE}=${token}`
  const memberCookie = (token = MEMBER_TOKEN) => `${MEMBER_COOKIE}=${token}`

  it('sends an unlinked account that holds a valid staff cookie to /staff-invite/continue (303)', async () => {
    h.state.claims = UNLINKED
    const response = await callback(staffCookie())
    expect(response.status).toBe(303)
    expect(location(response)).toBe('/staff-invite/continue')
    expect(h.state.exchangedCodes).toEqual(['abc123'])
  })

  it('never puts the token in the redirect', async () => {
    h.state.claims = UNLINKED
    const response = await callback(staffCookie())
    expect(response.headers.get('location')).not.toContain(TOKEN)
  })

  it('lets a valid MEMBER invite cookie win when both are valid (the staff branch comes after INV\'s)', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback(`${staffCookie()}; ${memberCookie()}`))).toBe('/invite/continue')
    expect(location(await callback(`${memberCookie()}; ${staffCookie()}`))).toBe('/invite/continue')
  })

  it('honours the staff cookie when the member cookie is present but not a valid token', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback(`${memberCookie('short')}; ${staffCookie()}`))).toBe('/staff-invite/continue')
    expect(location(await callback(`${memberCookie(`${MEMBER_TOKEN}A`)}; ${staffCookie()}`))).toBe('/staff-invite/continue')
  })

  it('still sends an unlinked account with only a valid member cookie to /invite/continue', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback(memberCookie()))).toBe('/invite/continue')
  })

  it.each([
    ['one character short', TOKEN.slice(1)], ['one character long', `${TOKEN}A`], ['padded', `${TOKEN.slice(0, 42)}=`], ['empty', ''],
    ['with a Latin-1 look-alike', `\u00e0${TOKEN.slice(1)}`], ['percent-encoded', `%41${TOKEN.slice(3)}`], ['a whole link', `https://a.example/staff-invite/${TOKEN}`],
  ])('ignores a staff cookie whose value is %s', async (_label, value) => {
    h.state.claims = UNLINKED
    expect(location(await callback(staffCookie(value)))).toBe('/not-linked')
  })

  it.each([
    ['prefixed', `x-${STAFF_COOKIE}`], ['suffixed', `${STAFF_COOKIE}_x`], ['upper-cased', STAFF_COOKIE.toUpperCase()], ['dashed', 'fitcruxx-staff-invite'],
  ])('ignores a look-alike cookie name (%s)', async (_label, name) => {
    h.state.claims = UNLINKED
    expect(location(await callback(`${name}=${TOKEN}`))).toBe('/not-linked')
  })

  it('leaves an unlinked account with no invite cookie exactly where it was: /not-linked', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback(''))).toBe('/not-linked')
    expect(location(await callback(SB_COOKIES))).toBe('/not-linked')
  })

  it.each([
    ['owner', OWNER, '/dashboard'], ['manager', MANAGER, '/dashboard'], ['front desk', FRONT_DESK, '/console/check-in'], ['trainer', TRAINER, '/console'],
    ['member', MEMBER, '/member'], ['platform administrator', SUPER_ADMIN, '/platform'], ['platform support', PLATFORM_SUPPORT, '/platform'],
    ['support preview', IMPERSONATOR, '/console'],
  ])('does not divert an already linked %s: they go home, cookie or not', async (_label, claims, home) => {
    h.state.claims = claims
    expect(location(await callback(staffCookie()))).toBe(home)
    expect(location(await callback(`${staffCookie()}; ${memberCookie()}`))).toBe(home)
  })

  it('sends a failed code exchange to /sign-in?failed=1 even with a valid staff cookie', async () => {
    h.state.claims = UNLINKED
    h.state.exchangeFails = true
    expect(location(await callback(staffCookie()))).toBe('/sign-in?failed=1')
  })

  it('sends a callback with no code to /sign-in?failed=1 even with a valid staff cookie', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback(staffCookie(), ''))).toBe('/sign-in?failed=1')
    expect(h.state.exchangedCodes).toEqual([])
  })

  it('still ignores next and redirect parameters', async () => {
    h.state.claims = UNLINKED
    expect(location(await callback('', 'code=abc&next=/staff-invite/continue&redirect_to=https://evil.example/'))).toBe('/not-linked')
    expect(location(await callback(staffCookie(), 'code=abc&next=https://evil.example/&redirect_to=https://evil.example/'))).toBe('/staff-invite/continue')
  })

  it('redirects only within the deploy-owned origin', async () => {
    h.state.claims = UNLINKED
    const response = await callback(staffCookie(), 'code=abc&next=https://evil.example/')
    expect(new URL(response.headers.get('location') as string, ORIGIN).origin).not.toBe('https://evil.example')
  })
})

// ===========================================================================
// STI-014: the server action that carries the token across Google OAuth
// ===========================================================================
describe('STI-014 startStaffInviteGoogleSignIn', () => {
  const run = async (token: unknown) => {
    const module = (await authActions()) as unknown as { startStaffInviteGoogleSignIn?: (t: unknown) => Promise<void> }
    expect(typeof module.startStaffInviteGoogleSignIn, 'lib/auth-actions.ts must export startStaffInviteGoogleSignIn').toBe('function')
    const action = module.startStaffInviteGoogleSignIn as (t: unknown) => Promise<void>
    return settle(async () => {
      await action(token)
      return new Response(null)
    })
  }

  it('sets the staff invite cookie (HttpOnly, SameSite=Lax, Path=/, Max-Age 1800, host-only) BEFORE starting Google OAuth', async () => {
    vi.stubEnv('WEB_APP_URL', 'https://app.fitcruxx.example')
    await run(TOKEN)
    expect(h.state.cookieSets).toHaveLength(1)
    const [set] = h.state.cookieSets
    expect(set?.name).toBe(STAFF_COOKIE)
    expect(set?.value).toBe(TOKEN)
    expect(set?.options.httpOnly).toBe(true)
    expect(String(set?.options.sameSite).toLowerCase()).toBe('lax')
    expect(set?.options.path).toBe('/')
    expect(set?.options.maxAge).toBe(1800)
    expect(set?.options.domain).toBeUndefined()
    expect(h.state.events.indexOf('cookie:set')).toBeGreaterThanOrEqual(0)
    expect(h.state.events.indexOf('cookie:set')).toBeLessThan(h.state.events.indexOf('oauth:start'))
  })

  it('marks the cookie Secure on https and not on plain http (AMBIGUITY 9: decided from the deploy-owned origin)', async () => {
    vi.stubEnv('WEB_APP_URL', 'https://app.fitcruxx.example')
    await run(TOKEN)
    expect(h.state.cookieSets[0]?.options.secure).toBe(true)
    h.state.cookieSets = []
    vi.stubEnv('WEB_APP_URL', 'http://127.0.0.1:3000')
    await run(TOKEN)
    expect(h.state.cookieSets[0]?.options.secure === true).toBe(false)
  })

  it('starts Google OAuth with the fixed callback and carries the token nowhere else', async () => {
    vi.stubEnv('WEB_APP_URL', 'https://app.fitcruxx.example')
    const outcome = await run(TOKEN)
    expect(outcome.thrown).toBeDefined()
    expect(h.state.oauthCalls).toHaveLength(1)
    const [call] = h.state.oauthCalls as Array<{ provider?: string; options?: { redirectTo?: string } }>
    expect(call?.provider).toBe('google')
    expect(call?.options?.redirectTo).toBe('https://app.fitcruxx.example/auth/callback')
    expect(stringify(h.state.oauthCalls)).not.toContain(TOKEN)
    expect(h.state.redirects).toEqual([h.GOOGLE_URL])
    expect(h.GOOGLE_URL).not.toContain(TOKEN)
  })

  it('does not touch the member invite cookie', async () => {
    await run(TOKEN)
    expect(h.state.cookieSets.map((set) => set.name)).toEqual([STAFF_COOKIE])
    expect(h.state.cookieDeletes).not.toContain(MEMBER_COOKIE)
  })

  // The action is a public endpoint: its argument can be anything a client chooses to post.
  it.each([
    ['empty', ''], ['whitespace', '   '], ['one character short', TOKEN.slice(1)], ['one character long', `${TOKEN}A`],
    ['cookie attribute injection', `${TOKEN};Domain=evil.example`], ['header injection', `${TOKEN}\r\nSet-Cookie: x=y`],
    ['path injection', `${TOKEN}; Path=/admin`], ['leading space', ` ${TOKEN}`], ['trailing newline', `${TOKEN}\n`], ['a whole link', `https://a.example/staff-invite/${TOKEN}`],
    ['Cyrillic look-alike', `\u0430${TOKEN.slice(1)}`], ['__proto__', '__proto__'], ['percent-encoded', `%41${TOKEN.slice(3)}`], ['padded', `${TOKEN.slice(0, 42)}=`],
    ['null', null], ['undefined', undefined], ['a number', 123], ['an array holding a valid token', [TOKEN]],
  ])('refuses a token that is %s: no cookie, no OAuth, and nothing it sends the person to carries any of it', async (_label, token) => {
    await run(token)
    expect(h.state.cookieSets).toEqual([])
    expect(h.state.oauthCalls).toEqual([])
    for (const target of h.state.redirects) {
      expect(target).not.toContain(TOKEN)
      expect(target).not.toContain('evil.example')
      expect(target).not.toContain(h.GOOGLE_URL)
    }
  })

  it('sends the person away from Google and keeps the token out of the failure redirect when OAuth cannot start', async () => {
    h.state.oauthFails = true
    await run(TOKEN)
    expect(h.state.oauthCalls).toHaveLength(1)
    for (const target of h.state.redirects) {
      expect(target).not.toContain(TOKEN)
      expect(target).not.toBe(h.GOOGLE_URL)
    }
  })
})

// ===========================================================================
// STI-013: the post-link notice on the sign-in page.
// A .tsx server page cannot be imported by the root test runner (no JSX transform at the repo root, and
// apps/web/tsconfig.json sets jsx: preserve), so the page is held to its source, like the other holdouts do.
// ===========================================================================
describe('STI-013 sign-in page after a staff link (static contract)', () => {
  const NOTICE = 'Linked. Sign in with Google again to open your workspace.'
  const source = () => readRepo('apps/web/app/sign-in/page.tsx')

  it('contains the exact notice sentence from the proposal', () => {
    expect(source()).toContain(NOTICE)
  })

  it('keys the notice on the query value "staff" and does not show it unconditionally', () => {
    const text = source()
    expect(text).toMatch(/['"]staff['"]/)
    const at = text.indexOf(NOTICE)
    expect(text.slice(Math.max(0, at - 500), at)).toMatch(/linked/)
  })

  it('never claims the workspace is already open or the person is already signed in', () => {
    expect(source()).not.toMatch(/workspace is (?:now )?open|you(?:'|\u2019)re signed in|you are signed in/i)
  })

  it('still carries the existing Google sign-in action (the notice is added, nothing is removed)', () => {
    expect(source()).toMatch(/startGoogleSignIn/)
  })
})

// ===========================================================================
// Static wiring (hard rules 2, 3, 4, 11 and the pages/console that a unit test cannot render)
// ===========================================================================
describe('STI static wiring', () => {
  const root = repoFile
  const read = readRepo
  const walk = (relative: string): string[] => {
    const absolute = root(relative)
    if (!existsSync(absolute)) return []
    return readdirSync(absolute).flatMap((entry) => {
      const child = `${relative}/${entry}`
      return statSync(root(child)).isDirectory() ? (entry === '__tests__' || entry === 'node_modules' ? [] : walk(child)) : /\.(ts|tsx)$/.test(entry) ? [child] : []
    })
  }

  const NEW_FILES = [
    'packages/shared/src/api/staff-invites.ts',
    'apps/web/lib/staff-invites.ts',
    'apps/web/app/api/staff-members/route.ts',
    'apps/web/app/api/staff-invites/route.ts',
    'apps/web/app/api/staff-invites/revoke/route.ts',
    'apps/web/app/api/staff-invites/redeem/route.ts',
    'apps/web/app/api/staff-identity/unlink/route.ts',
  ]

  it.each(NEW_FILES)('%s exists', (file) => {
    expect(existsSync(root(file))).toBe(true)
  })

  it.each(NEW_FILES)('%s reads no environment directly, holds no service-role credential and carries no suppression comment', (file) => {
    const source = read(file)
    expect(source).not.toMatch(/process\.env/)
    expect(source).not.toMatch(/SUPABASE_SERVICE_ROLE_KEY|service_role|auth\.admin\./)
    expect(source).not.toMatch(/(\/\/|\/\*)\s*(eslint-disable|@ts-ignore|@ts-expect-error|@ts-nocheck)/)
  })

  it.each(NEW_FILES.filter((file) => file.startsWith('apps/web/app/api/')))('%s never names the member family\'s RPCs, cookie or routes', (file) => {
    const source = read(file)
    expect(source).not.toMatch(/_member_invite\b|member_app_access|unlink_member_identity/)
    expect(source).not.toMatch(/(?<![A-Za-z_])INVITE_COOKIE_NAME/)
    expect(source).not.toMatch(/['"`]\/api\/member-(?:invites|identity)/)
    expect(source).not.toMatch(/(?<![A-Za-z])inviteRefusalMessage|(?<![A-Za-z_])INVITE_REFUSAL_COPY/)
  })

  it('the redeem route never calls refreshSession (the staff trigger already deleted the sessions)', () => {
    expect(read('apps/web/app/api/staff-invites/redeem/route.ts')).not.toMatch(/refreshSession/)
  })

  it('the redeem route answers refusals through the staff copy', () => {
    expect(read('apps/web/app/api/staff-invites/redeem/route.ts')).toMatch(/staffInviteRefusalMessage|STAFF_INVITE_REFUSAL_COPY/)
  })

  it('the staff pages exist, are noindex and no-referrer, use the staff notice and copy, and stay out of the member flow', () => {
    for (const file of ['apps/web/app/staff-invite/[token]/page.tsx', 'apps/web/app/staff-invite/continue/page.tsx']) {
      expect(existsSync(root(file)), file).toBe(true)
      const source = read(file)
      expect(source, file).toMatch(/noindex/i)
      expect(source, file).toMatch(/no-referrer/)
      expect(source, file).not.toMatch(/(?<![A-Za-z_])INVITE_COOKIE_NAME|(?<![A-Za-z])peekInvite\b|['"`]\/api\/member-invites/)
    }
    const landing = read('apps/web/app/staff-invite/[token]/page.tsx')
    expect(landing).toMatch(/staffInviteNotice/)
    expect(landing).toMatch(/peekStaffInvite/)
    expect(landing).toMatch(/startStaffInviteGoogleSignIn/)
    expect(landing).toMatch(/\/privacy|PUBLIC_PAGE_PATHS/)
    const cont = read('apps/web/app/staff-invite/continue/page.tsx')
    expect(cont).toMatch(/staffInviteRefusalMessage/)
    expect(cont).toMatch(/\/api\/staff-invites\/redeem/)
    expect(cont).toMatch(/STAFF_INVITE_COOKIE_NAME|fitcruxx_staff_invite/)
  })

  it('the server action sets only the staff cookie and never the member cookie constant', () => {
    const source = read('apps/web/lib/auth-actions.ts')
    expect(source).toMatch(/startStaffInviteGoogleSignIn/)
    expect(source).toMatch(/STAFF_INVITE_COOKIE_NAME/)
    expect(source).toMatch(/STAFF_INVITE_LIMITS/)
  })

  it('the team console exists, is gated to gym_owner, shows the five dot-plus-word states and the read-only owner row', () => {
    const files = [
      'apps/web/app/(console)/team/page.tsx', 'apps/web/app/(console)/team/new/page.tsx', 'apps/web/app/(console)/team/[staffId]/page.tsx',
      'apps/web/app/(console)/team/[staffId]/staff-access-panel.tsx',
    ]
    for (const file of files) expect(existsSync(root(file)), file).toBe(true)
    const all = walk('apps/web/app/(console)/team').map(read).join('\n')
    expect(all).toMatch(/gym_owner/)
    for (const word of ['Linked', 'Invite pending', 'Invite expired', 'Not invited', 'Inactive']) expect(all, word).toContain(word)
    expect(all).toContain('Owner \u2014 linked by the platform team')
    expect(all).toMatch(/export\s+(?:function|const)\s+StaffAccessPanel\b/)
    expect(read('apps/web/app/(console)/team/[staffId]/staff-access-panel.tsx')).toMatch(/^\s*['"]use client['"]/)
  })

  it('records the staff_invites retention row beside member_invites in docs/security.md (STI-017)', () => {
    const doc = read('docs/security.md')
    expect(doc).toMatch(/member_invites/)
    expect(doc).toMatch(/staff_invites/)
  })

  it('console navigation offers Team', () => {
    const navigation = `${read('apps/web/app/(console)/layout.tsx')}\n${read('apps/web/app/console-navigation.tsx')}`
    expect(navigation).toMatch(/['"]\/team['"]/)
    expect(navigation).toMatch(/\bTeam\b/)
  })
})
