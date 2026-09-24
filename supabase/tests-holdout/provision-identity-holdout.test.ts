import { afterEach, describe, expect, it, vi } from 'vitest'

import { main, provisionIdentity } from '../../scripts/provision-identity.mjs'

const tenantId = '11111111-1111-4111-8111-111111111111'
const otherTenantId = '22222222-2222-4222-8222-222222222222'
const memberId = '33333333-3333-4333-8333-333333333333'
const staffId = '44444444-4444-4444-8444-444444444444'
const authId = '55555555-5555-4555-8555-555555555555'
const createdId = '66666666-6666-4666-8666-666666666666'
const differentAuthId = '77777777-7777-4777-8777-777777777777'
const gymCode = 'P1L0T9'
const email = 'alice.pilot@example.test'
const redactedEmail = 'a***@example.test'
const poison = 'FAKE_SERVICE_ROLE_KEY_HOLDOUT_123'

const member = {
  id: memberId,
  tenantId,
  email,
  userId: null as string | null,
  status: 'active',
  erasedAt: null as string | null,
}
const staff = {
  id: staffId,
  tenantId,
  email,
  userId: null as string | null,
  role: 'front_desk',
  isActive: true,
}
type Member = typeof member
type Staff = typeof staff
type AuthUser = { id: string; email: string }
type BindingCount = { members: number; staff: number; platform: number }
type Options = {
  gym?: { id: string; gymCode: string } | null
  member?: Member | null
  staff?: Staff | null
  authUser?: AuthUser | null
  bindings?: BindingCount
  memberBindRows?: number
  staffBindRows?: number
  createError?: Error
  bindError?: Error
}
type Event = { method: string; args: unknown[] }

function witness(options: Options = {}) {
  const calls: Event[] = []
  const record = (method: string, ...args: unknown[]) => calls.push({ method, args })
  const gym = options.gym === undefined ? { id: tenantId, gymCode } : options.gym
  const targetMember = options.member === undefined ? member : options.member
  const targetStaff = options.staff === undefined ? staff : options.staff
  const existingUser = options.authUser === undefined ? null : options.authUser
  const emptyBindings = { members: 0, staff: 0, platform: 0 }

  return {
    calls,
    port: {
      async findGymByCode(code: string) {
        record('findGymByCode', code)
        return gym?.gymCode === code ? gym : null
      },
      async findMember(requestedTenant: string, requestedId: string) {
        record('findMember', requestedTenant, requestedId)
        return targetMember?.tenantId === requestedTenant && targetMember.id === requestedId ? targetMember : null
      },
      async findStaff(requestedTenant: string, requestedId: string) {
        record('findStaff', requestedTenant, requestedId)
        return targetStaff?.tenantId === requestedTenant && targetStaff.id === requestedId ? targetStaff : null
      },
      async findAuthUserByEmail(requestedEmail: string) {
        record('findAuthUserByEmail', requestedEmail)
        return existingUser?.email.trim().toLowerCase() === requestedEmail.trim().toLowerCase()
          ? existingUser : null
      },
      async countBindings(requestedId: string) {
        record('countBindings', requestedId)
        return requestedId === authId ? (options.bindings ?? emptyBindings) : emptyBindings
      },
      async createConfirmedAuthUser(requestedEmail: string) {
        record('createConfirmedAuthUser', requestedEmail)
        if (options.createError) throw options.createError
        return { id: createdId }
      },
      async deleteAuthUser(requestedId: string) {
        record('deleteAuthUser', requestedId)
      },
      async bindMember(requestedTenant: string, requestedId: string, requestedUser: string) {
        record('bindMember', requestedTenant, requestedId, requestedUser)
        if (options.bindError) throw options.bindError
        return options.memberBindRows ?? 1
      },
      async bindStaff(requestedTenant: string, requestedId: string, requestedUser: string) {
        record('bindStaff', requestedTenant, requestedId, requestedUser)
        if (options.bindError) throw options.bindError
        return options.staffBindRows ?? 1
      },
    },
  }
}

