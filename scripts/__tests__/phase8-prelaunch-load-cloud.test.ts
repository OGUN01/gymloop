import { randomUUID } from 'node:crypto';
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve, sep } from 'node:path';
import { afterEach, describe, expect, it } from 'vitest';

import { buildPrelaunchSyntheticPlan } from '../phase8-prelaunch-load-fixture.mjs';
import {
  createPrelaunchCloudBackend,
  parsePrelaunchK6Raw,
} from '../phase8-prelaunch-load-cloud.mjs';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const MARKER = 'PHASE8-LOAD-11111111-2222-4333-8444-555555555555';
const AUTH_ID = '11111111-2222-4333-8444-666666666666';
const TARGET = {
  mode: 'prelaunch-shared',
  projectRef: PROJECT_REF,
  observedApiProjectRef: PROJECT_REF,
  observedSupabaseProjectRef: PROJECT_REF,
  apiUrl: 'https://gymloop.example.test',
  supabaseUrl: `https://${PROJECT_REF}.supabase.co`,
  confirmation: 'PRELAUNCH_SHARED_LOAD_APPROVED',
  credentials: { kind: 'prelaunch-shared', present: true, projectRef: PROJECT_REF },
  noLiveCustomers: true,
};
const directories: string[] = [];
let cachedPlan: ReturnType<typeof buildPrelaunchSyntheticPlan> | undefined;
const plan = () => cachedPlan ??= buildPrelaunchSyntheticPlan(MARKER);
const plannedEmail = () => {
  const gym = plan().gyms[0] as Record<string, unknown>;
  const emails = Object.entries(gym).filter(([key, value]) => /email/i.test(key) && typeof value === 'string');
  if (emails.length !== 1) throw new Error('The planned gym must have one synthetic Auth email');
  return emails[0][1] as string;
};
const AUTH_EMAIL = plannedEmail();
const point = (metric: string, scenario: string, value: number, tags: Record<string, string> = {}) =>
  JSON.stringify({ metric, type: 'Point', data: { value, tags: { scenario, ...tags } } });
const MORNING_REQUEST = point('http_reqs', 'morning_check_in_spike', 1, { status: '200' });
const MORNING_DURATION = point('http_req_duration', 'morning_check_in_spike', 42.5);
const READ_DENIAL = point('checks', 'cross_tenant_read_denial', 1, { check: 'cross-tenant member read is denied' });
const MUTATION_DENIAL = point('http_reqs', 'cross_tenant_mutation_denial', 1, { status: '403' });
const RAW = [
  JSON.stringify({ metric: 'http_reqs', type: 'Metric', data: { type: 'counter' } }),
  MORNING_REQUEST,
  MORNING_DURATION,
  READ_DENIAL,
  MUTATION_DENIAL,
].join('\n');

const privateConfig = () => {
  const directory = mkdtempSync(join(tmpdir(), 'gymloop-cloud-adapter-'));
  directories.push(directory);
  const campaignConfig = {
    target: TARGET,
    marker: MARKER,
    fixturePath: join(directory, 'fixture.json'),
    baselineManifestPath: join(directory, 'baseline.json'),
    cleanupManifestPath: join(directory, 'recovery.jsonl'),
    rawResultPath: join(directory, 'raw.jsonl'),
    thresholds: { p95Ms: 750 },
    monitorIntervalMs: 30_000,
  };
  return { directory, campaignConfig, anonKey: 'public-anon-key-for-test' };
};
const fakePorts = () => {
  const calls: Array<{ name: string; args: unknown[] }> = [];
  let createdPassword: string | undefined;
  const record = (name: string, ...args: unknown[]) => calls.push({ name, args });
  const ports = {
    async queryLinked(sql: string) {
      record('queryLinked', sql);
      if (/pg_database_size|database_bytes/i.test(sql)) {
        return JSON.stringify({ boundary: 'linked', rows: [{ database_bytes: 34_000_000 }], warning: null });
      }
      return JSON.stringify({ boundary: 'linked', rows: [{ ids: [], count: 0 }], warning: null });
    },
    async createAuthUser(email: string, password: string) {
      record('createAuthUser', email, password);
      createdPassword = password;
      return AUTH_ID;
    },
    async signIn(email: string, password: string) {
      record('signIn', email, password);
      return 'private-bearer-token';
    },
    async listAuthUsers() {
      record('listAuthUsers');
      return [{ id: AUTH_ID, email: AUTH_EMAIL }];
    },
    async deleteAuthUser(id: string) { record('deleteAuthUser', id); },
    async executeK6(request: { signal: AbortSignal; env: Record<string, string>; rawResultPath: string }) {
      record('executeK6', request);
      return { exitCode: 0, raw: RAW };
    },
  };
  return { ports, calls, password: () => createdPassword };
};

