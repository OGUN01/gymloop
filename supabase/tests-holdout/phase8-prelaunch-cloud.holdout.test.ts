import { randomUUID } from 'node:crypto'
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { afterEach, describe, expect, it } from 'vitest'
import { buildPrelaunchSyntheticPlan } from '../../scripts/phase8-prelaunch-load-fixture.mjs'
import {
  parsePrelaunchK6Raw,
  createPrelaunchCloudBackend,
} from '../../scripts/phase8-prelaunch-load-cloud.mjs'

const linkedRef = 'pecxrpskmfeuyzngvewq'
const temporaryRoots: string[] = []

afterEach(() => {
  for (const root of temporaryRoots.splice(0)) rmSync(root, { recursive: true, force: true })
})

function rawPoints(): Array<{ metric: string; type: string; data: { value?: number; tags?: Record<string, string>; type?: string } }> {
  return [
    { metric: 'http_reqs', type: 'Metric', data: { type: 'counter' } },
    { metric: 'http_reqs', type: 'Point', data: { value: 1, tags: { scenario: 'morning_check_in_spike', status: '200', extra: 'allowed' } } },
    { metric: 'http_reqs', type: 'Point', data: { value: 1, tags: { scenario: 'morning_check_in_spike', status: '201' } } },
    { metric: 'http_reqs', type: 'Point', data: { value: 1, tags: { scenario: 'morning_check_in_spike', status: '500' } } },
    { metric: 'http_reqs', type: 'Point', data: { value: 1, tags: { scenario: 'other_scenario', status: '200' } } },
    { metric: 'http_req_duration', type: 'Point', data: { value: 42.5, tags: { scenario: 'morning_check_in_spike' } } },
    { metric: 'http_req_duration', type: 'Point', data: { value: 42.5, tags: { scenario: 'morning_check_in_spike' } } },
    { metric: 'http_req_duration', type: 'Point', data: { value: 900, tags: { scenario: 'other_scenario' } } },
    { metric: 'checks', type: 'Point', data: { value: 1, tags: { scenario: 'cross_tenant_read_denial', check: 'cross-tenant member read is denied' } } },
    { metric: 'http_reqs', type: 'Point', data: { value: 1, tags: { scenario: 'cross_tenant_mutation_denial', status: '403' } } },
  ]
}

function asRaw(points: unknown[]) {
  return points.map((point) => JSON.stringify(point)).join('\n')
}

function containsString(value: unknown, expected: string): boolean {
  if (typeof value === 'string') return value === expected
  if (Array.isArray(value)) return value.some((item) => containsString(item, expected))
  if (value && typeof value === 'object') return Object.values(value).some((item) => containsString(item, expected))
  return false
}

function configuration() {
  const root = mkdtempSync(join(tmpdir(), 'gymloop-cloud-holdout-'))
  temporaryRoots.push(root)
  const campaignConfig = {
    target: {
      mode: 'prelaunch-shared',
      projectRef: linkedRef,
      observedApiProjectRef: linkedRef,
      observedSupabaseProjectRef: linkedRef,
      apiUrl: 'https://api.gymloop.example',
      supabaseUrl: `https://${linkedRef}.supabase.co`,
      confirmation: 'PRELAUNCH_SHARED_LOAD_APPROVED',
      credentials: { kind: 'prelaunch-shared', present: true, projectRef: linkedRef },
      noLiveCustomers: true,
    },
    marker: `PHASE8-LOAD-${randomUUID()}`,
    fixturePath: join(root, 'fixture.json'),
    baselineManifestPath: join(root, 'baseline.json'),
    cleanupManifestPath: join(root, 'recovery.jsonl'),
    rawResultPath: join(root, 'raw-k6.json'),
    thresholds: { p95Ms: 1_000 },
    monitorIntervalMs: 10,
  }
  return { campaignConfig, anonKey: 'HOLDOUT_PUBLIC_ANON_KEY' }
}

function plannedEmail(plan: { gyms: Array<Record<string, unknown>> }) {
  const email = Object.values(plan.gyms[0]).find((value): value is string => typeof value === 'string' && value.includes('@'))
  expect(email).toBeDefined()
  return email!
}

function fakePorts() {
  const state = {
    queries: [] as string[],
    created: new Map<string, { id: string; password: string }>(),
    deleted: [] as string[],
    k6Requests: [] as Array<{ signal: AbortSignal; env: Record<string, string>; rawResultPath: string }>,
    listed: 0,
  }
  const ports = {
    async queryLinked(sql: string) {
      state.queries.push(sql)
      if (/pg_database_size/i.test(sql)) return JSON.stringify([{ database_bytes: 34_000_000 }])
      return JSON.stringify([{ id: '00000000-0000-4000-8000-000000000001' }])
    },
    async createAuthUser(email: string, password: string) {
      const id = randomUUID()
      state.created.set(email, { id, password })
      return id
    },
    async signIn(email: string, password: string) {
      expect(password).toBe(state.created.get(email)?.password)
      return `HOLDOUT_PRIVATE_BEARER_${email}`
    },
    async listAuthUsers() {
      state.listed += 1
      return [...state.created].map(([email, { id }]) => ({ id, email }))
    },
    async deleteAuthUser(id: string) {
      state.deleted.push(id)
      for (const [email, user] of state.created) {
        if (user.id === id) state.created.delete(email)
      }
    },
    async executeK6(request: { signal: AbortSignal; env: Record<string, string>; rawResultPath: string }) {
      state.k6Requests.push(request)
      return { exitCode: 0, raw: asRaw(rawPoints()) }
    },
  }
  return { ports, state }
}

