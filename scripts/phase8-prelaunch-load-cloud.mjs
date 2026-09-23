/** Cloud-facing HARD-004 adapter. External calls are injected for blind tests. */
import { randomUUID } from 'node:crypto';
import { mkdir, open } from 'node:fs/promises';
import { dirname } from 'node:path';
import { PHASE8_PRELAUNCH_LOAD_LIMITS } from '../packages/shared/src/config/constants.ts';
import { assertSafePrelaunchTarget } from './phase8-prelaunch-load-safety.mjs';
import { buildPrelaunchSyntheticPlan, parseLinkedDatabaseSize } from './phase8-prelaunch-load-fixture.mjs';

const { providerQuotaBytes, abortBytes, httpSuccessMin, httpSuccessMax,
  p95Percentile, p95RankOffset, authPasswordPrefixLength, privateFileMode,
  adapterConfigFieldCount, authRefreshLeadSeconds, millisecondsPerSecond } = PHASE8_PRELAUNCH_LOAD_LIMITS;
const PORTS = ['queryLinked', 'createAuthUser', 'signIn', 'listAuthUsers', 'deleteAuthUser', 'executeK6'];
const BASELINE_TABLES = [
  ['organizations', 'id', 'id'], ['organization_settings', 'tenant_id', 'tenant_id'],
  ['branches', 'id', 'tenant_id'], ['plans', 'id', 'tenant_id'],
  ['staff', 'id', 'tenant_id'], ['members', 'id', 'tenant_id'],
  ['memberships', 'id', 'tenant_id'], ['attendance', 'id', 'tenant_id'],
];

function requireRecord(value, label) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error(`${label} must be a record.`);
  return value;
}

function oneLinkedRow(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') throw new Error('Linked Cloud query returned no JSON.');
  let parsed;
  try { parsed = JSON.parse(raw); } catch { throw new Error('Linked Cloud query returned malformed JSON.'); }
  const rows = Array.isArray(parsed) ? parsed : parsed?.rows;
  if (!Array.isArray(rows) || rows.length !== 1) throw new Error('Linked Cloud query returned an ambiguous row count.');
  return requireRecord(rows[0], 'Linked Cloud row');
}

function pointOf(line) {
  let point;
  try { point = JSON.parse(line); } catch { throw new Error('k6 raw evidence is malformed.'); }
  if (!point || typeof point !== 'object') throw new Error('k6 raw evidence has an invalid line.');
  if (point.type !== 'Point') return null;
  const data = requireRecord(point.data, 'k6 point data');
  const tags = requireRecord(data.tags, 'k6 point tags');
  if (typeof point.metric !== 'string' ||
      (typeof tags.scenario !== 'string' && tags.group !== '::setup') ||
      typeof data.value !== 'number' || !Number.isFinite(data.value)) {
    throw new Error('k6 raw evidence has an incomplete point.');
  }
  return { metric: point.metric, value: data.value, tags };
}

