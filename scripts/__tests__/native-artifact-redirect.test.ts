import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';

// DBV-007/012: independent transport fixtures, authored before construction.
// Workflow bytes are mechanically extracted and executed; never inspected or
// copied into a replacement reader. Neither the workflow nor GitHub is run.
async function executeNativeArtifactReader(options = {}, trace = { api: [], fetch: [], storage: [], python: [] }) {
  trace.decodeCalls = 0;
  const require = createRequire(import.meta.url);
  const yaml = createRequire(require.resolve('eslint'))('js-yaml');
  const workflow = yaml.load(readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8'));
  const steps = workflow.jobs['database-recovery-preflight'].steps.filter((step) => step.name === "Require the previous armed attempt's verified restoration");
  if (steps.length !== 1 || typeof steps[0].with?.script !== 'string') throw new Error('Named artifact fixture boundary unavailable.');
  const parsed = ts.createSourceFile('artifact-fixture.js', steps[0].with.script, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const readers = [];
  const visit = (node) => {
    if (ts.isVariableDeclaration(node) && node.name.getText(parsed) === 'readArtifact' && node.initializer) readers.push(node.initializer.getText(parsed));
    if (ts.isFunctionDeclaration(node) && node.name?.text === 'readArtifact') readers.push(node.getText(parsed));
    ts.forEachChild(node, visit);
  };
  visit(parsed);
  if (readers.length !== 1) throw new Error('Artifact fixture reader is ambiguous.');

  const limits = { ...NATIVE_DB_VALIDATION, ...options.limits };
  const filename = 'receipt.json';
  const value = { formatVersion: NATIVE_DB_VALIDATION.formatVersion, marker: 'independent-visible-artifact' };
  const body = options.body ?? Buffer.from(`${JSON.stringify(value)}\n`);
  const python = process.platform === 'win32' ? 'python' : 'python3';
  const zip = execFileSync(python, ['-c', `
import base64,io,json,stat,struct,sys,zipfile
p=json.loads(sys.stdin.buffer.read())
out=io.BytesIO()
with zipfile.ZipFile(out,'w') as z:
 for name in p['members']:
  i=zipfile.ZipInfo(name,(2026,10,7,0,0,0)); i.create_system=3
  i.external_attr=p['mode'] << p['shift']
  i.compress_type=zipfile.ZIP_STORED
  z.writestr(i,base64.b64decode(p['body']))
b=bytearray(out.getvalue())
if p['encrypted']:
 struct.pack_into('<H',b,6,1); struct.pack_into('<H',b,b.index(b'PK\\x01\\x02')+8,1)
if p['unsupported']:
 struct.pack_into('<H',b,8,99); struct.pack_into('<H',b,b.index(b'PK\\x01\\x02')+10,99)
sys.stdout.buffer.write(b)
`], {
    input: JSON.stringify({ members: options.members ?? [filename], body: body.toString('base64'), mode: options.mode ?? 0o100600, shift: limits.artifactUnixModeShiftBits, encrypted: options.encrypted ?? false, unsupported: options.unsupported ?? false }),
    timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs,
    maxBuffer: NATIVE_DB_VALIDATION.maxProcessBytes,
    stdio: ['pipe', 'pipe', 'pipe'],
  });
  const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
  const artifact = { id: 77, expired: false, size_in_bytes: zip.length, digest: `sha256:${hash(zip)}`, ...options.artifact };
  const archiveBytes = options.corrupt ? Buffer.from(zip) : (options.storageBytes ?? zip);
  if (options.corrupt) archiveBytes[0] ^= 1;
  const storageUrl = options.location === undefined ? 'https://storage.fixture.invalid/verified.zip?signature=synthetic' : options.location;
  const fetch = async (url, init = {}) => {
    const address = typeof url === 'string' ? url : (url.url ?? String(url));
    trace.fetch.push({ address, redirect: init.redirect, signal: init.signal, headers: init.headers });
    if (address.startsWith('https://api.github.com/')) {
      const status = options.apiStatus ?? limits.artifactRedirectStatus;
      if (options.apiError) throw new Error('Synthetic API network error.');
      if (options.apiWaitForAbort) await new Promise((resolve, reject) => {
        if (!init.signal) { reject(new Error('Unbounded synthetic API request.')); return; }
        if (init.signal.aborted) { reject(new Error('Synthetic API aborted.')); return; }
        init.signal.addEventListener('abort', () => reject(new Error('Synthetic API aborted.')), { once: true });
      });
      if (status === limits.artifactRedirectStatus && init.redirect !== 'manual') {
        // Deployed-Octokit-shaped default transport: request.redirect is ignored
        // and a valid signed download is automatically followed to HTTP 200.
        return new Response(archiveBytes, { status: limits.artifactMetadataStatus });
      }
      const headers = storageUrl === null ? {} : { location: storageUrl };
      return new Response(null, { status, headers });
    }
    trace.storage.push({ address, redirect: init.redirect, signal: init.signal, headers: init.headers });
    if (options.storageWaitForAbort) await new Promise((resolve, reject) => {
      if (!init.signal) { reject(new Error('Unbounded synthetic storage request.')); return; }
      if (init.signal.aborted) { reject(new Error('Synthetic storage aborted.')); return; }
      init.signal.addEventListener('abort', () => reject(new Error('Synthetic storage aborted.')), { once: true });
    });
    if (options.storageError) throw new Error('Synthetic storage network error.');
    if (options.storageRedirect) {
      if (init.redirect === 'error') throw new Error('Synthetic storage redirect refused.');
      return new Response(archiveBytes, { status: limits.artifactMetadataStatus });
    }
    const chunks = options.chunks ?? [archiveBytes];
    let chunk = 0;
    const stream = new ReadableStream({ pull(controller) { if (chunk === chunks.length) controller.close(); else controller.enqueue(chunks[chunk++]); } });
    return new Response(stream, { status: options.storageStatus ?? limits.artifactMetadataStatus, headers: { 'content-length': String(options.contentLength ?? archiveBytes.length) } });
  };
  const download = async (parameters) => {
    trace.api.push(parameters);
    const transport = parameters.request?.fetch ?? fetch;
    // Honor only the documented custom request.fetch transport port. Never
    // honor request.redirect, which is the production regression under test.
    const response = await transport('https://api.github.com/repos/OGUN01/gymloop/actions/artifacts/77/zip', { method: 'GET', redirect: 'follow', headers: { authorization: 'Bearer SYNTHETIC_API_ONLY', 'x-api-fixture': 'official-request-only' } });
    return { status: response.status, headers: Object.fromEntries(response.headers.entries()), data: null };
  };
  const github = { rest: { actions: { downloadArtifact: download } }, request: async (_route, parameters) => download(parameters) };
  const execute = Object.getPrototypeOf(async function () {}).constructor;
  const result = await new execute('hash', 'limits', 'github', 'fetch', 'execFileSync', 'context', 'artifact', 'filename', 'JSON', `return (${readers[0]})(artifact, filename);`)(hash, limits, github, fetch, (command, args, settings) => {
    trace.python.push({ command, inputLength: settings.input.length, maxBuffer: settings.maxBuffer, timeout: settings.timeout });
    if (command !== 'python3') throw new Error('Unexpected synthetic archive process.');
    return execFileSync(python, args, settings);
  }, { repo: { owner: 'OGUN01', repo: 'gymloop' } }, artifact, filename, Object.create(JSON, {
    parse: { value: (...args) => { trace.decodeCalls++; return JSON.parse(...args); } },
  }));
  return { result, value, hash: hash(body), archiveSha256: hash(zip), trace, limits };
}

describe('frozen hosted artifact redirect transport', () => {
  it('retrieves the exact valid canonical archive through manual first hop and unauthenticated bounded storage', async () => {
    const observed = await executeNativeArtifactReader();
    expect(observed.result).toEqual({ value: observed.value, hash: observed.hash, archiveSha256: observed.archiveSha256 });
    expect(typeof observed.trace.api[0].request.fetch).toBe('function');
    expect(observed.trace.fetch[0].redirect).toBe('manual');
    expect(observed.trace.fetch[0].signal).toBeInstanceOf(AbortSignal);
    expect(observed.trace.fetch[0].signal.aborted).toBe(false);
    expect(observed.trace.storage).toHaveLength(1);
    expect(observed.trace.storage[0].redirect).toBe('error');
    expect(observed.trace.storage[0].signal).toBeInstanceOf(AbortSignal);
    const storageHeaders = new Headers(observed.trace.storage[0].headers);
    expect(storageHeaders.has('authorization')).toBe(false);
    expect(storageHeaders.has('x-api-fixture')).toBe(false);
    expect(observed.trace.python).toHaveLength(1);
    expect(observed.trace.python[0].maxBuffer).toBe(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes);
    expect(observed.trace.python[0].timeout).toBe(NATIVE_DB_VALIDATION.nativeCleanupReserveMs);
  });

  it('accepts ordinary permission-only ZIP file metadata with every archive check intact', async () => {
    const observed = await executeNativeArtifactReader({ mode: 0o600 });
    expect(observed.result).toEqual({ value: observed.value, hash: observed.hash, archiveSha256: observed.archiveSha256 });
    expect(observed.trace.storage).toHaveLength(1);
    expect(observed.trace.python).toHaveLength(1);
    expect(observed.trace.decodeCalls).toBe(1);
  });

  it('actually aborts a hung first hop using the supplied finite cleanup bound', async () => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    const timer = setTimeout(() => {}, NATIVE_DB_VALIDATION.processStopGraceMs);
    try {
      await expect(executeNativeArtifactReader({ apiWaitForAbort: true, limits: { nativeCleanupReserveMs: 20 } }, trace)).rejects.toThrow();
      expect(trace.fetch[0].redirect).toBe('manual');
      expect(trace.fetch[0].signal).toBeInstanceOf(AbortSignal);
      expect(trace.fetch[0].signal.aborted).toBe(true);
      expect(trace.storage).toHaveLength(0);
    } finally { clearTimeout(timer); }
  });

  it('actually aborts a hung unauthenticated storage request using the supplied finite cleanup bound', async () => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    const timer = setTimeout(() => {}, NATIVE_DB_VALIDATION.processStopGraceMs);
    try {
      await expect(executeNativeArtifactReader({ storageWaitForAbort: true, limits: { nativeCleanupReserveMs: 20 } }, trace)).rejects.toThrow();
      expect(trace.fetch[0].redirect).toBe('manual');
      expect(trace.storage).toHaveLength(1);
      expect(trace.storage[0].redirect).toBe('error');
      expect(trace.storage[0].signal).toBeInstanceOf(AbortSignal);
      expect(trace.storage[0].signal.aborted).toBe(true);
      expect(new Headers(trace.storage[0].headers).has('authorization')).toBe(false);
      expect(trace.python).toHaveLength(0);
    } finally { clearTimeout(timer); }
  });

  it.each([
    ['automatically followed success', { apiStatus: NATIVE_DB_VALIDATION.artifactMetadataStatus }],
    ['wrong redirect status', { apiStatus: 301 }],
    ['missing location', { location: null }],
    ['relative location', { location: '/archive.zip' }],
    ['plain HTTP', { location: 'http://storage.fixture.invalid/archive.zip' }],
    ['URL credentials', { location: 'https://username:password@storage.fixture.invalid/archive.zip' }],
    ['URL fragment', { location: 'https://storage.fixture.invalid/archive.zip#hidden' }],
    ['API network failure', { apiError: true }],
  ])('refuses %s before separate storage access', async (_name, options) => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    await expect(executeNativeArtifactReader(options, trace)).rejects.toThrow();
    expect(trace.storage).toHaveLength(0);
    expect(trace.python).toHaveLength(0);
  });

  it.each([
    ['expired metadata', { expired: true }],
    ['zero declared size', { size_in_bytes: 0 }],
    ['negative declared size', { size_in_bytes: -1 }],
    ['nonintegral declared size', { size_in_bytes: 1.5 }],
    ['missing API digest', { digest: null }],
  ])('refuses %s without archive processing', async (_name, artifact) => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    await expect(executeNativeArtifactReader({ artifact }, trace)).rejects.toThrow();
    expect(trace.python).toHaveLength(0);
  });

  it.each([
    ['storage redirect', { storageRedirect: true }],
    ['storage network failure', { storageError: true }],
    ['storage error status', { storageStatus: 403 }],
    ['storage byte corruption', { corrupt: true }],
    ['wrong declared API size', { artifact: { size_in_bytes: 1 } }],
    ['oversized stream', { limits: { maxProcessBytes: 1024 }, chunks: [Buffer.alloc(1025)] }],
  ])('refuses %s after genuine manual redirect but before Python', async (_name, options) => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    await expect(executeNativeArtifactReader(options, trace)).rejects.toThrow();
    expect(trace.fetch[0].redirect).toBe('manual');
    expect(trace.storage).toHaveLength(1);
    expect(trace.python).toHaveLength(0);
  });

  it.each([
    ['wrong member', { members: ['other.json'] }],
    ['duplicate member', { members: ['receipt.json', 'receipt.json'] }],
    ['directory member', { mode: 0o040600 }],
    ['symlink member', { mode: 0o120600 }],
    ['unsupported FIFO file type', { mode: 0o010600 }],
    ['encrypted member', { encrypted: true }],
    ['unsupported compression', { unsupported: true }],
    ['malformed JSON', { body: Buffer.from('{"broken":\n') }],
    ['noncanonical JSON', { body: Buffer.from(' {"formatVersion":1}\n') }],
    ['oversized member', { body: Buffer.from(`${JSON.stringify({ pad: 'x'.repeat(NATIVE_DB_VALIDATION.timeoutQueryMaxBytes) })}\n`) }],
  ])('refuses %s through the real controlled archive boundary', async (_name, options) => {
    const trace = { api: [], fetch: [], storage: [], python: [] };
    await expect(executeNativeArtifactReader(options, trace)).rejects.toThrow();
    if (_name === 'oversized member') expect(trace.decodeCalls).toBe(0);
    else {
      expect(trace.storage).toHaveLength(1);
      expect(trace.python).toHaveLength(1);
    }
  });
});