function request(overrides: Record<string, unknown> = {}) {
  return { email, gymCode, target: { kind: 'member', id: memberId }, apply: false, ...overrides }
}

const writeMethods = new Set(['createConfirmedAuthUser', 'deleteAuthUser', 'bindMember', 'bindStaff'])
function methodCalls(w: ReturnType<typeof witness>, method: string) {
  return w.calls.filter((call) => call.method === method)
}
function expectNoWrites(w: ReturnType<typeof witness>) {
  expect(w.calls.filter((call) => writeMethods.has(call.method))).toEqual([])
}

async function exposedOutcome(operation: () => Promise<unknown>): Promise<string> {
  try {
    return JSON.stringify(await operation())
  } catch (caught) {
    return caught instanceof Error ? caught.message : String(caught)
  }
}

function captureCli() {
  const output: string[] = []
  const network = vi.fn(async () => { throw new Error('unexpected network attempt') })
  vi.stubGlobal('fetch', network)
  vi.spyOn(console, 'log').mockImplementation((...parts: unknown[]) => { output.push(`${parts.map(String).join(' ')}\n`) })
  vi.spyOn(console, 'error').mockImplementation((...parts: unknown[]) => { output.push(`${parts.map(String).join(' ')}\n`) })
  vi.spyOn(process.stdout, 'write').mockImplementation((part) => { output.push(String(part)); return true })
  vi.spyOn(process.stderr, 'write').mockImplementation((part) => { output.push(String(part)); return true })
  return { output, network }
}

const baseArgs = ['--email', email, '--gym', gymCode, '--member', memberId]

afterEach(() => {
  vi.unstubAllGlobals()
  vi.restoreAllMocks()
})

describe('PROV-002 input boundary', () => {
  it.each([
    ['missing at sign', { email: 'alice.example.test' }],
    ['multiple at signs', { email: 'alice@example@test' }],
    ['missing local part', { email: '@example.test' }],
    ['undotted domain', { email: 'alice@example' }],
    ['internal whitespace', { email: 'alice @example.test' }],
    ['missing email', { email: undefined }],
    ['lowercase gym code', { gymCode: 'p1l0t9' }],
    ['short gym code', { gymCode: 'P1L0T' }],
    ['long gym code', { gymCode: 'P1L0T99' }],
    ['punctuation in gym code', { gymCode: 'P1L-T9' }],
    ['non-UUID target', { target: { kind: 'member', id: '33333333' } }],
    ['unknown target kind', { target: { kind: 'owner', id: memberId } }],
    ['missing target', { target: null }],
  ])('refuses %s before opening a port', async (_label, override) => {
    const w = witness()
    const result = await provisionIdentity(w.port, request(override))
    expect(result).toMatchObject({ ok: false, code: 'invalid_request' })
    expect(w.calls).toEqual([])
    expect(JSON.stringify(result)).not.toContain(email)
  })
})

