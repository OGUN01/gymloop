import { createHash } from 'node:crypto';
import { Buffer } from 'node:buffer';
import { URL } from 'node:url';
import { TextDecoder } from 'node:util';
import { NATIVE_DB_VALIDATION as limits } from '../../packages/shared/src/config/constants.ts';
import { exactNativeDataArray, exactNativeDataRecord } from './data-record.mjs';
import { chooseNativeRunnerLabels, verifyNativeRunnerJob } from './runner-job.mjs';

function nativeReadinessJob(value) {
  const job = exactNativeDataRecord(value, ['repository', 'eventName', 'ref', 'sourceSha', 'runId', 'runAttempt', 'workflowRef']);
  if (!job || typeof job.sourceSha !== 'string') return null;
  const expected = { sourceSha: job.sourceSha, runId: job.runId, runAttempt: job.runAttempt,
    label: `${limits.labelPrefix}-${job.runId}-${job.runAttempt}-${job.sourceSha.slice(0, limits.labelShaLength)}` };
  return verifyNativeRunnerJob(expected, { ...job, runnerOs: limits.runnerOs, job: limits.job }).trusted ? job : null;
}

function nativeReadinessClock(value) {
  return Number.isSafeInteger(value) && value >= 0 ? value : null;
}

function nativeReadinessTimestamp(value, milliseconds = false) {
  if (typeof value !== 'string' || !(milliseconds
    ? /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/
    : /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/).test(value)) return null;
  const time = nativeReadinessClock(Date.parse(value));
  if (time === null) return null;
  const canonical = new Date(time).toISOString();
  return (canonical === value || (!milliseconds && canonical.replace('.000Z', 'Z') === value)) ? time : null;
}

function nativeReadinessSecond(value) {
  const date = new Date(value);
  date.setUTCMilliseconds(0);
  return date.getTime();
}

function nativeReadinessBytes(value, maximum = limits.timeoutQueryMaxBytes, nonempty = true) {
  if (!(value instanceof Uint8Array) || value.byteLength > maximum || (nonempty && value.byteLength === 0)) return null;
  return Buffer.from(value);
}

function nativeReadinessJson(value) {
  const bytes = nativeReadinessBytes(value);
  if (!bytes) return null;
  return JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes));
}

function nativeReadinessPayload(value, job, now) {
  const readiness = exactNativeDataRecord(value, ['formatVersion', 'verifiedAt', 'expiresAt', 'runner']);
  if (!readiness || readiness.formatVersion !== limits.formatVersion) return null;
  const verified = nativeReadinessTimestamp(readiness.verifiedAt, true);
  const expires = nativeReadinessTimestamp(readiness.expiresAt, true);
  const runner = exactNativeDataRecord(readiness.runner,
    ['id', 'status', 'busy', 'ephemeral', 'guardVerified', 'label', 'sourceSha', 'runId', 'runAttempt']);
  if (verified === null || expires === null || verified > now || now - verified > limits.readinessMaxAgeMs
    || expires <= now || expires <= verified || expires - verified > limits.readinessMaxAgeMs || !runner
    || chooseNativeRunnerLabels({ job, runner })[0] !== 'self-hosted') return null;
  return { readiness, runner, verified, expires };
}

/** Produce only a fresh, source-bound nonsecret readiness artifact. */
export function createNativeRunnerReadinessPublication(input) {
  try {
    input = exactNativeDataRecord(input, ['job', 'readiness', 'now']);
    if (!input || typeof input.readiness !== 'string' || nativeReadinessClock(input.now) === null
      || Buffer.byteLength(input.readiness, 'utf8') > limits.timeoutQueryMaxBytes) return null;
    const job = nativeReadinessJob(input.job);
    if (!job) return null;
    const value = JSON.parse(input.readiness);
    if (!nativeReadinessPayload(value, job, input.now)) return null;
    const body = `${JSON.stringify(value)}\n`;
    if (Buffer.byteLength(body, 'utf8') > limits.timeoutQueryMaxBytes) return null;
    return { artifactName: `native-db-readiness-${job.runId}-${job.runAttempt}-${job.sourceSha}`, member: 'readiness.json', body };
  } catch { return null; }
}

