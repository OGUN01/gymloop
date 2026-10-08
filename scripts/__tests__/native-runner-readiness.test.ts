import { createHash } from 'node:crypto';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

// Independently authored from the frozen runtime-readiness-artifact.md contract.
// No production implementation or another author's suite was read to construct it.
function executeNativeRunnerReadinessPublisher() {
  const job = {
    repository: NATIVE_DB_VALIDATION.repository,
    eventName: 'push',
    ref: NATIVE_DB_VALIDATION.mainRef,
    sourceSha: 'abc123def4567890abc123def4567890abc123de',
    runId: '801001',
    runAttempt: '2',
    workflowRef: NATIVE_DB_VALIDATION.workflowRef,
  };
  const runner = {
    id: 902001,
    status: 'online',
    busy: false,
    ephemeral: true,
    guardVerified: true,
    label: `${NATIVE_DB_VALIDATION.labelPrefix}-${job.runId}-${job.runAttempt}-${job.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`,
    sourceSha: job.sourceSha,
    runId: job.runId,
    runAttempt: job.runAttempt,
  };
  const readiness = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    verifiedAt: '2026-10-08T12:00:00.750Z',
    expiresAt: '2026-10-08T12:05:00.750Z',
    runner,
  };
  const now = Date.parse('2026-10-08T12:00:10.750Z');
  const body = Buffer.from(`${JSON.stringify(readiness)}\n`);
  const name = `native-db-readiness-${job.runId}-${job.runAttempt}-${job.sourceSha}`;
  const repository = { id: 701001, full_name: NATIVE_DB_VALIDATION.repository, name: 'gymloop', owner: { login: 'OGUN01' } };
  const workflow = { id: 701002, path: '.github/workflows/native-runner-readiness.yml', state: 'active' };
  const target = {
    id: Number(job.runId), run_attempt: Number(job.runAttempt), workflow_id: 701003,
    head_sha: job.sourceSha, head_branch: 'main', path: '.github/workflows/db.yml',
    event: 'push', status: 'in_progress', conclusion: null,
    repository: structuredClone(repository), head_repository: structuredClone(repository),
    actor: { login: 'OGUN01' }, triggering_actor: { login: 'OGUN01' },
    created_at: '2026-10-08T11:59:00Z', run_started_at: '2026-10-08T11:59:30Z', updated_at: '2026-10-08T12:00:05Z',
  };
  const publisher = {
    id: 801002, run_attempt: 1, workflow_id: workflow.id,
    head_sha: job.sourceSha, head_branch: 'main', path: workflow.path,
    event: 'workflow_dispatch', status: 'completed', conclusion: 'success',
    repository: structuredClone(repository), head_repository: structuredClone(repository),
    actor: { login: 'OGUN01' }, triggering_actor: { login: 'OGUN01' },
    created_at: '2026-10-08T12:00:00Z', run_started_at: '2026-10-08T12:00:01Z', updated_at: '2026-10-08T12:00:04Z',
  };
  const publisherJob = {
    id: 801003, run_id: publisher.id, run_attempt: 1,
    head_sha: job.sourceSha,
    name: 'Publish verified readiness', status: 'completed', conclusion: 'success',
    started_at: '2026-10-08T12:00:01Z', completed_at: '2026-10-08T12:00:04Z',
    steps: [
      { name: 'Set up job', number: 1, status: 'completed', conclusion: 'success', started_at: '2026-10-08T12:00:01Z', completed_at: '2026-10-08T12:00:01Z' },
      { name: 'Produce bound readiness', number: 2, status: 'completed', conclusion: 'success', started_at: '2026-10-08T12:00:01Z', completed_at: '2026-10-08T12:00:02Z' },
      { name: 'Retain bound readiness', number: 3, status: 'completed', conclusion: 'success', started_at: '2026-10-08T12:00:02Z', completed_at: '2026-10-08T12:00:03Z' },
      { name: 'Complete job', number: 4, status: 'completed', conclusion: 'success', started_at: '2026-10-08T12:00:04Z', completed_at: '2026-10-08T12:00:04Z' },
    ],
  };
  // Ordinary STORED ZIP, independently constructed without importing project fixtures.
  const filename = Buffer.from('readiness.json');
  let crc = 0xffffffff;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  crc = (crc ^ 0xffffffff) >>> 0;
  const local = Buffer.alloc(30);
  local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4);
  local.writeUInt32LE(crc, 14); local.writeUInt32LE(body.length, 18); local.writeUInt32LE(body.length, 22); local.writeUInt16LE(filename.length, 26);
  const central = Buffer.alloc(46);
  central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
  central.writeUInt32LE(crc, 16); central.writeUInt32LE(body.length, 20); central.writeUInt32LE(body.length, 24); central.writeUInt16LE(filename.length, 28);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(1, 8); end.writeUInt16LE(1, 10);
  end.writeUInt32LE(central.length + filename.length, 12); end.writeUInt32LE(local.length + filename.length + body.length, 16);
  const archive = Buffer.concat([local, filename, body, central, filename, end]);
  const artifact = {
    id: 601001, name, size_in_bytes: archive.length, expired: false,
    digest: `sha256:${createHash('sha256').update(archive).digest('hex')}`,
    expires_at: '2026-10-15T12:00:03Z',
    created_at: '2026-10-08T12:00:02Z', updated_at: '2026-10-08T12:00:03Z',
    workflow_run: { id: publisher.id, repository_id: repository.id, head_repository_id: repository.id, head_branch: 'main', head_sha: job.sourceSha },
  };
  const state = {
    repository, workflow, target, publisher, publisherJob, artifact, archive, member: body,
    listing: { total_count: 1, artifacts: [artifact] },
    jobs: { total_count: 1, jobs: [publisherJob] },
    location: 'https://storage.invalid/verified-readiness.zip?lease=synthetic',
    absentCount: 0, pendingCount: 0, reread: null as null | typeof artifact,
    apiStatus: NATIVE_DB_VALIDATION.artifactMetadataStatus as number,
    storageStatus: NATIVE_DB_VALIDATION.artifactMetadataStatus as number,
    downloadStatus: NATIVE_DB_VALIDATION.artifactRedirectStatus as number,
    stall: '', fail: '', invalidBody: false, monotonic: 0,
    utc: now, monotonicReadings: [] as number[], boundaryAdvance: 0,
    boundaryAdvanceOnce: false,
  };
  const calls: { kind: string; path?: string; query?: unknown; ms?: number; signal?: AbortSignal; filename?: string; maxBytes?: number }[] = [];
  const entered: Record<string, Promise<void>> = {};
  const entryResolvers = new Map<string, () => void>();
  for (const kind of ['api', 'storage', 'zip', 'pause']) {
    entered[kind] = new Promise(resolve => { entryResolvers.set(kind, resolve); });
  }
  const base = `/repos/${NATIVE_DB_VALIDATION.repository}`;
  const origin = Date.now();
  const ports = {
    apiGet: vi.fn(async (path: string, query: Record<string, unknown>, signal: AbortSignal) => {
      calls.push({ kind: 'api', path, query, signal });
      entryResolvers.get('api')?.();
      state.monotonic += state.boundaryAdvance;
      if (state.boundaryAdvanceOnce) state.boundaryAdvance = 0;
      if (state.stall === path || state.stall === 'api') return new Promise<never>(() => {});
      if (state.fail === path || state.fail === 'api') throw new Error('synthetic refusal');
      let value: unknown;
      if (path === base) value = state.repository;
      else if (path === `${base}/actions/workflows/native-runner-readiness.yml` || path === `${base}/actions/workflows/${workflow.id}`) value = state.workflow;
      else if (path === `${base}/actions/runs/${job.runId}/attempts/${job.runAttempt}`) value = state.target;
      else if (path === `${base}/actions/artifacts`) value = state.absentCount-- > 0 ? { total_count: 0, artifacts: [] } : state.listing;
      else if (path === `${base}/actions/artifacts/${artifact.id}`) value = state.reread ?? state.artifact;
      else if (path === `${base}/actions/runs/${publisher.id}` || path === `${base}/actions/runs/${publisher.id}/attempts/1`) {
        value = state.pendingCount-- > 0 ? { ...state.publisher, status: 'in_progress', conclusion: null } : state.publisher;
      } else if (path === `${base}/actions/runs/${publisher.id}/attempts/1/jobs`) value = state.jobs;
      else if (path === `${base}/actions/artifacts/${artifact.id}/zip`) return { status: state.downloadStatus, body: Buffer.alloc(0), location: state.location };
      else throw new Error('undeclared endpoint');
      return { status: state.apiStatus, body: state.invalidBody ? Buffer.from('{') : Buffer.from(JSON.stringify(value)), location: null };
    }),
    storageGet: vi.fn(async (url: string, signal: AbortSignal) => {
      calls.push({ kind: 'storage', path: url, signal });
      entryResolvers.get('storage')?.();
      state.monotonic += state.boundaryAdvance;
      if (state.stall === 'storage') return new Promise<never>(() => {});
      if (state.fail === 'storage') throw new Error('synthetic storage refusal');
      return { status: state.storageStatus, body: state.archive };
    }),
    readZipMember: vi.fn(async (bytes: Uint8Array, member: string, maxBytes: number, signal: AbortSignal) => {
      calls.push({ kind: 'zip', filename: member, maxBytes, signal });
      entryResolvers.get('zip')?.();
      state.monotonic += state.boundaryAdvance;
      if (state.stall === 'zip') return new Promise<never>(() => {});
      if (state.fail === 'zip') throw new Error('synthetic constrained ZIP refusal');
      expect(Buffer.from(bytes)).toEqual(state.archive);
      expect(member).toBe('readiness.json');
      expect(maxBytes).toBe(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes);
      return state.member;
    }),
    utcNow: vi.fn(() => state.utc + state.monotonic + Date.now() - origin),
    monotonicNow: vi.fn(() => state.monotonicReadings.length ? state.monotonicReadings.shift()! : state.monotonic + Date.now() - origin),
    pause: vi.fn(async (ms: number, signal: AbortSignal) => {
      calls.push({ kind: 'pause', ms, signal });
      entryResolvers.get('pause')?.();
      if (state.stall === 'pause') return new Promise<never>(() => {});
      if (state.fail === 'pause') throw new Error('synthetic pause refusal');
      state.monotonic += ms;
    }),
  };
  const load = async () => {
    // Late import keeps all contract cases collected when implementation is absent.
    const moduleUrl = new URL('../pgtap/runner-readiness.mjs', import.meta.url).href;
    const module = await import(/* @vite-ignore */ moduleUrl);
    expect(typeof module.createNativeRunnerReadinessPublication).toBe('function');
    expect(typeof module.resolveNativeRunnerReadiness).toBe('function');
    return module;
  };
  const publication = async (input: unknown = { job, readiness: JSON.stringify(readiness), now }) => (await load()).createNativeRunnerReadinessPublication(input);
  const resolve = async (input: unknown = { job }, suppliedPorts: unknown = ports) => (await load()).resolveNativeRunnerReadiness(input, suppliedPorts);
  const workflowText = () => readFileSync(new URL('../../.github/workflows/native-runner-readiness.yml', import.meta.url), 'utf8');
  const step = (source: string, name: string) => {
    const lines = source.split(/\r?\n/);
    const start = lines.findIndex(line => new RegExp(`^\\s*- name: ["']?${name}["']?\\s*$`).test(line));
    expect(start).toBeGreaterThanOrEqual(0);
    const indentation = lines[start].match(/^\s*/)![0].length;
    let finish = start + 1;
    while (finish < lines.length && !new RegExp(`^\\s{0,${indentation}}- `).test(lines[finish]) && !/^\S/.test(lines[finish])) finish++;
    return lines.slice(start, finish).join('\n');
  };
  const producer = {
    context: {
      repo: { owner: 'OGUN01', repo: 'gymloop' }, eventName: 'workflow_dispatch', actor: 'OGUN01',
      ref: NATIVE_DB_VALIDATION.mainRef, sha: job.sourceSha, runId: publisher.id,
      payload: { inputs: { readiness: JSON.stringify(readiness) } },
    },
    outputs: new Map<string, unknown>(),
    failures: [] as unknown[],
    directories: [] as { path: string; options: Record<string, unknown> }[],
    files: [] as { path: string; body: unknown; options: Record<string, unknown> }[],
    collision: false,
    github: {
      rest: { actions: {
        getWorkflowRun: vi.fn(async (input: unknown) => { void input; return { status: NATIVE_DB_VALIDATION.artifactMetadataStatus, data: { ...state.publisher, status: 'in_progress', conclusion: null } }; }),
        getWorkflowRunAttempt: vi.fn(async (input: unknown) => { void input; return { status: NATIVE_DB_VALIDATION.artifactMetadataStatus, data: state.target }; }),
      } },
    },
  };
  const executeProducer = async () => {
    const section = step(workflowText(), 'Produce bound readiness');
    const lines = section.split('\n');
    const marker = lines.findIndex(line => /^\s*script:\s*\|[+-]?\s*$/.test(line));
    expect(marker).toBeGreaterThanOrEqual(0);
    const indentation = lines[marker].match(/^\s*/)![0].length;
    const selected: string[] = [];
    for (const line of lines.slice(marker + 1)) {
      if (line.trim() && line.match(/^\s*/)![0].length <= indentation) break;
      selected.push(line);
    }
    const margin = Math.min(...selected.filter(line => line.trim()).map(line => line.match(/^\s*/)![0].length));
    const script = selected.map(line => line.slice(margin)).join('\n').replace(/\bimport\s*\(/g, 'fixtureImport(');
    const fs = {
      mkdir: vi.fn(async (path: string, options: Record<string, unknown>) => {
        if (producer.collision) throw new Error('synthetic EEXIST');
        producer.directories.push({ path, options });
      }),
      writeFile: vi.fn(async (path: string, bytes: unknown, options: Record<string, unknown>) => {
        producer.files.push({ path, body: bytes, options });
      }),
      open: vi.fn(async (path: string, flag: string, mode: number) => ({
        writeFile: async (bytes: unknown) => { producer.files.push({ path, body: bytes, options: { flag, mode } }); },
        close: async () => {},
      })),
    };
    const core = {
      setOutput: vi.fn((key: string, value: unknown) => { producer.outputs.set(key, value); }),
      setFailed: vi.fn((value: unknown) => { producer.failures.push(value); }),
      info: vi.fn(), warning: vi.fn(), error: vi.fn(),
    };
    const fixtureImport = async (specifier: unknown) => {
      const spec = String(specifier);
      if (spec.includes('runner-readiness.mjs')) return load();
      if (spec.includes('config/constants')) return { NATIVE_DB_VALIDATION };
      if (spec === 'node:fs/promises' || spec === 'fs/promises') return fs;
      if (spec === 'node:path' || spec === 'path') return import('node:path');
      if (spec === 'node:url' || spec === 'url') return import('node:url');
      throw new Error('undeclared publisher import');
    };
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    try { await new AsyncFunction('context', 'github', 'core', 'fixtureImport', script)(producer.context, producer.github, core, fixtureImport); }
    catch (error) { producer.failures.push(error); }
    return { refused: producer.failures.length > 0, core, fs };
  };
  const selector = {
    captured: null as null | typeof ports,
    input: null as unknown,
    outputs: new Map<string, unknown>(),
    requests: [] as { url: string; options: Record<string, unknown> }[],
    apiBytes: Buffer.from(JSON.stringify(repository)), storageBytes: archive,
    context: { repo: { owner: 'OGUN01', repo: 'gymloop' }, eventName: job.eventName, ref: job.ref, sha: job.sourceSha, runId: Number(job.runId), payload: {} },
  };
  const executeSelector = async () => {
    const source = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    const section = step(source, 'Resolve source-bound online readiness or hosted fallback');
    const lines = section.split('\n'); const marker = lines.findIndex(line => /^\s*script:\s*\|[+-]?\s*$/.test(line));
    expect(marker).toBeGreaterThanOrEqual(0);
    const indentation = lines[marker].match(/^\s*/)![0].length;
    const selected: string[] = [];
    for (const line of lines.slice(marker + 1)) {
      if (line.trim() && line.match(/^\s*/)![0].length <= indentation) break;
      selected.push(line);
    }
    const margin = Math.min(...selected.filter(line => line.trim()).map(line => line.match(/^\s*/)![0].length));
    const expressions: Record<string, string> = { 'github.run_attempt': job.runAttempt, 'github.workflow_ref': job.workflowRef, 'github.event_name': job.eventName, 'github.repository': job.repository, 'github.ref': job.ref, 'github.sha': job.sourceSha, 'github.run_id': job.runId };
    const serializedExpressions: Record<string, string> = {
      'toJSON(github.run_attempt)': JSON.stringify(expressions['github.run_attempt']),
      'toJSON(github.workflow_ref)': JSON.stringify(expressions['github.workflow_ref']),
    };
    const script = selected.map(line => line.slice(margin)).join('\n').replace(/\bimport\s*\(/g, 'fixtureImport(').replace(/\$\{\{\s*([^}]+?)\s*\}\}/g, (_all, expression: string) => expressions[expression.trim()] ?? serializedExpressions[expression.trim()] ?? 'null');
    const fakeFetch = vi.fn(async (url: unknown, options: Record<string, unknown> = {}) => {
      selector.requests.push({ url: String(url), options });
      return new Response(String(url).startsWith('https://api.github.com/') ? selector.apiBytes : selector.storageBytes, { status: NATIVE_DB_VALIDATION.artifactMetadataStatus });
    });
    const github = {
      request: vi.fn(async (route: string, options: Record<string, unknown> = {}) => {
        const path = route.replace(/^GET /, '');
        const request = options.request as { fetch?: typeof fakeFetch; signal?: AbortSignal } | undefined;
        if (request?.fetch) {
          const response = await request.fetch(`https://api.github.com${path}`, { method: 'GET', headers: { authorization: 'Bearer fixture-only' }, signal: request.signal });
          const raw = new Uint8Array(await response.arrayBuffer());
          return { status: response.status, data: JSON.parse(Buffer.from(raw).toString('utf8')), headers: {} };
        }
        selector.requests.push({ url: `https://api.github.com${path}`, options });
        return { status: NATIVE_DB_VALIDATION.artifactMetadataStatus, data: JSON.parse(selector.apiBytes.toString('utf8')), headers: {} };
      }),
    };
    const observeBytes = <T extends object>(response: T): T => {
      const descriptors = Object.getOwnPropertyDescriptors(response);
      const body = descriptors.body;
      if (!body || !('value' in body) || !(body.value instanceof Uint8Array)) throw new Error('Invalid byte observation');
      const bytes = body.value;
      return Object.create(Object.getPrototypeOf(response), {
        ...descriptors,
        body: { ...body, value: new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength) },
      }) as T;
    };
    const fixtureImport = async (specifier: unknown) => {
      const spec = String(specifier);
      if (spec.includes('runner-readiness.mjs')) return { resolveNativeRunnerReadiness: async (input: unknown, concretePorts: typeof ports) => {
        selector.input = input;
        selector.captured = {
          ...concretePorts,
          apiGet: vi.fn(async (...args: Parameters<typeof concretePorts.apiGet>) => observeBytes(await concretePorts.apiGet(...args))),
          storageGet: vi.fn(async (...args: Parameters<typeof concretePorts.storageGet>) => observeBytes(await concretePorts.storageGet(...args))),
        };
        return null;
      } };
      if (spec.includes('runner-job.mjs')) { const moduleUrl = new URL('../pgtap/runner-job.mjs', import.meta.url).href; return import(/* @vite-ignore */ moduleUrl); }
      if (spec.endsWith('/scripts/pgtap/data-record.mjs') || spec.endsWith('\\scripts\\pgtap\\data-record.mjs')) {
        const moduleUrl = new URL('../pgtap/data-record.mjs', import.meta.url).href;
        return import(/* @vite-ignore */ moduleUrl);
      }
      if (spec.includes('config/constants')) return { NATIVE_DB_VALIDATION };
      if (spec === 'node:fs/promises' || spec === 'fs/promises') return { readFile: async () => { throw new Error('undeclared file'); } };
      if (spec.startsWith('node:') && spec !== 'node:fs' && spec !== 'node:child_process') return import(/* @vite-ignore */ spec);
      if (spec === 'node:child_process') return { spawn: (command: string, args: readonly string[], options: Parameters<typeof spawn>[2]) => {
        if (command !== 'python3' && command !== 'python') throw new Error('undeclared extraction executable');
        return spawn(process.platform === 'win32' ? 'python' : command, args, options);
      }, execFileSync: (command: string, args: readonly string[], options: object) => {
        if (command !== 'python3' && command !== 'python') throw new Error('undeclared extraction executable');
        return execFileSync(process.platform === 'win32' ? 'python' : 'python3', args, options);
      } };
      throw new Error('undeclared selector import');
    };
    const core = { setOutput: (key: string, value: unknown) => { selector.outputs.set(key, value); }, setFailed: (reason: unknown) => { throw new Error(String(reason)); }, info: vi.fn(), warning: vi.fn(), error: vi.fn() };
    const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
    await new AsyncFunction('context', 'github', 'core', 'fixtureImport', 'fetch', script)(selector.context, github, core, fixtureImport, fakeFetch);
    expect(selector.captured).not.toBeNull();
    return { concretePorts: selector.captured!, fakeFetch, github, core };
  };
  return { job, runner, readiness, now, body, name, base, state, ports, calls, entered, publication, resolve, workflowText, step, producer, executeProducer, selector, executeSelector };
}

