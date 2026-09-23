/** Monitored HARD-004 campaign. All Cloud and filesystem effects are injected. */
import { resolve } from 'node:path';
import { PHASE8_PRELAUNCH_LOAD_LIMITS } from '../packages/shared/src/config/constants.ts';
import {
  assertSafePrelaunchFixture,
  assertSafePrelaunchQuota,
  assertSafePrelaunchTarget,
  summarizePrelaunchResult,
} from './phase8-prelaunch-load-safety.mjs';
import {
  buildPrelaunchSyntheticPlan,
  renderPrelaunchCleanupSql,
  renderPrelaunchStageSql,
} from './phase8-prelaunch-load-fixture.mjs';

const { checkInCount, defaultMonitorIntervalMs, maxMonitorGapSeconds,
  millisecondsPerSecond, minimumMonitorSamples } = PHASE8_PRELAUNCH_LOAD_LIMITS;
const CONFIG_KEYS = ['target', 'marker', 'fixturePath', 'baselineManifestPath',
  'cleanupManifestPath', 'rawResultPath', 'thresholds', 'monitorIntervalMs'];
const BACKEND_METHODS = ['writeManifest', 'observeSize', 'captureBaseline', 'createAuthUser',
  'stageSql', 'signIn', 'writeFixture', 'runK6', 'countAttendance', 'cleanupSql',
  'deleteAuthUser', 'verifyPostflight'];
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function assertLocalPath(value) {
  if (typeof value !== 'string' || value.trim() === '' || value.includes('\0') ||
      /^[a-z][a-z\d+.-]*:\/\//i.test(value)) throw new Error('A private local artifact path is required.');
  return resolve(value);
}

function validateConfig(config, backend) {
  if (!config || typeof config !== 'object' || Array.isArray(config) ||
      Object.keys(config).some((key) => !CONFIG_KEYS.includes(key))) throw new Error('Unexpected campaign configuration.');
  for (const method of BACKEND_METHODS) {
    if (typeof backend?.[method] !== 'function') throw new Error('Campaign backend is incomplete.');
  }
  assertSafePrelaunchTarget(config.target);
  const plan = buildPrelaunchSyntheticPlan(config.marker);
  const paths = [config.fixturePath, config.baselineManifestPath,
    config.cleanupManifestPath, config.rawResultPath].map(assertLocalPath);
  if (new Set(paths).size !== paths.length) throw new Error('Private artifact paths must be distinct.');
  if (!config.thresholds || Object.keys(config.thresholds).length !== 1 ||
      typeof config.thresholds.p95Ms !== 'number' || !Number.isFinite(config.thresholds.p95Ms) ||
      config.thresholds.p95Ms <= 0) throw new Error('A positive predeclared p95 budget is required.');
  const interval = config.monitorIntervalMs ?? defaultMonitorIntervalMs;
  if (!Number.isInteger(interval) || interval <= 0 || interval > defaultMonitorIntervalMs) {
    throw new Error('Size sampling interval exceeds the campaign limit.');
  }
  return { plan, interval };
}

/** Run one bounded, recoverable same-Cloud campaign and return secret-free evidence. */
export async function runPrelaunchLoadCampaign(config, backend) {
  let plan;
  let interval;
  let firstQuota;
  let baseline;
  let fixture;
  let measured;
  let attendanceCount;
  let cleanupFacts;
  let stoppedAt = 'preflight';
  let manifestWritten = false;
  let failed = false;
  let monitorFailed = false;
  let monitorTimer;
  let previousSampleAt;
  let maxGapSeconds = 0;
  let maxObservedDatabaseBytes = 0;
  let observations = 0;
  let pendingSample = Promise.resolve();
  const controller = new globalThis.AbortController();
  const auth = [];
  const blocked = () => ({ status: 'blocked', ...(typeof config?.rawResultPath === 'string' &&
    config.rawResultPath.trim() !== '' ? { rawResultPath: config.rawResultPath } : {}) });

  async function observe() {
    const sample = pendingSample.then(async () => {
      const snapshot = assertSafePrelaunchQuota(await backend.observeSize());
      const now = Date.now();
      if (previousSampleAt !== undefined) {
        const gapSeconds = (now - previousSampleAt) / millisecondsPerSecond;
        maxGapSeconds = Math.max(maxGapSeconds, gapSeconds);
        if (gapSeconds > maxMonitorGapSeconds) throw new Error('Cloud size observer gap exceeded the limit.');
      }
      previousSampleAt = now;
      maxObservedDatabaseBytes = Math.max(maxObservedDatabaseBytes, snapshot.databaseBytes);
      observations += 1;
      return snapshot;
    });
    pendingSample = sample.catch((error) => {
      monitorFailed = true;
      controller.abort(error);
    });
    return sample;
  }

  function ensureObserved() {
    if (monitorFailed || controller.signal.aborted) throw new Error('Cloud size monitor aborted the campaign.');
    if (previousSampleAt !== undefined &&
        (Date.now() - previousSampleAt) / millisecondsPerSecond > maxMonitorGapSeconds) {
      monitorFailed = true;
      controller.abort();
      throw new Error('Cloud size observation is stale.');
    }
  }

  try {
    ({ plan, interval } = validateConfig(config, backend));
    firstQuota = await observe();
    baseline = await backend.captureBaseline(plan);
    ensureObserved();
    await backend.writeManifest({ marker: plan.marker, plan, phase: 'planned' });
    manifestWritten = true;
    monitorTimer = globalThis.setInterval(() => { void observe().catch(() => {}); }, interval);

    stoppedAt = 'auth';
    for (const gym of plan.gyms) {
      ensureObserved();
      const binding = { email: gym.email, userId: undefined };
      await backend.writeManifest({ marker: plan.marker, authIntent: { email: gym.email } });
      auth.push(binding);
      binding.userId = await backend.createAuthUser(gym.email);
      if (typeof binding.userId !== 'string' || !UUID.test(binding.userId) ||
          auth.slice(0, -1).some((prior) => prior.userId === binding.userId)) {
        throw new Error('Cloud Auth returned a missing, invalid or duplicate identity.');
      }
      await backend.writeManifest({ marker: plan.marker, authCreated: { email: gym.email, userId: binding.userId } });
      ensureObserved();
    }

    await observe();
    ensureObserved();
    stoppedAt = 'stage';
    await backend.stageSql(renderPrelaunchStageSql(plan, auth));
    await observe();
    ensureObserved();
    const tokens = new Set();
    const gymFixtures = [];
    stoppedAt = 'sign-in';
    for (const gym of plan.gyms) {
      const token = await backend.signIn(gym.email);
      if (typeof token !== 'string' || token.trim() === '' || tokens.has(token)) {
        throw new Error('Synthetic gym sign-in returned a missing or reused bearer token.');
      }
      tokens.add(token);
      const memberIds = gym.members.map((member) => member.memberId);
      gymFixtures.push({ gymId: gym.gymId, token, memberIds, ownedMemberIds: [...memberIds] });
      ensureObserved();
    }
    fixture = { marker: plan.marker, gymFixtures, fixturePath: config.fixturePath,
      baselineManifestPath: config.baselineManifestPath, cleanupManifestPath: config.cleanupManifestPath };
    assertSafePrelaunchFixture(fixture);
    stoppedAt = 'fixture';
    await backend.writeFixture(fixture);
    await observe();
    ensureObserved();
    stoppedAt = 'k6';
    measured = await backend.runK6({ signal: controller.signal });
    ensureObserved();
    await observe();
    ensureObserved();
    stoppedAt = 'count-attendance';
    attendanceCount = await backend.countAttendance(plan);
    if (!Number.isSafeInteger(attendanceCount) || attendanceCount !== checkInCount ||
        measured?.completedCheckIns !== attendanceCount) failed = true;
  } catch {
    failed = true;
    controller.abort();
    if (manifestWritten && plan) {
      try { await backend.writeManifest({ marker: plan.marker, phase: 'failed', stoppedAt, monitorFailed }); }
      catch { /* The existing recovery journal remains authoritative. */ }
    }
  } finally {
    if (monitorTimer !== undefined) globalThis.clearInterval(monitorTimer);
    await pendingSample;
    if (manifestWritten && plan) {
      let cleanupSucceeded = true;
      try {
        await backend.cleanupSql(renderPrelaunchCleanupSql(plan));
      } catch { cleanupSucceeded = false; }
      for (const binding of auth) {
        try { await backend.deleteAuthUser(binding.email, binding.userId); }
        catch { cleanupSucceeded = false; }
      }
      try {
        cleanupFacts = await backend.verifyPostflight(plan, baseline);
      } catch { cleanupSucceeded = false; }
      if (!cleanupSucceeded) failed = true;
      try {
        await backend.writeManifest({ marker: plan.marker, phase: cleanupSucceeded ? 'cleaned' : 'recovery-required',
          cleanup: cleanupFacts });
      } catch { failed = true; }
    }
  }

  if (failed || monitorFailed || !fixture || !measured || !cleanupFacts ||
      observations < minimumMonitorSamples) return blocked();
  try {
    return summarizePrelaunchResult({ status: 'passed', target: config.target, quota: firstQuota,
      fixture, rawResultPath: config.rawResultPath, thresholds: config.thresholds,
      measured, monitor: { completed: true, maxObservedDatabaseBytes, maxGapSeconds },
      cleanup: cleanupFacts });
  } catch { return blocked(); }
}
