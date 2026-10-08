import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { deflateRawSync, inflateRawSync } from 'node:zlib';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type HeldReadinessRecord = Record<string, unknown>;
type HeldReadinessPorts = {
  apiGet: (path: string, query: HeldReadinessRecord, signal: AbortSignal) => Promise<unknown>;
  storageGet: (url: string, signal: AbortSignal) => Promise<unknown>;
  readZipMember: (bytes: Uint8Array, member: string, limit: number, signal: AbortSignal) => Promise<Uint8Array>;
  utcNow: () => number;
  monotonicNow: () => number;
  pause: (ms: number, signal: AbortSignal) => Promise<void>;
};
type HeldReadinessFixture = {
  job: HeldReadinessRecord;
  runner: HeldReadinessRecord;
  payload: HeldReadinessRecord;
  repository: HeldReadinessRecord;
  workflow: HeldReadinessRecord;
  target: HeldReadinessRecord;
  publisher: HeldReadinessRecord;
  jobs: HeldReadinessRecord;
  artifact: HeldReadinessRecord;
  refreshedArtifact: HeldReadinessRecord | null;
  artifacts: HeldReadinessRecord;
  ports: HeldReadinessPorts;
  calls: { port: string; args: unknown[]; signal: AbortSignal }[];
  archive: Buffer;
  canonical: Buffer;
  utc: number;
  monotonic: number;
  absent: number;
  pending: number;
  apiStatus: number;
  storageStatus: number;
  location: unknown;
  rawResponse: Buffer | null;
  apiHook: ((path: string) => Promise<unknown> | unknown) | null;
  zipHook: (() => Promise<Uint8Array> | Uint8Array) | null;
};

async function heldReadinessModule() {
  let loaded: HeldReadinessRecord = {};
  try {
    const path = '../../scripts/pgtap/runner-readiness.mjs';
    loaded = await import(path);
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== 'ERR_MODULE_NOT_FOUND' && code !== 'MODULE_NOT_FOUND') throw error;
  }
  expect(typeof loaded.createNativeRunnerReadinessPublication).toBe('function');
  expect(typeof loaded.resolveNativeRunnerReadiness).toBe('function');
  return loaded as {
    createNativeRunnerReadinessPublication: (input: unknown) => HeldReadinessRecord | null;
    resolveNativeRunnerReadiness: (input: unknown, ports: unknown) => Promise<HeldReadinessRecord | null>;
  };
}

function heldReadinessDate(offset = 0) {
  return new Date(Date.parse('2026-10-08T13:00:00.750Z') + offset).toISOString();
}

function heldReadinessZip(entries: {
  name?: string; body: Buffer; compression?: number; flags?: number; mode?: number;
}[]) {
  const locals: Buffer[] = [];
  const centrals: Buffer[] = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name ?? 'readiness.json');
    const compression = entry.compression ?? 0;
    const encoded = compression === 8 ? deflateRawSync(entry.body) : entry.body;
    let crc = 0xffffffff;
    for (const byte of entry.body) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
    crc = (crc ^ 0xffffffff) >>> 0;
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(entry.flags ?? 0, 6);
    local.writeUInt16LE(compression, 8);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(encoded.length, 18);
    local.writeUInt32LE(entry.body.length, 22);
    local.writeUInt16LE(name.length, 26);
    locals.push(local, name, encoded);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(entry.flags ?? 0, 8);
    central.writeUInt16LE(compression, 10);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(encoded.length, 20);
    central.writeUInt32LE(entry.body.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(((entry.mode ?? 0o100600) << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += local.length + name.length + encoded.length;
  }
  const directory = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, directory, end]);
}

function heldReadinessReplace(record: HeldReadinessRecord, key: string, value: unknown) {
  record[key] = value;
}

function heldReadinessMutate(fixture: HeldReadinessFixture, change: (payload: HeldReadinessRecord) => void) {
  change(fixture.payload);
  fixture.canonical = Buffer.from(JSON.stringify(fixture.payload) + '\n');
  fixture.archive = heldReadinessZip([{ body: fixture.canonical }]);
  fixture.artifact.size_in_bytes = fixture.archive.length;
  fixture.artifact.digest = 'sha256:' + createHash('sha256').update(fixture.archive).digest('hex');
}

