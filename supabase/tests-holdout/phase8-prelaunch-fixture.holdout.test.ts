import { randomUUID } from 'node:crypto'
import { describe, expect, it } from 'vitest'
import {
  buildPrelaunchSyntheticPlan,
  renderPrelaunchStageSql,
  renderPrelaunchCleanupSql,
  parseLinkedDatabaseSize,
} from '../../scripts/phase8-prelaunch-load-fixture.mjs'

const marker = `PHASE8-LOAD-${randomUUID()}`
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

function emailFor(gym: Record<string, unknown>) {
  const email = Object.values(gym).find(
    (value): value is string => typeof value === 'string' && value.includes('@'),
  )
  expect(email).toBeDefined()
  return email!
}

function bindingsFor(plan: ReturnType<typeof buildPrelaunchSyntheticPlan>) {
  return plan.gyms.map((gym: Record<string, unknown>) => ({
    email: emailFor(gym),
    userId: randomUUID(),
  }))
}

function membersFor(gym: Record<string, unknown>) {
  const members = Object.values(gym).find(
    (value) => Array.isArray(value) && value.length > 0 && typeof value[0]?.memberId === 'string',
  ) as Array<{ memberId: string; membershipId: string }> | undefined
  expect(members).toBeDefined()
  return members!
}

function everyPlanId(plan: ReturnType<typeof buildPrelaunchSyntheticPlan>) {
  return plan.gyms.flatMap((gym: {
    gymId: string
    branchId: string
    planId: string
    staffId: string
  }) => [
    gym.gymId,
    gym.branchId,
    gym.planId,
    gym.staffId,
    ...membersFor(gym).flatMap((member) => [member.memberId, member.membershipId]),
  ])
}

describe('HARD-004 deterministic prelaunch fixture plan holdout', () => {
  it('produces 100 gyms and 500 member/membership pairs per gym with globally distinct UUIDs', () => {
    const plan = buildPrelaunchSyntheticPlan(marker)
    expect(plan.marker).toBe(marker)
    expect(plan.gyms).toHaveLength(100)
    for (const gym of plan.gyms) {
      expect(membersFor(gym)).toHaveLength(500)
      const email = emailFor(gym)
      expect(email).toMatch(/@[^@]+\.(?:invalid|test)$/i)
    }
    const ids = everyPlanId(plan)
    expect(ids).toHaveLength(100_400)
    expect(new Set(ids).size).toBe(ids.length)
    expect(ids.every((id) => uuidPattern.test(id))).toBe(true)
    expect(new Set(plan.gyms.map(emailFor)).size).toBe(100)
    expect(JSON.stringify(plan)).not.toMatch(/password|bearer|service.?key|access.?token|refresh.?token/i)
  })

  it('reproduces the exact IDs for a marker and isolates separate run markers', () => {
    const first = buildPrelaunchSyntheticPlan(marker)
    const replay = buildPrelaunchSyntheticPlan(marker)
    const next = buildPrelaunchSyntheticPlan(`PHASE8-LOAD-${randomUUID()}`)
    const firstIds = everyPlanId(first)
    const nextIds = new Set(everyPlanId(next))
    expect(everyPlanId(replay)).toEqual(firstIds)
    expect(firstIds.some((id) => nextIds.has(id))).toBe(false)
    expect(first.gyms.map(emailFor)).not.toEqual(next.gyms.map(emailFor))
  })

  it.each(['', 'PHASE8-LOAD-old', randomUUID(), `PHASE8-LOAD-${randomUUID()};DROP TABLE members`])(
    'rejects a marker outside the approved run-marker format',
    (unsafeMarker) => {
      expect(() => buildPrelaunchSyntheticPlan(unsafeMarker)).toThrow()
    },
  )
})