describe('HARD-004 k6 raw result parser holdout', () => {
  it('counts only successful spike requests and uses measured spike durations', () => {
    const result = parsePrelaunchK6Raw(asRaw(rawPoints()))
    expect(result.completedCheckIns).toBe(2)
    expect(result.p95Ms).toBe(42.5)
    expect(result.crossTenantReadDenied).toBe(true)
    expect(result.crossTenantMutationStatus).toBe(403)
    expect(JSON.stringify(result)).not.toContain('extra')
  })

  it.each([
    ['missing read denial', (points: ReturnType<typeof rawPoints>) => points.filter((point) => point.data.tags?.scenario !== 'cross_tenant_read_denial')],
    ['failed read denial', (points: ReturnType<typeof rawPoints>) => points.map((point) => point.data.tags?.scenario === 'cross_tenant_read_denial' ? { ...point, data: { ...point.data, value: 0 } } : point)],
    ['duplicate read denial', (points: ReturnType<typeof rawPoints>) => [...points, points[8]]],
    ['missing mutation probe', (points: ReturnType<typeof rawPoints>) => points.filter((point) => point.data.tags?.scenario !== 'cross_tenant_mutation_denial')],
    ['successful foreign mutation', (points: ReturnType<typeof rawPoints>) => points.map((point) => point.data.tags?.scenario === 'cross_tenant_mutation_denial' ? { ...point, data: { ...point.data, tags: { ...point.data.tags, status: '204' } } } : point)],
    ['duplicate mutation probe', (points: ReturnType<typeof rawPoints>) => [...points, points[9]]],
    ['no measured spike durations', (points: ReturnType<typeof rawPoints>) => points.filter((point) => !(point.metric === 'http_req_duration' && point.data.tags?.scenario === 'morning_check_in_spike'))],
  ])('refuses %s', (_case, change) => {
    expect(() => parsePrelaunchK6Raw(asRaw(change(rawPoints())))).toThrow()
  })

  it.each(['{broken', '', '{"metric":"checks","type":"Point","data":{}}'])('refuses malformed or incomplete raw lines', (raw) => {
    expect(() => parsePrelaunchK6Raw(raw)).toThrow()
  })
})