function heldReadinessFixture(): HeldReadinessFixture {
  const job = {
    repository: 'OGUN01/gymloop', eventName: 'push', ref: 'refs/heads/main',
    sourceSha: '9f731ac5266d9bc09a217938456bae0ae07532dc', runId: '74102938561',
    runAttempt: '2', workflowRef: 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/main',
  };
  const runner = {
    id: 6158, status: 'online', busy: false, ephemeral: true, guardVerified: true,
    label: 'fitcruxx-db-win-x64-74102938561-2-9f731ac5266d',
    sourceSha: job.sourceSha, runId: job.runId, runAttempt: job.runAttempt,
  };
  const payload = {
    formatVersion: 1, verifiedAt: heldReadinessDate(),
    expiresAt: heldReadinessDate(NATIVE_DB_VALIDATION.readinessMaxAgeMs), runner,
  };
  const repository = { id: 810527493, full_name: job.repository };
  const target = {
    id: Number(job.runId), run_attempt: 2, event: 'push', head_sha: job.sourceSha,
    head_branch: 'main', path: '.github/workflows/db.yml',
    repository: { ...repository }, head_repository: { ...repository },
    status: 'in_progress', conclusion: null, created_at: heldReadinessDate(-12_000),
    run_started_at: heldReadinessDate(-8_000), updated_at: heldReadinessDate(5_250),
    actor: { login: 'OGUN01' }, triggering_actor: { login: 'OGUN01' },
  };
  const workflow = { id: 21581468, path: '.github/workflows/native-runner-readiness.yml', state: 'active' };
  const publisher = {
    id: 74102940019, run_attempt: 1, workflow_id: workflow.id, path: workflow.path,
    head_sha: job.sourceSha, head_branch: 'main', repository: { ...repository },
    head_repository: { ...repository }, event: 'workflow_dispatch',
    actor: { login: 'OGUN01' }, triggering_actor: { login: 'OGUN01' },
    status: 'completed', conclusion: 'success', created_at: '2026-10-08T13:00:00Z',
    run_started_at: '2026-10-08T13:00:01Z', updated_at: '2026-10-08T13:00:05Z',
  };
  const jobs = {
    total_count: 1,
    jobs: [{
      id: 8875236147, run_id: publisher.id, run_attempt: 1, name: 'Publish verified readiness',
      head_sha: job.sourceSha,
      status: 'completed', conclusion: 'success', started_at: '2026-10-08T13:00:01Z',
      completed_at: '2026-10-08T13:00:05Z',
      steps: [
        { name: 'Produce bound readiness', status: 'completed', conclusion: 'success', number: 2,
          started_at: '2026-10-08T13:00:01Z', completed_at: '2026-10-08T13:00:02Z' },
        { name: 'Retain bound readiness', status: 'completed', conclusion: 'success', number: 3,
          started_at: '2026-10-08T13:00:03Z', completed_at: '2026-10-08T13:00:04Z' },
      ],
    }],
  };
  const canonical = Buffer.from(JSON.stringify(payload) + '\n');
  const archive = heldReadinessZip([{ body: canonical }]);
  const artifact = {
    id: 3927426871, name: `native-db-readiness-${job.runId}-${job.runAttempt}-${job.sourceSha}`,
    size_in_bytes: archive.length, expired: false, digest: 'sha256:' + createHash('sha256').update(archive).digest('hex'),
    created_at: '2026-10-08T13:00:03Z', updated_at: '2026-10-08T13:00:03Z',
    expires_at: '2026-10-15T13:00:03Z',
    workflow_run: { id: publisher.id, repository_id: repository.id,
      head_repository_id: repository.id, head_branch: 'main', head_sha: job.sourceSha },
  };
  const fixture = {
    job, runner, payload, repository, workflow, target, publisher, jobs, artifact,
    refreshedArtifact: null, artifacts: { total_count: 1, artifacts: [artifact] },
    calls: [], archive, canonical, utc: Date.parse(heldReadinessDate(6_375)), monotonic: 0,
    absent: 0, pending: 0, apiStatus: 200, storageStatus: 200,
    location: 'https://productionresultssa7.blob.core.windows.net/actions/readiness.zip?sig=synthetic',
    rawResponse: null, apiHook: null, zipHook: null,
  } as Omit<HeldReadinessFixture, 'ports'>;
  const ports: HeldReadinessPorts = {
    apiGet: async (path, query, signal) => {
      fixture.calls.push({ port: 'apiGet', args: [path, query], signal });
      fixture.monotonic++;
      if (signal.aborted) throw new Error('HELD_ABORTED');
      const hooked = await fixture.apiHook?.(path);
      if (hooked !== undefined) return hooked;
      const prefix = '/repos/OGUN01/gymloop';
      let result: unknown;
      if (path === prefix) result = fixture.repository;
      else if (path === prefix + '/actions/workflows/native-runner-readiness.yml') result = fixture.workflow;
      else if (path === prefix + `/actions/runs/${job.runId}/attempts/${job.runAttempt}`) result = fixture.target;
      else if (path === prefix + `/actions/runs/${fixture.publisher.id}` ||
        path === prefix + `/actions/runs/${fixture.publisher.id}/attempts/1`) {
        if (fixture.pending > 0) {
          fixture.pending--;
          result = { ...fixture.publisher, status: 'in_progress', conclusion: null };
        } else result = fixture.publisher;
      } else if (path === prefix + `/actions/runs/${fixture.publisher.id}/attempts/1/jobs` ||
        path === prefix + `/actions/runs/${fixture.publisher.id}/jobs`) result = fixture.jobs;
      else if (path === prefix + '/actions/artifacts') {
        expect(query.name).toBe(fixture.artifact.name);
        expect(query.page === undefined || query.page === 1).toBe(true);
        expect(query.per_page).toBeUndefined();
        if (fixture.absent > 0) {
          fixture.absent--;
          result = { total_count: 0, artifacts: [] };
        } else result = fixture.artifacts;
      } else if (path === prefix + `/actions/artifacts/${fixture.artifact.id}`) {
        result = fixture.refreshedArtifact ?? fixture.artifact;
      } else if (path === prefix + `/actions/artifacts/${fixture.artifact.id}/zip`) {
        return { status: 302, body: Buffer.alloc(0), location: fixture.location };
      } else throw new Error('HELD_UNDECLARED_ENDPOINT');
      return { status: fixture.apiStatus,
        body: fixture.rawResponse ?? Buffer.from(JSON.stringify(result)), location: null };
    },
    storageGet: async (url, signal) => {
      fixture.calls.push({ port: 'storageGet', args: [url], signal });
      fixture.monotonic++;
      if (signal.aborted) throw new Error('HELD_ABORTED');
      return { status: fixture.storageStatus, body: fixture.archive };
    },
    readZipMember: async (bytes, member, limit, signal) => {
      fixture.calls.push({ port: 'readZipMember', args: [bytes, member, limit], signal });
      fixture.monotonic++;
      if (signal.aborted) throw new Error('HELD_ABORTED');
      if (fixture.zipHook) return fixture.zipHook();
      if (member !== 'readiness.json' || limit !== NATIVE_DB_VALIDATION.timeoutQueryMaxBytes) throw new Error('HELD_ZIP_BOUND');
      const archiveBytes = Buffer.from(bytes);
      const end = archiveBytes.length - 22;
      if (end < 0 || archiveBytes.readUInt32LE(end) !== 0x06054b50 ||
        archiveBytes.readUInt16LE(end + 10) !== 1) throw new Error('HELD_ZIP_STRUCTURE');
      const central = archiveBytes.readUInt32LE(end + 16);
      if (archiveBytes.readUInt32LE(central) !== 0x02014b50) throw new Error('HELD_ZIP_STRUCTURE');
      const flags = archiveBytes.readUInt16LE(central + 8);
      const compression = archiveBytes.readUInt16LE(central + 10);
      const mode = archiveBytes.readUInt32LE(central + 38) >>> 16;
      const nameLength = archiveBytes.readUInt16LE(central + 28);
      const name = archiveBytes.subarray(central + 46, central + 46 + nameLength).toString('utf8');
      if (flags !== 0 || (compression !== 0 && compression !== 8) ||
        (mode & 0o170000) !== 0o100000 || name !== member) throw new Error('HELD_ZIP_MEMBER');
      const local = archiveBytes.readUInt32LE(central + 42);
      const size = archiveBytes.readUInt32LE(central + 20);
      const start = local + 30 + archiveBytes.readUInt16LE(local + 26) + archiveBytes.readUInt16LE(local + 28);
      const encoded = archiveBytes.subarray(start, start + size);
      const decoded = compression === 8 ? inflateRawSync(encoded, { maxOutputLength: limit }) : encoded;
      if (decoded.length > limit || decoded.length !== archiveBytes.readUInt32LE(central + 24)) throw new Error('HELD_ZIP_SIZE');
      return decoded;
    },
    utcNow: () => fixture.utc,
    monotonicNow: () => fixture.monotonic,
    pause: async (ms, signal) => {
      fixture.calls.push({ port: 'pause', args: [ms], signal });
      if (signal.aborted || !Number.isFinite(ms) || ms <= 0 || ms > NATIVE_DB_VALIDATION.processStopGraceMs) throw new Error('HELD_WAIT_BOUND');
      fixture.monotonic += ms;
      fixture.utc += ms;
    },
  };
  return Object.assign(fixture, { ports });
}

