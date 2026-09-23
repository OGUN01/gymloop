import { existsSync, readFileSync } from 'node:fs';
import ts from 'typescript';
import { afterEach, beforeAll, describe, expect, it, vi } from 'vitest';

const CRON = '*/5 * * * *';
const TOKEN = 'private-gymloop-actions-token';
const DISPATCH_URL = 'https://api.github.com/repos/OGUN01/gymloop/actions/workflows/phase8-production-monitor.yml/dispatches';
const WORKER_PATH = new URL('../../workers/phase8-monitor-dispatch.mjs', import.meta.url);
const CONFIG_PATH = new URL('../../wrangler.phase8-monitor.jsonc', import.meta.url);
const WORKFLOW_PATH = new URL('../../.github/workflows/phase8-production-monitor.yml', import.meta.url);
type Scheduler = {
  scheduled: (event: { cron?: string }, env: { GITHUB_ACTIONS_DISPATCH_TOKEN?: string }) => Promise<unknown>;
};
let worker: Scheduler | undefined;
const scheduled = (cron = CRON, token = TOKEN) => {
  if (!worker) throw new Error('Monitor dispatch Worker is unavailable');
  return worker.scheduled({ cron }, { GITHUB_ACTIONS_DISPATCH_TOKEN: token });
};
const requestFrom = (input: Request | string | URL, init?: RequestInit) =>
  input instanceof Request ? input : new Request(input, init);

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

describe('HARD-005 dedicated five-minute monitor dispatch Worker', () => {
  beforeAll(async () => {
    const module = await import('../../workers/phase8-monitor-dispatch.mjs');
    expect(module.default).toBeDefined();
    worker = module.default;
  });

  it('exports only a Cron scheduled handler and exposes no public HTTP handler', () => {
    expect(Object.keys(worker ?? {})).toEqual(['scheduled']);
    expect(typeof worker?.scheduled).toBe('function');
    expect('fetch' in (worker ?? {})).toBe(false);
  });

  it('posts exactly one safe dispatch to the Gymloop monitor workflow on main', async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    await scheduled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [input, init] = fetchMock.mock.calls[0] as unknown as [Request | string | URL, RequestInit | undefined];
    const request = requestFrom(input, init);
    expect(request.url).toBe(DISPATCH_URL);
    expect(request.method).toBe('POST');
    expect(request.headers.get('authorization')).toBe(`Bearer ${TOKEN}`);
    expect(request.headers.get('accept')).toContain('application/vnd.github+json');
    expect(request.headers.get('content-type')).toContain('application/json');
    const body = await request.json() as Record<string, unknown>;
    expect(Object.keys(body).sort()).toEqual(['inputs', 'ref']);
    expect(body.ref).toBe('main');
    expect(Object.keys(body.inputs as Record<string, unknown>)).toEqual(['force_test_alert']);
    expect([false, 'false']).toContain((body.inputs as Record<string, unknown>).force_test_alert);
  });

  it('refuses any other or missing Cron expression before sending a request', async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    for (const cron of ['', '* * * * *', '*/10 * * * *']) {
      await expect(scheduled(cron)).rejects.toThrow();
    }
    await expect(worker!.scheduled({}, { GITHUB_ACTIONS_DISPATCH_TOKEN: TOKEN })).rejects.toThrow();
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('refuses a missing credential before dispatch', async () => {
    const fetchMock = vi.fn(async () => new Response(null, { status: 204 }));
    vi.stubGlobal('fetch', fetchMock);
    for (const token of ['', ' ']) {
      await expect(scheduled(CRON, token)).rejects.toThrow();
    }
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it('requires HTTP 204 rather than treating another successful status as dispatch proof', async () => {
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    for (const status of [200, 201, 202, 403, 500]) {
      const fetchMock = vi.fn(async () => new Response('private response body', { status }));
      vi.stubGlobal('fetch', fetchMock);
      let caught: unknown;
      try { await scheduled(); } catch (error) { caught = error; }
      expect(caught).toBeInstanceOf(Error);
      expect(fetchMock).toHaveBeenCalledTimes(1);
      const emitted = `${String(caught)} ${JSON.stringify(log.mock.calls)}`;
      expect(emitted).not.toContain(TOKEN);
      expect(emitted).not.toContain('private response body');
      expect(log).toHaveBeenCalled();
      log.mockClear();
    }
  });

  it('reports network failures generically without leaking the token or upstream error', async () => {
    const secret = 'private upstream diagnostic';
    const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    const fetchMock = vi.fn(async () => { throw new Error(`${secret} ${TOKEN}`); });
    vi.stubGlobal('fetch', fetchMock);
    let caught: unknown;
    try { await scheduled(); } catch (error) { caught = error; }
    expect(caught).toBeInstanceOf(Error);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(log).toHaveBeenCalled();
    const emitted = `${String(caught)} ${JSON.stringify(log.mock.calls)}`;
    expect(emitted).not.toContain(TOKEN);
    expect(emitted).not.toContain(secret);
  });
});

describe('HARD-005 Cron deployment and GitHub fallback', () => {
  const configText = existsSync(CONFIG_PATH) ? readFileSync(CONFIG_PATH, 'utf8') : '';
  const workerSource = existsSync(WORKER_PATH) ? readFileSync(WORKER_PATH, 'utf8') : '';
  const githubWorkflow = readFileSync(WORKFLOW_PATH, 'utf8');

  it('configures only the fixed five-minute Cron and no public route', () => {
    const parsed = ts.parseConfigFileTextToJson('wrangler.phase8-monitor.jsonc', configText);
    expect(parsed.error).toBeUndefined();
    const config = parsed.config as Record<string, unknown>;
    expect(config.triggers).toEqual({ crons: [CRON] });
    expect(config.workers_dev).toBe(false);
    expect(config).not.toHaveProperty('route');
    expect(config).not.toHaveProperty('routes');
    expect(configText).not.toContain(TOKEN);
  });

  it('keeps the GitHub five-minute schedule as an independent fallback', () => {
    expect(githubWorkflow).toMatch(/schedule:\s*\r?\n\s*-\s*cron:\s*['"]?\*\/5 \* \* \* \*['"]?/);
    expect(githubWorkflow).toMatch(/workflow_dispatch:/);
    expect(workerSource).not.toMatch(/\bfetch\s*\(\s*(?:request|event)\s*\)\s*\{/);
  });
});