/** Derive request, latency and isolation facts only from actual k6 JSON points. */
export function parsePrelaunchK6Raw(raw) {
  if (typeof raw !== 'string' || raw.trim() === '') throw new Error('k6 raw evidence is empty.');
  let completedCheckIns = 0;
  let readChecks = 0;
  let mutationRequests = 0;
  let crossTenantReadDenied = false;
  let crossTenantMutationStatus;
  const durations = [];
  for (const line of raw.split(/\r?\n/)) {
    if (line.trim() === '') continue;
    const point = pointOf(line);
    if (!point) continue;
    const { metric, value, tags } = point;
    if (metric === 'http_reqs' && tags.scenario === 'morning_check_in_spike' &&
        tags.name === 'morning_check_in') {
      const status = Number(tags.status);
      if (value !== 1 || !Number.isInteger(status)) throw new Error('Morning request has no status.');
      if (status >= httpSuccessMin && status <= httpSuccessMax) completedCheckIns += 1;
    }
    if (metric === 'http_req_duration' && tags.scenario === 'morning_check_in_spike' &&
        tags.name === 'morning_check_in') {
      if (value < 0) throw new Error('k6 latency cannot be negative.');
      durations.push(value);
    }
    if (metric === 'checks' && tags.check === 'cross-tenant member read is denied') {
      if (tags.group !== '::setup' || tags.scenario !== undefined) {
        throw new Error('Tenant read probe was not executed during setup.');
      }
      readChecks += 1;
      crossTenantReadDenied = value === 1;
    }
    if (metric === 'http_reqs' && tags.name === 'cross_tenant_mutation') {
      if (tags.group !== '::setup' || tags.scenario !== undefined) {
        throw new Error('Tenant mutation probe was not executed during setup.');
      }
      mutationRequests += 1;
      const status = Number(tags.status);
      if (value !== 1 || !Number.isInteger(status)) throw new Error('Mutation probe has no status.');
      crossTenantMutationStatus = status;
    }
  }
  if (durations.length === 0 || readChecks !== 1 || !crossTenantReadDenied ||
      mutationRequests !== 1 || crossTenantMutationStatus >= httpSuccessMin &&
      crossTenantMutationStatus <= httpSuccessMax) {
    throw new Error('k6 raw evidence lacks a valid latency or tenant isolation proof.');
  }
  durations.sort((left, right) => left - right);
  const rank = p95Percentile * (durations.length - p95RankOffset);
  const lower = Math.floor(rank);
  const upper = Math.ceil(rank);
  const p95Ms = durations[lower] + (durations[upper] - durations[lower]) * (rank - lower);
  return { p95Ms, completedCheckIns, crossTenantReadDenied, crossTenantMutationStatus };
}

function baselineSql(plan) {
  const ids = `ARRAY[${plan.gyms.map((gym) => `'${gym.gymId}'::uuid`).join(', ')}]`;
  const fragments = BASELINE_TABLES.map(([table, identity, tenancy]) => {
    const filter = tenancy === 'id' ? `id <> all(${ids})` : `tenant_id <> all(${ids})`;
    return `'${table}', (select jsonb_build_object('count', count(*), 'ids',
      md5(coalesce(string_agg(${identity}::text, ',' order by ${identity}), '')))
      from public.${table} where ${filter})`;
  });
  return `select jsonb_build_object(${fragments.join(', ')}) as identity_snapshot;`;
}

function remainderSql(plan) {
  const ids = `ARRAY[${plan.gyms.map((gym) => `'${gym.gymId}'::uuid`).join(', ')}]`;
  const parts = BASELINE_TABLES.map(([table, , tenancy]) =>
    `(select count(*) from public.${table} where ${tenancy} = any(${ids}))`);
  return `select (${parts.join(' + ')})::int as synthetic_remainder_count;`;
}

async function writeExclusive(path, contents) {
  await mkdir(dirname(path), { recursive: true });
  const file = await open(path, 'wx', privateFileMode);
  try { await file.writeFile(contents); await file.sync(); }
  finally { await file.close(); }
}

async function appendSynced(path, contents) {
  const file = await open(path, 'a', privateFileMode);
  try { await file.writeFile(contents); await file.sync(); }
  finally { await file.close(); }
}

function publicAuthSnapshot(users, plannedEmails) {
  if (!Array.isArray(users)) throw new Error('Cloud Auth listing is invalid.');
  return users.filter((user) => !plannedEmails.has(user?.email))
    .map((user) => {
      if (typeof user?.id !== 'string' || typeof user.email !== 'string') throw new Error('Cloud Auth identity is invalid.');
      return `${user.id}:${user.email}`;
    }).sort();
}