describe('HARD-004 Auth bindings and single transaction staging holdout', () => {
  it('stages only new planned identities and checks exact row counts', () => {
    const plan = buildPrelaunchSyntheticPlan(marker)
    const bindings = bindingsFor(plan)
    const sql = renderPrelaunchStageSql(plan, bindings)
    expect(sql).toMatch(/^\s*begin\b/i)
    expect(sql).toMatch(/\bcommit\s*;?\s*$/i)
    expect(sql).toContain(plan.gyms[0].gymId)
    expect(sql).toContain(membersFor(plan.gyms[99])[499].memberId)
    expect(sql).toContain(bindings[0].userId)
    for (const table of ['organizations', 'organization_settings', 'branches', 'plans', 'staff', 'members', 'memberships']) {
      expect(sql).toMatch(new RegExp(`\\binsert\\s+into\\s+(?:public\\.)?"?${table}"?\\b`, 'i'))
    }
    expect(sql).toMatch(/\bcount\s*\(/i)
    expect(sql).toMatch(/\b50_?000\b/)
    expect(sql).not.toMatch(/\bon\s+conflict\b|\btruncate\b|\bdisable\s+trigger\b|\bupdate\s+(?:public\.)?\w+\b/i)
  })

  it.each([
    ['one Auth user missing', (bindings: Array<{email: string; userId: string}>) => { bindings.pop() }],
    ['foreign Auth email', (bindings: Array<{email: string; userId: string}>) => { bindings[0].email = 'foreign@example.invalid' }],
    ['repeated Auth email', (bindings: Array<{email: string; userId: string}>) => { bindings[1].email = bindings[0].email }],
    ['repeated Auth user ID', (bindings: Array<{email: string; userId: string}>) => { bindings[1].userId = bindings[0].userId }],
    ['malformed Auth user ID', (bindings: Array<{email: string; userId: string}>) => { bindings[0].userId = 'not-a-uuid' }],
    ['extra foreign Auth user', (bindings: Array<{email: string; userId: string}>) => { bindings.push({ email: 'foreign@example.invalid', userId: randomUUID() }) }],
  ])('refuses %s', (_case, corrupt) => {
    const plan = buildPrelaunchSyntheticPlan(marker)
    const bindings = bindingsFor(plan)
    corrupt(bindings)
    expect(() => renderPrelaunchStageSql(plan, bindings)).toThrow()
  })

  it('revalidates the plan instead of trusting caller-declared counts', () => {
    const plan = buildPrelaunchSyntheticPlan(marker)
    const bindings = bindingsFor(plan)
    const changed = structuredClone(plan)
    membersFor(changed.gyms[1])[0].memberId = membersFor(changed.gyms[0])[0].memberId
    expect(() => renderPrelaunchStageSql(changed, bindings)).toThrow()
  })
})

describe('HARD-004 interruption-safe exact cleanup holdout', () => {
  it('guards the marker and deletes planned gym data in one scoped transaction', () => {
    const plan = buildPrelaunchSyntheticPlan(marker)
    const sql = renderPrelaunchCleanupSql(plan)
    expect(sql).toMatch(/^\s*begin\b/i)
    expect(sql).toMatch(/\bcommit\s*;?\s*$/i)
    expect(sql).toContain(marker)
    expect(sql).toContain(plan.gyms[0].gymId)
    expect(sql).toContain(plan.gyms[99].gymId)
    expect(sql).toMatch(/\bdelete\s+from\s+(?:public\.)?"?attendance"?\b/i)
    expect(sql).toMatch(/\bdelete\s+from\s+(?:public\.)?"?organizations"?\b/i)
    expect(sql).toMatch(/\bcount\s*\(/i)
    expect(sql).not.toMatch(/\btruncate\b|\bdelete\s+from\s+auth\.users\b|\bon\s+conflict\b/i)
    for (const statement of sql.split(/\bdelete\s+from\b/i).slice(1)) {
      expect(statement.split(';')[0]).toMatch(/\bwhere\b/i)
    }
  })

  it('keeps attendance before memberships and parent gyms last for partial-run cleanup', () => {
    const sql = renderPrelaunchCleanupSql(buildPrelaunchSyntheticPlan(marker)).toLowerCase()
    const deletedTable = (name: string) => sql.search(new RegExp(`\\bdelete\\s+from\\s+(?:public\\.)?"?${name}"?\\b`))
    expect(deletedTable('attendance')).toBeGreaterThanOrEqual(0)
    expect(deletedTable('memberships')).toBeGreaterThan(deletedTable('attendance'))
    expect(deletedTable('members')).toBeGreaterThan(deletedTable('memberships'))
    expect(deletedTable('organizations')).toBeGreaterThan(deletedTable('members'))
  })
})

describe('HARD-004 linked database size parser holdout', () => {
  it.each([0, 34_000_000, 399_999_999, 400_000_000])('reads one exact safe integer %i', (bytes) => {
    expect(parseLinkedDatabaseSize(JSON.stringify([{ database_bytes: bytes }]))).toBe(bytes)
  })

  it.each([
    'not json',
    '{}',
    '[]',
    '[{},{}]',
    '[{"database_bytes":null}]',
    '[{"database_bytes":"34000000"}]',
    '[{"database_bytes":-1}]',
    '[{"database_bytes":1.5}]',
    '[{"database_bytes":9007199254740992}]',
    '[{"database_bytes":34},{"database_bytes":34}]',
    '{"error":"permission denied"}',
  ])('rejects a missing, ambiguous or untrustworthy CLI reading', (raw) => {
    expect(() => parseLinkedDatabaseSize(raw)).toThrow()
  })
})
