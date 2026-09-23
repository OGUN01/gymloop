import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import { runPrelaunchLoadCampaign } from '../phase8-prelaunch-load-campaign.mjs';

const PROJECT_REF = 'pecxrpskmfeuyzngvewq';
const MARKER = 'PHASE8-LOAD-11111111-2222-4333-8444-555555555555';
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
const CONFIG = {
  target: TARGET,
  marker: MARKER,
  fixturePath: 'artifacts/phase8-load/private-fixture.json',
  baselineManifestPath: 'artifacts/phase8-load/baseline.json',
  cleanupManifestPath: 'artifacts/phase8-load/cleanup.json',
  rawResultPath: 'artifacts/phase8-load/raw.json',
  thresholds: { p95Ms: 750 },
  monitorIntervalMs: 5,
};
const size = (databaseBytes = 34_000_000) => ({
  observedAt: new Date().toISOString(),
  databaseBytes,
  providerQuotaBytes: 500_000_000,
  maxDatabaseBytes: 400_000_000,
});
const MEASURED = {
  p95Ms: 700,
  completedCheckIns: 50_000,
  crossTenantReadDenied: true,
  crossTenantMutationStatus: 403,
};
const POSTFLIGHT = {
  completed: true,
  preexistingUnchanged: true,
  syntheticRemainderCount: 0,
  authRemainderCount: 0,
};
type Event = { name: string; args: unknown[] };

const fakeBackend = () => {
  const events: Event[] = [];
  const ids = new Map<string, string>();
  const baseline = { identitySnapshot: 'pre-existing-data-sentinel' };
  const record = (name: string, ...args: unknown[]) => events.push({ name, args });
  const manifestEvidence = (state: unknown) => {
    const raw = JSON.stringify(state);
    const lastCreatedId = [...ids.values()].at(-1);
    return {
      hasMarker: raw.includes(MARKER),
      hasGymPlan: raw.includes('gymId'),
      emails: [...new Set(raw.match(/[a-z0-9._%+-]+@[a-z0-9.-]+\.invalid/gi) ?? [])],
      lastCreatedId,
      hasLastCreatedId: lastCreatedId !== undefined && raw.includes(lastCreatedId),
      hasBearerToken: raw.includes('private-token-'),
    };
  };
  const backend = {
    async writeManifest(state: unknown) { record('writeManifest', manifestEvidence(state)); },
    async observeSize() { record('observeSize'); return size(); },
    async captureBaseline(plan: unknown) { record('captureBaseline', plan); return baseline; },
    async createAuthUser(email: string) {
      record('createAuthUser', email);
      const userId = randomUUID();
      ids.set(email, userId);
      return userId;
    },
    async stageSql(sql: string) { record('stageSql', sql); },
    async signIn(email: string) { record('signIn', email); return `private-token-${email}`; },
    async writeFixture(fixture: unknown) { record('writeFixture', fixture); },
    async runK6(request: { signal: AbortSignal }) {
      record('runK6', request);
      return MEASURED;
    },
    async countAttendance(plan: unknown) { record('countAttendance', plan); return 50_000; },
    async cleanupSql(sql: string) { record('cleanupSql', sql); },
    async deleteAuthUser(email: string, userId: string) { record('deleteAuthUser', email, userId); },
    async verifyPostflight(plan: unknown, prior: unknown) {
      record('verifyPostflight', plan, prior);
      return POSTFLIGHT;
    },
  };
  return { backend, events, ids, baseline };
};
const names = (events: Event[]) => events.map((event) => event.name);
const firstIndex = (events: Event[], name: string) => names(events).indexOf(name);
const lastIndex = (events: Event[], name: string) => names(events).lastIndexOf(name);
const expectBlocked = async (config: unknown, backend: unknown) => {
  const result = await runPrelaunchLoadCampaign(config, backend);
  expect(result).toMatchObject({ status: 'blocked' });
  return result;
};