function nativeReadinessBudget(ports) {
  let last = ports.monotonicNow();
  if (!Number.isFinite(last) || last < 0) throw new Error('Readiness clock unavailable.');
  const started = last;
  const remaining = () => {
    const now = ports.monotonicNow();
    if (!Number.isFinite(now) || now < last || now < 0) throw new Error('Readiness clock unavailable.');
    last = now;
    const left = limits.nativeCleanupReserveMs - (now - started);
    if (left <= 0) throw new Error('Readiness budget exhausted.');
    return left;
  };
  return async operation => {
    const allowance = Math.min(limits.processStopGraceMs, remaining());
    const controller = new globalThis.AbortController();
    let timer;
    try {
      const pending = Promise.resolve(operation(controller.signal, allowance));
      const timeout = new Promise((resolve, reject) => {
        timer = globalThis.setTimeout(() => {
          controller.abort();
          reject(new Error('Readiness operation expired.'));
        }, allowance);
      });
      const result = await Promise.race([pending, timeout]);
      remaining();
      return result;
    } finally {
      globalThis.clearTimeout(timer);
      controller.abort();
    }
  };
}

function nativeReadinessRun(run, { job, repositoryId, workflowId, publisher, now }) {
  if (!run || typeof run !== 'object' || Array.isArray(run)
    || !Number.isSafeInteger(run.id) || run.id <= 0 || !Number.isSafeInteger(run.run_attempt) || run.run_attempt <= 0
    || run.repository?.id !== repositoryId || run.repository?.full_name !== limits.repository
    || run.head_repository?.id !== repositoryId || run.head_repository?.full_name !== limits.repository
    || run.head_sha !== job.sourceSha || run.head_branch !== 'main'
    || run.path !== (publisher ? '.github/workflows/native-runner-readiness.yml' : '.github/workflows/db.yml')) return null;
  if (publisher ? run.workflow_id !== workflowId || run.event !== 'workflow_dispatch' || run.run_attempt !== 1
      || run.actor?.login !== 'OGUN01' || run.triggering_actor?.login !== 'OGUN01'
    : String(run.id) !== job.runId || String(run.run_attempt) !== job.runAttempt || run.event !== job.eventName
      || run.status !== 'in_progress' || run.conclusion !== null) return null;
  const created = nativeReadinessTimestamp(run.created_at);
  const updated = nativeReadinessTimestamp(run.updated_at);
  const started = nativeReadinessTimestamp(run.run_started_at);
  const second = nativeReadinessSecond(now);
  if (created === null || updated === null || created > updated || nativeReadinessSecond(updated) > second
    || started === null || created > started || started > updated) return null;
  const pending = publisher && ['queued', 'in_progress'].includes(run.status) && run.conclusion === null;
  if (publisher && !pending && (run.status !== 'completed' || run.conclusion !== 'success')) return null;
  return { run, created, updated, started, pending };
}

function nativeReadinessArtifact(value, { name, repositoryId, job, now }) {
  if (!value || typeof value !== 'object' || Array.isArray(value)
    || !Number.isSafeInteger(value.id) || value.id <= 0 || value.name !== name || value.expired !== false
    || !Number.isSafeInteger(value.size_in_bytes) || value.size_in_bytes <= 0 || value.size_in_bytes > limits.timeoutQueryMaxBytes
    || typeof value.digest !== 'string' || !new RegExp(`^sha256:[a-f0-9]{${limits.digestHexLength}}$`).test(value.digest)) return null;
  const producer = value.workflow_run;
  if (!producer || !Number.isSafeInteger(producer.id) || producer.id <= 0
    || producer.repository_id !== repositoryId || producer.head_repository_id !== repositoryId
    || producer.head_branch !== 'main' || producer.head_sha !== job.sourceSha) return null;
  const created = nativeReadinessTimestamp(value.created_at);
  const updated = nativeReadinessTimestamp(value.updated_at);
  if (!Object.hasOwn(value, 'expires_at')) return null;
  const expires = value.expires_at === null ? null : nativeReadinessTimestamp(value.expires_at);
  if (created === null || updated === null || created > updated
    || (value.expires_at !== null && (expires === null || expires <= now))
    || nativeReadinessSecond(updated) > nativeReadinessSecond(now)) return null;
  return { id: value.id, name: value.name, size: value.size_in_bytes, digest: value.digest,
    created, updated, expires, producerId: producer.id, repositoryId, sourceSha: producer.head_sha };
}