/** Bind the tested campaign to strict linked-Cloud ports and private artifacts. */
export function createPrelaunchCloudBackend(config, ports) {
  requireRecord(config, 'Cloud adapter config');
  if (Object.keys(config).length !== adapterConfigFieldCount || !Object.hasOwn(config, 'campaignConfig') ||
      !Object.hasOwn(config, 'anonKey') || typeof config.anonKey !== 'string' ||
      config.anonKey.trim() === '') throw new Error('Cloud adapter needs only campaign config and public anon key.');
  const campaign = requireRecord(config.campaignConfig, 'Campaign config');
  const target = assertSafePrelaunchTarget(campaign.target);
  const plan = buildPrelaunchSyntheticPlan(campaign.marker);
  for (const method of PORTS) {
    if (typeof ports?.[method] !== 'function') throw new Error('A required linked-Cloud port is missing.');
  }
  const plannedEmails = new Set(plan.gyms.map((gym) => gym.email));
  const passwords = new Map();
  let journalStarted = false;
  let authForCleanup;
  const { fixturePath, baselineManifestPath, cleanupManifestPath, rawResultPath } = campaign;
  const markerEmail = (email) => typeof email === 'string' && email.endsWith('.invalid') &&
    (plannedEmails.has(email) || email.toLowerCase().includes(campaign.marker.toLowerCase()));

  return {
    async writeManifest(state) {
      requireRecord(state, 'Recovery journal state');
      if (!journalStarted) {
        if (!state.plan || JSON.stringify(state.plan) !== JSON.stringify(plan)) {
          throw new Error('The initial recovery record must contain the complete marker-derived plan.');
        }
        const first = { projectRef: target.projectRef,
          artifactPaths: { fixturePath, baselineManifestPath, cleanupManifestPath, rawResultPath }, state };
        await writeExclusive(cleanupManifestPath, `${JSON.stringify(first)}\n`);
        journalStarted = true;
      } else {
        await appendSynced(cleanupManifestPath, `${JSON.stringify(state)}\n`);
      }
    },
    async observeSize() {
      const raw = await ports.queryLinked('select pg_database_size(current_database())::bigint as database_bytes;');
      return { observedAt: new Date().toISOString(), databaseBytes: parseLinkedDatabaseSize(raw),
        providerQuotaBytes, maxDatabaseBytes: abortBytes };
    },
    async captureBaseline(requestedPlan) {
      if (JSON.stringify(requestedPlan) !== JSON.stringify(plan)) throw new Error('Baseline plan differs from the marker.');
      const row = oneLinkedRow(await ports.queryLinked(baselineSql(plan)));
      const auth = publicAuthSnapshot(await ports.listAuthUsers(), plannedEmails);
      const baseline = { projectRef: target.projectRef, data: row, auth };
      await writeExclusive(baselineManifestPath, JSON.stringify(baseline));
      return baseline;
    },
    async createAuthUser(email) {
      if (!markerEmail(email)) throw new Error('Auth creation email is outside the marker.');
      const password = `${randomUUID().slice(0, authPasswordPrefixLength)}A1!${randomUUID()}`;
      passwords.set(email, password);
      return ports.createAuthUser(email, password);
    },
    async stageSql(sql) { await ports.queryLinked(sql); },
    async signIn(email) {
      const password = passwords.get(email);
      if (!markerEmail(email) || !password) throw new Error('No synthetic Auth password is held for sign-in.');
      return ports.signIn(email, password);
    },
    async writeFixture(fixture) {
      if (fixture?.fixturePath !== fixturePath || fixture?.marker !== plan.marker) {
        throw new Error('Private fixture identity does not match the campaign.');
      }
      await writeExclusive(fixturePath, JSON.stringify(fixture));
    },
    async runK6({ signal }) {
      if (!(signal instanceof globalThis.AbortSignal)) throw new Error('k6 must be cancellable.');
      const ref = target.projectRef;
      const k6Env = {
        PHASE8_LOAD_MODE: target.mode,
        PHASE8_LOAD_PROJECT_REF: ref,
        PHASE8_LOAD_OBSERVED_API_PROJECT_REF: ref,
        PHASE8_LOAD_OBSERVED_SUPABASE_PROJECT_REF: ref,
        PHASE8_LOAD_CREDENTIAL_PROJECT_REF: ref,
        PHASE8_LOAD_CREDENTIAL_KIND: target.mode,
        PHASE8_LOAD_CONFIRMATION: campaign.target.confirmation,
        PHASE8_LOAD_NO_LIVE_CUSTOMERS: 'true',
        PHASE8_LOAD_API_URL: target.apiUrl,
        PHASE8_LOAD_SUPABASE_URL: target.supabaseUrl,
        PHASE8_LOAD_SUPABASE_ANON_KEY: config.anonKey,
        PHASE8_LOAD_P95_MS: String(campaign.thresholds.p95Ms),
        PHASE8_LOAD_RUN_ID: plan.marker.slice('PHASE8-LOAD-'.length),
        PHASE8_LOAD_FIXTURE_PATH: fixturePath,
        PHASE8_LOAD_REFRESH_LEAD_SECONDS: String(authRefreshLeadSeconds),
        PHASE8_LOAD_MS_PER_SECOND: String(millisecondsPerSecond),
      };
      const result = await ports.executeK6({ signal, env: k6Env, rawResultPath });
      requireRecord(result, 'k6 result');
      if (typeof result.raw !== 'string') throw new Error('k6 raw evidence was not returned.');
      await writeExclusive(rawResultPath, result.raw);
      if (result.exitCode !== 0) throw new Error('k6 thresholds or checks failed.');
      return parsePrelaunchK6Raw(result.raw);
    },
    async countAttendance(requestedPlan) {
      if (JSON.stringify(requestedPlan) !== JSON.stringify(plan)) throw new Error('Attendance plan differs from the marker.');
      const ids = `ARRAY[${plan.gyms.map((gym) => `'${gym.gymId}'::uuid`).join(', ')}]`;
      const row = oneLinkedRow(await ports.queryLinked(
        `select count(*)::int as attendance_count from public.attendance where tenant_id = any(${ids});`));
      if (!Number.isSafeInteger(row.attendance_count) || row.attendance_count < 0) {
        throw new Error('Persisted synthetic attendance count is invalid.');
      }
      return row.attendance_count;
    },
    async cleanupSql(sql) { await ports.queryLinked(sql); },
    async deleteAuthUser(email, userId) {
      if (!markerEmail(email)) throw new Error('Auth deletion email is outside the marker.');
      authForCleanup ??= await ports.listAuthUsers();
      if (!Array.isArray(authForCleanup)) throw new Error('Cloud Auth listing is invalid.');
      const matched = authForCleanup.filter((user) => user?.email === email);
      if (matched.length > 1) throw new Error('Synthetic Auth email is ambiguous.');
      const byId = userId === undefined ? undefined : authForCleanup.find((user) => user?.id === userId);
      if (byId && byId.email !== email) throw new Error('Auth ID belongs to another email.');
      if (matched.length === 0) return;
      if (userId !== undefined && matched[0].id !== userId) throw new Error('Auth ID and marker email differ.');
      await ports.deleteAuthUser(matched[0].id);
      authForCleanup = authForCleanup.filter((user) => user?.id !== matched[0].id);
    },
    async verifyPostflight(requestedPlan, baseline) {
      if (JSON.stringify(requestedPlan) !== JSON.stringify(plan) ||
          baseline?.projectRef !== target.projectRef) throw new Error('Postflight baseline identity differs.');
      const current = oneLinkedRow(await ports.queryLinked(baselineSql(plan)));
      const remainder = oneLinkedRow(await ports.queryLinked(remainderSql(plan)));
      if (!Number.isSafeInteger(remainder.synthetic_remainder_count) ||
          remainder.synthetic_remainder_count < 0) throw new Error('Synthetic remainder query is invalid.');
      const users = await ports.listAuthUsers();
      const preexistingAuth = publicAuthSnapshot(users, plannedEmails);
      const authRemainderCount = users.filter((user) => plannedEmails.has(user?.email)).length;
      return { completed: true,
        preexistingUnchanged: JSON.stringify(current) === JSON.stringify(baseline.data) &&
          JSON.stringify(preexistingAuth) === JSON.stringify(baseline.auth),
        syntheticRemainderCount: remainder.synthetic_remainder_count, authRemainderCount };
    },
  };
}
