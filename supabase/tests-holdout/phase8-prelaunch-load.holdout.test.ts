import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { tmpdir } from 'node:os'
import { describe, expect, it } from 'vitest'
import {
  assertSafePrelaunchTarget,
  assertSafePrelaunchQuota,
  assertSafePrelaunchFixture,
  summarizePrelaunchResult,
} from '../../scripts/phase8-prelaunch-load-safety.mjs'
import { assertSafeLoadTarget } from '../../scripts/phase8-load-safety.mjs'

const linkedRef = 'pecxrpskmfeuyzngvewq'
const secretTokenPrefix = 'HOLDOUT_PRIVATE_BEARER_'
const localRoot = join(tmpdir(), 'gymloop-prelaunch-holdout')

function target() {
  return {
    mode: 'prelaunch-shared',
    projectRef: linkedRef,
    observedApiProjectRef: linkedRef,
    observedSupabaseProjectRef: linkedRef,
    apiUrl: 'https://api.gymloop.example/',
    supabaseUrl: `https://${linkedRef}.supabase.co/`,
    confirmation: 'PRELAUNCH_SHARED_LOAD_APPROVED',
    credentials: {
      kind: 'prelaunch-shared',
      present: true,
      projectRef: linkedRef,
    },
    noLiveCustomers: true,
  }
}

function quota() {
  return {
    observedAt: new Date().toISOString(),
    databaseBytes: 34_000_000,
    providerQuotaBytes: 500_000_000,
    maxDatabaseBytes: 400_000_000,
  }
}

function syntheticId(value: number) {
  return `00000000-0000-4000-8000-${value.toString(16).padStart(12, '0')}`
}

function fixture() {
  return {
    marker: `PHASE8-LOAD-${randomUUID()}`,
    fixturePath: join(localRoot, 'fixture.json'),
    baselineManifestPath: join(localRoot, 'baseline.json'),
    cleanupManifestPath: join(localRoot, 'cleanup.json'),
    gymFixtures: Array.from({ length: 100 }, (_, gymIndex) => {
      const memberIds = Array.from(
        { length: 500 },
        (_, memberIndex) => syntheticId(1_000 + gymIndex * 500 + memberIndex),
      )
      return {
        gymId: syntheticId(gymIndex + 1),
        token: `${secretTokenPrefix}${gymIndex}`,
        memberIds,
        ownedMemberIds: [...memberIds].reverse(),
      }
    }),
  }
}

function completedResult() {
  return {
    status: 'passed',
    target: target(),
    quota: quota(),
    fixture: fixture(),
    rawResultPath: join(localRoot, 'raw-k6.json'),
    thresholds: { p95Ms: 1_000 },
    measured: {
      p95Ms: 750,
      completedCheckIns: 50_000,
      crossTenantReadDenied: true,
      crossTenantMutationStatus: 403,
    },
    monitor: {
      completed: true,
      maxObservedDatabaseBytes: 350_000_000,
      maxGapSeconds: 60,
    },
    cleanup: {
      completed: true,
      preexistingUnchanged: true,
      syntheticRemainderCount: 0,
      authRemainderCount: 0,
    },
  }
}

function expectNonPassing(input: ReturnType<typeof completedResult>) {
  let result
  try {
    result = summarizePrelaunchResult(input)
  } catch (error) {
    expect(error).toBeInstanceOf(Error)
    return
  }
  expect(result.status).not.toBe('passed')
}