function nativeReadinessUploadedJob(value, producer, now) {
  const jobs = exactNativeDataArray(value?.jobs);
  if (!Number.isSafeInteger(value?.total_count) || value.total_count !== 1 || !jobs || jobs.length !== value.total_count) return null;
  const job = jobs[0];
  if (!job || !Number.isSafeInteger(job.id) || job.id <= 0 || job.run_id !== producer.run.id
    || job.head_sha !== producer.run.head_sha || job.name !== 'Publish verified readiness'
    || job.status !== 'completed' || job.conclusion !== 'success'
    || (Object.hasOwn(job, 'run_attempt') && (!Number.isSafeInteger(job.run_attempt)
      || job.run_attempt !== producer.run.run_attempt))) return null;
  const started = nativeReadinessTimestamp(job.started_at);
  const completed = nativeReadinessTimestamp(job.completed_at);
  const steps = exactNativeDataArray(job.steps);
  if (!steps || started === null || completed === null || started > completed
    || started < nativeReadinessSecond(producer.created) || completed > nativeReadinessSecond(producer.updated)
    || nativeReadinessSecond(completed) > nativeReadinessSecond(now)) return null;
  const required = [];
  for (const name of ['Produce bound readiness', 'Retain bound readiness']) {
    const matches = steps.filter(step => step?.name === name);
    if (matches.length !== 1) return null;
    const step = matches[0];
    const beginning = nativeReadinessTimestamp(step.started_at);
    const ending = nativeReadinessTimestamp(step.completed_at);
    if (step.status !== 'completed' || step.conclusion !== 'success' || beginning === null || ending === null
      || beginning > ending || beginning < started || ending > completed) return null;
    required.push({ started: beginning, completed: ending });
  }
  if (required[0].completed > required[1].started) return null;
  return { started, completed, upload: required[1] };
}