afterEach(() => vi.useRealTimers());

describe('DBV-008/009 independent runtime publication', () => {
  it('HPR001', async () => {
    const api = await heldReadinessModule();
    const f = heldReadinessFixture();
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload, null, 2), now: f.utc }))
      .toEqual({ artifactName: f.artifact.name, member: 'readiness.json', body: f.canonical.toString('utf8') });
    expect(f.calls).toEqual([]);
  });

  it('HPR002', async () => {
    const api = await heldReadinessModule();
    const f = heldReadinessFixture();
    const ordered = { runner: f.runner, expiresAt: f.payload.expiresAt,
      verifiedAt: f.payload.verifiedAt, formatVersion: f.payload.formatVersion };
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(ordered), now: f.utc })?.body)
      .toBe(JSON.stringify(ordered) + '\n');
  });

  it.each([
    ['repository', 'OGUN01/another'], ['eventName', 'pull_request'], ['ref', 'refs/heads/dev'],
    ['sourceSha', 'ABCDEF'], ['runId', '074102938561'], ['runAttempt', '0'],
    ['workflowRef', 'OGUN01/gymloop/.github/workflows/db.yml@refs/heads/dev'], ['unknown', true],
  ])('HPR003 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f.job, key, value);
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now: f.utc })).toBeNull();
  });

  it.each([
    ['id', 0], ['id', Number.MAX_SAFE_INTEGER + 1], ['status', 'offline'], ['busy', true],
    ['ephemeral', false], ['guardVerified', false], ['guardVerified', 1], ['label', 'self-hosted'],
    ['sourceSha', 'f'.repeat(40)], ['runId', '74102938562'], ['runAttempt', '1'], ['extra', 1],
  ])('HPR004 %s %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f.runner, key, value);
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now: f.utc })).toBeNull();
  });

  it.each([
    ['formatVersion', 2], ['verifiedAt', '2026-10-08T13:00:00Z'], ['verifiedAt', '2026-02-30T13:00:00.000Z'],
    ['verifiedAt', heldReadinessDate(7_000)], ['verifiedAt', heldReadinessDate(-NATIVE_DB_VALIDATION.readinessMaxAgeMs)],
    ['expiresAt', heldReadinessDate(6_375)], ['expiresAt', heldReadinessDate(-1)],
    ['expiresAt', heldReadinessDate(NATIVE_DB_VALIDATION.readinessMaxAgeMs + 1)],
    ['runner', null], ['extra', true],
  ])('HPR005 %s %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f.payload, key, value);
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now: f.utc })).toBeNull();
  });

  it.each(['', '{', 'null', '[]', 'true', '{"formatVersion":1}', '{"__proto__":{}}'])('HPR006', async (readiness) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness, now: f.utc })).toBeNull();
  });

  it.each([NaN, Infinity, -1, 0.5, Number.MAX_SAFE_INTEGER + 1, '2026-10-08', null])('HPR007', async (now) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now })).toBeNull();
  });

  it('HPR008', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); const getter = vi.fn(() => f.job);
    const input = { readiness: JSON.stringify(f.payload), now: f.utc };
    Object.defineProperty(input, 'job', { enumerable: true, get: getter });
    expect(api.createNativeRunnerReadinessPublication(input)).toBeNull(); expect(getter).not.toHaveBeenCalled();
    const input2 = { job: f.job, readiness: JSON.stringify(f.payload), now: f.utc, [Symbol('held')]: true };
    expect(api.createNativeRunnerReadinessPublication(input2)).toBeNull();
    expect(api.createNativeRunnerReadinessPublication(Object.assign(Object.create({}), input2))).toBeNull();
  });

  it('HPR009', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    f.utc = Date.parse(heldReadinessDate()) + NATIVE_DB_VALIDATION.readinessMaxAgeMs - 1;
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now: f.utc })).not.toBeNull();
    f.utc++;
    expect(api.createNativeRunnerReadinessPublication({ job: f.job, readiness: JSON.stringify(f.payload), now: f.utc })).toBeNull();
  });
});