beforeEach(() => {
  vi.useFakeTimers();
  vi.setSystemTime(new Date('2026-10-08T12:00:10.750Z'));
});
afterEach(() => { vi.useRealTimers(); vi.restoreAllMocks(); });

describe('DBV-008/009 exact nonsecret readiness publication', () => {
  it('retains canonical compact bytes, supplied property order and exactly one LF', async () => {
    const f = executeNativeRunnerReadinessPublisher();
    const reordered = { runner: f.runner, expiresAt: f.readiness.expiresAt, verifiedAt: f.readiness.verifiedAt, formatVersion: f.readiness.formatVersion };
    const before = JSON.stringify(reordered);
    expect(await f.publication({ job: f.job, readiness: JSON.stringify(reordered, null, 2), now: f.now })).toEqual({ artifactName: f.name, member: 'readiness.json', body: `${before}\n` });
    expect(JSON.stringify(reordered)).toBe(before);
  });
  it('accepts trusted dispatch and the exact last allowed verification-age boundary', async () => {
    const f = executeNativeRunnerReadinessPublisher();
    f.job.eventName = 'workflow_dispatch';
    const verified = Date.parse(f.readiness.verifiedAt);
    f.readiness.expiresAt = new Date(verified + NATIVE_DB_VALIDATION.readinessMaxAgeMs).toISOString();
    expect(await f.publication({ job: f.job, readiness: JSON.stringify(f.readiness), now: verified })).toEqual({ artifactName: f.name, member: 'readiness.json', body: `${JSON.stringify(f.readiness)}\n` });
    expect(await f.publication({ job: f.job, readiness: JSON.stringify(f.readiness), now: verified + NATIVE_DB_VALIDATION.readinessMaxAgeMs })).toBeNull();
  });
  it.each([
    ['repository', 'fork/gymloop'], ['eventName', 'pull_request'], ['eventName', 'schedule'], ['ref', 'refs/heads/topic'],
    ['sourceSha', 'A'.repeat(40)], ['sourceSha', 'a'.repeat(39)], ['runId', '0'], ['runId', '0801001'], ['runAttempt', '02'],
    ['runAttempt', '0'], ['workflowRef', 'OGUN01/gymloop/.github/workflows/other.yml@refs/heads/main'],
  ])('refuses untrusted chooser identity %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.job, { [key]: value });
    expect(await f.publication()).toBeNull();
  });
  it.each([
    ['id', 0], ['id', Number.MAX_SAFE_INTEGER + 1], ['id', '902001'], ['status', 'offline'], ['status', 'ONLINE'],
    ['busy', true], ['busy', 0], ['ephemeral', false], ['ephemeral', 1], ['guardVerified', false], ['guardVerified', 'true'],
    ['label', 'self-hosted'], ['label', 'fitcruxx-db-linux-x64-801001-2-abc123def456'], ['sourceSha', 'f'.repeat(40)],
    ['runId', '801002'], ['runAttempt', '1'],
  ])('refuses invalid bound runner %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.runner, { [key]: value });
    expect(await f.publication()).toBeNull();
  });
  it.each([
    ['formatVersion', 2], ['formatVersion', '1'], ['verifiedAt', '2026-10-08T12:00:10.751Z'],
    ['verifiedAt', '2026-10-08T11:55:10.749Z'], ['verifiedAt', '2026-10-08T12:00:00Z'],
    ['verifiedAt', '2026-10-08T12:00:00.750+00:00'], ['verifiedAt', '2026-02-30T12:00:00.750Z'],
    ['verifiedAt', '1969-12-31T23:59:59.999Z'], ['verifiedAt', '+002026-10-08T12:00:00.750Z'],
    ['expiresAt', '2026-10-08T12:00:10.750Z'], ['expiresAt', '2026-10-08T12:00:00.750Z'],
    ['expiresAt', '2026-10-08T12:05:00.751Z'], ['expiresAt', '2026-10-08T12:05:00Z'],
  ])('refuses malformed, future, stale or overlong payload time %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.readiness, { [key]: value });
    expect(await f.publication()).toBeNull();
  });
  it.each([null, false, [], '{', '', 'null', '[]', '{}', '{"runner":null}', 1])('refuses readiness that is not the exact JSON record: %j', async readiness => {
    const f = executeNativeRunnerReadinessPublisher(); expect(await f.publication({ job: f.job, readiness, now: f.now })).toBeNull();
  });
  it.each([-1, NaN, Infinity, 1.5, Number.MAX_SAFE_INTEGER + 1, '1791460810750', null])('refuses invalid current UTC %s', async now => {
    const f = executeNativeRunnerReadinessPublisher(); expect(await f.publication({ job: f.job, readiness: JSON.stringify(f.readiness), now })).toBeNull();
  });
  it.each(['outer-extra', 'outer-missing', 'job-extra', 'job-missing', 'payload-extra', 'payload-missing', 'runner-extra', 'runner-missing'])('refuses exact-shape violation %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    const input: Record<string, unknown> = { job: f.job, readiness: JSON.stringify(f.readiness), now: f.now };
    if (kind === 'outer-extra') input.extra = true;
    if (kind === 'outer-missing') delete input.now;
    if (kind === 'job-extra') Object.assign(f.job, { runnerOs: 'Windows' });
    if (kind === 'job-missing') Reflect.deleteProperty(f.job, 'runId');
    if (kind === 'payload-extra') input.readiness = JSON.stringify({ ...f.readiness, extra: true });
    if (kind === 'payload-missing') { const data = { ...f.readiness }; Reflect.deleteProperty(data, 'verifiedAt'); input.readiness = JSON.stringify(data); }
    if (kind === 'runner-extra') { Object.assign(f.runner, { extra: true }); input.readiness = JSON.stringify(f.readiness); }
    if (kind === 'runner-missing') { Reflect.deleteProperty(f.runner, 'guardVerified'); input.readiness = JSON.stringify(f.readiness); }
    expect(await f.publication(input)).toBeNull();
  });
  it.each(['getter', 'nonenumerable', 'symbol', 'prototype', 'reflection'])('refuses hostile outer descriptors without invoking them: %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const getter = vi.fn(() => { throw new Error('must not invoke'); });
    let input: object = { job: f.job, readiness: JSON.stringify(f.readiness), now: f.now };
    if (kind === 'getter') Object.defineProperty(input, 'readiness', { enumerable: true, get: getter });
    if (kind === 'nonenumerable') Object.defineProperty(input, 'now', { enumerable: false, value: f.now });
    if (kind === 'symbol') Object.defineProperty(input, Symbol('armed'), { value: true });
    if (kind === 'prototype') Object.setPrototypeOf(input, { inherited: true });
    if (kind === 'reflection') input = new Proxy(input, { ownKeys: getter });
    expect(await f.publication(input)).toBeNull(); expect(getter).not.toHaveBeenCalledWith('readiness');
    if (kind !== 'reflection') expect(getter).not.toHaveBeenCalled();
  });
});