describe('HARD-004 prelaunch shared target and quota holdout', () => {
  it('accepts only the linked Cloud identity and returns no credential object', () => {
    const result = assertSafePrelaunchTarget(target())
    expect(result).toEqual({
      mode: 'prelaunch-shared',
      projectRef: linkedRef,
      apiUrl: 'https://api.gymloop.example',
      supabaseUrl: `https://${linkedRef}.supabase.co`,
    })
    expect(JSON.stringify(result)).not.toContain('credentials')
  })

  it('keeps the existing isolated-project route closed to the linked project', () => {
    const shared = target()
    expect(() => assertSafeLoadTarget({
      projectRef: shared.projectRef,
      observedApiProjectRef: shared.observedApiProjectRef,
      observedSupabaseProjectRef: shared.observedSupabaseProjectRef,
      apiUrl: shared.apiUrl,
      supabaseUrl: shared.supabaseUrl,
      confirmation: 'NON_PRODUCTION_LOAD_APPROVED',
      credentials: { kind: 'non-production', present: true, projectRef: linkedRef },
    })).toThrow()
  })

  it.each([
    ['missing mode', { mode: undefined }],
    ['isolated mode', { mode: 'non-production' }],
    ['wrong API observation', { observedApiProjectRef: 'other-project' }],
    ['wrong Supabase observation', { observedSupabaseProjectRef: 'other-project' }],
    ['wrong configured project', { projectRef: 'other-project' }],
    ['wrong confirmation', { confirmation: 'NON_PRODUCTION_LOAD_APPROVED' }],
    ['truthy no-live assertion', { noLiveCustomers: 'true' }],
    ['no no-live assertion', { noLiveCustomers: false }],
    ['HTTP API', { apiUrl: 'http://api.gymloop.example' }],
    ['API user info', { apiUrl: 'https://user:password@api.gymloop.example' }],
    ['API path', { apiUrl: 'https://api.gymloop.example/v1' }],
    ['API query', { apiUrl: 'https://api.gymloop.example/?member=1' }],
    ['API fragment', { apiUrl: 'https://api.gymloop.example/#member' }],
    ['alternate Supabase host', { supabaseUrl: 'https://example.supabase.co' }],
  ])('refuses %s before a shared-project write', (_label, change) => {
    expect(() => assertSafePrelaunchTarget({ ...target(), ...change })).toThrow()
  })

  it.each([
    ['missing credentials', undefined],
    ['wrong credential kind', { kind: 'non-production', present: true, projectRef: linkedRef }],
    ['truthy credential flag', { kind: 'prelaunch-shared', present: 'true', projectRef: linkedRef }],
    ['absent credential', { kind: 'prelaunch-shared', present: false, projectRef: linkedRef }],
    ['foreign credential project', { kind: 'prelaunch-shared', present: true, projectRef: 'other-project' }],
  ])('refuses %s', (_label, credentials) => {
    expect(() => assertSafePrelaunchTarget({ ...target(), credentials })).toThrow()
  })

  it('accepts a current observation below the abort ceiling', () => {
    const snapshot = { ...quota(), databaseBytes: 399_999_999 }
    expect(assertSafePrelaunchQuota(snapshot)).toEqual(snapshot)
  })

  it.each([
    ['at abort ceiling', { databaseBytes: 400_000_000 }],
    ['past abort ceiling', { databaseBytes: 400_000_001 }],
    ['missing collection', { databaseBytes: undefined }],
    ['negative size', { databaseBytes: -1 }],
    ['fractional size', { databaseBytes: 34.5 }],
    ['wrong provider quota', { providerQuotaBytes: 512_000_000 }],
    ['relaxed ceiling', { maxDatabaseBytes: 499_000_000 }],
    ['stale observation', { observedAt: new Date(Date.now() - 16 * 60_000).toISOString() }],
    ['future observation', { observedAt: new Date(Date.now() + 60_000).toISOString() }],
    ['unclear observation time', { observedAt: '2026-09-23' }],
  ])('refuses %s', (_label, change) => {
    expect(() => assertSafePrelaunchQuota({ ...quota(), ...change })).toThrow()
  })
})

describe('HARD-004 exact synthetic fixture holdout', () => {
  it('accepts 100 separate sessions and 50,000 uniquely owned members without echoing secrets', () => {
    const result = assertSafePrelaunchFixture(fixture())
    const serialized = JSON.stringify(result)
    expect(result.marker).toMatch(/^PHASE8-LOAD-[0-9a-f-]{36}$/i)
    expect(result.fixturePath).toBe(join(localRoot, 'fixture.json'))
    expect(serialized).not.toContain(secretTokenPrefix)
    expect(serialized).not.toContain(syntheticId(1_000))
    expect(serialized).not.toContain('gymFixtures')
    expect(serialized).not.toContain('memberIds')
  })

  it.each([
    ['missing marker', (value: ReturnType<typeof fixture>) => { value.marker = '' }],
    ['reused marker shape', (value: ReturnType<typeof fixture>) => { value.marker = 'PHASE8-LOAD-old' }],
    ['missing cleanup manifest', (value: ReturnType<typeof fixture>) => { value.cleanupManifestPath = '' }],
    ['same fixture and cleanup path', (value: ReturnType<typeof fixture>) => { value.cleanupManifestPath = value.fixturePath }],
    ['same baseline and cleanup path', (value: ReturnType<typeof fixture>) => { value.cleanupManifestPath = value.baselineManifestPath }],
    ['only 99 gyms', (value: ReturnType<typeof fixture>) => { value.gymFixtures.pop() }],
    ['duplicate gym identity', (value: ReturnType<typeof fixture>) => { value.gymFixtures[1].gymId = value.gymFixtures[0].gymId }],
    ['duplicate bearer token', (value: ReturnType<typeof fixture>) => { value.gymFixtures[1].token = value.gymFixtures[0].token }],
    ['only 499 members', (value: ReturnType<typeof fixture>) => { value.gymFixtures[0].memberIds.pop() }],
    ['duplicate member in one gym', (value: ReturnType<typeof fixture>) => { value.gymFixtures[0].memberIds[1] = value.gymFixtures[0].memberIds[0] }],
    ['duplicate member across gyms', (value: ReturnType<typeof fixture>) => { value.gymFixtures[1].memberIds[0] = value.gymFixtures[0].memberIds[0] }],
    ['cross-owned member', (value: ReturnType<typeof fixture>) => { value.gymFixtures[0].ownedMemberIds[0] = value.gymFixtures[1].memberIds[0] }],
  ])('refuses %s', (_label, change) => {
    const value = fixture()
    change(value)
    expect(() => assertSafePrelaunchFixture(value)).toThrow()
  })
})