/** Retrieve one bounded, authenticated and independently bound readiness publication. */
export async function resolveNativeRunnerReadiness(input, ports) {
  try {
    input = exactNativeDataRecord(input, ['job']);
    const job = input && nativeReadinessJob(input.job);
    if (!job) return null;
    ports = exactNativeDataRecord(ports, ['apiGet', 'storageGet', 'readZipMember', 'utcNow', 'monotonicNow', 'pause']);
    if (!ports || !Object.values(ports).every(port => typeof port === 'function')) return null;
    const boundary = nativeReadinessBudget(ports);
    const utc = () => {
      const now = nativeReadinessClock(ports.utcNow());
      if (now === null) throw new Error('Readiness UTC unavailable.');
      return now;
    };
    const prefix = `/repos/${limits.repository}`;
    const get = async (path, query = {}) => {
      const response = exactNativeDataRecord(await boundary(signal => ports.apiGet(path, query, signal)), ['status', 'body', 'location']);
      if (!response || response.status !== limits.artifactMetadataStatus || response.location !== null) throw new Error('Readiness API unavailable.');
      const value = nativeReadinessJson(response.body);
      if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('Readiness API malformed.');
      return value;
    };
    const repository = await get(prefix);
    if (!Number.isSafeInteger(repository.id) || repository.id <= 0 || repository.full_name !== limits.repository) return null;
    const workflow = await get(`${prefix}/actions/workflows/native-runner-readiness.yml`);
    if (!Number.isSafeInteger(workflow.id) || workflow.id <= 0 || workflow.path !== '.github/workflows/native-runner-readiness.yml'
      || workflow.state !== 'active') return null;
    const name = `native-db-readiness-${job.runId}-${job.runAttempt}-${job.sourceSha}`;
    for (;;) {
      const target = nativeReadinessRun(await get(`${prefix}/actions/runs/${job.runId}/attempts/${job.runAttempt}`),
        { job, repositoryId: repository.id, workflowId: workflow.id, publisher: false, now: utc() });
      if (!target) return null;
      const listing = await get(`${prefix}/actions/artifacts`, { name });
      const artifacts = exactNativeDataArray(listing.artifacts);
      if (!Number.isSafeInteger(listing.total_count) || listing.total_count < 0 || !artifacts || artifacts.length !== listing.total_count) return null;
      if (listing.total_count === 0) {
        await boundary((signal, allowance) => ports.pause(allowance, signal));
        continue;
      }
      if (listing.total_count !== 1) return null;
      const artifact = nativeReadinessArtifact(artifacts[0], { name, repositoryId: repository.id, job, now: utc() });
      if (!artifact) return null;
      const producerRun = await get(`${prefix}/actions/runs/${artifact.producerId}`);
      const producer = nativeReadinessRun(producerRun,
        { job, repositoryId: repository.id, workflowId: workflow.id, publisher: true, now: utc() });
      if (!producer || producer.run.id !== artifact.producerId) return null;
      const attempt = nativeReadinessRun(await get(`${prefix}/actions/runs/${artifact.producerId}/attempts/${producer.run.run_attempt}`),
        { job, repositoryId: repository.id, workflowId: workflow.id, publisher: true, now: utc() });
      if (!attempt || attempt.run.id !== artifact.producerId || attempt.created !== producer.created) return null;
      if (producer.pending || attempt.pending) {
        await boundary((signal, allowance) => ports.pause(allowance, signal));
        continue;
      }
      const uploaded = nativeReadinessUploadedJob(await get(`${prefix}/actions/runs/${artifact.producerId}/attempts/${attempt.run.run_attempt}/jobs`), attempt, utc());
      if (!uploaded || nativeReadinessSecond(artifact.created) < nativeReadinessSecond(uploaded.upload.started)
        || nativeReadinessSecond(artifact.updated) > nativeReadinessSecond(uploaded.upload.completed)
        || nativeReadinessSecond(attempt.updated) < nativeReadinessSecond(uploaded.upload.completed)) return null;
      const currentArtifact = nativeReadinessArtifact(await get(`${prefix}/actions/artifacts/${artifact.id}`),
        { name, repositoryId: repository.id, job, now: utc() });
      if (!currentArtifact || JSON.stringify(currentArtifact) !== JSON.stringify(artifact)) return null;
      const currentTarget = nativeReadinessRun(await get(`${prefix}/actions/runs/${job.runId}/attempts/${job.runAttempt}`),
        { job, repositoryId: repository.id, workflowId: workflow.id, publisher: false, now: utc() });
      if (!currentTarget || currentTarget.created !== target.created || currentTarget.started !== target.started) return null;
      const response = exactNativeDataRecord(await boundary(signal => ports.apiGet(`${prefix}/actions/artifacts/${artifact.id}/zip`, {}, signal)),
        ['status', 'body', 'location']);
      if (!response || response.status !== limits.artifactRedirectStatus || typeof response.location !== 'string'
        || !nativeReadinessBytes(response.body, limits.timeoutQueryMaxBytes, false)
        || /[\p{Cc}\s]/u.test(response.location) || response.location.includes('#')
        || /^https:[/\\]*[^/\\?#]*@/i.test(response.location)) return null;
      const url = new URL(response.location);
      if (url.protocol !== 'https:' || url.username || url.password || url.hash) return null;
      const download = exactNativeDataRecord(await boundary(signal => ports.storageGet(response.location, signal)), ['status', 'body']);
      const bytes = download && nativeReadinessBytes(download.body);
      if (!bytes || download.status !== limits.artifactMetadataStatus || bytes.length !== artifact.size
        || `sha256:${createHash('sha256').update(bytes).digest('hex')}` !== artifact.digest) return null;
      const member = nativeReadinessBytes(await boundary(signal => ports.readZipMember(bytes, 'readiness.json', limits.timeoutQueryMaxBytes, signal)));
      if (!member) return null;
      const payload = nativeReadinessJson(member);
      const now = utc();
      const publication = createNativeRunnerReadinessPublication({ job, readiness: new TextDecoder('utf-8', { fatal: true }).decode(member), now });
      const checked = nativeReadinessPayload(payload, job, now);
      if (!publication || !checked || !member.equals(Buffer.from(publication.body, 'utf8'))
        || nativeReadinessSecond(target.created) > nativeReadinessSecond(checked.verified)
        || nativeReadinessSecond(target.started) > nativeReadinessSecond(checked.verified)
        || nativeReadinessSecond(attempt.created) < nativeReadinessSecond(checked.verified)
        || nativeReadinessSecond(attempt.updated) >= nativeReadinessSecond(checked.expires)) return null;
      await boundary(() => undefined);
      return checked.runner;
    }
  } catch { return null; }
}