describe('DBV-008/009 independent runtime transport', () => {
  it('HRT001', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toEqual(f.runner);
    expect(f.calls.filter(call => call.port === 'storageGet')).toHaveLength(1);
    expect(f.calls.filter(call => call.port === 'readZipMember')).toHaveLength(1);
    expect(f.calls.every(call => call.signal instanceof AbortSignal)).toBe(true);
    expect(f.calls.filter(call => call.port === 'apiGet').every(call => String(call.args[0]).startsWith('/repos/OGUN01/gymloop'))).toBe(true);
  });

  it.each([null, JSON.stringify({ verifiedAt: heldReadinessDate(-NATIVE_DB_VALIDATION.readinessMaxAgeMs), runner: null })])('HRT002', async (legacyContext) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.absent = 2;
    Object.defineProperty(globalThis, '__heldLegacyNativeContext', { value: legacyContext, configurable: true });
    try {
      expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toEqual(f.runner);
      expect(f.calls.filter(call => call.port === 'pause')).toHaveLength(2);
    } finally { Reflect.deleteProperty(globalThis, '__heldLegacyNativeContext'); }
  });

  it('HRT003', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.pending = 1;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toEqual(f.runner);
    expect(f.calls.filter(call => call.port === 'pause')).toHaveLength(1);
  });

  it.each([
    ['repository', 'OGUN01/another'], ['eventName', 'pull_request_target'], ['ref', 'refs/heads/other'],
    ['sourceSha', 'x'.repeat(40)], ['runId', '-1'], ['runAttempt', '02'], ['workflowRef', 'fake'], ['extra', true],
  ])('HRT004 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); heldReadinessReplace(f.job, key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull(); expect(f.calls).toEqual([]);
  });

  it('HRT005', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); const getter = vi.fn(() => f.job);
    const input = {}; Object.defineProperty(input, 'job', { enumerable: true, get: getter });
    expect(await api.resolveNativeRunnerReadiness(input, f.ports)).toBeNull(); expect(getter).not.toHaveBeenCalled(); expect(f.calls).toEqual([]);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job, runner: f.runner }, f.ports)).toBeNull();
    const portGetter = vi.fn(() => f.ports.apiGet); const hostile = { ...f.ports };
    Object.defineProperty(hostile, 'apiGet', { enumerable: true, get: portGetter });
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, hostile)).toBeNull(); expect(portGetter).not.toHaveBeenCalled();
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, { ...f.ports, extra: () => true })).toBeNull();
  });

  it.each([
    ['repository', 'id', 0], ['repository', 'full_name', 'ogun01/gymloop'],
    ['workflow', 'id', -1], ['workflow', 'path', '.github/workflows/other.yml'], ['workflow', 'state', 'disabled_manually'],
    ['target', 'id', 74102938562], ['target', 'run_attempt', 1], ['target', 'head_sha', 'f'.repeat(40)],
    ['target', 'head_branch', 'dev'], ['target', 'path', '.github/workflows/other.yml'],
    ['target', 'event', 'pull_request'], ['target', 'status', 'completed'],
    ['target', 'repository', { id: 1, full_name: 'OGUN01/gymloop' }],
    ['target', 'head_repository', { id: 810527493, full_name: 'fork/gymloop' }],
    ['publisher', 'id', 0], ['publisher', 'run_attempt', 2], ['publisher', 'workflow_id', 1],
    ['publisher', 'path', '.github/workflows/other.yml'], ['publisher', 'event', 'push'],
    ['publisher', 'head_sha', 'e'.repeat(40)], ['publisher', 'head_branch', 'topic'],
    ['publisher', 'repository', { id: 1, full_name: 'OGUN01/gymloop' }],
    ['publisher', 'head_repository', { id: 810527493, full_name: 'fork/gymloop' }],
    ['publisher', 'actor', { login: 'somebody' }], ['publisher', 'triggering_actor', { login: 'somebody' }],
    ['publisher', 'status', 'completed'],
  ])('HRT006 %s %s', async (section, key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f[section as 'repository' | 'workflow' | 'target' | 'publisher'], key, value);
    if (section === 'publisher' && key === 'status') f.publisher.conclusion = 'failure';
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'storageGet')).toEqual([]);
  });

  it.each([
    ['total_count', 2], ['total_count', -1], ['total_count', 0.5], ['total_count', '1'],
    ['artifacts', []], ['artifacts', [null]], ['artifacts', [null, null]],
  ])('HRT007 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); heldReadinessReplace(f.artifacts, key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'pause' || call.port === 'storageGet')).toEqual([]);
  });

  it.each([
    ['id', 0], ['id', Number.MAX_SAFE_INTEGER + 1], ['name', 'native-db-readiness-unbound'],
    ['expired', true], ['expired', 'false'], ['size_in_bytes', 0],
    ['size_in_bytes', NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1], ['size_in_bytes', 1.5],
    ['digest', 'SHA256:' + '1'.repeat(64)], ['digest', 'sha256:' + 'A'.repeat(64)],
    ['digest', 'sha256:' + 'a'.repeat(63)], ['workflow_run', null],
    ['expires_at', '2026-10-08T13:00:06Z'],
  ])('HRT008 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); heldReadinessReplace(f.artifact, key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'storageGet')).toEqual([]);
  });

  it.each([
    ['id', 0], ['repository_id', 1], ['head_repository_id', 1], ['head_branch', 'dev'], ['head_sha', 'a'.repeat(40)],
  ])('HRT009 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f.artifact.workflow_run as HeldReadinessRecord, key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each([
    ['name', 'Publish unverified readiness'], ['status', 'in_progress'], ['conclusion', 'failure'],
    ['started_at', null], ['completed_at', '2026-10-08T13:00:00Z'], ['run_attempt', 2],
  ])('HRT010 %s', async (key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace((f.jobs.jobs as HeldReadinessRecord[])[0], key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each(['Produce bound readiness', 'Retain bound readiness'])('HRT011 %s', async (name) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    const steps = ((f.jobs.jobs as HeldReadinessRecord[])[0].steps as HeldReadinessRecord[]);
    const step = steps.find(item => item.name === name)!; step.conclusion = 'failure';
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each(['jobs', 'steps'])('HRT012 %s', async (where) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    const jobs = f.jobs.jobs as HeldReadinessRecord[];
    if (where === 'jobs') { jobs.push(structuredClone(jobs[0])); f.jobs.total_count = jobs.length; }
    else (jobs[0].steps as HeldReadinessRecord[]).push(structuredClone((jobs[0].steps as HeldReadinessRecord[])[1]));
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each([
    ['target', 'created_at', heldReadinessDate(1)], ['target', 'run_started_at', heldReadinessDate(1)],
    ['publisher', 'created_at', '2026-10-08T12:59:59Z'], ['publisher', 'updated_at', '2026-10-08T13:00:03Z'],
    ['publisher', 'updated_at', '2026-10-08T13:05:00Z'], ['publisher', 'updated_at', '2026-10-08T13:00:08Z'],
    ['artifact', 'created_at', '2026-10-08T13:00:02Z'], ['artifact', 'updated_at', '2026-10-08T13:00:05Z'],
    ['artifact', 'created_at', '2026-02-30T13:00:03Z'], ['publisher', 'created_at', '2026-10-08T13:00:00+00:00'],
  ])('HRT013 %s %s', async (section, key, value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessReplace(f[section as 'target' | 'publisher' | 'artifact'], key, value);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each(['name', 'id', 'size_in_bytes', 'digest', 'created_at', 'updated_at'])('HRT014 %s', async (field) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.refreshedArtifact = { ...f.artifact };
    const changes: HeldReadinessRecord = { name: 'changed', id: 3927426872, size_in_bytes: f.archive.length + 1,
      digest: 'sha256:' + '1'.repeat(64), created_at: '2026-10-08T13:00:04Z', updated_at: '2026-10-08T13:00:04Z' };
    f.refreshedArtifact[field] = changes[field];
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'storageGet')).toEqual([]);
  });

  it.each([404, 403, 500, 201, 302])('HRT015', async (status) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.apiStatus = status;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'pause')).toEqual([]);
  });

  it.each(['{', 'null', '[]', '\ufeff{}', 'x'.repeat(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1)])('HRT016', async (raw) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.rawResponse = Buffer.from(raw);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'pause')).toEqual([]);
  });

  it.each([null, '', 'http://storage.example/file', 'https://user:password@storage.example/file',
    'https://storage.example/file#fragment', '/relative', 'https://storage.example/a\r\nb'])('HRT017', async (location) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.location = location;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'storageGet')).toEqual([]);
  });

  it.each([301, 200, 307, 404])('HRT018', async (status) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    f.apiHook = path => path.endsWith('/zip') ? { status, body: Buffer.alloc(0), location: f.location } : undefined;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each([302, 404, 500])('HRT019', async (status) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.storageStatus = status;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'readZipMember')).toEqual([]);
  });

  it.each(['empty', 'size', 'digest', 'oversized'])('HRT020 %s', async (kind) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    if (kind === 'empty') f.archive = Buffer.alloc(0);
    if (kind === 'size') f.archive = Buffer.concat([f.archive, Buffer.from([0])]);
    if (kind === 'digest') f.archive[f.archive.length - 1] ^= 1;
    if (kind === 'oversized') f.archive = Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1);
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'readZipMember')).toEqual([]);
  });

  it.each(['directory', 'symlink', 'extra', 'encrypted', 'compression', 'escape', 'wrong'])('HRT021 %s', async (kind) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    const entry = { body: f.canonical } as { body: Buffer; name?: string; mode?: number; flags?: number; compression?: number };
    if (kind === 'directory') { entry.name = 'readiness.json/'; entry.mode = 0o040700; }
    if (kind === 'symlink') entry.mode = 0o120777;
    if (kind === 'encrypted') entry.flags = 1;
    if (kind === 'compression') entry.compression = 12;
    if (kind === 'escape') entry.name = '../readiness.json';
    if (kind === 'wrong') entry.name = 'other.json';
    f.archive = heldReadinessZip(kind === 'extra' ? [entry, { name: 'extra', body: Buffer.from('x') }] : [entry]);
    f.artifact.size_in_bytes = f.archive.length; f.artifact.digest = 'sha256:' + createHash('sha256').update(f.archive).digest('hex');
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it('HRT022', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    f.archive = heldReadinessZip([{ body: f.canonical, compression: 8 }]);
    f.artifact.size_in_bytes = f.archive.length; f.artifact.digest = 'sha256:' + createHash('sha256').update(f.archive).digest('hex');
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toEqual(f.runner);
  });

  it.each(['spaces', 'no-lf', 'two-lf', 'bom', 'invalid-utf8', 'oversized-decoded'])('HRT023 %s', async (kind) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    const alternatives: Record<string, Buffer> = {
      spaces: Buffer.from(JSON.stringify(f.payload, null, 2) + '\n'),
      'no-lf': Buffer.from(JSON.stringify(f.payload)), 'two-lf': Buffer.from(JSON.stringify(f.payload) + '\n\n'),
      bom: Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), f.canonical]),
      'invalid-utf8': Buffer.concat([f.canonical, Buffer.from([0xff])]),
      'oversized-decoded': Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1, 32),
    };
    f.archive = heldReadinessZip([{ body: alternatives[kind], compression: kind === 'oversized-decoded' ? 8 : 0 }]);
    f.artifact.size_in_bytes = f.archive.length; f.artifact.digest = 'sha256:' + createHash('sha256').update(f.archive).digest('hex');
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each(['verifiedAt', 'expiresAt', 'runner'])('HRT024 %s', async (kind) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    heldReadinessMutate(f, payload => {
      if (kind === 'verifiedAt') payload.verifiedAt = heldReadinessDate(7_000);
      if (kind === 'expiresAt') payload.expiresAt = heldReadinessDate(6_375);
      if (kind === 'runner') (payload.runner as HeldReadinessRecord).guardVerified = false;
    });
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it('HRT025', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.absent = Infinity;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.monotonic).toBeLessThanOrEqual(NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
    expect(f.calls.filter(call => call.port === 'pause').length).toBeGreaterThan(0);
    expect(f.calls.filter(call => call.port === 'pause').every(call => Number(call.args[0]) <= NATIVE_DB_VALIDATION.processStopGraceMs)).toBe(true);
  });

  it('HRT026', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); vi.useFakeTimers();
    f.ports.apiGet = (path, query, signal) => {
      f.calls.push({ port: 'apiGet', args: [path, query], signal });
      return new Promise(() => undefined);
    };
    const answer = api.resolveNativeRunnerReadiness({ job: f.job }, f.ports);
    await vi.advanceTimersByTimeAsync(NATIVE_DB_VALIDATION.processStopGraceMs + 1);
    expect(await answer).toBeNull(); expect(f.calls).toHaveLength(1); expect(f.calls[0].signal.aborted).toBe(true);
  });

  it('HRT027', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); vi.useFakeTimers(); f.absent = 1;
    f.ports.pause = (ms, signal) => {
      f.calls.push({ port: 'pause', args: [ms], signal }); return new Promise(() => undefined);
    };
    const answer = api.resolveNativeRunnerReadiness({ job: f.job }, f.ports);
    await vi.advanceTimersByTimeAsync(NATIVE_DB_VALIDATION.processStopGraceMs + 1);
    expect(await answer).toBeNull(); expect(f.calls.find(call => call.port === 'pause')?.signal.aborted).toBe(true);
  });

  it('HRT028', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.absent = 1;
    f.ports.pause = async (ms, signal) => {
      f.calls.push({ port: 'pause', args: [ms], signal }); f.monotonic = NATIVE_DB_VALIDATION.nativeCleanupReserveMs;
    };
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.filter(call => call.port === 'storageGet')).toEqual([]);
  });

  it.each([NaN, Infinity, -1])('HRT029', async (value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.ports.monotonicNow = () => value;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull(); expect(f.calls).toEqual([]);
  });

  it('HRT030', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); let reads = 0;
    f.ports.monotonicNow = () => ++reads === 1 ? 10 : 9;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
    expect(f.calls.length).toBeLessThanOrEqual(1);
  });

  it.each([NaN, Infinity, -1, 0.5])('HRT031', async (value) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); f.ports.utcNow = () => value;
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it.each(['apiGet', 'storageGet', 'readZipMember', 'pause'])('HRT032 %s', async (port) => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture(); if (port === 'pause') f.absent = 1;
    Reflect.set(f.ports, port, async () => { throw new Error('HELD_SYNTHETIC_FAILURE'); });
    expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toBeNull();
  });

  it('HRT033', async () => {
    const api = await heldReadinessModule(); const f = heldReadinessFixture();
    const streams = [vi.spyOn(console, 'log'), vi.spyOn(console, 'error'), vi.spyOn(console, 'warn')];
    try {
      expect(await api.resolveNativeRunnerReadiness({ job: f.job }, f.ports)).toEqual(f.runner);
      expect(streams.every(spy => spy.mock.calls.length === 0)).toBe(true);
      expect(Object.keys(f.ports)).toHaveLength(6);
      for (const call of f.calls.filter(item => item.port === 'storageGet')) expect(call.args).toEqual([f.location]);
    } finally { streams.forEach(spy => spy.mockRestore()); }
  });
});