describe('PROV-001, PROV-003–006 read-only gatekeeping', () => {
  it('does not infer a tenant when the code is absent', async () => {
    const w = witness({ gym: null })
    expect(await provisionIdentity(w.port, request())).toMatchObject({ ok: false, code: 'gym_not_found' })
    expect(w.calls.map((call) => call.method)).toEqual(['findGymByCode'])
  })

  it.each([
    ['member', { kind: 'member', id: memberId }],
    ['staff', { kind: 'staff', id: staffId }],
  ])('cannot see an identically shaped %s row in a different tenant', async (_kind, target) => {
    const w = witness({
      member: { ...member, tenantId: otherTenantId },
      staff: { ...staff, tenantId: otherTenantId },
    })
    expect(await provisionIdentity(w.port, request({ target }))).toMatchObject({ ok: false, code: 'target_not_found' })
    expect(methodCalls(w, target.kind === 'member' ? 'findMember' : 'findStaff')[0]?.args).toEqual([tenantId, target.id])
    expectNoWrites(w)
  })

  it('refuses a target row without an email even if its id matches', async () => {
    const w = witness({ member: { ...member, email: null as unknown as string } })
    expect(await provisionIdentity(w.port, request())).toMatchObject({ ok: false, code: 'email_mismatch' })
    expectNoWrites(w)
  })

  it('rejects an email with a visually similar but different domain', async () => {
    const w = witness({ member: { ...member, email: 'alice.pilot@example.tests' } })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'email_mismatch' })
    expectNoWrites(w)
  })

  it.each([
    ['cancelled', { status: 'cancelled' }],
    ['blocked', { status: 'blocked' }],
    ['erased', { erasedAt: '2026-09-23T12:00:00Z' }],
  ])('refuses a %s member even when apply is requested', async (_label, override) => {
    const w = witness({ member: { ...member, ...override } })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' })
    expectNoWrites(w)
  })

  it.each([
    ['inactive', { isActive: false }],
    ['gym owner', { role: 'gym_owner' }],
  ])('refuses %s staff before linking', async (_label, override) => {
    const w = witness({ staff: { ...staff, ...override } })
    const target = { kind: 'staff', id: staffId }
    expect(await provisionIdentity(w.port, request({ target, apply: true }))).toMatchObject({ ok: false, code: 'target_ineligible' })
    expectNoWrites(w)
  })

  it('does not overwrite a target already linked to a different Auth user', async () => {
    const w = witness({ member: { ...member, userId: differentAuthId }, authUser: { id: authId, email } })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_already_linked' })
    expectNoWrites(w)
  })

  it('treats the exact existing binding as an idempotent no-write success', async () => {
    const w = witness({
      member: { ...member, userId: authId },
      authUser: { id: authId, email },
      bindings: { members: 1, staff: 0, platform: 0 },
    })
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({ ok: true, code: 'already_linked', authUserId: authId })
    expectNoWrites(w)
  })

  it.each(['members', 'staff', 'platform'] as const)('refuses an Auth identity bound through %s', async (binding) => {
    const w = witness({
      authUser: { id: authId, email },
      bindings: { members: 0, staff: 0, platform: 0, [binding]: 1 },
    })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'identity_bound_elsewhere',
    })
    expect(methodCalls(w, 'countBindings')[0]?.args).toEqual([authId])
    expectNoWrites(w)
  })

  it('plans a new identity with no writes and no made-up Auth id', async () => {
    const w = witness()
    const result = await provisionIdentity(w.port, request())
    expect(result).toMatchObject({
      ok: true, code: 'planned', authUser: 'would_create', authUserId: null,
      target: { kind: 'member', id: memberId }, email: redactedEmail,
    })
    expectNoWrites(w)
  })

  it('compares surrounding whitespace and casing, reusing an unbound identity in dry run', async () => {
    const w = witness({
      member: { ...member, email: '  ALICE.PILOT@EXAMPLE.TEST ' },
      authUser: { id: authId, email: 'Alice.Pilot@Example.Test' },
    })
    const result = await provisionIdentity(w.port, request({ email: ` ${email.toUpperCase()} ` }))
    expect(result).toMatchObject({
      ok: true, code: 'planned', authUser: 'would_reuse', authUserId: authId,
    })
    expect(result.email?.toLowerCase()).toBe(redactedEmail)
    expectNoWrites(w)
  })
})