describe('HARD-004 completed result holdout', () => {
  it('requires a complete measured result and leaves fixture secrets out of the summary', () => {
    const input = completedResult()
    const result = summarizePrelaunchResult(input)
    expect(result.status).toBe('passed')
    expect(result.rawResultPath).toBe(input.rawResultPath)
    expect(JSON.stringify(result)).not.toContain(secretTokenPrefix)
    expect(JSON.stringify(result)).not.toContain(syntheticId(1_000))
    expect(JSON.stringify(result)).not.toContain('credentials')
  })

  it.each([
    ['unobserved quota', (value: ReturnType<typeof completedResult>) => { value.quota.databaseBytes = 400_000_000 }],
    ['missing fixture manifest', (value: ReturnType<typeof completedResult>) => { value.fixture.cleanupManifestPath = '' }],
    ['missing p95 budget', (value: ReturnType<typeof completedResult>) => { value.thresholds.p95Ms = 0 }],
    ['missing raw artifact path', (value: ReturnType<typeof completedResult>) => { value.rawResultPath = '' }],
    ['p95 over budget', (value: ReturnType<typeof completedResult>) => { value.measured.p95Ms = 1_001 }],
    ['short attendance count', (value: ReturnType<typeof completedResult>) => { value.measured.completedCheckIns = 49_999 }],
    ['extra attendance count', (value: ReturnType<typeof completedResult>) => { value.measured.completedCheckIns = 50_001 }],
    ['read probe not denied', (value: ReturnType<typeof completedResult>) => { value.measured.crossTenantReadDenied = false }],
    ['successful foreign mutation', (value: ReturnType<typeof completedResult>) => { value.measured.crossTenantMutationStatus = 204 }],
    ['observer stopped', (value: ReturnType<typeof completedResult>) => { value.monitor.completed = false }],
    ['observer saw abort ceiling', (value: ReturnType<typeof completedResult>) => { value.monitor.maxObservedDatabaseBytes = 400_000_000 }],
    ['observer gap exceeded one minute', (value: ReturnType<typeof completedResult>) => { value.monitor.maxGapSeconds = 61 }],
    ['cleanup incomplete', (value: ReturnType<typeof completedResult>) => { value.cleanup.completed = false }],
    ['preexisting identity changed', (value: ReturnType<typeof completedResult>) => { value.cleanup.preexistingUnchanged = false }],
    ['synthetic row remains', (value: ReturnType<typeof completedResult>) => { value.cleanup.syntheticRemainderCount = 1 }],
    ['synthetic Auth user remains', (value: ReturnType<typeof completedResult>) => { value.cleanup.authRemainderCount = 1 }],
  ])('does not pass with %s', (_label, change) => {
    const value = completedResult()
    change(value)
    expectNonPassing(value)
  })

  it.each([200, 201, 250, 299])('treats HTTP %i from a foreign mutation as a failure', (status) => {
    const value = completedResult()
    value.measured.crossTenantMutationStatus = status
    expectNonPassing(value)
  })

  it('does not let a caller-declared passed status bypass absent evidence', () => {
    const value = completedResult()
    expectNonPassing({
      ...value,
      target: undefined,
      quota: undefined,
      fixture: undefined,
      measured: undefined,
      monitor: undefined,
      cleanup: undefined,
    } as unknown as ReturnType<typeof completedResult>)
  })
})

describe('HARD-004 k6 fixture transport holdout', () => {
  it('loads the private fixture from a local file rather than a giant environment value', () => {
    const source = readFileSync(resolve('tests/load/phase8-morning-checkin.js'), 'utf8')
    expect(source).toMatch(/\bopen\s*\(/)
    expect(source).not.toMatch(/PHASE8_LOAD_TENANTS_JSON/)
  })
})