describe('DBV-008/009 bounded runtime Actions artifact resolution', () => {
  it.each([null, 'stale previously queued context'])('accepts fresh runtime publication independently of old context %j', async oldContext => {
    const f = executeNativeRunnerReadinessPublisher();
    const unavailableOldContext = oldContext;
    expect(unavailableOldContext).toBe(oldContext);
    expect(await f.resolve()).toEqual(f.runner);
    expect(f.ports.storageGet).toHaveBeenCalledTimes(1); expect(f.ports.readZipMember).toHaveBeenCalledTimes(1);
    const artifactCalls = f.calls.filter(call => call.path === `${f.base}/actions/artifacts`);
    expect(artifactCalls).toHaveLength(1); expect(artifactCalls[0].query).toEqual({ name: f.name });
    expect(f.calls.some(call => call.path === `${f.base}/actions/runs/${f.job.runId}/attempts/${f.job.runAttempt}`)).toBe(true);
    expect(f.calls.filter(call => call.kind !== 'pause').every(call => call.signal instanceof AbortSignal)).toBe(true);
    expect(f.calls.filter(call => call.kind === 'api').every(call => call.path?.startsWith(`${f.base}/`) || call.path === f.base)).toBe(true);
  });
  it.each(['absent', 'pending'])('waits for a delayed %s artifact within the original budget', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'absent') f.state.absentCount = 2; else f.state.pendingCount = 2;
    expect(await f.resolve()).toEqual(f.runner);
    expect(f.calls.filter(call => call.kind === 'pause').map(call => call.ms)).toEqual([NATIVE_DB_VALIDATION.processStopGraceMs, NATIVE_DB_VALIDATION.processStopGraceMs]);
  });
  it('ends absent-artifact polling at one total deadline without renewing the budget', async () => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.absentCount = Number.MAX_SAFE_INTEGER;
    expect(await f.resolve()).toBeNull();
    const waits = f.calls.filter(call => call.kind === 'pause');
    expect(waits.length).toBeGreaterThan(0);
    expect(waits.reduce((total, call) => total + call.ms!, 0)).toBeLessThanOrEqual(NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
    expect(f.state.monotonic).toBe(NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
    expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it('caps the final poll to the remaining monotonic budget', async () => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.absentCount = Number.MAX_SAFE_INTEGER;
    f.state.boundaryAdvance = NATIVE_DB_VALIDATION.processStopGraceMs - 1; f.state.boundaryAdvanceOnce = true;
    expect(await f.resolve()).toBeNull();
    const waits = f.calls.filter(call => call.kind === 'pause').map(call => call.ms!);
    expect(waits.every(ms => ms > 0 && ms <= NATIVE_DB_VALIDATION.processStopGraceMs)).toBe(true);
    expect(waits.some(ms => ms < NATIVE_DB_VALIDATION.processStopGraceMs)).toBe(true);
  });
  it.each(['api', 'storage', 'zip', 'pause'])('actively aborts and races an uncooperative %s promise', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.stall = kind;
    if (kind === 'pause') f.state.absentCount = 1;
    await f.publication();
    let settled = false;
    const pending = f.resolve().then(value => { settled = true; return value; });
    void pending.catch(() => {});
    await f.entered[kind];
    await vi.advanceTimersByTimeAsync(NATIVE_DB_VALIDATION.processStopGraceMs - 1);
    expect(settled).toBe(false);
    await vi.advanceTimersByTimeAsync(1);
    expect(await pending).toBeNull(); expect(settled).toBe(true);
    const captured = f.calls.filter(call => (kind === 'api' ? call.kind === 'api' : call.kind === kind));
    expect(captured).toHaveLength(1); expect(captured[0].signal?.aborted).toBe(true);
  });
  it.each([[-1], [NaN], [Infinity], [1, 0], [0, 1, 0]].map(readings => ({ readings })))('refuses invalid or decreasing monotonic readings $readings', async ({ readings }) => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.monotonicReadings = [...readings];
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each([-1, NaN, Infinity, 1.5, Number.MAX_SAFE_INTEGER + 1])('refuses an invalid UTC port value %s', async utc => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.utc = utc; expect(await f.resolve()).toBeNull();
  });
  it.each(['repository', 'eventName', 'ref', 'sourceSha', 'runId', 'runAttempt', 'workflowRef'])('refuses malformed input job %s before effects', async key => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.job, { [key]: null });
    expect(await f.resolve()).toBeNull(); expect(f.calls).toEqual([]);
    expect(f.ports.utcNow).not.toHaveBeenCalled(); expect(f.ports.monotonicNow).not.toHaveBeenCalled();
  });
  it.each(['extra', 'missing', 'getter', 'symbol', 'prototype', 'reflection'])('refuses hostile resolver input %s before effects', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const getter = vi.fn(() => { throw new Error('input getter'); });
    let input: object = { job: f.job };
    if (kind === 'extra') Object.assign(input, { runner: f.runner });
    if (kind === 'missing') Reflect.deleteProperty(input, 'job');
    if (kind === 'getter') Object.defineProperty(input, 'job', { enumerable: true, get: getter });
    if (kind === 'symbol') Object.defineProperty(input, Symbol('extra'), { value: true });
    if (kind === 'prototype') Object.setPrototypeOf(input, { job: f.job });
    if (kind === 'reflection') input = new Proxy(input, { ownKeys: getter });
    expect(await f.resolve(input)).toBeNull(); expect(f.calls).toEqual([]);
    if (kind !== 'reflection') expect(getter).not.toHaveBeenCalled();
  });
  it.each(['extra', 'missing', 'getter', 'symbol', 'prototype', 'reflection', 'not-function'])('refuses hostile six-port record %s before effects', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const getter = vi.fn(() => { throw new Error('port getter'); });
    let ports: object = { ...f.ports };
    if (kind === 'extra') Object.assign(ports, { httpPut: vi.fn() });
    if (kind === 'missing') Reflect.deleteProperty(ports, 'pause');
    if (kind === 'getter') Object.defineProperty(ports, 'apiGet', { enumerable: true, get: getter });
    if (kind === 'symbol') Object.defineProperty(ports, Symbol('extra'), { value: true });
    if (kind === 'prototype') Object.setPrototypeOf(ports, { inherited: true });
    if (kind === 'reflection') ports = new Proxy(ports, { ownKeys: getter });
    if (kind === 'not-function') Object.assign(ports, { pause: null });
    expect(await f.resolve({ job: f.job }, ports)).toBeNull(); expect(f.calls).toEqual([]);
    if (kind !== 'reflection') expect(getter).not.toHaveBeenCalled();
  });
  it.each(['api', 'storage', 'zip', 'pause'])('returns null immediately after a rejected %s port', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.fail = kind;
    if (kind === 'pause') f.state.absentCount = 1;
    expect(await f.resolve()).toBeNull();
    expect(f.calls.filter(call => call.kind === 'pause').length).toBeLessThanOrEqual(1);
  });
  it.each(['extra', 'missing', 'wrong-body', 'getter', 'nonenumerable', 'symbol', 'prototype', 'reflection'])('refuses hostile exact API response record %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const getter = vi.fn(() => { throw new Error('API getter'); });
    let output = { status: NATIVE_DB_VALIDATION.artifactMetadataStatus as number, body: Buffer.from(JSON.stringify(f.state.repository)), location: null };
    if (kind === 'extra') Object.assign(output, { extra: true });
    if (kind === 'missing') Reflect.deleteProperty(output, 'location');
    if (kind === 'wrong-body') Object.assign(output, { body: JSON.stringify(f.state.repository) });
    if (kind === 'getter') Object.defineProperty(output, 'body', { enumerable: true, get: getter });
    if (kind === 'nonenumerable') Object.defineProperty(output, 'body', { enumerable: false, value: output.body });
    if (kind === 'symbol') Object.defineProperty(output, Symbol('extra'), { value: true });
    if (kind === 'prototype') Object.setPrototypeOf(output, { inherited: true });
    if (kind === 'reflection') output = new Proxy(output, { ownKeys: getter });
    f.ports.apiGet.mockImplementationOnce(async () => output);
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled(); expect(f.ports.pause).not.toHaveBeenCalled();
    if (kind !== 'reflection') expect(getter).not.toHaveBeenCalled();
  });
  it.each(['extra', 'missing', 'wrong-body', 'getter'])('refuses hostile exact storage response record %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const getter = vi.fn(() => { throw new Error('storage getter'); });
    const output = { status: NATIVE_DB_VALIDATION.artifactMetadataStatus, body: f.state.archive };
    if (kind === 'extra') Object.assign(output, { location: 'https://other.invalid' });
    if (kind === 'missing') Reflect.deleteProperty(output, 'status');
    if (kind === 'wrong-body') Object.assign(output, { body: [] });
    if (kind === 'getter') Object.defineProperty(output, 'body', { enumerable: true, get: getter });
    f.ports.storageGet.mockImplementationOnce(async () => output);
    expect(await f.resolve()).toBeNull(); expect(f.ports.readZipMember).not.toHaveBeenCalled(); expect(getter).not.toHaveBeenCalled();
  });
  it.each([301, 403, 404, 429, 500])('never retries API status %s', async status => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.apiStatus = status;
    expect(await f.resolve()).toBeNull(); expect(f.calls.filter(call => call.kind === 'api')).toHaveLength(1); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it('refuses malformed provider JSON immediately', async () => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.invalidBody = true;
    expect(await f.resolve()).toBeNull(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each(['bad-id', 'bad-repository', 'inactive', 'workflow-id', 'workflow-path'])('refuses repository/workflow discovery mismatch %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'bad-id') f.state.repository.id = 0;
    if (kind === 'bad-repository') Object.assign(f.state.repository, { full_name: 'other/gymloop' });
    if (kind === 'inactive') f.state.workflow.state = 'disabled_manually';
    if (kind === 'workflow-id') f.state.workflow.id = 0;
    if (kind === 'workflow-path') f.state.workflow.path = '.github/workflows/forged.yml';
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each([
    ['id', 801002], ['run_attempt', 1], ['head_sha', 'f'.repeat(40)], ['head_branch', 'topic'],
    ['path', '.github/workflows/other.yml'], ['event', 'pull_request'], ['status', 'completed'], ['conclusion', 'success'],
    ['created_at', '2026-10-08T12:00:01Z'], ['run_started_at', '2026-10-08T12:00:01Z'],
  ])('refuses wrong active target %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.state.target, { [key]: value });
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each(['repository', 'head_repository'])('refuses a target from another %s', async key => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.state.target[key as 'repository' | 'head_repository'], { id: 701009, full_name: 'fork/gymloop' });
    expect(await f.resolve()).toBeNull();
  });
  it.each([
    ['id', 801009], ['run_attempt', 2], ['workflow_id', 701009], ['head_sha', 'f'.repeat(40)], ['head_branch', 'topic'],
    ['path', '.github/workflows/forged.yml'], ['event', 'push'], ['status', 'cancelled'],
    ['conclusion', 'failure'], ['conclusion', 'cancelled'], ['conclusion', 'timed_out'],
    ['created_at', '2026-10-08T11:59:59Z'], ['updated_at', '2026-10-08T12:00:02Z'],
    ['updated_at', '2026-10-08T12:05:00Z'], ['updated_at', '2026-10-08T12:00:11Z'],
  ])('refuses wrong publisher %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.state.publisher, { [key]: value });
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each(['actor', 'triggering_actor', 'repository', 'head_repository'])('refuses publisher trust mismatch %s', async key => {
    const f = executeNativeRunnerReadinessPublisher();
    if (key === 'actor' || key === 'triggering_actor') f.state.publisher[key].login = 'attacker';
    else Object.assign(f.state.publisher[key as 'repository' | 'head_repository'], { id: 701009, full_name: 'fork/gymloop' });
    expect(await f.resolve()).toBeNull(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it('does not wait for an otherwise pending publisher with an untrusted actor', async () => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.publisher.actor.login = 'attacker'; f.state.pendingCount = 1;
    expect(await f.resolve()).toBeNull(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each([
    ['id', 0], ['id', Number.MAX_SAFE_INTEGER + 1], ['name', 'native-db-readiness-wrong'], ['expired', true], ['expired', 'false'],
    ['size_in_bytes', 0], ['size_in_bytes', NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1], ['size_in_bytes', 1.5],
    ['digest', 'sha256:' + 'A'.repeat(64)], ['digest', 'sha512:' + 'a'.repeat(64)], ['digest', 'sha256:' + 'a'.repeat(63)],
    ['created_at', '2026-10-08T12:00:01Z'], ['updated_at', '2026-10-08T12:00:04Z'],
  ])('refuses invalid artifact %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.state.artifact, { [key]: value });
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled(); expect(f.ports.pause).not.toHaveBeenCalled();
  });
  it.each([
    ['id', 0], ['repository_id', 701009], ['head_repository_id', 701009], ['head_branch', 'topic'], ['head_sha', 'f'.repeat(40)],
  ])('refuses artifact workflow-run binding %s=%s', async (key, value) => {
    const f = executeNativeRunnerReadinessPublisher(); Object.assign(f.state.artifact.workflow_run, { [key]: value });
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each(['count-two', 'count-mismatch', 'negative-count', 'fractional-count', 'unsafe-count', 'empty-with-count', 'duplicate'])('refuses incomplete or ambiguous first-page listing %s without pagination', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'count-two') f.state.listing.total_count = 2;
    if (kind === 'count-mismatch') f.state.listing.total_count = 0;
    if (kind === 'negative-count') f.state.listing.total_count = -1;
    if (kind === 'fractional-count') f.state.listing.total_count = 1.5;
    if (kind === 'unsafe-count') f.state.listing.total_count = Number.MAX_SAFE_INTEGER + 1;
    if (kind === 'empty-with-count') f.state.listing.artifacts = [];
    if (kind === 'duplicate') { f.state.listing.artifacts.push(f.state.artifact); f.state.listing.total_count = 2; }
    expect(await f.resolve()).toBeNull(); expect(f.ports.pause).not.toHaveBeenCalled(); expect(f.ports.storageGet).not.toHaveBeenCalled();
    expect(f.calls.filter(call => call.path === `${f.base}/actions/artifacts`)).toHaveLength(1);
  });
  it.each(['name', 'duplicate-job', 'missing-step', 'duplicate-step', 'failed-produce', 'skipped-upload', 'job-running', 'wrong-attempt', 'wrong-run', 'bad-times'])('refuses incomplete publisher job/steps %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'name') f.state.publisherJob.name = 'forged publisher';
    if (kind === 'duplicate-job') { f.state.jobs.jobs.push(structuredClone(f.state.publisherJob)); f.state.jobs.total_count = 2; }
    if (kind === 'missing-step') f.state.publisherJob.steps.splice(1, 1);
    if (kind === 'duplicate-step') f.state.publisherJob.steps.push(structuredClone(f.state.publisherJob.steps[2]));
    if (kind === 'failed-produce') f.state.publisherJob.steps[1].conclusion = 'failure';
    if (kind === 'skipped-upload') f.state.publisherJob.steps[2].conclusion = 'skipped';
    if (kind === 'job-running') f.state.publisherJob.status = 'in_progress';
    if (kind === 'wrong-attempt') f.state.publisherJob.run_attempt = 2;
    if (kind === 'wrong-run') f.state.publisherJob.run_id = 801009;
    if (kind === 'bad-times') f.state.publisherJob.steps[2].completed_at = '2026-10-08T12:00:01Z';
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each(['id', 'name', 'size_in_bytes', 'digest', 'created_at', 'updated_at'])('refuses metadata changed at reread: %s', async key => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.reread = structuredClone(f.state.artifact);
    const values: Record<string, unknown> = { id: 601002, name: f.name + '-other', size_in_bytes: f.state.archive.length + 1, digest: 'sha256:' + 'f'.repeat(64), created_at: '2026-10-08T12:00:03Z', updated_at: '2026-10-08T12:00:02Z' };
    Object.assign(f.state.reread, { [key]: values[key] });
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each(['http://storage.invalid/a.zip', 'https://user@storage.invalid/a.zip', 'https://user:secret@storage.invalid/a.zip', 'https://storage.invalid/a.zip#fragment', '/a.zip', '', 'https://storage.invalid/a.zip\nhttps://other.invalid/b.zip'])('refuses unsafe download redirect %j', async location => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.location = location;
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each([200, 301, 303, 307, 403, 500])('requires the exact authenticated artifact redirect status %s', async status => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.downloadStatus = status;
    expect(await f.resolve()).toBeNull(); expect(f.ports.storageGet).not.toHaveBeenCalled();
  });
  it.each([302, 403, 404, 500])('refuses storage HTTP status %s', async status => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.storageStatus = status;
    expect(await f.resolve()).toBeNull(); expect(f.ports.readZipMember).not.toHaveBeenCalled();
  });
  it.each(['empty', 'short', 'long', 'oversize', 'digest'])('refuses incorrect downloaded archive bytes %s before ZIP extraction', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'empty') f.state.archive = Buffer.alloc(0);
    if (kind === 'short') f.state.archive = f.state.archive.subarray(1);
    if (kind === 'long') f.state.archive = Buffer.concat([f.state.archive, Buffer.from([0])]);
    if (kind === 'oversize') f.state.archive = Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1);
    if (kind === 'digest') f.state.archive[40] ^= 1;
    expect(await f.resolve()).toBeNull(); expect(f.ports.readZipMember).not.toHaveBeenCalled();
  });
  it.each(['extra-LF', 'missing-LF', 'indent', 'BOM', 'CRLF', 'garbage', 'invalid-UTF8', 'oversize', 'stale', 'extra-field'])('refuses invalid canonical extracted readiness bytes %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'extra-LF') f.state.member = Buffer.concat([f.body, Buffer.from('\n')]);
    if (kind === 'missing-LF') f.state.member = f.body.subarray(0, -1);
    if (kind === 'indent') f.state.member = Buffer.from(JSON.stringify(f.readiness, null, 2) + '\n');
    if (kind === 'BOM') f.state.member = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), f.body]);
    if (kind === 'CRLF') f.state.member = Buffer.from(JSON.stringify(f.readiness) + '\r\n');
    if (kind === 'garbage') f.state.member = Buffer.from('{\n');
    if (kind === 'invalid-UTF8') f.state.member = Buffer.concat([f.body, Buffer.from([0xff])]);
    if (kind === 'oversize') f.state.member = Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1);
    if (kind === 'stale') f.state.member = Buffer.from(JSON.stringify({ ...f.readiness, expiresAt: '2026-10-08T12:00:10.750Z' }) + '\n');
    if (kind === 'extra-field') f.state.member = Buffer.from(JSON.stringify({ ...f.readiness, extra: true }) + '\n');
    expect(await f.resolve()).toBeNull();
  });
  it.each(['2026-10-08T12:00:02+00:00', '2026-02-30T12:00:02Z', '+002026-10-08T12:00:02Z', '1969-12-31T23:59:59Z', '2026-10-08 12:00:02', '2026-10-08T12:00:11Z'])('refuses invalid or future provider timestamp %s', async timestamp => {
    const f = executeNativeRunnerReadinessPublisher(); f.state.artifact.created_at = timestamp;
    expect(await f.resolve()).toBeNull();
  });
  it('checks freshness at final acceptance after an initially valid download', async () => {
    const f = executeNativeRunnerReadinessPublisher();
    f.ports.readZipMember.mockImplementationOnce(async () => { f.state.utc = Date.parse(f.readiness.expiresAt); return f.body; });
    expect(await f.resolve()).toBeNull();
  });
  it('never prints readiness, redirects or raw provider bodies on failure', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const log = vi.spyOn(console, 'log').mockImplementation(() => {}); const error = vi.spyOn(console, 'error').mockImplementation(() => {}); const warn = vi.spyOn(console, 'warn').mockImplementation(() => {});
    f.state.artifact.digest = 'sha256:' + 'f'.repeat(64);
    expect(await f.resolve()).toBeNull(); expect(log).not.toHaveBeenCalled(); expect(error).not.toHaveBeenCalled(); expect(warn).not.toHaveBeenCalled();
  });
});