async function executeHeldNativeRunnerReadinessPublisher(options: {
  context?: HeldReadinessRecord; publisher?: HeldReadinessRecord; target?: HeldReadinessRecord;
  readiness?: string; writeFailure?: boolean;
} = {}) {
  let workflow = '';
  try { workflow = await readFile(new URL('../../.github/workflows/native-runner-readiness.yml', import.meta.url), 'utf8'); }
  catch (error) { if ((error as { code?: string }).code !== 'ENOENT') throw error; }
  expect(workflow.length).toBeGreaterThan(0);
  const lines = workflow.split(/\r?\n/);
  const produce = lines.findIndex(line => /^\s*- name:\s*Produce bound readiness\s*$/.test(line));
  expect(produce).toBeGreaterThanOrEqual(0);
  const script = lines.findIndex((line, index) => index > produce && /^\s+script:\s*\|\s*$/.test(line));
  expect(script).toBeGreaterThan(produce);
  const indentation = lines[script].match(/^\s*/)?.[0].length ?? 0;
  const body: string[] = [];
  for (const line of lines.slice(script + 1)) {
    const leading = line.match(/^\s*/)?.[0].length ?? 0;
    if (line.trim() && leading <= indentation) break;
    body.push(line.slice(indentation + 2));
  }
  expect(body.length).toBeGreaterThan(0);
  const f = heldReadinessFixture();
  const publisher = { ...f.publisher, ...options.publisher };
  const target = { ...f.target, ...options.target };
  const context: HeldReadinessRecord = {
    repo: { owner: 'OGUN01', repo: 'gymloop' }, runId: f.publisher.id,
    eventName: 'workflow_dispatch', sha: f.job.sourceSha, ref: 'refs/heads/main', actor: 'OGUN01',
    payload: { inputs: { readiness: options.readiness ?? JSON.stringify(f.payload) },
      repository: { full_name: 'OGUN01/gymloop' } }, ...options.context,
  };
  const calls: { name: string; args: unknown[] }[] = [];
  const files: { name: string; args: unknown[] }[] = [];
  const outputs: HeldReadinessRecord = {};
  const errors: unknown[] = [];
  const github = { rest: { actions: {
    getWorkflowRun: async (...args: unknown[]) => { calls.push({ name: 'producer', args }); return { data: publisher }; },
    getWorkflowRunAttempt: async (...args: unknown[]) => { calls.push({ name: 'target', args }); return { data: target }; },
  } } };
  const core = {
    setOutput: (key: string, value: unknown) => { outputs[key] = value; },
    setFailed: (error: unknown) => { errors.push(error); },
    info: (value: unknown) => { calls.push({ name: 'info', args: [value] }); },
    warning: (value: unknown) => { calls.push({ name: 'warning', args: [value] }); },
    error: (value: unknown) => { calls.push({ name: 'error', args: [value] }); },
  };
  const filesystem = {
    mkdir: async (...args: unknown[]) => { files.push({ name: 'mkdir', args }); },
    writeFile: async (...args: unknown[]) => {
      files.push({ name: 'writeFile', args }); if (options.writeFailure) throw new Error('HELD_EXCLUSIVE_WRITE_FAILURE');
    },
  };
  const heldImports = async (moduleName: string) => {
    if (moduleName.includes('runner-readiness.mjs')) return heldReadinessModule();
    if (moduleName.includes('constants')) return { NATIVE_DB_VALIDATION };
    if (moduleName === 'node:fs/promises') return filesystem;
    if (moduleName === 'node:path') return import('node:path');
    throw new Error('HELD_UNDECLARED_IMPORT');
  };
  const execute = Object.getPrototypeOf(async () => undefined).constructor;
  const injectedDate = class extends Date {
    constructor(value?: string | number) { super(value ?? f.utc); }
    static now() { return f.utc; }
  };
  const source = body.join('\n').replace(/\bimport\s*\(/g, 'heldImports(');
  try {
    await execute('github', 'context', 'core', 'heldImports', 'Date', 'Buffer', 'console', source)(
      github, context, core, heldImports, injectedDate, Buffer,
      { log: (...args: unknown[]) => calls.push({ name: 'console', args }), error: (...args: unknown[]) => calls.push({ name: 'console', args }) },
    );
  } catch (error) { errors.push(error); }
  return { workflow, context, target, publisher, calls, files, outputs, errors, fixture: f };
}

describe('DBV-008/012 independent publisher wiring', () => {
  it('HPW001', async () => {
    const { workflow } = await executeHeldNativeRunnerReadinessPublisher();
    expect(workflow).toMatch(/workflow_dispatch:/);
    expect(workflow).toMatch(/readiness:[\s\S]*?required:\s*true/);
    expect(workflow).toMatch(/contents:\s*read/); expect(workflow).toMatch(/actions:\s*read/);
    expect(workflow).toMatch(/name:\s*Publish verified readiness/);
    expect(workflow).toMatch(/runs-on:\s*ubuntu-latest/);
    expect(workflow).not.toMatch(/\b(?:pull_request|push|schedule|workflow_run|repository_dispatch):/);
    expect(workflow).not.toMatch(/\b(?:secrets|environment|services|concurrency):/);
    expect(workflow).not.toMatch(/\$\{\{\s*secrets\./);
    expect(workflow).not.toMatch(/(?:supabase\s+(?:link|test|db|migration)|\bpsql\b|\bexecute_sql\b|\bapply_migration\b)/);
  });

  it('HPW002', async () => {
    const { workflow } = await executeHeldNativeRunnerReadinessPublisher();
    expect(workflow).toMatch(/name:\s*Produce bound readiness/); expect(workflow).toMatch(/name:\s*Retain bound readiness/);
    expect(workflow).toMatch(/uses:\s*actions\/upload-artifact@v5/);
    expect(workflow).toMatch(/path:\s*\.native-db-readiness\/readiness\.json/);
    expect(workflow).toMatch(/if-no-files-found:\s*error/);
    expect(workflow).not.toMatch(/overwrite:\s*true/);
    expect(workflow).not.toMatch(/\$\{\{[^}]*inputs\.readiness[^}]*\}\}/);
    expect(workflow).toMatch(/createNativeRunnerReadinessPublication/);
  });

  it('HPW003', async () => {
    const { workflow } = await executeHeldNativeRunnerReadinessPublisher();
    expect(workflow).toMatch(/OGUN01\/gymloop/); expect(workflow).toMatch(/refs\/heads\/main/);
    expect(workflow).toMatch(/triggering_actor/); expect(workflow).toMatch(/run_attempt/);
    expect(workflow).toMatch(/\.github\/workflows\/db\.yml/);
    expect(workflow).toMatch(/in_progress/);
    expect(workflow).not.toMatch(/github\.(?:request|rest)\([^\n]*\b(?:POST|PUT|PATCH|DELETE)\b/);
  });

  it('HPW004', async () => {
    let workflow = '';
    try { workflow = await readFile(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8'); }
    catch (error) { if ((error as { code?: string }).code !== 'ENOENT') throw error; }
    expect(workflow).toContain('.github/workflows/native-runner-readiness.yml');
    expect(workflow).toContain('resolveNativeRunnerReadiness');
  });

  it('HPW005', async () => {
    const result = await executeHeldNativeRunnerReadinessPublisher();
    expect(result.errors).toEqual([]);
    expect(result.calls.filter(call => call.name === 'producer')).toHaveLength(1);
    expect(result.calls.filter(call => call.name === 'target')).toHaveLength(1);
    expect(result.files.map(file => file.name)).toEqual(['mkdir', 'writeFile']);
    const [directory, file] = result.files;
    expect(String(directory.args[0]).replaceAll('\\', '/')).toMatch(/(?:^|\/)\.native-db-readiness$/);
    expect(directory.args[1]).toEqual(expect.objectContaining({ mode: NATIVE_DB_VALIDATION.privateDirectoryMode }));
    expect((directory.args[1] as HeldReadinessRecord).recursive).not.toBe(true);
    expect(String(file.args[0]).replaceAll('\\', '/')).toMatch(/(?:^|\/)\.native-db-readiness\/readiness\.json$/);
    expect(String(file.args[1])).toBe(result.fixture.canonical.toString('utf8'));
    expect(file.args[2]).toEqual(expect.objectContaining({ flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode }));
    expect(result.outputs).toEqual({ artifact_name: result.fixture.artifact.name,
      retention_days: NATIVE_DB_VALIDATION.artifactRetentionDays });
    const targetCall = result.calls.find(call => call.name === 'target');
    expect(targetCall?.args).toEqual([expect.objectContaining({ owner: 'OGUN01', repo: 'gymloop',
      run_id: Number(result.fixture.job.runId), attempt_number: Number(result.fixture.job.runAttempt) })]);
  });

  it.each([
    ['actor', { login: 'other' }], ['triggering_actor', { login: 'other' }], ['run_attempt', 2],
    ['head_sha', 'f'.repeat(40)], ['head_branch', 'other'], ['event', 'push'],
    ['repository', { id: 810527493, full_name: 'fork/gymloop' }],
  ])('HPW006 %s', async (key, value) => {
    const result = await executeHeldNativeRunnerReadinessPublisher({ publisher: { [key]: value } });
    expect(result.errors.length).toBeGreaterThan(0); expect(result.files).toEqual([]); expect(result.outputs).toEqual({});
  });

  it.each([
    ['id', 74102938562], ['run_attempt', 1], ['head_sha', 'f'.repeat(40)], ['head_branch', 'other'],
    ['path', '.github/workflows/other.yml'], ['status', 'completed'], ['event', 'pull_request'],
    ['repository', { id: 810527493, full_name: 'fork/gymloop' }],
    ['head_repository', { id: 810527493, full_name: 'fork/gymloop' }],
  ])('HPW007 %s', async (key, value) => {
    const result = await executeHeldNativeRunnerReadinessPublisher({ target: { [key]: value } });
    expect(result.errors.length).toBeGreaterThan(0); expect(result.files).toEqual([]); expect(result.outputs).toEqual({});
  });

  it.each([
    ['eventName', 'push'], ['ref', 'refs/heads/other'], ['actor', 'other'],
    ['repo', { owner: 'other', repo: 'gymloop' }],
  ])('HPW008 %s', async (key, value) => {
    const result = await executeHeldNativeRunnerReadinessPublisher({ context: { [key]: value } });
    expect(result.errors.length).toBeGreaterThan(0); expect(result.files).toEqual([]); expect(result.outputs).toEqual({});
  });

  it.each(['{', 'null', '[]', '{"runner":{"runId":"$(echo forbidden)"}}'])('HPW009', async (readiness) => {
    const result = await executeHeldNativeRunnerReadinessPublisher({ readiness });
    expect(result.errors.length).toBeGreaterThan(0); expect(result.files).toEqual([]); expect(result.outputs).toEqual({});
  });

  it('HPW010', async () => {
    const result = await executeHeldNativeRunnerReadinessPublisher({ writeFailure: true });
    expect(result.errors.length).toBeGreaterThan(0); expect(result.outputs).toEqual({});
  });
});