describe('HARD-004 monitored prelaunch campaign preflight', () => {
  it('refuses another target or missing owner assertion before any Cloud mutation', async () => {
    for (const target of [
      { ...TARGET, projectRef: 'other-project' },
      { ...TARGET, observedApiProjectRef: 'other-project' },
      { ...TARGET, noLiveCustomers: false },
      { ...TARGET, confirmation: 'NON_PRODUCTION_LOAD_APPROVED' },
    ]) {
      const fake = fakeBackend();
      await expectBlocked({ ...CONFIG, target }, fake.backend);
      expect(names(fake.events)).not.toContain('createAuthUser');
      expect(names(fake.events)).not.toContain('stageSql');
      expect(names(fake.events)).not.toContain('runK6');
    }
  });

  it('rejects malformed configuration and aliased private artifact paths before staging', async () => {
    for (const config of [
      { ...CONFIG, marker: 'reused-marker' },
      { ...CONFIG, fixturePath: CONFIG.cleanupManifestPath },
      { ...CONFIG, rawResultPath: CONFIG.fixturePath },
      { ...CONFIG, cleanupManifestPath: 'https://example.test/cleanup.json' },
      { ...CONFIG, monitorIntervalMs: 30_001 },
      { ...CONFIG, monitorIntervalMs: 0 },
    ]) {
      const fake = fakeBackend();
      await expectBlocked(config, fake.backend);
      expect(names(fake.events)).not.toContain('createAuthUser');
      expect(names(fake.events)).not.toContain('stageSql');
    }
  });

  it('samples current linked size and fixed quota before the first Auth user', async () => {
    for (const observed of [
      size(400_000_000),
      { ...size(), providerQuotaBytes: 600_000_000 },
      { ...size(), observedAt: new Date(Date.now() - 16 * 60_000).toISOString() },
    ]) {
      const fake = fakeBackend();
      fake.backend.observeSize = async () => { fake.events.push({ name: 'observeSize', args: [] }); return observed; };
      await expectBlocked(CONFIG, fake.backend);
      expect(names(fake.events)).not.toContain('createAuthUser');
      expect(names(fake.events)).not.toContain('stageSql');
    }
  });

  it('persists the synthetic plan before Auth creation and stops if that write fails', async () => {
    const fake = fakeBackend();
    fake.backend.writeManifest = async (state: unknown) => {
      fake.events.push({ name: 'writeManifest', args: [JSON.stringify(state)] });
      throw new Error('manifest unavailable');
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(names(fake.events)).toContain('observeSize');
    expect(names(fake.events)).toContain('writeManifest');
    expect(names(fake.events)).not.toContain('createAuthUser');
    expect(names(fake.events)).not.toContain('stageSql');
    expect(names(fake.events)).not.toContain('runK6');
  });
});

describe('HARD-004 monitored prelaunch campaign execution', () => {
  it('records each Auth intent and ID, stages one transaction, and passes only after postflight', async () => {
    const fake = fakeBackend();
    const summary = await runPrelaunchLoadCampaign(CONFIG, fake.backend);
    expect(summary).toMatchObject({ status: 'passed' });

    const authEvents = fake.events.filter((event) => event.name === 'createAuthUser');
    const signIns = fake.events.filter((event) => event.name === 'signIn');
    const deletions = fake.events.filter((event) => event.name === 'deleteAuthUser');
    expect(authEvents).toHaveLength(100);
    expect(new Set(authEvents.map((event) => event.args[0])).size).toBe(100);
    expect(signIns).toHaveLength(100);
    expect(deletions).toHaveLength(100);
    expect(fake.events.filter((event) => event.name === 'stageSql')).toHaveLength(1);
    expect(fake.events.filter((event) => event.name === 'writeFixture')).toHaveLength(1);
    expect(fake.events.filter((event) => event.name === 'runK6')).toHaveLength(1);
    expect(fake.events.filter((event) => event.name === 'countAttendance')).toHaveLength(1);
    expect(fake.events.filter((event) => event.name === 'cleanupSql')).toHaveLength(1);
    expect(fake.events.filter((event) => event.name === 'verifyPostflight')).toHaveLength(1);

    expect(firstIndex(fake.events, 'observeSize')).toBeLessThan(firstIndex(fake.events, 'createAuthUser'));
    expect(firstIndex(fake.events, 'stageSql')).toBeGreaterThan(lastIndex(fake.events, 'createAuthUser'));
    expect(firstIndex(fake.events, 'writeFixture')).toBeGreaterThan(lastIndex(fake.events, 'signIn'));
    expect(firstIndex(fake.events, 'runK6')).toBeGreaterThan(lastIndex(fake.events, 'writeFixture'));
    expect(lastIndex(fake.events.slice(0, firstIndex(fake.events, 'runK6')), 'observeSize'))
      .toBeGreaterThan(firstIndex(fake.events, 'writeFixture'));
    expect(firstIndex(fake.events, 'countAttendance')).toBeGreaterThan(firstIndex(fake.events, 'runK6'));
    expect(firstIndex(fake.events, 'cleanupSql')).toBeGreaterThan(firstIndex(fake.events, 'countAttendance'));
    expect(firstIndex(fake.events, 'verifyPostflight')).toBeGreaterThan(firstIndex(fake.events, 'cleanupSql'));
    expect(lastIndex(fake.events, 'observeSize')).toBeGreaterThan(firstIndex(fake.events, 'runK6'));
    expect(fake.events.filter((event) => event.name === 'writeManifest')
      .every((event) => !(event.args[0] as { hasBearerToken: boolean }).hasBearerToken)).toBe(true);

    const fixture = fake.events.find((event) => event.name === 'writeFixture')?.args[0] as {
      gymFixtures: Array<{ gymId: string; token: string; memberIds: string[]; ownedMemberIds: string[] }>;
    };
    expect(fixture.gymFixtures).toHaveLength(100);
    expect(new Set(fixture.gymFixtures.map((gym) => gym.gymId)).size).toBe(100);
    expect(new Set(fixture.gymFixtures.map((gym) => gym.token)).size).toBe(100);
    const allMembers = fixture.gymFixtures.flatMap((gym) => gym.memberIds);
    expect(allMembers).toHaveLength(50_000);
    expect(new Set(allMembers).size).toBe(50_000);
    for (const gym of fixture.gymFixtures) {
      expect(gym.memberIds).toHaveLength(500);
      expect(new Set(gym.memberIds)).toEqual(new Set(gym.ownedMemberIds));
    }

    const priorToFirstAuth = fake.events.slice(0, firstIndex(fake.events, 'createAuthUser'));
    expect(priorToFirstAuth.some((event) => event.name === 'writeManifest' &&
      (event.args[0] as { hasMarker: boolean; hasGymPlan: boolean }).hasMarker &&
      (event.args[0] as { hasMarker: boolean; hasGymPlan: boolean }).hasGymPlan)).toBe(true);
    for (let index = 0; index < authEvents.length; index += 1) {
      const eventIndex = fake.events.indexOf(authEvents[index]);
      const email = authEvents[index].args[0] as string;
      const nextAuthIndex = index + 1 < authEvents.length ? fake.events.indexOf(authEvents[index + 1]) : firstIndex(fake.events, 'stageSql');
      const priorAuthIndex = index > 0 ? fake.events.indexOf(authEvents[index - 1]) : 0;
      expect(fake.events.slice(priorAuthIndex, eventIndex).some((event) =>
        event.name === 'writeManifest' &&
        (event.args[0] as { emails: string[] }).emails.includes(email))).toBe(true);
      expect(fake.events.slice(eventIndex + 1, nextAuthIndex).some((event) =>
        event.name === 'writeManifest' &&
        (event.args[0] as { lastCreatedId: string; hasLastCreatedId: boolean }).lastCreatedId === fake.ids.get(email) &&
        (event.args[0] as { hasLastCreatedId: boolean }).hasLastCreatedId)).toBe(true);
    }
    expect(fake.events.find((event) => event.name === 'verifyPostflight')?.args[1]).toBe(fake.baseline);

    const runRequest = fake.events.find((event) => event.name === 'runK6')?.args[0] as { signal: AbortSignal };
    expect(runRequest.signal).toBeInstanceOf(AbortSignal);
    const printed = JSON.stringify(summary);
    expect(printed).not.toMatch(/private-token|memberId|membershipId|password|serviceRoleKey/);
    expect(printed).not.toContain(allMembers[0]);
    expect(JSON.stringify(runRequest)).not.toContain('private-token');
    expect(JSON.stringify(runRequest)).not.toContain(allMembers[0]);
  });

  it('rejects duplicate returned Auth IDs before staging or k6', async () => {
    const fake = fakeBackend();
    const repeatedUserId = randomUUID();
    fake.backend.createAuthUser = async (email: string) => {
      fake.events.push({ name: 'createAuthUser', args: [email] });
      fake.ids.set(email, repeatedUserId);
      return repeatedUserId;
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(names(fake.events)).not.toContain('stageSql');
    expect(names(fake.events)).not.toContain('runK6');
    expect(names(fake.events)).toContain('cleanupSql');
  });

  it('blocks duplicate sign-in credentials before writing the k6 fixture or calling k6', async () => {
    const fake = fakeBackend();
    fake.backend.signIn = async (email: string) => {
      fake.events.push({ name: 'signIn', args: [email] });
      return 'same-private-token';
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(names(fake.events)).not.toContain('writeFixture');
    expect(names(fake.events)).not.toContain('runK6');
    expect(names(fake.events)).toContain('cleanupSql');
    expect(fake.events.filter((event) => event.name === 'deleteAuthUser')).toHaveLength(100);
    expect(names(fake.events)).toContain('verifyPostflight');
  });

  it('blocks when persisted attendance disagrees with k6, while still cleaning exact identities', async () => {
    const fake = fakeBackend();
    fake.backend.countAttendance = async (plan: unknown) => {
      fake.events.push({ name: 'countAttendance', args: [plan] });
      return 49_999;
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(names(fake.events)).toContain('cleanupSql');
    expect(fake.events.filter((event) => event.name === 'deleteAuthUser')).toHaveLength(100);
    expect(names(fake.events)).toContain('verifyPostflight');
  });

  it('blocks when SQL cleanup fails but still deletes marker Auth users and verifies postflight', async () => {
    const fake = fakeBackend();
    fake.backend.cleanupSql = async (sql: string) => {
      fake.events.push({ name: 'cleanupSql', args: [sql] });
      throw new Error('cleanup failed');
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(fake.events.filter((event) => event.name === 'deleteAuthUser')).toHaveLength(100);
    expect(names(fake.events)).toContain('verifyPostflight');
  });

  it('blocks if pre-existing identities change or any synthetic Auth user remains', async () => {
    const fake = fakeBackend();
    fake.backend.verifyPostflight = async (plan: unknown, baseline: unknown) => {
      fake.events.push({ name: 'verifyPostflight', args: [plan, baseline] });
      return { ...POSTFLIGHT, preexistingUnchanged: false, authRemainderCount: 1 };
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(names(fake.events)).toContain('cleanupSql');
  });
});

describe('HARD-004 interrupted campaign recovery', () => {
  it('cleans an Auth creation whose manifest ID write fails', async () => {
    const fake = fakeBackend();
    let failed = false;
    fake.backend.writeManifest = async (state: unknown) => {
      const snapshot = JSON.stringify(state);
      fake.events.push({ name: 'writeManifest', args: [snapshot] });
      const firstCreatedId = [...fake.ids.values()][0];
      if (!failed && firstCreatedId !== undefined && snapshot.includes(firstCreatedId)) {
        failed = true;
        throw new Error('ID record interrupted');
      }
    };
    await expectBlocked(CONFIG, fake.backend);
    expect(failed).toBe(true);
    expect(fake.events.filter((event) => event.name === 'createAuthUser')).toHaveLength(1);
    expect(names(fake.events)).not.toContain('stageSql');
    const firstEmail = [...fake.ids.keys()][0];
    expect(fake.events.some((event) => event.name === 'deleteAuthUser' &&
      event.args[0] === firstEmail && event.args[1] === fake.ids.get(firstEmail))).toBe(true);
    expect(names(fake.events)).toContain('verifyPostflight');
  });

  it('aborts k6 on a later size sample at the 400 MB ceiling, then cleans up', async () => {
    const fake = fakeBackend();
    let k6Started = false;
    let aborted = false;
    fake.backend.observeSize = async () => {
      fake.events.push({ name: 'observeSize', args: [] });
      return size(k6Started ? 400_000_000 : 34_000_000);
    };
    fake.backend.runK6 = async (request: { signal: AbortSignal }) => {
      fake.events.push({ name: 'runK6', args: [request] });
      k6Started = true;
      return new Promise<typeof MEASURED>((_resolve, reject) => {
        const timeout = setTimeout(() => reject(new Error('k6 was not aborted')), 250);
        request.signal.addEventListener('abort', () => {
          aborted = true;
          clearTimeout(timeout);
          reject(new Error('k6 aborted'));
        }, { once: true });
      });
    };
    await expectBlocked({ ...CONFIG, monitorIntervalMs: 1 }, fake.backend);
    expect(aborted).toBe(true);
    expect(names(fake.events)).toContain('cleanupSql');
    expect(fake.events.filter((event) => event.name === 'deleteAuthUser')).toHaveLength(100);
    expect(names(fake.events)).toContain('verifyPostflight');
  });
});