describe('DBV-008/012 dedicated readiness publisher and fail-closed routing', () => {
  it('declares dispatch-only input and read-only repository/actions permissions', () => {
    const f = executeNativeRunnerReadinessPublisher(); const text = f.workflowText();
    expect(text).toMatch(/^on:\s*\n\s+workflow_dispatch:/m); expect(text).toMatch(/readiness:\s*\n(?:\s+[^\n]+\n)*?\s+required: true/m); expect(text).toMatch(/type: string/);
    expect(text).not.toMatch(/^\s{2}(push|pull_request|schedule|workflow_run|repository_dispatch):/m);
    expect(text).toMatch(/^permissions:\s*\n\s+contents: read\s*\n\s+actions: read/m);
    expect(text).not.toMatch(/:\s*write\b|secrets\.|\benvironment:|\bservices:|\bconcurrency:|supabase|ALTER ROLE|execute_sql|apply_migration/);
  });
  it('has one Ubuntu publisher job with owner, main and first-attempt admission', () => {
    const f = executeNativeRunnerReadinessPublisher(); const text = f.workflowText();
    expect(text.slice(text.indexOf('\njobs:')).match(/^ {2}[a-z][\w-]*:\s*$/gm)).toHaveLength(1);
    expect(text).toMatch(/name: ["']?Publish verified readiness["']?/); expect(text).toMatch(/runs-on: ubuntu-latest/);
    for (const key of ['github.repository', 'github.ref', 'github.actor', 'github.triggering_actor', 'github.run_attempt']) expect(text).toContain(key);
    expect(text).toContain('OGUN01/gymloop'); expect(text).toContain('refs/heads/main'); expect(text).toContain('OGUN01');
    expect(text).toMatch(/github\.run_attempt\s*==\s*(?:1|'1'|"1")/);
    expect(text).toMatch(/uses: actions\/checkout@\S+/); expect(text).toMatch(/ref: \$\{\{\s*github\.sha\s*\}\}/);
  });
  it('uses the official immutable uploader with exact file, bound name and retention', () => {
    const f = executeNativeRunnerReadinessPublisher(); const text = f.workflowText();
    const produce = f.step(text, 'Produce bound readiness');
    expect(produce).toMatch(/createNativeRunnerReadinessPublication|runner-readiness/);
    expect(produce).toMatch(/uses: actions\/github-script@v8/); expect(produce).toMatch(/id: produce/); expect(produce).toContain('context.payload.inputs.readiness');
    const upload = f.step(text, 'Retain bound readiness'); expect(upload).toMatch(/uses: actions\/upload-artifact@v5/);
    expect(upload).toMatch(/path: ["']?\.native-db-readiness\/readiness\.json["']?\s*$/m); expect(upload).toContain('if-no-files-found: error');
    expect(upload).not.toMatch(/overwrite:\s*true/); expect(upload).toMatch(/name:.*(?:artifactName|artifact_name|native-db-readiness)/);
    expect(upload).toMatch(new RegExp(`retention-days: (?:${NATIVE_DB_VALIDATION.artifactRetentionDays}|\\$\\{\\{[^}]+\\}\\})`));
  });
  it('produces only bound canonical private bytes after both official metadata reads', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const result = await f.executeProducer();
    expect(result.refused).toBe(false);
    expect(f.producer.github.rest.actions.getWorkflowRun).toHaveBeenCalledTimes(1);
    expect(f.producer.github.rest.actions.getWorkflowRunAttempt).toHaveBeenCalledTimes(1);
    expect(f.producer.github.rest.actions.getWorkflowRun.mock.calls[0][0]).toMatchObject({ owner: 'OGUN01', repo: 'gymloop', run_id: f.state.publisher.id });
    const targetRequest = f.producer.github.rest.actions.getWorkflowRunAttempt.mock.calls[0][0] as Record<string, unknown>;
    expect(targetRequest).toMatchObject({ owner: 'OGUN01', repo: 'gymloop' });
    expect(String(targetRequest.run_id)).toBe(f.job.runId); expect(String(targetRequest.attempt_number)).toBe(f.job.runAttempt);
    expect(f.producer.directories).toHaveLength(1); expect(f.producer.files).toHaveLength(1);
    expect(f.producer.directories[0].path.replaceAll('\\', '/')).toMatch(/(?:^|\/)\.native-db-readiness$/);
    expect(f.producer.directories[0].options.mode).toBe(NATIVE_DB_VALIDATION.privateDirectoryMode);
    expect(f.producer.directories[0].options.recursive).not.toBe(true);
    expect(f.producer.files[0].path.replaceAll('\\', '/')).toBe(f.producer.directories[0].path.replaceAll('\\', '/') + '/readiness.json');
    expect(f.producer.files[0].options).toMatchObject({ flag: 'wx', mode: NATIVE_DB_VALIDATION.privateFileMode });
    expect(Buffer.from(f.producer.files[0].body as string | Uint8Array)).toEqual(f.body);
    expect([...f.producer.outputs.keys()].sort()).toEqual(['artifact_name', 'retention_days']);
    expect(f.producer.outputs.get('artifact_name')).toBe(f.name); expect(String(f.producer.outputs.get('retention_days'))).toBe(String(NATIVE_DB_VALIDATION.artifactRetentionDays));
  });
  it.each(['actor', 'triggering_actor', 'head_sha', 'head_branch', 'event', 'path', 'run_attempt', 'repository', 'head_repository'])('producer refuses its actual own metadata mismatch %s before filesystem publication', async key => {
    const f = executeNativeRunnerReadinessPublisher();
    const mutations: Record<string, unknown> = { actor: { login: 'attacker' }, triggering_actor: { login: 'attacker' }, head_sha: 'f'.repeat(40), head_branch: 'topic', event: 'push', path: '.github/workflows/forged.yml', run_attempt: 2, repository: { id: 701009, full_name: 'fork/gymloop' }, head_repository: { id: 701009, full_name: 'fork/gymloop' } };
    Object.assign(f.state.publisher, { [key]: mutations[key] });
    expect((await f.executeProducer()).refused).toBe(true);
    expect(f.producer.files).toEqual([]); expect(f.producer.directories).toEqual([]); expect([...f.producer.outputs]).toEqual([]);
  });
  it.each(['id', 'run_attempt', 'head_sha', 'head_branch', 'event', 'path', 'status', 'repository', 'head_repository'])('producer refuses official target mismatch %s before filesystem publication', async key => {
    const f = executeNativeRunnerReadinessPublisher();
    const mutations: Record<string, unknown> = { id: 801009, run_attempt: 1, head_sha: 'f'.repeat(40), head_branch: 'topic', event: 'pull_request', path: '.github/workflows/forged.yml', status: 'completed', repository: { id: 701009, full_name: 'fork/gymloop' }, head_repository: { id: 701009, full_name: 'fork/gymloop' } };
    Object.assign(f.state.target, { [key]: mutations[key] });
    expect((await f.executeProducer()).refused).toBe(true);
    expect(f.producer.files).toEqual([]); expect(f.producer.directories).toEqual([]); expect([...f.producer.outputs]).toEqual([]);
  });
  it.each(['malformed', 'not-string', 'stale', 'collision', 'target-api', 'own-api'])('producer refuses unsafe input/custody condition %s', async kind => {
    const f = executeNativeRunnerReadinessPublisher();
    if (kind === 'malformed') f.producer.context.payload.inputs.readiness = '{';
    if (kind === 'not-string') Object.assign(f.producer.context.payload.inputs, { readiness: null });
    if (kind === 'stale') f.producer.context.payload.inputs.readiness = JSON.stringify({ ...f.readiness, expiresAt: '2026-10-08T12:00:10.750Z' });
    if (kind === 'collision') f.producer.collision = true;
    if (kind === 'target-api') f.producer.github.rest.actions.getWorkflowRunAttempt.mockRejectedValueOnce(new Error('synthetic transport'));
    if (kind === 'own-api') f.producer.github.rest.actions.getWorkflowRun.mockRejectedValueOnce(new Error('synthetic transport'));
    expect((await f.executeProducer()).refused).toBe(true); expect(f.producer.files).toEqual([]); expect([...f.producer.outputs]).toEqual([]);
  });
  it('loads readiness at selector runtime and classifies the publisher workflow as a database input', () => {
    const text = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
    expect(text).toContain('.github/workflows/native-runner-readiness.yml'); expect(text).toContain('resolveNativeRunnerReadiness');
    expect(text).not.toMatch(/(?:fromJson|fromJSON)\(\s*vars\.NATIVE_DB_RUNNER_READINESS/);
    expect(text).toMatch(/scripts\/pgtap/);
  });
  it('selector passes exactly the runtime identity and six ports and retains hosted fallback', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector();
    expect(f.selector.input).toEqual({ job: f.job });
    expect(Object.keys(concretePorts).sort()).toEqual(['apiGet', 'storageGet', 'readZipMember', 'utcNow', 'monotonicNow', 'pause'].sort());
    expect([...f.selector.outputs.values()].some(value => value === '["ubuntu-latest"]' || JSON.stringify(value) === '["ubuntu-latest"]')).toBe(true);
  });
  it('selector official API port uses a fixed read-only URL, manual redirects and effective caller signal', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector(); const control = new AbortController();
    const response = await concretePorts.apiGet(f.base, {}, control.signal);
    expect(response).toEqual({ status: NATIVE_DB_VALIDATION.artifactMetadataStatus, body: new Uint8Array(f.selector.apiBytes), location: null });
    expect(f.selector.requests).toHaveLength(1); expect(f.selector.requests[0].url).toBe(`https://api.github.com${f.base}`);
    expect(f.selector.requests[0].options).toMatchObject({ method: 'GET', redirect: 'manual', signal: control.signal });
  });
  it('selector storage port never carries authorization and refuses automatic redirects', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector(); const control = new AbortController();
    const response = await concretePorts.storageGet(f.state.location, control.signal);
    expect(response).toEqual({ status: NATIVE_DB_VALIDATION.artifactMetadataStatus, body: new Uint8Array(f.state.archive) });
    expect(f.selector.requests).toHaveLength(1); expect(f.selector.requests[0].url).toBe(f.state.location);
    expect(f.selector.requests[0].options).toMatchObject({ redirect: 'error', signal: control.signal });
    expect(JSON.stringify(f.selector.requests[0].options.headers ?? {})).not.toMatch(/authorization|fixture-only/i);
  });
  it.each(['api', 'storage'])('selector bounds actual %s response bytes even without content-length', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector();
    if (kind === 'api') f.selector.apiBytes = Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1, 32);
    else f.selector.storageBytes = Buffer.alloc(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1);
    let refused: boolean;
    try {
      const response = kind === 'api' ? await concretePorts.apiGet(f.base, {}, new AbortController().signal) : await concretePorts.storageGet(f.state.location, new AbortController().signal);
      refused = response.body.byteLength > NATIVE_DB_VALIDATION.timeoutQueryMaxBytes ? false : response.status !== NATIVE_DB_VALIDATION.artifactMetadataStatus;
    } catch { refused = true; }
    expect(refused).toBe(true);
  });
  it('selector constrained ZIP port extracts exactly the ordinary canonical member', async () => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector();
    expect(Buffer.from(await concretePorts.readZipMember(f.state.archive, 'readiness.json', NATIVE_DB_VALIDATION.timeoutQueryMaxBytes, new AbortController().signal))).toEqual(f.body);
  });
  it.each(['directory', 'escape', 'symlink', 'encrypted', 'unsupported-compression', 'truncated', 'decoded-size'])('selector constrained ZIP refuses %s member', async kind => {
    const f = executeNativeRunnerReadinessPublisher(); const { concretePorts } = await f.executeSelector();
    const bytes = Buffer.from(f.state.archive); const central = 30 + Buffer.byteLength('readiness.json') + f.body.length;
    if (kind === 'directory' || kind === 'escape') {
      const replacement = kind === 'directory' ? 'readiness.jso/' : '../secret.json';
      bytes.write(replacement, 30); bytes.write(replacement, central + 46);
    }
    if (kind === 'symlink') bytes.writeUInt32LE((0o120777 << NATIVE_DB_VALIDATION.artifactUnixModeShiftBits) >>> 0, central + 38);
    if (kind === 'encrypted') { bytes.writeUInt16LE(1, 6); bytes.writeUInt16LE(1, central + 8); }
    if (kind === 'unsupported-compression') { bytes.writeUInt16LE(12, 8); bytes.writeUInt16LE(12, central + 10); }
    if (kind === 'decoded-size') bytes.writeUInt32LE(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes + 1, central + 24);
    await expect(concretePorts.readZipMember(kind === 'truncated' ? bytes.subarray(0, -1) : bytes, 'readiness.json', NATIVE_DB_VALIDATION.timeoutQueryMaxBytes, new AbortController().signal)).rejects.toThrow();
  });
});