afterEach(() => {
  const temporaryRoot = `${resolve(tmpdir())}${sep}`;
  for (const directory of directories.splice(0)) {
    if (!resolve(directory).startsWith(temporaryRoot)) throw new Error('Refusing cleanup outside the temporary directory');
    rmSync(directory, { recursive: true, force: true });
  }
});

describe('HARD-004 raw k6 result extraction', () => {
  it('counts only successful morning requests and returns measured p95 plus both isolation proofs', () => {
    const raw = [
      RAW,
      point('http_reqs', 'morning_check_in_spike', 1, { status: '201' }),
      point('http_req_duration', 'morning_check_in_spike', 42.5),
      point('http_reqs', 'morning_check_in_spike', 1, { status: '500' }),
      point('http_reqs', 'unrelated_scenario', 1, { status: '200' }),
    ].join('\n');
    expect(parsePrelaunchK6Raw(raw)).toEqual({
      p95Ms: 42.5,
      completedCheckIns: 2,
      crossTenantReadDenied: true,
      crossTenantMutationStatus: 403,
    });
  });

  it('rejects missing, failed, duplicate, ambiguous and malformed isolation probes', () => {
    for (const raw of [
      [MORNING_REQUEST, MORNING_DURATION, MUTATION_DENIAL].join('\n'),
      [MORNING_REQUEST, MORNING_DURATION, READ_DENIAL].join('\n'),
      [MORNING_REQUEST, MORNING_DURATION, point('checks', 'cross_tenant_read_denial', 0, { check: 'cross-tenant member read is denied' }), MUTATION_DENIAL].join('\n'),
      [RAW, READ_DENIAL].join('\n'),
      [RAW, MUTATION_DENIAL].join('\n'),
      [MORNING_REQUEST, MORNING_DURATION, READ_DENIAL, point('http_reqs', 'cross_tenant_mutation_denial', 1, { status: '204' })].join('\n'),
      [MORNING_REQUEST, MORNING_DURATION, READ_DENIAL, point('http_reqs', 'cross_tenant_mutation_denial', 1, { status: '299' })].join('\n'),
      [MORNING_REQUEST, READ_DENIAL, MUTATION_DENIAL].join('\n'),
      `${RAW}\n{broken-json`,
      '',
    ]) {
      expect(() => parsePrelaunchK6Raw(raw)).toThrow();
    }
  });
});

