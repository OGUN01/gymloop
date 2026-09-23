import { randomUUID } from 'node:crypto'
import { join } from 'node:path'
import { tmpdir } from 'node:os'
import { describe, expect, it } from 'vitest'
import { runPrelaunchLoadCampaign } from '../../scripts/phase8-prelaunch-load-campaign.mjs'

const linkedRef = 'pecxrpskmfeuyzngvewq'

function config() {
  const root = join(tmpdir(), `gymloop-campaign-${randomUUID()}`)
  return {
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
    cleanupManifestPath: join(root, 'cleanup.json'),
    rawResultPath: join(root, 'raw-k6.json'),
    thresholds: { p95Ms: 1_000 },
    monitorIntervalMs: 5,
  }
}

function snapshot(databaseBytes = 34_000_000) {
  return {
    observedAt: new Date().toISOString(),
    databaseBytes,
    providerQuotaBytes: 500_000_000,
    maxDatabaseBytes: 400_000_000,
  }
}

function measured() {
  return {
    p95Ms: 750,
    completedCheckIns: 50_000,
    crossTenantReadDenied: true,
    crossTenantMutationStatus: 403,
  }
}

type FakeState = {
  calls: string[]
  manifests: string[]
  auth: Map<string, string>
  deleted: Array<{ email: string; userId: string | undefined }>
  fixture: unknown
  plan: unknown
  baseline: unknown
  observed: number
  k6Started: boolean
  signalSeen: AbortSignal | undefined
  k6Aborted: boolean
}

type Hooks = {
  writeManifest?: (value: unknown, state: FakeState) => void | Promise<void>
  observeSize?: (state: FakeState) => ReturnType<typeof snapshot> | Promise<ReturnType<typeof snapshot>>
  createAuthUser?: (email: string, userId: string, state: FakeState) => void | Promise<void>
  runK6?: (request: Record<string, unknown>, state: FakeState) => ReturnType<typeof measured> | Promise<ReturnType<typeof measured>>
  countAttendance?: (state: FakeState) => number | Promise<number>
  cleanupSql?: (state: FakeState) => void | Promise<void>
  deleteAuthUser?: (email: string, userId: string | undefined, state: FakeState) => void | Promise<void>
  verifyPostflight?: (state: FakeState) => Record<string, unknown> | Promise<Record<string, unknown>>
}

function fakeBackend(hooks: Hooks = {}) {
  const state: FakeState = {
    calls: [],
    manifests: [],
    auth: new Map(),
    deleted: [],
    fixture: undefined,
    plan: undefined,
    baseline: undefined,
    observed: 0,
    k6Started: false,
    signalSeen: undefined,
    k6Aborted: false,
  }
  const backend = {
    async writeManifest(value: unknown) {
      state.calls.push('writeManifest')
      await hooks.writeManifest?.(value, state)
      state.manifests.push(JSON.stringify(value))
    },
    async observeSize() {
      state.calls.push('observeSize')
      state.observed += 1
      return hooks.observeSize ? await hooks.observeSize(state) : snapshot()
    },
    async captureBaseline(plan: unknown) {
      state.calls.push('captureBaseline')
      expect(plan).toBeDefined()
      state.plan = plan
      state.baseline = { existing: 'unchanged' }
      return state.baseline
    },
    async createAuthUser(email: string) {
      state.calls.push('createAuthUser')
      for (const previouslyCreatedId of state.auth.values()) {
        expect(state.manifests.some((manifest) => manifest.includes(previouslyCreatedId))).toBe(true)
      }
      const userId = randomUUID()
      state.auth.set(email, userId)
      await hooks.createAuthUser?.(email, userId, state)
      return userId
    },
    async stageSql(sql: string) {
      state.calls.push('stageSql')
      expect(sql).toMatch(/\bbegin\b/i)
    },
    async signIn(email: string) {
      state.calls.push('signIn')
      expect(state.auth.has(email)).toBe(true)
      return `HOLDOUT_PRIVATE_BEARER_${email}`
    },
    async writeFixture(value: unknown) {
      state.calls.push('writeFixture')
      state.fixture = value
    },
    async runK6(request: Record<string, unknown>) {
      state.calls.push('runK6')
      state.k6Started = true
      state.signalSeen = Object.values(request).find((value): value is AbortSignal => value instanceof AbortSignal)
      return hooks.runK6 ? await hooks.runK6(request, state) : measured()
    },
    async countAttendance(_plan: unknown) {
      state.calls.push('countAttendance')
      return hooks.countAttendance ? await hooks.countAttendance(state) : 50_000
    },
    async cleanupSql(sql: string) {
      state.calls.push('cleanupSql')
      expect(sql).toMatch(/\bdelete\s+from\b/i)
      await hooks.cleanupSql?.(state)
    },
    async deleteAuthUser(email: string, userId: string | undefined) {
      state.calls.push('deleteAuthUser')
      state.deleted.push({ email, userId })
      await hooks.deleteAuthUser?.(email, userId, state)
      const actualId = state.auth.get(email)
      if (userId && actualId && userId !== actualId) throw new Error('foreign Auth ID')
      state.auth.delete(email)
    },
    async verifyPostflight(_plan: unknown, baseline: unknown) {
      state.calls.push('verifyPostflight')
      expect(baseline).toBe(state.baseline)
      return hooks.verifyPostflight ? await hooks.verifyPostflight(state) : {
        completed: true,
        preexistingUnchanged: true,
        syntheticRemainderCount: 0,
        authRemainderCount: state.auth.size,
      }
    },
  }
  return { backend, state }
}

