import { afterEach, describe, expect, it, vi } from 'vitest'

import { createSupabaseProvisionPort, main, provisionIdentity } from '../../scripts/provision-identity.mjs'

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
type AuthUser = {
  id: string
  email: string
  provisioned: boolean
  googleVerified: boolean
  hasEmailIdentity: boolean
}
type BindingCount = { members: number; staff: number; platform: number }
type LookupMethod = 'findGymByCode' | 'findMember' | 'findStaff' | 'findAuthUserByEmail' | 'countBindings'
type Options = {
  gym?: { id: string; gymCode: string } | null
  member?: Member | null
  staff?: Staff | null
  authUser?: AuthUser | null
  bindings?: BindingCount | Record<string, unknown>
  postBindings?: BindingCount | Record<string, unknown>
  memberAtBind?: Member
  staffAtBind?: Staff
  memberBindRows?: number
  staffBindRows?: number
  lookupErrors?: Partial<Record<LookupMethod, Error>>
  postCountError?: Error
  createError?: Error
  bindError?: Error
  unbindError?: Error
}
type Event = { method: string; args: unknown[] }
const verifiedAuth: AuthUser = {
  id: authId,
  email,
  provisioned: true,
  googleVerified: false,
  hasEmailIdentity: true,
}

function witness(options: Options = {}) {
  const calls: Event[] = []
  const record = (method: string, ...args: unknown[]) => calls.push({ method, args })
  const gym = options.gym === undefined ? { id: tenantId, gymCode } : options.gym
  const targetMember = options.member === undefined ? member : options.member
  const targetStaff = options.staff === undefined ? staff : options.staff
  const existingUser = options.authUser === undefined ? null : options.authUser
  const emptyBindings = { members: 0, staff: 0, platform: 0 }
  const singleMemberBinding = { members: 1, staff: 0, platform: 0 }
  const singleStaffBinding = { members: 0, staff: 1, platform: 0 }
  const failLookup = (method: LookupMethod) => {
    if (options.lookupErrors?.[method]) throw options.lookupErrors[method]
  }

  return {
    calls,
    port: {
      async findGymByCode(code: string) {
        record('findGymByCode', code)
        failLookup('findGymByCode')
        return gym?.gymCode === code ? gym : null
      },
      async findMember(requestedTenant: string, requestedId: string) {
        record('findMember', requestedTenant, requestedId)
        failLookup('findMember')
        return targetMember?.tenantId === requestedTenant && targetMember.id === requestedId ? targetMember : null
      },
      async findStaff(requestedTenant: string, requestedId: string) {
        record('findStaff', requestedTenant, requestedId)
        failLookup('findStaff')
        return targetStaff?.tenantId === requestedTenant && targetStaff.id === requestedId ? targetStaff : null
      },
      async findAuthUserByEmail(requestedEmail: string) {
        record('findAuthUserByEmail', requestedEmail)
        failLookup('findAuthUserByEmail')
        return existingUser?.email.trim().toLowerCase() === requestedEmail.trim().toLowerCase()
          ? existingUser : null
      },
      async countBindings(requestedId: string) {
        record('countBindings', requestedId)
        failLookup('countBindings')
        if (options.postCountError && methodCalls({ calls }, 'countBindings').length > 1) throw options.postCountError
        const attemptedBind = calls.some((call) =>
          (call.method === 'bindMember' || call.method === 'bindStaff') && call.args[2] === requestedId,
        )
        if (attemptedBind && options.postBindings) return options.postBindings
        const boundMember = calls.some((call) => call.method === 'bindMember' &&
          call.args[2] === requestedId && options.memberBindRows === undefined && !options.memberAtBind)
        const boundStaff = calls.some((call) => call.method === 'bindStaff' &&
          call.args[2] === requestedId && options.staffBindRows === undefined && !options.staffAtBind)
        if (boundMember || boundStaff) return boundMember ? singleMemberBinding : singleStaffBinding
        if (requestedId === authId) return options.bindings ?? emptyBindings
        return emptyBindings
      },
      async createConfirmedAuthUser(requestedEmail: string) {
        record('createConfirmedAuthUser', requestedEmail)
        if (options.createError) throw options.createError
        return { id: createdId }
      },
      async deleteAuthUser(requestedId: string) {
        record('deleteAuthUser', requestedId)
      },
      async bindMember(requestedTenant: string, requestedId: string, requestedUser: string, expectedEmail: string) {
        record('bindMember', requestedTenant, requestedId, requestedUser, expectedEmail)
        if (options.bindError) throw options.bindError
        if (options.memberAtBind && (
          options.memberAtBind.tenantId !== requestedTenant || options.memberAtBind.id !== requestedId ||
          options.memberAtBind.userId !== null || options.memberAtBind.status === 'cancelled' ||
          options.memberAtBind.status === 'blocked' || options.memberAtBind.erasedAt !== null ||
          options.memberAtBind.email.trim().toLowerCase() !== expectedEmail.trim().toLowerCase()
        )) return 0
        return options.memberBindRows ?? 1
      },
      async bindStaff(requestedTenant: string, requestedId: string, requestedUser: string, expectedEmail: string) {
        record('bindStaff', requestedTenant, requestedId, requestedUser, expectedEmail)
        if (options.bindError) throw options.bindError
        if (options.staffAtBind && (
          options.staffAtBind.tenantId !== requestedTenant || options.staffAtBind.id !== requestedId ||
          options.staffAtBind.userId !== null || options.staffAtBind.role === 'gym_owner' ||
          !options.staffAtBind.isActive ||
          options.staffAtBind.email.trim().toLowerCase() !== expectedEmail.trim().toLowerCase()
        )) return 0
        return options.staffBindRows ?? 1
      },
      async unbindMember(requestedTenant: string, requestedId: string, requestedUser: string) {
        record('unbindMember', requestedTenant, requestedId, requestedUser)
        if (options.unbindError) throw options.unbindError
        return 1
      },
      async unbindStaff(requestedTenant: string, requestedId: string, requestedUser: string) {
        record('unbindStaff', requestedTenant, requestedId, requestedUser)
        if (options.unbindError) throw options.unbindError
        return 1
      },
    },
  }
}