describe('HARD-004 same-cloud backend with injected ports', () => {
  it('requires the two-field configuration and injected external ports', () => {
    const config = privateConfig();
    const fake = fakePorts();
    expect(() => createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: '' }, fake.ports)).toThrow();
    expect(() => createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey, serviceRoleKey: 'private' }, fake.ports)).toThrow();
    expect(() => createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, {})).toThrow();
    expect(fake.calls).toHaveLength(0);
  });

  it('records the full plan in a private append-only recovery journal and rejects reuse', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    const syntheticPlan = plan();
    await backend.writeManifest({ plan: syntheticPlan, target: TARGET, artifactPaths: config.campaignConfig, phase: 'planned' });
    const first = readFileSync(config.campaignConfig.cleanupManifestPath, 'utf8');
    expect(first.includes(MARKER)).toBe(true);
    expect(first.includes(PROJECT_REF)).toBe(true);
    expect(first.includes(syntheticPlan.gyms[0].gymId)).toBe(true);
    expect(first.includes(config.campaignConfig.fixturePath)).toBe(true);
    expect(first.includes(config.campaignConfig.baselineManifestPath)).toBe(true);
    expect(first.includes(config.campaignConfig.rawResultPath)).toBe(true);
    if (process.platform !== 'win32') {
      expect(statSync(config.campaignConfig.cleanupManifestPath).mode & 0o077).toBe(0);
    }

    await backend.writeManifest({ phase: 'auth-intent', email: AUTH_EMAIL });
    const appended = readFileSync(config.campaignConfig.cleanupManifestPath, 'utf8');
    expect(appended.startsWith(first)).toBe(true);
    expect(appended.includes(AUTH_EMAIL)).toBe(true);
    const secondBackend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    await expect(secondBackend.writeManifest({ plan: syntheticPlan })).rejects.toThrow();
    expect(readFileSync(config.campaignConfig.cleanupManifestPath, 'utf8')).toBe(appended);
    expect(fake.calls).toHaveLength(0);
  });

  it('persists the read-only baseline and obtains size through a linked query', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    fake.ports.listAuthUsers = async () => {
      fake.calls.push({ name: 'listAuthUsers', args: [] });
      return [{ id: randomUUID(), email: 'preexisting@example.invalid' }];
    };
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    const observed = await backend.observeSize();
    expect(observed).toMatchObject({ databaseBytes: 34_000_000, providerQuotaBytes: 500_000_000, maxDatabaseBytes: 400_000_000 });
    expect(typeof observed.observedAt).toBe('string');
    expect(fake.calls.some((call) => call.name === 'queryLinked')).toBe(true);

    const snapshot = await backend.captureBaseline(plan());
    expect(snapshot).toBeDefined();
    expect(existsSync(config.campaignConfig.baselineManifestPath)).toBe(true);
    const persisted = readFileSync(config.campaignConfig.baselineManifestPath, 'utf8');
    expect(persisted.includes(PROJECT_REF)).toBe(true);
    expect(persisted.includes('private-bearer-token')).toBe(false);
    const linkedQueries = fake.calls.filter((call) => call.name === 'queryLinked').map((call) => String(call.args[0]));
    for (const table of ['organizations', 'organization_settings', 'branches', 'plans', 'staff', 'members', 'memberships', 'attendance']) {
      expect(linkedQueries.some((sql) => new RegExp(`\\b${table}\\b`, 'i').test(sql)), table).toBe(true);
    }
    expect(fake.calls.some((call) => call.name === 'listAuthUsers')).toBe(true);
    if (process.platform !== 'win32') {
      expect(statSync(config.campaignConfig.baselineManifestPath).mode & 0o077).toBe(0);
    }
    expect(fake.calls.some((call) => call.name === 'createAuthUser')).toBe(false);
  });

  it('fails closed when the linked size query errors or returns ambiguous rows', async () => {
    for (const result of [
      JSON.stringify({ boundary: 'linked', rows: [{ database_bytes: 1 }, { database_bytes: 2 }], warning: null }),
      '{"error":"linked query failed"}',
    ]) {
      const config = privateConfig();
      const fake = fakePorts();
      fake.ports.queryLinked = async (sql: string) => {
        fake.calls.push({ name: 'queryLinked', args: [sql] });
        return result;
      };
      const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
      await expect(backend.observeSize()).rejects.toThrow();
      expect(fake.calls.some((call) => call.name === 'createAuthUser')).toBe(false);
    }
  });

  it('keeps generated Auth passwords in memory and requires exact email plus ID before deletion', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    await backend.writeManifest({ plan: plan(), target: TARGET, artifactPaths: config.campaignConfig });
    expect(await backend.createAuthUser(AUTH_EMAIL)).toBe(AUTH_ID);
    expect(fake.password()).toEqual(expect.any(String));
    expect(fake.password()?.length).toBeGreaterThan(12);
    expect(await backend.signIn(AUTH_EMAIL)).toBe('private-bearer-token');
    const signInCall = fake.calls.find((call) => call.name === 'signIn');
    expect(signInCall?.args[1]).toBe(fake.password());
    const journal = readFileSync(config.campaignConfig.cleanupManifestPath, 'utf8');
    expect(journal.includes(fake.password()!)).toBe(false);
    expect(journal.includes('private-bearer-token')).toBe(false);

    await backend.deleteAuthUser(AUTH_EMAIL, AUTH_ID);
    expect(fake.calls.filter((call) => call.name === 'deleteAuthUser').map((call) => call.args[0])).toEqual([AUTH_ID]);
  });

  it('fails closed on an Auth ID mismatch and recovers an unrecorded ID by exact marker email', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    await expect(backend.deleteAuthUser(AUTH_EMAIL, randomUUID())).rejects.toThrow();
    expect(fake.calls.some((call) => call.name === 'deleteAuthUser')).toBe(false);
    await backend.deleteAuthUser(AUTH_EMAIL, undefined);
    expect(fake.calls.filter((call) => call.name === 'deleteAuthUser').map((call) => call.args[0])).toEqual([AUTH_ID]);
  });

  it('never deletes an Auth row with a different email, even when the ID matches', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    fake.ports.listAuthUsers = async () => {
      fake.calls.push({ name: 'listAuthUsers', args: [] });
      return [{ id: AUTH_ID, email: 'somebody-else@example.invalid' }];
    };
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    await expect(backend.deleteAuthUser(AUTH_EMAIL, AUTH_ID)).rejects.toThrow();
    expect(fake.calls.some((call) => call.name === 'deleteAuthUser')).toBe(false);
  });

  it('writes the private fixture and k6 raw artifact while passing only bounded non-secret env values', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    const fixture = {
      marker: MARKER,
      gymFixtures: Array.from({ length: 100 }, (_, gymIndex) => ({
        gymId: randomUUID(),
        token: `private-bearer-${gymIndex}`,
        memberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
        ownedMemberIds: Array.from({ length: 500 }, (_, memberIndex) => `member-${gymIndex}-${memberIndex}`),
      })),
      fixturePath: config.campaignConfig.fixturePath,
      baselineManifestPath: config.campaignConfig.baselineManifestPath,
      cleanupManifestPath: config.campaignConfig.cleanupManifestPath,
    };
    await backend.writeFixture(fixture);
    const storedFixture = readFileSync(config.campaignConfig.fixturePath, 'utf8');
    expect(storedFixture.includes(fixture.gymFixtures[0].memberIds[0])).toBe(true);
    expect(storedFixture.includes(fixture.gymFixtures[99].token)).toBe(true);
    if (process.platform !== 'win32') {
      expect(statSync(config.campaignConfig.fixturePath).mode & 0o077).toBe(0);
    }

    const signal = new AbortController().signal;
    const measured = await backend.runK6({ signal });
    expect(measured).toEqual({
      p95Ms: 42.5,
      completedCheckIns: 1,
      crossTenantReadDenied: true,
      crossTenantMutationStatus: 403,
    });
    const request = fake.calls.find((call) => call.name === 'executeK6')?.args[0] as {
      signal: AbortSignal; env: Record<string, string>; rawResultPath: string;
    };
    expect(request.signal).toBe(signal);
    expect(request.rawResultPath).toBe(config.campaignConfig.rawResultPath);
    expect(JSON.stringify(request.env).includes(config.campaignConfig.fixturePath)).toBe(true);
    expect(/private-bearer-|member-0-0|password/i.test(JSON.stringify(request.env))).toBe(false);
    expect(readFileSync(config.campaignConfig.rawResultPath, 'utf8').includes(MORNING_REQUEST)).toBe(true);
  });

  it('rejects a nonzero k6 exit despite otherwise valid raw points', async () => {
    const config = privateConfig();
    const fake = fakePorts();
    fake.ports.executeK6 = async (request) => {
      fake.calls.push({ name: 'executeK6', args: [request] });
      return { exitCode: 1, raw: RAW };
    };
    const backend = createPrelaunchCloudBackend({ campaignConfig: config.campaignConfig, anonKey: config.anonKey }, fake.ports);
    await expect(backend.runK6({ signal: new AbortController().signal })).rejects.toThrow();
  });
});