function expectBlocked(result: { status: string }) {
  expect(result.status).toBe('blocked')
}

describe('HARD-004 monitored prelaunch campaign holdout', () => {
  it('persists intent before Auth, records returned Auth IDs, and passes only after independent cleanup', async () => {
    const input = config()
    const { backend, state } = fakeBackend()
    const result = await runPrelaunchLoadCampaign(input, backend)
    expect(result.status).toBe('passed')
    expect(state.calls.indexOf('writeManifest')).toBeLessThan(state.calls.indexOf('createAuthUser'))
    expect(state.manifests[0]).toContain(input.marker)
    expect(state.manifests[0]).toContain((state.plan as { gyms: Array<{ gymId: string }> }).gyms[0].gymId)
    expect(state.calls.filter((call) => call === 'createAuthUser')).toHaveLength(100)
    expect(state.calls.filter((call) => call === 'signIn')).toHaveLength(100)
    expect(state.calls).toContain('writeFixture')
    expect(state.calls).toContain('countAttendance')
    expect(state.calls.indexOf('countAttendance')).toBeLessThan(state.calls.indexOf('cleanupSql'))
    expect(state.calls.indexOf('cleanupSql')).toBeLessThan(state.calls.indexOf('verifyPostflight'))
    expect(state.deleted).toHaveLength(100)
    expect(state.deleted.every(({ userId }) => userId && state.manifests.some((manifest) => manifest.includes(userId)))).toBe(true)
    expect(state.auth.size).toBe(0)
    expect(state.observed).toBeGreaterThanOrEqual(2)
    expect(state.signalSeen).toBeInstanceOf(AbortSignal)
    const summary = JSON.stringify(result)
    expect(summary).not.toContain('HOLDOUT_PRIVATE_BEARER_')
    expect(summary).not.toContain('credentials')
    expect(summary).not.toContain('memberIds')
  }, 20_000)

  it('refuses an initial quota ceiling before any Cloud mutation', async () => {
    const { backend, state } = fakeBackend({ observeSize: () => snapshot(400_000_000) })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.calls).not.toContain('createAuthUser')
    expect(state.calls).not.toContain('stageSql')
    expect(state.calls).not.toContain('runK6')
  })

  it('cleans a marker-scoped Auth user after creation succeeds but its ID response is lost', async () => {
    let lostEmail: string | undefined
    const { backend, state } = fakeBackend({
      createAuthUser(email) {
        lostEmail = email
        throw new Error('connection lost after Auth accepted creation')
      },
    })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(lostEmail).toBeDefined()
    expect(state.deleted.some((entry) => entry.email === lostEmail)).toBe(true)
    expect(state.auth.size).toBe(0)
    expect(state.calls).toContain('cleanupSql')
    expect(state.calls).not.toContain('runK6')
  }, 20_000)

  it('cleans an Auth user if manifest persistence fails after the ID returns', async () => {
    const { backend, state } = fakeBackend({
      writeManifest(_value, current) {
        if (current.auth.size > 0) throw new Error('manifest disk full')
      },
    })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.auth.size).toBe(0)
    expect(state.deleted.length).toBeGreaterThan(0)
    expect(state.calls).not.toContain('runK6')
  }, 20_000)

  it('aborts active k6 when the size observer reaches the ceiling', async () => {
    const { backend, state } = fakeBackend({
      observeSize(current) {
        return snapshot(current.k6Started ? 400_000_000 : 34_000_000)
      },
      runK6(_request, current) {
        return new Promise((resolve) => {
          current.signalSeen?.addEventListener('abort', () => {
            current.k6Aborted = true
            resolve(measured())
          }, { once: true })
          setTimeout(() => resolve(measured()), 500)
        })
      },
    })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.signalSeen).toBeInstanceOf(AbortSignal)
    expect(state.k6Aborted).toBe(true)
    expect(state.calls).toContain('cleanupSql')
    expect(state.auth.size).toBe(0)
  }, 20_000)

  it('aborts active k6 when the size observer fails to collect', async () => {
    const { backend, state } = fakeBackend({
      observeSize(current) {
        if (current.k6Started) throw new Error('CLI size query failed')
        return snapshot()
      },
      runK6(_request, current) {
        return new Promise((resolve) => {
          current.signalSeen?.addEventListener('abort', () => {
            current.k6Aborted = true
            resolve(measured())
          }, { once: true })
          setTimeout(() => resolve(measured()), 500)
        })
      },
    })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.k6Aborted).toBe(true)
    expect(state.calls).toContain('cleanupSql')
  }, 20_000)

  it('blocks green k6 when the independent persisted attendance count differs', async () => {
    const { backend, state } = fakeBackend({ countAttendance: () => 49_999 })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.calls).toContain('runK6')
    expect(state.calls).toContain('cleanupSql')
    expect(state.calls).toContain('verifyPostflight')
  }, 20_000)

  it('blocks a green k6 result when SQL cleanup fails and retains recovery intent', async () => {
    const { backend, state } = fakeBackend({ cleanupSql: () => { throw new Error('cleanup refused') } })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.calls).toContain('runK6')
    expect(state.manifests.length).toBeGreaterThan(0)
    expect(state.calls).toContain('deleteAuthUser')
    expect(state.calls).toContain('verifyPostflight')
  }, 20_000)

  it('blocks when a synthetic Auth user cannot be deleted', async () => {
    let failedEmail: string | undefined
    const { backend, state } = fakeBackend({
      deleteAuthUser(email) {
        failedEmail ??= email
        if (email === failedEmail) throw new Error('Auth Admin API unavailable')
      },
    })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.auth.size).toBeGreaterThan(0)
    expect(state.calls).toContain('verifyPostflight')
  }, 20_000)

  it.each([
    ['pre-existing identity changed', { completed: true, preexistingUnchanged: false, syntheticRemainderCount: 0, authRemainderCount: 0 }],
    ['synthetic DB row remains', { completed: true, preexistingUnchanged: true, syntheticRemainderCount: 1, authRemainderCount: 0 }],
    ['synthetic Auth row remains', { completed: true, preexistingUnchanged: true, syntheticRemainderCount: 0, authRemainderCount: 1 }],
  ])('blocks after postflight reports %s', async (_label, postflight) => {
    const { backend, state } = fakeBackend({ verifyPostflight: () => postflight })
    const result = await runPrelaunchLoadCampaign(config(), backend)
    expectBlocked(result)
    expect(state.calls).toContain('verifyPostflight')
  }, 20_000)
})