describe('HARD-004 injected Cloud adapter holdout', () => {
  it('uses the linked size query rather than a caller-declared number', async () => {
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(configuration(), ports)
    const size = await backend.observeSize()
    expect(size.databaseBytes).toBe(34_000_000)
    expect(size.providerQuotaBytes).toBe(500_000_000)
    expect(size.maxDatabaseBytes).toBe(400_000_000)
    expect(state.queries.some((sql) => /pg_database_size/i.test(sql))).toBe(true)
    expect(state.queries.every((sql) => !/\b(seed|reset|migrate|truncate)\b/i.test(sql))).toBe(true)
  })

  it('keeps the first recovery record, appends intent, and rejects journal reuse', async () => {
    const input = configuration()
    const plan = buildPrelaunchSyntheticPlan(input.campaignConfig.marker)
    const { ports } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    await backend.writeManifest({ plan, target: input.campaignConfig.target, status: 'planned' })
    const journalPath = input.campaignConfig.cleanupManifestPath
    expect(existsSync(journalPath)).toBe(true)
    const first = readFileSync(journalPath, 'utf8')
    const firstRecord = JSON.parse(first.split(/\r?\n/, 1)[0])
    expect(first).toContain(input.campaignConfig.marker)
    expect(first).toContain(plan.gyms[0].gymId)
    expect(first).toContain(linkedRef)
    expect(containsString(firstRecord, input.campaignConfig.fixturePath)).toBe(true)
    await backend.writeManifest({ status: 'auth-intent', email: plannedEmail(plan) })
    const after = readFileSync(journalPath, 'utf8')
    expect(after.startsWith(first)).toBe(true)
    expect(after.length).toBeGreaterThan(first.length)
    expect(after).not.toContain(input.anonKey)
    if (process.platform !== 'win32') expect(statSync(journalPath).mode & 0o777).toBe(0o600)
    let second
    try {
      second = createPrelaunchCloudBackend(input, ports)
    } catch (error) {
      expect(error).toBeInstanceOf(Error)
    }
    if (second) await expect(second.writeManifest({ plan, status: 'planned' })).rejects.toThrow()
  }, 20_000)

  it('keeps Auth passwords in memory and deletes only the exact marker user', async () => {
    const input = configuration()
    const plan = buildPrelaunchSyntheticPlan(input.campaignConfig.marker)
    const email = plannedEmail(plan)
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    await backend.writeManifest({ plan, target: input.campaignConfig.target, status: 'planned' })
    const id = await backend.createAuthUser(email)
    const bearer = await backend.signIn(email)
    expect(id).toBe(state.created.get(email)?.id)
    expect(bearer).toContain('HOLDOUT_PRIVATE_BEARER_')
    const password = state.created.get(email)?.password
    expect(password).toBeTruthy()
    await backend.writeManifest({ kind: 'auth-created', email, userId: id })
    const journal = readFileSync(input.campaignConfig.cleanupManifestPath, 'utf8')
    expect(journal).not.toContain(password!)
    expect(journal).not.toContain(bearer)
    await backend.deleteAuthUser(email, id)
    expect(state.deleted).toEqual([id])
    expect(state.created.size).toBe(0)
    expect(state.listed).toBeGreaterThan(0)
  }, 20_000)

  it('persists a read-only baseline across all linked identity tables', async () => {
    const input = configuration()
    const plan = buildPrelaunchSyntheticPlan(input.campaignConfig.marker)
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    await backend.writeManifest({ plan, target: input.campaignConfig.target, status: 'planned' })
    const baseline = await backend.captureBaseline(plan)
    expect(baseline).toBeDefined()
    expect(existsSync(input.campaignConfig.baselineManifestPath)).toBe(true)
    expect(state.queries.length).toBeGreaterThan(0)
    const queries = state.queries.join('\n')
    for (const table of ['organizations', 'organization_settings', 'branches', 'plans', 'staff', 'members', 'memberships', 'attendance']) {
      expect(queries).toContain(table)
    }
    expect(state.listed > 0 || /auth[.\s"]+users/i.test(queries)).toBe(true)
    expect(state.queries.every((sql) => !/\b(insert|update|delete|truncate|reset|migrate)\b/i.test(sql))).toBe(true)
  }, 20_000)

  it('recovers a created marker user by exact email when the ID was lost', async () => {
    const input = configuration()
    const plan = buildPrelaunchSyntheticPlan(input.campaignConfig.marker)
    const email = plannedEmail(plan)
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    await backend.writeManifest({ plan, target: input.campaignConfig.target, status: 'planned' })
    const id = await ports.createAuthUser(email, 'external-created-password')
    await backend.deleteAuthUser(email, undefined)
    expect(state.deleted).toEqual([id])
    expect(state.created.size).toBe(0)
  }, 20_000)

  it('refuses an expected Auth ID mismatch and preserves that user', async () => {
    const input = configuration()
    const plan = buildPrelaunchSyntheticPlan(input.campaignConfig.marker)
    const email = plannedEmail(plan)
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    await backend.writeManifest({ plan, target: input.campaignConfig.target, status: 'planned' })
    await ports.createAuthUser(email, 'external-created-password')
    await expect(backend.deleteAuthUser(email, randomUUID())).rejects.toThrow()
    expect(state.deleted).toHaveLength(0)
    expect(state.created.has(email)).toBe(true)
  }, 20_000)

  it('passes only bounded non-secret env and the AbortSignal into the k6 port', async () => {
    const input = configuration()
    const { ports, state } = fakePorts()
    const backend = createPrelaunchCloudBackend(input, ports)
    const signal = new AbortController().signal
    const result = await backend.runK6({ signal })
    expect(result.completedCheckIns).toBe(2)
    expect(state.k6Requests).toHaveLength(1)
    const request = state.k6Requests[0]
    expect(request.signal).toBe(signal)
    expect(request.rawResultPath).toBe(input.campaignConfig.rawResultPath)
    expect(request.env.PHASE8_LOAD_FIXTURE_PATH).toBe(input.campaignConfig.fixturePath)
    const env = JSON.stringify(request.env)
    expect(env).not.toContain('HOLDOUT_PRIVATE_BEARER_')
    expect(env).not.toMatch(/password|memberIds|ownedMemberIds/i)
  }, 20_000)

  it('blocks a nonzero k6 exit even when the raw points appear successful', async () => {
    const input = configuration()
    const { ports } = fakePorts()
    ports.executeK6 = async () => ({ exitCode: 1, raw: asRaw(rawPoints()) })
    const backend = createPrelaunchCloudBackend(input, ports)
    await expect(backend.runK6({ signal: new AbortController().signal })).rejects.toThrow()
  }, 20_000)

  it('refuses a pre-existing journal path without overwriting its recovery bytes', async () => {
    const input = configuration()
    const prior = 'PRIOR-RECOVERY-RECORD\n'
    writeFileSync(input.campaignConfig.cleanupManifestPath, prior)
    const { ports } = fakePorts()
    let backend
    try {
      backend = createPrelaunchCloudBackend(input, ports)
    } catch (error) {
      expect(error).toBeInstanceOf(Error)
    }
    if (backend) await expect(backend.writeManifest({ plan: buildPrelaunchSyntheticPlan(input.campaignConfig.marker) })).rejects.toThrow()
    expect(readFileSync(input.campaignConfig.cleanupManifestPath, 'utf8')).toBe(prior)
  }, 20_000)
})