describe('PROV-007–009 effect sequence and secrecy', () => {
  it('creates one Auth identity and binds exactly one member row', async () => {
    const w = witness()
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({
      ok: true, code: 'linked', authUser: 'created', authUserId: createdId, email: redactedEmail,
    })
    expect(methodCalls(w, 'createConfirmedAuthUser').map((call) => call.args)).toEqual([[email]])
    expect(methodCalls(w, 'bindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId]])
    expect(methodCalls(w, 'bindStaff')).toEqual([])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
    expect(w.calls.findIndex((call) => call.method === 'createConfirmedAuthUser'))
      .toBeLessThan(w.calls.findIndex((call) => call.method === 'bindMember'))
  })

  it('reuses an unbound Auth user when binding one staff row', async () => {
    const w = witness({ authUser: { id: authId, email } })
    const result = await provisionIdentity(w.port, request({ target: { kind: 'staff', id: staffId }, apply: true }))
    expect(result).toMatchObject({ ok: true, code: 'linked', authUser: 'reused', authUserId: authId })
    expect(methodCalls(w, 'bindStaff').map((call) => call.args)).toEqual([[tenantId, staffId, authId]])
    expect(methodCalls(w, 'bindMember')).toEqual([])
    expect(methodCalls(w, 'createConfirmedAuthUser')).toEqual([])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
  })

  it.each([0, 2])('compensates exactly once when a new-user bind reports %i rows', async (affected) => {
    const w = witness({ memberBindRows: affected })
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' })
    expect(methodCalls(w, 'createConfirmedAuthUser')).toHaveLength(1)
    expect(methodCalls(w, 'bindMember')).toHaveLength(1)
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
  })

  it('never deletes a reused Auth user when conditional binding loses a race', async () => {
    const w = witness({ authUser: { id: authId, email }, memberBindRows: 0 })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'bind_conflict',
    })
    expect(methodCalls(w, 'bindMember').map((call) => call.args)).toEqual([[tenantId, memberId, authId]])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
  })

  it('never echoes the raw provider failure from Auth creation', async () => {
    const w = witness({ createError: new Error(`creation failed ${email} ${poison}`) })
    const exposed = await exposedOutcome(() => provisionIdentity(w.port, request({ apply: true })))
    expect(methodCalls(w, 'createConfirmedAuthUser')).toHaveLength(1)
    expect(methodCalls(w, 'bindMember')).toEqual([])
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
  })

  it('compensates a created user on a thrown bind without leaking exception text', async () => {
    const w = witness({ bindError: new Error(`binding failed ${email} ${poison}`) })
    const exposed = await exposedOutcome(() => provisionIdentity(w.port, request({ apply: true })))
    expect(methodCalls(w, 'bindMember')).toHaveLength(1)
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
  })

  it('never compensates a reused user when a bind throws', async () => {
    const w = witness({ authUser: { id: authId, email }, bindError: new Error(`binding failed ${email} ${poison}`) })
    const exposed = await exposedOutcome(() => provisionIdentity(w.port, request({ apply: true })))
    expect(methodCalls(w, 'bindMember')).toHaveLength(1)
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
  })

  it('redacts the address in a refusal as well as a successful plan', async () => {
    const w = witness({ member: { ...member, email: 'someone-else@example.test' } })
    const result = await provisionIdentity(w.port, request())
    expect(result).toMatchObject({ ok: false, code: 'email_mismatch', email: redactedEmail })
    const serialized = JSON.stringify(result)
    expect(serialized).not.toContain(email)
    expect(serialized).not.toContain('someone-else@example.test')
    expect(serialized).not.toContain(poison)
  })
})

describe('PROV-002, PROV-009–010 CLI guardrails', () => {
  it.each([
    ['missing email', ['--gym', gymCode, '--member', memberId]],
    ['missing gym code', ['--email', email, '--member', memberId]],
    ['missing target', ['--email', email, '--gym', gymCode]],
    ['both target kinds', [...baseArgs, '--staff', staffId]],
    ['duplicate email flag', [...baseArgs, '--email', 'elsewhere@example.test']],
    ['duplicate apply flag', [...baseArgs, '--apply', '--apply']],
    ['unknown flag', [...baseArgs, '--unknown']],
    ['missing member id', ['--email', email, '--gym', gymCode, '--member']],
  ])('rejects %s as one sanitized JSON line without network access', async (_label, argv) => {
    const { output, network } = captureCli()
    const exitCode = await main(argv)
    const lines = output.join('').trim().split(/\r?\n/)
    expect(exitCode).toBe(1)
    expect(lines).toHaveLength(1)
    const result = JSON.parse(lines[0]) as { ok: boolean; code: string; email: string | null }
    expect(result).toMatchObject({ ok: false, code: 'invalid_request' })
    expect(result.email === null || result.email.toLowerCase() === redactedEmail).toBe(true)
    expect(output.join('')).not.toContain(email)
    expect(output.join('')).not.toContain(poison)
    expect(network).not.toHaveBeenCalled()
  })
})