function request(overrides: Record<string, unknown> = {}) {
  return { email, gymCode, target: { kind: 'member', id: memberId }, apply: false, ...overrides }
}

const writeMethods = new Set([
  'createConfirmedAuthUser', 'deleteAuthUser', 'bindMember', 'bindStaff', 'unbindMember', 'unbindStaff',
])
function methodCalls(w: { calls: Event[] }, method: string) {
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
    const w = witness({ member: { ...member, userId: differentAuthId }, authUser: verifiedAuth })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({ ok: false, code: 'target_already_linked' })
    expectNoWrites(w)
  })

  it('treats the exact existing binding as an idempotent no-write success', async () => {
    const w = witness({
      member: { ...member, userId: authId },
      authUser: verifiedAuth,
      bindings: { members: 1, staff: 0, platform: 0 },
    })
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({ ok: true, code: 'already_linked', authUserId: authId })
    expectNoWrites(w)
  })

  it.each(['members', 'staff', 'platform'] as const)('refuses an Auth identity bound through %s', async (binding) => {
    const w = witness({
      authUser: verifiedAuth,
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
      authUser: { ...verifiedAuth, email: 'Alice.Pilot@Example.Test' },
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
    expect(methodCalls(w, 'bindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId, email]])
    expect(methodCalls(w, 'countBindings').map((call) => call.args)).toEqual([[createdId]])
    expect(methodCalls(w, 'bindStaff')).toEqual([])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
    expect(w.calls.findIndex((call) => call.method === 'createConfirmedAuthUser'))
      .toBeLessThan(w.calls.findIndex((call) => call.method === 'bindMember'))
  })

  it('reuses an unbound Auth user when binding one staff row', async () => {
    const w = witness({ authUser: verifiedAuth })
    const result = await provisionIdentity(w.port, request({ target: { kind: 'staff', id: staffId }, apply: true }))
    expect(result).toMatchObject({ ok: true, code: 'linked', authUser: 'reused', authUserId: authId })
    expect(methodCalls(w, 'bindStaff').map((call) => call.args)).toEqual([[tenantId, staffId, authId, email]])
    expect(methodCalls(w, 'countBindings')).toHaveLength(2)
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
    const w = witness({ authUser: verifiedAuth, memberBindRows: 0 })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'bind_conflict',
    })
    expect(methodCalls(w, 'bindMember').map((call) => call.args)).toEqual([[tenantId, memberId, authId, email]])
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
    const w = witness({ authUser: verifiedAuth, bindError: new Error(`binding failed ${email} ${poison}`) })
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

describe('PROV-006a, PROV-006b and PROV-012 identity proof and lookup failure', () => {
  it.each([
    ['self-registered password', { provisioned: false, googleVerified: false, hasEmailIdentity: true }],
    ['unverified signup', { provisioned: false, googleVerified: false, hasEmailIdentity: false }],
    ['Google added to password signup', { provisioned: false, googleVerified: true, hasEmailIdentity: true }],
  ])('does not trust a %s identity even on apply', async (_label, attributes) => {
    const w = witness({ authUser: { ...verifiedAuth, ...attributes } })
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({ ok: false, code: 'identity_unverified' })
    expectNoWrites(w)
  })

  it('accepts a Google-only verified identity without a password identity', async () => {
    const w = witness({
      authUser: { ...verifiedAuth, provisioned: false, googleVerified: true, hasEmailIdentity: false },
    })
    expect(await provisionIdentity(w.port, request())).toMatchObject({
      ok: true, code: 'planned', authUser: 'would_reuse', authUserId: authId,
    })
    expectNoWrites(w)
  })

  it.each([
    ['extra member', { members: 2, staff: 0, platform: 0 }],
    ['extra staff', { members: 1, staff: 1, platform: 0 }],
    ['extra platform', { members: 1, staff: 0, platform: 1 }],
    ['missing own binding', { members: 0, staff: 0, platform: 0 }],
  ])('does not claim idempotence when %s appears in the binding count', async (_label, bindings) => {
    const w = witness({ member: { ...member, userId: authId }, authUser: verifiedAuth, bindings })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'identity_bound_elsewhere',
    })
    expect(methodCalls(w, 'countBindings').map((call) => call.args)).toEqual([[authId]])
    expectNoWrites(w)
  })

  it.each([
    ['gym lookup', 'findGymByCode', {}],
    ['member lookup', 'findMember', {}],
    ['staff lookup', 'findStaff', { target: { kind: 'staff', id: staffId } }],
    ['Auth directory lookup', 'findAuthUserByEmail', {}],
    ['binding count lookup', 'countBindings', {}],
  ] as const)('fails closed on throwing %s', async (_label, method, override) => {
    const w = witness({
      authUser: verifiedAuth,
      lookupErrors: { [method]: new Error(`lookup unavailable ${email} ${poison}`) },
    })
    const result = await provisionIdentity(w.port, request({ ...override, apply: true }))
    expect(result).toMatchObject({ ok: false, code: 'lookup_failed' })
    expectNoWrites(w)
    expect(JSON.stringify(result)).not.toContain(email)
    expect(JSON.stringify(result)).not.toContain(poison)
  })
})

describe('PROV-007a, PROV-008 and PROV-011 concurrent mutation', () => {
  it.each([
    ['email changed', { email: 'other.person@example.test' }],
    ['cancelled', { status: 'cancelled' }],
    ['erased', { erasedAt: '2026-09-24T12:00:00Z' }],
    ['bound elsewhere', { userId: differentAuthId }],
  ])('passes the expected email to a guarded member bind after %s', async (_label, changed) => {
    const w = witness({ memberAtBind: { ...member, ...changed } })
    const result = await provisionIdentity(w.port, request({ apply: true }))
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' })
    expect(methodCalls(w, 'bindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId, email]])
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
    expect(methodCalls(w, 'unbindMember')).toEqual([])
  })

  it.each([
    ['email changed', { email: 'other.person@example.test' }],
    ['owner promoted', { role: 'gym_owner' }],
    ['deactivated', { isActive: false }],
  ])('passes the expected email to a guarded staff bind after %s', async (_label, changed) => {
    const w = witness({ staffAtBind: { ...staff, ...changed }, authUser: verifiedAuth })
    const result = await provisionIdentity(w.port, request({ apply: true, target: { kind: 'staff', id: staffId } }))
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' })
    expect(methodCalls(w, 'bindStaff').map((call) => call.args)).toEqual([[tenantId, staffId, authId, email]])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
    expect(methodCalls(w, 'unbindStaff')).toEqual([])
  })

  it.each([
    ['member', { target: { kind: 'member', id: memberId } }, 'unbindMember', memberId],
    ['staff', { target: { kind: 'staff', id: staffId } }, 'unbindStaff', staffId],
  ] as const)('unwinds exactly its own %s binding on concurrent reuse', async (_label, overrides, unbind, id) => {
    const w = witness({
      authUser: verifiedAuth,
      postBindings: { members: 1, staff: 1, platform: 0 },
    })
    const result = await provisionIdentity(w.port, request({ ...overrides, apply: true }))
    expect(result).toMatchObject({ ok: false, code: 'bind_conflict' })
    expect(methodCalls(w, 'countBindings')).toHaveLength(2)
    expect(methodCalls(w, unbind).map((call) => call.args)).toEqual([[tenantId, id, authId]])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
  })

  it.each([
    ['new identity', undefined, createdId],
    ['reused identity', verifiedAuth, authId],
  ] as const)('unwinds a post-bind zero for %s without reporting linked', async (_label, authUser, id) => {
    const w = witness({ authUser, postBindings: { members: 0, staff: 0, platform: 0 } })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'bind_conflict',
    })
    expect(methodCalls(w, 'unbindMember').map((call) => call.args)).toEqual([[tenantId, memberId, id]])
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args))
      .toEqual(id === createdId ? [[createdId]] : [])
  })

  it.each([
    ['missing field', { members: 1, staff: 0 }],
    ['null field', { members: 1, staff: null, platform: 0 }],
    ['numeric string', { members: '1', staff: 0, platform: 0 }],
    ['non-numeric field', { members: 1, staff: 'unknown', platform: 0 }],
  ])('fails closed on %s in an initial count without writes', async (_label, bindings) => {
    const w = witness({ authUser: verifiedAuth, bindings })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'lookup_failed',
    })
    expectNoWrites(w)
  })

  it.each([
    ['missing field', { members: 1, staff: 0 }],
    ['null field', { members: 1, staff: null, platform: 0 }],
    ['numeric string', { members: '1', staff: 0, platform: 0 }],
  ])('unwinds a %s in the post-bind count', async (_label, postBindings) => {
    const w = witness({ postBindings })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'bind_conflict',
    })
    expect(methodCalls(w, 'unbindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId]])
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
  })

  it('unwinds the binding and deletes only the identity created in this run', async () => {
    const w = witness({ postBindings: { members: 2, staff: 0, platform: 0 } })
    expect(await provisionIdentity(w.port, request({ apply: true }))).toMatchObject({
      ok: false, code: 'bind_conflict',
    })
    expect(methodCalls(w, 'unbindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId]])
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
    expect(w.calls.findIndex((call) => call.method === 'unbindMember'))
      .toBeLessThan(w.calls.findIndex((call) => call.method === 'deleteAuthUser'))
  })

  it('never reports success when the post-bind count throws', async () => {
    const w = witness({ authUser: verifiedAuth, postCountError: new Error(`count failed ${email} ${poison}`) })
    const exposed = await exposedOutcome(() => provisionIdentity(w.port, request({ apply: true })))
    expect(exposed).toContain('bind_conflict')
    expect(exposed).not.toContain('"linked"')
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
    expect(methodCalls(w, 'unbindMember').map((call) => call.args)).toEqual([[tenantId, memberId, authId]])
    expect(methodCalls(w, 'deleteAuthUser')).toEqual([])
  })

  it('does not report linked or leak when undoing a concurrent conflict itself throws', async () => {
    const w = witness({
      postBindings: { members: 2, staff: 0, platform: 0 },
      unbindError: new Error(`undo failed ${email} ${poison}`),
    })
    const exposed = await exposedOutcome(() => provisionIdentity(w.port, request({ apply: true })))
    expect(exposed).toContain('bind_conflict')
    expect(exposed).not.toContain('"linked"')
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
    expect(methodCalls(w, 'unbindMember').map((call) => call.args)).toEqual([[tenantId, memberId, createdId]])
    expect(methodCalls(w, 'deleteAuthUser').map((call) => call.args)).toEqual([[createdId]])
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

type TableRow = Record<string, unknown>
type FilterStep = { method: string; column: string; values: unknown[] }
type QueryTrace = {
  table: string
  action: 'select' | 'update' | 'delete'
  filters: FilterStep[]
  options: { count?: string; head?: boolean }
  patch?: TableRow
  returnRows: boolean
}
type AdapterFixture = {
  rows?: Record<string, TableRow[]>
  users?: TableRow[]
  dbErrorTable?: string
  missingCountTable?: string
  authErrorPage?: number
}

function sqlPattern(pattern: string): RegExp {
  let source = '^'
  const escapeRegex = (char: string) => char.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
  for (let index = 0; index < pattern.length; index += 1) {
    const char = pattern[index]
    if (char === '\\' && index + 1 < pattern.length) {
      source += escapeRegex(pattern[++index]!)
    } else if (char === '%') {
      source += '.*'
    } else if (char === '_') {
      source += '.'
    } else {
      source += escapeRegex(char)
    }
  }
  return new RegExp(`${source}$`, 'i')
}

function strictSupabase(fixture: AdapterFixture = {}) {
  const rows: Record<string, TableRow[]> = {
    organizations: [{ id: tenantId, gym_code: gymCode }],
    members: [{ id: memberId, tenant_id: tenantId, email, user_id: null, status: 'active', erased_at: null }],
    staff: [{ id: staffId, tenant_id: tenantId, email, user_id: null, role: 'front_desk', is_active: true }],
    platform_users: [],
    ...fixture.rows,
  }
  const queries: QueryTrace[] = []
  const users = fixture.users ?? []
  const listUsers = vi.fn(async ({ page, perPage }: { page: number; perPage: number }) => ({
    data: { users: users.slice((page - 1) * perPage, page * perPage) },
    error: page === fixture.authErrorPage ? { message: `directory failed ${email} ${poison}` } : null,
  }))
  const createUser = vi.fn(async (attributes: TableRow) => ({
    data: { user: { id: createdId, email: attributes.email } }, error: null,
  }))
  const deleteUser = vi.fn(async (userId: string) => ({ data: { user: { id: userId } }, error: null }))

  function matches(row: TableRow, step: FilterStep): boolean {
    const [value, extra] = step.values
    const found = row[step.column]
    if (step.method === 'eq') return found === value
    if (step.method === 'neq') return found !== value
    if (step.method === 'is') return found === value
    if (step.method === 'ilike') return sqlPattern(String(value)).test(String(found ?? ''))
    if (step.method === 'in') return (value as unknown[]).includes(found)
    if (step.method === 'not' && value === 'in') {
      return !String(extra).replace(/^\(|\)$/g, '').split(',').includes(String(found))
    }
    if (step.method === 'not' && value === 'is') return found !== extra
    if (step.method === 'filter' && value === 'not.in') {
      return !String(extra).replace(/^\(|\)$/g, '').split(',').includes(String(found))
    }
    throw new Error(`unsupported query filter: ${step.method}`)
  }

  function build(table: string, action: QueryTrace['action'], patch?: TableRow, options: QueryTrace['options'] = {}) {
    const event: QueryTrace = { table, action, filters: [], options, patch, returnRows: action === 'select' }
    queries.push(event)
    let mode: 'array' | 'single' | 'maybeSingle' = 'array'
    const add = (method: string, column: string, ...values: unknown[]) => {
      event.filters.push({ method, column, values })
      return builder
    }
    const builder = {
      eq: (column: string, value: unknown) => add('eq', column, value),
      neq: (column: string, value: unknown) => add('neq', column, value),
      is: (column: string, value: unknown) => add('is', column, value),
      ilike: (column: string, value: unknown) => add('ilike', column, value),
      in: (column: string, values: unknown[]) => add('in', column, values),
      not: (column: string, operator: string, value: unknown) => add('not', column, operator, value),
      filter: (column: string, operator: string, value: unknown) => add('filter', column, operator, value),
      match: (attributes: TableRow) => {
        for (const [column, value] of Object.entries(attributes)) add('eq', column, value)
        return builder
      },
      select: (_columns: string, returnOptions: QueryTrace['options'] = {}) => {
        event.returnRows = true
        event.options = { ...event.options, ...returnOptions }
        return builder
      },
      maybeSingle: () => { mode = 'maybeSingle'; return builder },
      single: () => { mode = 'single'; return builder },
      then: (resolve: (outcome: unknown) => unknown, reject?: (reason: unknown) => unknown) => {
        const result = (() => {
          if (fixture.dbErrorTable === table) {
            return { data: null, error: { message: `database failed ${email} ${poison}` }, count: null }
          }
          const matched = (rows[table] ?? []).filter((row) => event.filters.every((step) => matches(row, step)))
          if (action === 'update' && patch) matched.forEach((row) => Object.assign(row, patch))
          if (action === 'delete') rows[table] = (rows[table] ?? []).filter((row) => !matched.includes(row))
          const data = event.options.head || !event.returnRows ? null
            : mode === 'array' ? matched : matched[0] ?? null
          const count = fixture.missingCountTable === table ? null : matched.length
          return { data, error: null, count }
        })()
        return Promise.resolve(result).then(resolve, reject)
      },
    }
    return builder
  }

  const client = {
    from(table: string) {
      if (!Object.hasOwn(rows, table)) throw new Error(`unknown table: ${table}`)
      // The pre-filter relation intentionally has NO eq/is/not/ilike methods.
      return {
        select: (_columns: string, options?: QueryTrace['options']) => build(table, 'select', undefined, options),
        update: (patch: TableRow, options?: QueryTrace['options']) => build(table, 'update', patch, options),
        delete: (options?: QueryTrace['options']) => build(table, 'delete', undefined, options),
      }
    },
    auth: { admin: { listUsers, createUser, deleteUser } },
  }
  return { client, rows, queries, listUsers, createUser, deleteUser }
}

describe('PROV-003, PROV-006a, PROV-007a, PROV-009, PROV-011–012 strict adapter', () => {
  it('reads a tenant and row through a strict v2 post-select filter builder', async () => {
    const f = strictSupabase()
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.findGymByCode(gymCode)).toMatchObject({ id: tenantId, gymCode })
    expect(await port.findMember(tenantId, memberId)).toMatchObject({ id: memberId, tenantId, email })
    expect(await port.findStaff(tenantId, staffId)).toMatchObject({ id: staffId, tenantId, email })
    const targetReads = f.queries.filter((query) => ['members', 'staff'].includes(query.table))
    expect(targetReads).toHaveLength(2)
    for (const read of targetReads) {
      expect(read.action).toBe('select')
      expect(read.filters).toEqual(expect.arrayContaining([
        { method: 'eq', column: 'tenant_id', values: [tenantId] },
      ]))
    }
  })

  it('counts every binding, including platform users by user_id rather than an id column', async () => {
    const f = strictSupabase({ rows: {
      members: [{ id: memberId, user_id: authId }],
      staff: [{ id: staffId, user_id: authId }],
      platform_users: [{ user_id: authId, role: 'super_admin' }],
    } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.countBindings(authId)).toEqual({ members: 1, staff: 1, platform: 1 })
    expect(f.queries.filter((query) => query.table === 'platform_users')).toHaveLength(1)
    for (const query of f.queries) {
      expect(query.filters).toContainEqual({ method: 'eq', column: 'user_id', values: [authId] })
      expect(query.options.count).toBe('exact')
    }
  })

  it('refuses an unavailable count rather than treating missing count as zero', async () => {
    const f = strictSupabase({ missingCountTable: 'staff' })
    const port = createSupabaseProvisionPort(f.client)
    await expect(port.countBindings(authId)).rejects.toThrow()
    const exposed = await exposedOutcome(() => port.countBindings(authId))
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
    expect(f.queries.some((query) => query.table === 'staff')).toBe(true)
  })

  it('marks only a confirmed no-password service-provisioned Auth identity', async () => {
    const f = strictSupabase()
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.createConfirmedAuthUser(email)).toEqual({ id: createdId })
    expect(f.createUser).toHaveBeenCalledTimes(1)
    expect(f.createUser).toHaveBeenCalledWith(expect.objectContaining({
      email, email_confirm: true, app_metadata: { gymloop_provisioned: true },
    }))
    expect(f.createUser.mock.calls[0]?.[0]).not.toHaveProperty('password')
  })

  it.each([
    ['member', 'members', 'bindMember', 'unbindMember', memberId],
    ['staff', 'staff', 'bindStaff', 'unbindStaff', staffId],
  ] as const)('guards %s UPDATE and undo with exact tenant, row, identity and email filters', async (_label, table, bind, unbind, id) => {
    const f = strictSupabase()
    const port = createSupabaseProvisionPort(f.client)
    expect(await port[bind](tenantId, id, authId, email)).toBe(1)
    const update = f.queries.at(-1)!
    expect(update.table).toBe(table)
    expect(update.action).toBe('update')
    expect(update.patch).toEqual({ user_id: authId })
    expect(update.filters).toEqual(expect.arrayContaining([
      { method: 'eq', column: 'tenant_id', values: [tenantId] },
      { method: 'eq', column: 'id', values: [id] },
      { method: 'is', column: 'user_id', values: [null] },
    ]))
    const emailGuards = update.filters.filter((step) => step.column === 'email')
    expect(emailGuards.length).toBeGreaterThan(0)
    expect(await port[unbind](tenantId, id, authId)).toBe(1)
    const reverse = f.queries.at(-1)!
    expect(reverse.action).toBe('update')
    expect(reverse.patch).toEqual({ user_id: null })
    expect(reverse.filters).toEqual(expect.arrayContaining([
      { method: 'eq', column: 'tenant_id', values: [tenantId] },
      { method: 'eq', column: 'id', values: [id] },
      { method: 'eq', column: 'user_id', values: [authId] },
    ]))
  })

  it('escapes SQL LIKE wildcards in the exact email predicate', async () => {
    const requested = 'alice%_pilot@example.test'
    const decoy = 'aliceXXpilot@example.test'
    const f = strictSupabase({ rows: {
      members: [{ id: memberId, tenant_id: tenantId, email: decoy, user_id: null,
        status: 'active', erased_at: null }],
    } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.bindMember(tenantId, memberId, authId, requested)).toBe(0)
    expect(f.rows.members[0]?.user_id).toBeNull()
    const emailFilters = f.queries.at(-1)?.filters.filter((step) => step.column === 'email') ?? []
    expect(emailFilters).not.toEqual([])
    expect(emailFilters.some((step) => String(step.values[0]).includes('\\%') &&
      String(step.values[0]).includes('\\_'))).toBe(true)
  })

  it('requires stored email to be exact after trimming only the request', async () => {
    const f = strictSupabase({ rows: {
      staff: [{ id: staffId, tenant_id: tenantId, email: ` ${email} `, user_id: null,
        role: 'front_desk', is_active: true }],
    } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.bindStaff(tenantId, staffId, authId, ` ${email} `)).toBe(0)
    expect(f.rows.staff[0]?.user_id).toBeNull()
  })

  it.each([
    ['cancelled', { status: 'cancelled' }],
    ['blocked', { status: 'blocked' }],
    ['erased', { erased_at: '2026-09-24T12:00:00Z' }],
  ])('reasserts member %s eligibility on the UPDATE itself', async (_label, changes) => {
    const f = strictSupabase({ rows: {
      members: [{ id: memberId, tenant_id: tenantId, email, user_id: null,
        status: 'active', erased_at: null, ...changes }],
    } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.bindMember(tenantId, memberId, authId, email)).toBe(0)
    expect(f.rows.members[0]?.user_id).toBeNull()
    const update = f.queries.at(-1)
    expect(update?.filters.some((filter) => filter.column === 'status')).toBe(true)
    expect(update?.filters.some((filter) => filter.column === 'erased_at')).toBe(true)
  })

  it.each([
    ['owner', { role: 'gym_owner' }],
    ['inactive', { is_active: false }],
  ])('reasserts staff %s eligibility on the UPDATE itself', async (_label, changes) => {
    const f = strictSupabase({ rows: {
      staff: [{ id: staffId, tenant_id: tenantId, email, user_id: null,
        role: 'front_desk', is_active: true, ...changes }],
    } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.bindStaff(tenantId, staffId, authId, email)).toBe(0)
    expect(f.rows.staff[0]?.user_id).toBeNull()
    const update = f.queries.at(-1)
    expect(update?.filters.some((filter) => filter.column === 'role')).toBe(true)
    expect(update?.filters.some((filter) => filter.column === 'is_active')).toBe(true)
  })

  it.each([
    ['member', 'members', 'bindMember', memberId],
    ['staff', 'staff', 'bindStaff', staffId],
  ] as const)('refuses a changed %s email despite a valid identity', async (_label, table, bind, id) => {
    const row = table === 'members'
      ? { id, tenant_id: tenantId, email: 'another@example.test', user_id: null, status: 'active', erased_at: null }
      : { id, tenant_id: tenantId, email: 'another@example.test', user_id: null, role: 'front_desk', is_active: true }
    const f = strictSupabase({ rows: { [table]: [row] } })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port[bind](tenantId, id, authId, email)).toBe(0)
    expect(f.rows[table][0]?.user_id).toBeNull()
  })

  it('reports Auth identity flags from app metadata and provider identities', async () => {
    const f = strictSupabase({ users: [
      { id: authId, email, app_metadata: { gymloop_provisioned: true }, identities: [
        { provider: 'google', identity_data: { email: email.toUpperCase() } },
        { provider: 'email', identity_data: { email } },
      ] },
    ] })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.findAuthUserByEmail(email)).toEqual({
      id: authId, email, provisioned: true, googleVerified: true, hasEmailIdentity: true,
    })
  })

  it('does not confuse a different Google email with verification of this address', async () => {
    const f = strictSupabase({ users: [
      { id: authId, email, app_metadata: {}, identities: [
        { provider: 'google', identity_data: { email: 'lookalike@example.tests' } },
      ] },
    ] })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.findAuthUserByEmail(email)).toMatchObject({ googleVerified: false })
  })

  it('searches beyond the first Auth directory page for an exact email match', async () => {
    const users = Array.from({ length: 201 }, (_, index) => ({
      id: `${index}`, email: `other-${index}@example.test`, app_metadata: {}, identities: [],
    }))
    users[200] = { ...users[200], id: authId, email }
    const f = strictSupabase({ users })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.findAuthUserByEmail(email)).toMatchObject({ id: authId })
    expect(f.listUsers.mock.calls.length).toBeGreaterThan(1)
  })

  it('does not mistake an exactly full final directory page for a truncated search', async () => {
    const users = Array.from({ length: 10_000 }, (_, index) => ({
      id: String(index), email: `other-${index}@example.test`, app_metadata: {}, identities: [],
    }))
    const f = strictSupabase({ users })
    const port = createSupabaseProvisionPort(f.client)
    expect(await port.findAuthUserByEmail(email)).toBeNull()
    expect(f.listUsers.mock.calls.length).toBeGreaterThanOrEqual(50)
  })

  it('rejects a directory that still has users after the hard page cap', async () => {
    const users = Array.from({ length: 10_001 }, (_, index) => ({
      id: String(index), email: `other-${index}@example.test`, app_metadata: {}, identities: [],
    }))
    const f = strictSupabase({ users })
    const port = createSupabaseProvisionPort(f.client)
    const exposed = await exposedOutcome(() => port.findAuthUserByEmail(email))
    expect(exposed).not.toBe('null')
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
    expect(f.listUsers.mock.calls.length).toBeGreaterThanOrEqual(50)
  })

  it('does not echo an Auth API error containing a raw address or forged key', async () => {
    const f = strictSupabase({ authErrorPage: 1 })
    const port = createSupabaseProvisionPort(f.client)
    const exposed = await exposedOutcome(() => port.findAuthUserByEmail(email))
    expect(exposed).not.toBe('null')
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
  })

  it('does not echo a database error containing a raw address or forged key', async () => {
    const f = strictSupabase({ dbErrorTable: 'members' })
    const port = createSupabaseProvisionPort(f.client)
    const exposed = await exposedOutcome(() => port.findMember(tenantId, memberId))
    expect(exposed).not.toBe('null')
    expect(exposed).not.toContain(email)
    expect(exposed).not.toContain(poison)
  })
})
