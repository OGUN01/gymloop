import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createContext, runInContext } from 'node:vm';
import { deflateRawSync } from 'node:zlib';
import ts from 'typescript';
import { describe, expect, it, vi } from 'vitest';
import { NATIVE_DB_VALIDATION as limits } from '../../packages/shared/src/config/constants';

// Authored from frozen historical-timeout-recovery.md at 1bc5e5d5.
// Source access below is mechanical extraction of the four declared boundaries.
type HistvRecord = Record<string, unknown>;
type HistvCallable = (...args: unknown[]) => unknown;
const histvFixture = {
  targetRun: '37556363035', targetAttempt: '1', currentRun: '37570000123', currentAttempt: '2',
  originalSource: 'a'.repeat(limits.sourceShaLength), currentSource: 'b'.repeat(limits.sourceShaLength),
  repositoryId: 721923, manifestId: 92001, recoveryId: 92002, restorationId: 92003, guardianId: 93001,
  capturedAt: '2026-10-07T01:00:00.000Z', completedAt: '2026-10-07T01:20:00.000Z',
  verifiedAt: '2026-10-07T02:00:00.000Z', guardianCompletedAt: '2026-10-07T02:15:00.000Z', reviewedAt: '2026-10-07T03:00:00.000Z',
  workflowPath: '.github/workflows/native-database-recovery.yml',
  unixRegular: 0o100600, unixPermissionOnly: 0o600, unixSymlink: 0o120777, unixDirectory: 0o040755,
  zipLocalBytes: 30, zipCentralBytes: 46, zipEndBytes: 22, zipMadeByUnix: 0x0314,
  crcPolynomial: 0xedb88320, crcInitial: 0xffffffff,
};
const histvWorkdir = '/fixture/current-source';
const histvDirectory = '/fixture/private-recovery';

function histvBytes(value: unknown): Buffer { return Buffer.from(`${JSON.stringify(value)}\n`); }
function histvHash(bytes: unknown): string { return createHash('sha256').update(bytes as Buffer).digest('hex'); }
function histvExact(value: unknown, keys: string[]): boolean {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    && Object.keys(value).length === keys.length && keys.every(key => Object.hasOwn(value, key));
}
function histvOriginal(value: unknown): boolean {
  if (!histvExact(value, ['originalPresent', 'originalValue'])) return false;
  const row = value as HistvRecord;
  return row.originalPresent === false ? row.originalValue === null
    : row.originalPresent === true && typeof row.originalValue === 'string' && row.originalValue.length > 0;
}
function histvRestoration(value: unknown, receipt: HistvRecord, recoveryHash: string): boolean {
  if (!histvExact(value, ['formatVersion', 'runId', 'sourceSha', 'manifestSha256', 'recoverySha256', 'original', 'observed', 'verified', 'verifiedAt'])) return false;
  const row = value as HistvRecord;
  const verifiedAt = row.verifiedAt;
  const original = row.original as HistvRecord; const observed = row.observed as HistvRecord; const captured = receipt.original as HistvRecord;
  return row.formatVersion === limits.formatVersion && row.runId === receipt.runId && row.sourceSha === receipt.sourceSha
    && row.manifestSha256 === receipt.manifestSha256 && row.recoverySha256 === recoveryHash
    && histvOriginal(row.original) && histvOriginal(row.observed)
    && original.originalPresent === captured.originalPresent && original.originalValue === captured.originalValue
    && observed.originalPresent === captured.originalPresent && observed.originalValue === captured.originalValue
    && row.verified === true && typeof verifiedAt === 'string' && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(verifiedAt)
    && Number.isFinite(Date.parse(verifiedAt)) && Date.parse(verifiedAt) >= 0 && new Date(verifiedAt).toISOString() === verifiedAt;
}
function histvRefuse(code: string): never { throw Object.assign(new Error('Fixture boundary refused.'), { code }); }
function histvManifest(): HistvRecord {
  return { formatVersion: limits.formatVersion, sourceSha: histvFixture.originalSource,
    schemaIdentity: { migrationsSha256: 'c'.repeat(limits.digestHexLength), generatedTypesSha256: 'd'.repeat(limits.digestHexLength) },
    files: [{ path: 'supabase/tests/fixture.sql', sha256: 'e'.repeat(limits.digestHexLength), plan: 1 },
      { path: 'supabase/tests-holdout/fixture.pg', sha256: 'f'.repeat(limits.digestHexLength), plan: 1 }] };
}
function histvRecovery(manifest = histvManifest()): HistvRecord {
  return { formatVersion: limits.formatVersion, runId: `${histvFixture.targetRun}-${histvFixture.targetAttempt}`,
    sourceSha: histvFixture.originalSource, manifestSha256: histvHash(histvBytes(manifest)),
    target: { projectRef: limits.projectRef, role: limits.role, parameter: limits.parameter },
    original: { originalPresent: true, originalValue: '120000ms' }, capturedAt: histvFixture.capturedAt, armed: true };
}
function histvRuntime(): HistvRecord {
  return { GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: limits.repository, GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_REF: limits.mainRef, GITHUB_SHA: histvFixture.currentSource, GITHUB_RUN_ID: histvFixture.currentRun,
    GITHUB_RUN_ATTEMPT: histvFixture.currentAttempt,
    GITHUB_WORKFLOW_REF: `${limits.repository}/${histvFixture.workflowPath}@${limits.mainRef}`,
    GITHUB_JOB: 'timeout-guardian', RUNNER_OS: 'Linux', RUNNER_ENVIRONMENT: 'github-hosted',
    GITHUB_WORKSPACE: histvWorkdir, RUNNER_TEMP: '/fixture/temp', GITHUB_API_URL: 'https://api.github.com',
    GITHUB_TOKEN: 'synthetic-official-api-token' };
}
function histvRun(recovery = false): HistvRecord {
  return { id: Number(recovery ? histvFixture.currentRun : histvFixture.targetRun),
    run_attempt: Number(recovery ? histvFixture.currentAttempt : histvFixture.targetAttempt),
    head_sha: recovery ? histvFixture.currentSource : histvFixture.originalSource,
    event: recovery ? 'workflow_dispatch' : 'push', head_branch: 'main', status: 'completed',
    conclusion: recovery ? 'success' : 'failure', path: recovery ? histvFixture.workflowPath : '.github/workflows/db.yml',
    repository: { id: histvFixture.repositoryId, full_name: limits.repository },
    head_repository: { id: histvFixture.repositoryId, full_name: limits.repository } };
}
function histvArtifact(name: string, id: number, bytes: Buffer, recovery = false): HistvRecord {
  return { id, name, expired: false, digest: `sha256:${histvHash(bytes)}`, size_in_bytes: bytes.length,
    workflow_run: { id: Number(recovery ? histvFixture.currentRun : histvFixture.targetRun),
      head_sha: recovery ? histvFixture.currentSource : histvFixture.originalSource,
      repository_id: histvFixture.repositoryId, head_repository_id: histvFixture.repositoryId } };
}
async function histvExtract(name: string, ports: HistvRecord, inline = false): Promise<HistvCallable> {
  let text = await readFile(resolve(inline ? '.github/workflows/db.yml' : 'scripts/native-database-validation.mjs'), 'utf8');
  if (inline) {
    const lines = text.split(/\r?\n/);
    const step = lines.findIndex(line => line.includes('name: Require the previous armed attempt\'s verified restoration'));
    if (step < 0) throw new Error('Declared preflight step is missing.');
    const script = lines.findIndex((line, index) => index > step && /script:\s*\|/.test(line));
    const first = lines[script + 1];
    const indent = first?.match(/^\s*/)?.[0].length ?? 0;
    const body: string[] = [];
    for (const line of lines.slice(script + 1)) {
      if (line.trim() && (line.match(/^\s*/)?.[0].length ?? 0) < indent) break;
      body.push(line.slice(indent));
    }
    text = body.join('\n');
  }
  const tree = ts.createSourceFile('mechanical-boundary.js', text, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  let declaration: string | undefined;
  function histvVisit(node: ts.Node): void {
    if (ts.isFunctionDeclaration(node) && node.name?.text === name) declaration = node.getText(tree);
    if (ts.isVariableDeclaration(node) && node.name.getText(tree) === name && node.initializer
      && (ts.isArrowFunction(node.initializer) || ts.isFunctionExpression(node.initializer))) declaration = node.initializer.getText(tree);
    ts.forEachChild(node, histvVisit);
  }
  histvVisit(tree);
  if (!declaration) return name === 'boundRecoveryReceipt'
    ? () => { throw new Error(`Declared boundary missing: ${name}`); }
    : async () => { throw new Error(`Declared boundary missing: ${name}`); };
  const context = createContext({ Buffer, URL, Response, Headers, AbortSignal, TextDecoder, TextEncoder,
    process: { platform: 'linux', execPath: process.execPath, cwd: () => histvWorkdir },
    limits, NATIVE_DB_VALIDATION: limits, target: { projectRef: limits.projectRef, role: limits.role, parameter: limits.parameter },
    hash: histvHash, jsonBytes: histvBytes, exact: histvExact,
    validOriginal: histvOriginal, original: histvOriginal,
    sourceString: (value: unknown) => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value),
    source: (value: unknown) => typeof value === 'string' && /^[a-f0-9]{40}$/.test(value),
    digest: (value: unknown) => typeof value === 'string' && /^[a-f0-9]{64}$/.test(value),
    refuse: histvRefuse, join: (...parts: string[]) => parts.join('/'), resolve, ...ports });
  return runInContext(`(${declaration})`, context) as HistvCallable;
}
function histvZip(body: Buffer, filename: string, options: HistvRecord = {}): Buffer {
  const name = Buffer.from(filename);
  const method = options.method === undefined ? 0 : Number(options.method);
  const payload = method === 8 ? deflateRawSync(body) : body;
  let crc = histvFixture.crcInitial;
  for (const byte of body) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ ((crc & 1) ? histvFixture.crcPolynomial : 0);
  }
  crc = (crc ^ histvFixture.crcInitial) >>> 0;
  const local = Buffer.alloc(histvFixture.zipLocalBytes);
  local.writeUInt32LE(0x04034b50); local.writeUInt16LE(20, 4); local.writeUInt16LE(options.encrypted ? 1 : 0, 6);
  local.writeUInt16LE(method, 8); local.writeUInt32LE(crc, 14); local.writeUInt32LE(payload.length, 18);
  local.writeUInt32LE(body.length, 22); local.writeUInt16LE(name.length, 26);
  const central = Buffer.alloc(histvFixture.zipCentralBytes);
  central.writeUInt32LE(0x02014b50); central.writeUInt16LE(histvFixture.zipMadeByUnix, 4); central.writeUInt16LE(20, 6);
  central.writeUInt16LE(options.encrypted ? 1 : 0, 8); central.writeUInt16LE(method, 10);
  central.writeUInt32LE(crc, 16); central.writeUInt32LE(payload.length, 20); central.writeUInt32LE(body.length, 24);
  central.writeUInt16LE(name.length, 28);
  central.writeUInt32LE((Number(options.mode ?? histvFixture.unixRegular) << limits.artifactUnixModeShiftBits) >>> 0, 38);
  let localMember = Buffer.concat([local, name, payload]);
  let centralMember = Buffer.concat([central, name]);
  if (options.duplicate) {
    const secondCentral = Buffer.from(central); secondCentral.writeUInt32LE(localMember.length, 42);
    localMember = Buffer.concat([localMember, localMember]);
    centralMember = Buffer.concat([centralMember, secondCentral, name]);
  }
  const end = Buffer.alloc(histvFixture.zipEndBytes);
  end.writeUInt32LE(0x06054b50); end.writeUInt16LE(options.duplicate ? 2 : 1, 8); end.writeUInt16LE(options.duplicate ? 2 : 1, 10);
  end.writeUInt32LE(centralMember.length, 12); end.writeUInt32LE(localMember.length, 16);
  return Buffer.concat([localMember, centralMember, end]);
}
async function histvTransport(options: HistvRecord = {}) {
  const body = options.body instanceof Buffer ? options.body : histvBytes({ fixture: 'receipt' });
  const filename = String(options.filename ?? 'recovery.json');
  const archive = options.archive instanceof Buffer ? options.archive : histvZip(body, String(options.member ?? filename), options);
  const artifact = { ...histvArtifact('fixture-receipt', histvFixture.recoveryId, archive), ...(options.artifact as HistvRecord ?? {}) };
  const api = vi.fn(async (_runtime: unknown, _path: string, expectedStatus: number) => {
    void _runtime; void _path;
    const status = Number(options.apiStatus ?? limits.artifactRedirectStatus);
    if (status !== expectedStatus) histvRefuse('RECEIPT_UNAVAILABLE');
    return new Response(null, { status,
      headers: options.location === null ? {} : { location: String(options.location ?? 'https://storage.example/receipt.zip?signature=fixture') } });
  });
  const storage = vi.fn(async (_url: string, _options: RequestInit) => {
    void _url; void _options;
    if (options.networkFailure) throw new Error('synthetic network refusal');
    return new Response(new Uint8Array(archive), { status: Number(options.storageStatus ?? limits.artifactMetadataStatus) });
  });
  const bounded = vi.fn(async (response: Response, limit: number) => {
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > limit) histvRefuse('RECEIPT_UNAVAILABLE');
    return bytes;
  });
  const python = vi.fn((command: string, args: string[], opts: HistvRecord) => {
    expect(command).toBe('python3');
    expect(args[0]).toBe('-c');
    expect(args.slice(-3)).toEqual([filename, String(limits.timeoutQueryMaxBytes), String(limits.artifactUnixModeShiftBits)]);
    expect(opts).toMatchObject({ maxBuffer: limits.timeoutQueryMaxBytes, timeout: limits.nativeCleanupReserveMs,
      stdio: ['pipe', 'pipe', 'pipe'] });
    return execFileSync('python', args, opts);
  });
  const reader = await histvExtract('readReceiptArtifact', { artifactApi: api, boundedResponseBytes: bounded,
    fetch: storage, execFileSync: python });
  return { body, archive, artifact, api, storage, python, reader, runtime: histvRuntime(), filename };
}
async function histvPrior(options: HistvRecord = {}) {
  const manifest = { ...histvManifest(), ...(options.manifest as HistvRecord ?? {}) };
  const receipt = { ...histvRecovery(manifest), ...(options.receipt as HistvRecord ?? {}) };
  const manifestBody = histvBytes(manifest); const receiptBody = histvBytes(receipt);
  const run = { ...histvRun(), ...(options.run as HistvRecord ?? {}) };
  const runtime = { ...histvRuntime(), ...(options.runtime as HistvRecord ?? {}) };
  const opts = { '--manifest': `${histvDirectory}/manifest.json`, '--receipt': `${histvDirectory}/recovery.json`,
    '--out-dir': histvDirectory, '--source-sha': histvFixture.currentSource,
    '--target-run-id': histvFixture.targetRun, '--target-run-attempt': histvFixture.targetAttempt,
    ...(options.opts as HistvRecord ?? {}) };
  const artifacts = options.artifacts as HistvRecord[] | undefined ?? [
    histvArtifact(`native-db-manifest-${histvFixture.targetRun}-${histvFixture.targetAttempt}`, histvFixture.manifestId, manifestBody),
    histvArtifact(`native-db-recovery-${histvFixture.targetRun}-${histvFixture.targetAttempt}`, histvFixture.recoveryId, receiptBody) ];
  const events: string[] = []; const files = new Map<string, Buffer>();
  const checked = vi.fn(async (command: string, args: string[]) => {
    events.push(`${command}:${args.join(' ')}`);
    if (command === 'git') return `${options.gitSource ?? histvFixture.currentSource}\n`;
    if (args[0] === '--version') return `${options.cliVersion ?? limits.cliVersion}\n`;
    if (command === 'supabase' && args[0] === 'link') return '';
    throw new Error('Forbidden synthetic native effect.');
  });
  const api = vi.fn(async (_runtime: unknown, path: string, status: number) => {
    expect(status).toBe(limits.artifactMetadataStatus);
    events.push(`api:${path}`);
    let value: unknown;
    if (path === `actions/runs/${histvFixture.targetRun}/attempts/${histvFixture.targetAttempt}`) value = run;
    else if (path.startsWith(`actions/runs/${histvFixture.targetRun}/artifacts?page=`)) {
      const page = Number(path.split('=').at(-1));
      const pages = options.pages as HistvRecord[][] | undefined;
      value = { total_count: options.total ?? artifacts.length, artifacts: pages ? pages[page - 1] ?? [] : page === 1 ? artifacts : [] };
    } else throw new Error('Unexpected official API path.');
    return new Response(new Uint8Array(histvBytes(value)));
  });
  const readReceipt = vi.fn(async (_runtime: unknown, artifact: HistvRecord, filename: string) => {
    events.push(`download:${filename}`);
    const value = artifact.id === histvFixture.manifestId ? manifest : receipt;
    return { value, hash: histvHash(histvBytes(value)), archiveSha256: String(artifact.digest).slice('sha256:'.length) };
  });
  const privateWrite = vi.fn(async (path: string, bytes: Buffer) => { events.push(`write:${path}`); files.set(path, Buffer.from(bytes)); });
  const validated = vi.fn(async (path: string, originalSource: string) => {
    events.push('manifest-valid'); expect(originalSource).toBe(histvFixture.originalSource);
    expect(files.get(path)).toEqual(manifestBody);
    if (manifest.sourceSha !== originalSource || options.invalidManifest) histvRefuse('MANIFEST_INVALID');
    return manifest;
  });
  const bound = await histvExtract('boundRecoveryReceipt', {});
  const bindPort = vi.fn((...args: unknown[]) => { events.push('recovery-valid'); return bound(...args); });
  const guardian = vi.fn(async (...args: unknown[]) => { events.push('guardian');
    if (options.guardianFailure) throw new Error('Restoration unverified.');
    expect(args[0]).toBe(runtime);
    expect(args[5]).toEqual({ runId: histvFixture.targetRun, runAttempt: histvFixture.targetAttempt, sourceSha: histvFixture.originalSource });
  });
  const read = vi.fn(async (path: string) => {
    if (path.replaceAll('\\', '/').endsWith('/supabase/.temp/project-ref')) {
      events.push('linked-project-read'); return options.linkedProject ?? `${limits.projectRef}\n`;
    }
    if (!files.has(path)) throw new Error('Fixture file unavailable.');
    return files.get(path);
  });
  const recover = await histvExtract('recoverPriorTimeout', { checked, artifactApi: api,
    boundedResponseBytes: async (response: Response, limit: number) => {
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length > limit) histvRefuse('RECEIPT_UNAVAILABLE'); return bytes;
    }, readReceiptArtifact: readReceipt, privateWrite, validatedManifest: validated,
    boundRecoveryReceipt: bindPort, guardian, readFile: read, privateDirectory: async () => histvDirectory });
  return { recover, runtime, opts, manifest, receipt, run, artifacts, checked, api, readReceipt, privateWrite,
    validated, bindPort, guardian, events, read,
    invoke: () => recover(runtime, opts, histvDirectory, histvWorkdir) };
}
function histvJob(native = false): HistvRecord {
  return { id: native ? 93002 : histvFixture.guardianId,
    run_id: Number(native ? histvFixture.targetRun : histvFixture.currentRun),
    head_sha: native ? histvFixture.originalSource : histvFixture.currentSource,
    boundAttempt: Number(native ? histvFixture.targetAttempt : histvFixture.currentAttempt),
    name: native ? 'pgtap' : 'timeout-guardian', status: 'completed', conclusion: native ? 'failure' : 'success',
    runner_id: 94101, runner_name: 'GitHub Actions 94101', runner_group_name: 'GitHub Actions', labels: ['ubuntu-latest'],
    completed_at: native ? histvFixture.completedAt : histvFixture.guardianCompletedAt,
    steps: ['Restore historical role timeout', 'Retain verified restoration metadata', 'Post Run supabase/setup-cli@v3',
      'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job'].map((name, index) => ({
      name, number: index + 1, status: 'completed', conclusion: 'success', started_at: histvFixture.capturedAt,
      completed_at: histvFixture.guardianCompletedAt })) };
}
async function histvHistorical(options: HistvRecord = {}) {
  const receipt = histvRecovery();
  const recovery = { value: receipt, hash: histvHash(histvBytes(receipt)), archiveSha256: '1'.repeat(limits.digestHexLength) };
  const restoration = { formatVersion: limits.formatVersion, runId: receipt.runId, sourceSha: receipt.sourceSha,
    manifestSha256: receipt.manifestSha256, recoverySha256: recovery.hash, original: receipt.original, observed: receipt.original,
    verified: true, verifiedAt: histvFixture.verifiedAt, ...(options.restoration as HistvRecord ?? {}) };
  const outside = { value: restoration, hash: histvHash(histvBytes(restoration)), archiveSha256: '2'.repeat(limits.digestHexLength),
    ...(options.download as HistvRecord ?? {}) };
  const review = { formatVersion: limits.formatVersion, targetRunId: histvFixture.targetRun, targetRunAttempt: histvFixture.targetAttempt,
    targetSourceSha: histvFixture.originalSource, recoveryRunId: histvFixture.currentRun, recoveryRunAttempt: histvFixture.currentAttempt,
    recoverySourceSha: histvFixture.currentSource, guardianJobId: histvFixture.guardianId, restorationArtifactId: histvFixture.restorationId,
    restorationArchiveSha256: '2'.repeat(limits.digestHexLength), privateProofSha256: '3'.repeat(limits.digestHexLength), reviewedAt: histvFixture.reviewedAt,
    ...(options.review as HistvRecord ?? {}) };
  const targetRun = { ...histvRun(), ...(options.targetRun as HistvRecord ?? {}) };
  const recoveryRun = { ...histvRun(true), ...(options.recoveryRun as HistvRecord ?? {}) };
  const job = { ...histvJob(), ...(options.job as HistvRecord ?? {}) };
  const artifact = { ...histvArtifact(`native-db-restoration-${histvFixture.targetRun}-${histvFixture.targetAttempt}-${histvFixture.currentRun}-${histvFixture.currentAttempt}`,
    histvFixture.restorationId, Buffer.from('fixture-zip'), true), digest: `sha256:${review.restorationArchiveSha256}`,
    ...(options.artifact as HistvRecord ?? {}) };
  const jobs = options.jobs as HistvRecord[] | undefined ?? [job];
  const artifacts = options.artifacts as HistvRecord[] | undefined ?? [artifact];
  const observations: string[] = [];
  const getAttempt = vi.fn(async (args: HistvRecord) => {
    observations.push(`attempt:${args.run_id}:${args.attempt_number}`);
    return { data: String(args.run_id) === histvFixture.targetRun ? targetRun : recoveryRun };
  });
  const listJobs = Object.assign(vi.fn(async () => ({ data: { total_count: jobs.length, jobs } })), { kind: 'jobs' });
  const listArtifacts = Object.assign(vi.fn(async () => ({ data: { total_count: artifacts.length, artifacts } })), { kind: 'artifacts' });
  const paginate = Object.assign(vi.fn(async (method: HistvCallable, args: HistvRecord) => {
    observations.push(`list:${(method as HistvCallable & { kind: string }).kind}:${args.run_id}`);
    if (options.incompleteJobs && (method as HistvCallable & { kind: string }).kind === 'jobs') throw new Error('Incomplete job listing.');
    if (options.incompleteArtifacts && (method as HistvCallable & { kind: string }).kind === 'artifacts') throw new Error('Incomplete artifact listing.');
    return (method as HistvCallable & { kind: string }).kind === 'jobs' ? jobs : artifacts;
  }), { iterator: async function* (method: HistvCallable, args: HistvRecord) {
    observations.push(`pages:${(method as HistvCallable & { kind: string }).kind}:${args.run_id}`);
    const data = (method as HistvCallable & { kind: string }).kind === 'jobs' ? jobs : artifacts;
    yield { data: data.slice(0, 1) };
    if (options.incompleteJobs && (method as HistvCallable & { kind: string }).kind === 'jobs') throw new Error('Incomplete job listing.');
    if (options.incompleteArtifacts && (method as HistvCallable & { kind: string }).kind === 'artifacts') throw new Error('Incomplete artifact listing.');
    yield { data: data.slice(1) };
  } });
  const github = { rest: { actions: { getWorkflowRunAttempt: getAttempt, listJobsForWorkflowRunAttempt: listJobs,
    listWorkflowRunArtifacts: listArtifacts } }, paginate };
  const download = vi.fn(async (actual: HistvRecord, filename: string) => {
    observations.push('download'); expect(actual.id).toBe(histvFixture.restorationId); expect(filename).toBe('restoration.json');
    return outside;
  });
  const resolver = await histvExtract('readHistoricalRestoration', { github,
    context: { repo: { owner: 'OGUN01', repo: 'gymloop' }, runId: 37580000123, sha: '4'.repeat(limits.sourceShaLength),
      eventName: 'push', ref: limits.mainRef }, readArtifact: download,
    timeoutRecoveryReviews: options.reviews ?? [review],
    priorJobs: new Map([[Number(histvFixture.targetRun), options.priorJobs ?? [histvJob(true)]]]) }, true);
  return { resolver, receipt, recovery, targetRun, review, job, artifact, outside, download, getAttempt, observations,
    invoke: async () => {
      const value = await resolver(receipt, recovery, targetRun);
      // The frozen resolver returns transport/provenance evidence; its caller
      // retains the existing final exact restoration predicate.
      if (!histvRestoration(value, receipt, recovery.hash)) throw new Error('Final restoration predicate refused.');
      return value;
    } };
}

describe('DBV-007 historical receipt transport', () => {
  it.each(['manifest.json', 'recovery.json'])('returns canonical body and actual archive digests for %s', async filename => {
    const fixture = await histvTransport({ filename });
    await expect(fixture.reader(fixture.runtime, fixture.artifact, filename)).resolves.toEqual({ value: { fixture: 'receipt' },
      hash: histvHash(fixture.body), archiveSha256: histvHash(fixture.archive) });
    expect(fixture.api).toHaveBeenCalledWith(fixture.runtime, `actions/artifacts/${histvFixture.recoveryId}/zip`, limits.artifactRedirectStatus);
    const storageOptions = fixture.storage.mock.calls[0]?.[1];
    expect(storageOptions?.redirect).toBe('error'); expect(storageOptions?.headers).toBeUndefined();
    expect(storageOptions?.signal).toBeDefined(); expect(fixture.python).toHaveBeenCalledOnce();
  });
  it.each([
    ['non-HTTPS', { location: 'http://storage.example/receipt.zip' }],
    ['URL credentials', { location: 'https://token@storage.example/receipt.zip' }],
    ['fragment', { location: 'https://storage.example/receipt.zip#fragment' }],
    ['missing Location', { location: null }], ['followed API status', { apiStatus: 200 }],
    ['storage redirect', { storageStatus: 302 }], ['storage unavailable', { networkFailure: true }],
    ['wrong size', { artifact: { size_in_bytes: 1 } }], ['wrong digest', { artifact: { digest: `sha256:${'0'.repeat(limits.digestHexLength)}` } }],
    ['uppercase digest', { artifact: { digest: `sha256:${'A'.repeat(limits.digestHexLength)}` } }],
    ['expired', { artifact: { expired: true } }], ['zero ID', { artifact: { id: 0 } }],
    ['unsafe ID', { artifact: { id: Number.MAX_SAFE_INTEGER + 1 } }], ['nonpositive size', { artifact: { size_in_bytes: 0 } }],
    ['oversized archive', { artifact: { size_in_bytes: limits.timeoutQueryMaxBytes + 1 } }],
    ['wrong ZIP member', { member: 'other.json' }], ['symlink member', { mode: histvFixture.unixSymlink }],
    ['directory member', { member: 'recovery.json/', mode: histvFixture.unixDirectory }],
    ['encrypted member', { encrypted: true }], ['unsupported compression', { method: 99 }],
    ['duplicate member', { duplicate: true }], ['explicit unsupported file type', { mode: 0o010600 }],
    ['noncanonical JSON', { body: Buffer.from('{ "fixture": "receipt" }\n') }],
    ['missing LF', { body: Buffer.from('{"fixture":"receipt"}') }],
    ['extra LF', { body: Buffer.from('{"fixture":"receipt"}\n\n') }],
    ['oversized member', { body: Buffer.alloc(limits.timeoutQueryMaxBytes + 1) }],
  ])('refuses %s with the existing generic transport code', async (_name, options) => {
    const fixture = await histvTransport(options as HistvRecord);
    await expect(fixture.reader(fixture.runtime, fixture.artifact, fixture.filename)).rejects.toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
  });
  it.each([{ mode: histvFixture.unixPermissionOnly }, { mode: 0 }, { method: 8 }])('accepts ordinary ZIP encoding %j', async options => {
    const fixture = await histvTransport(options);
    await expect(fixture.reader(fixture.runtime, fixture.artifact, fixture.filename)).resolves.toMatchObject({ hash: histvHash(fixture.body) });
  });
  it.each(['restoration.json', '../recovery.json', '', 'manifest.json\0'])('refuses unsupported filename %s before transport', async filename => {
    const fixture = await histvTransport({ filename });
    await expect(fixture.reader(fixture.runtime, fixture.artifact, filename)).rejects.toBeDefined(); expect(fixture.api).not.toHaveBeenCalled();
  });
  it.each([{ RUNNER_OS: 'Windows' }, { RUNNER_ENVIRONMENT: 'self-hosted' }])('requires the hosted Linux runtime %j', async changed => {
    const fixture = await histvTransport();
    await expect(fixture.reader({ ...fixture.runtime, ...changed }, fixture.artifact, fixture.filename)).rejects.toBeDefined();
    expect(fixture.api).not.toHaveBeenCalled();
  });
});

describe('DBV-007 explicit bound armed receipt', () => {
  it.each([{ originalPresent: true, originalValue: '120000ms' }, { originalPresent: false, originalValue: null }])('accepts captured catalog presence %j', async original => {
    const manifest = histvManifest(); const receipt = { ...histvRecovery(manifest), original };
    const bound = await histvExtract('boundRecoveryReceipt', {});
    expect(bound(histvBytes(receipt), manifest, { runId: histvFixture.targetRun, runAttempt: histvFixture.targetAttempt,
      sourceSha: histvFixture.originalSource }, `native-db-recovery-${histvFixture.targetRun}-${histvFixture.targetAttempt}`)).toEqual(receipt);
  });
  it.each([
    { armed: false }, { armed: 'true' }, { formatVersion: 2 }, { runId: `${histvFixture.currentRun}-${histvFixture.currentAttempt}` },
    { sourceSha: histvFixture.currentSource }, { manifestSha256: '0'.repeat(limits.digestHexLength) },
    { target: { projectRef: 'wrong-project', role: limits.role, parameter: limits.parameter } },
    { target: { projectRef: limits.projectRef, role: 'authenticated', parameter: limits.parameter } },
    { target: { projectRef: limits.projectRef, role: limits.role, parameter: 'lock_timeout' } },
    { original: { originalPresent: true, originalValue: null } }, { original: { originalPresent: false, originalValue: '2min' } },
    { original: { originalPresent: true, originalValue: '' } }, { capturedAt: '1969-12-31T23:59:59.000Z' },
    { capturedAt: '+002026-10-07T01:00:00.000Z' }, { capturedAt: '2026-02-30T01:00:00.000Z' },
    { capturedAt: '2026-10-07T01:00:00Z' }, { unexpected: true },
  ])('refuses malformed or rebound recovery %j', async changed => {
    const manifest = histvManifest(); const bound = await histvExtract('boundRecoveryReceipt', {});
    expect(() => bound(histvBytes({ ...histvRecovery(manifest), ...changed }), manifest,
      { runId: histvFixture.targetRun, runAttempt: histvFixture.targetAttempt, sourceSha: histvFixture.originalSource },
      `native-db-recovery-${histvFixture.targetRun}-${histvFixture.targetAttempt}`)).toThrow();
  });
  it('rejects noncanonical body and noncanonical explicit binding', async () => {
    const manifest = histvManifest(); const receipt = histvRecovery(manifest); const bound = await histvExtract('boundRecoveryReceipt', {});
    const binding = { runId: histvFixture.targetRun, runAttempt: histvFixture.targetAttempt, sourceSha: histvFixture.originalSource };
    expect(() => bound(Buffer.from(JSON.stringify(receipt)), manifest, binding, 'fixture')).toThrow();
    expect(() => bound(histvBytes(receipt), manifest, { ...binding, runAttempt: '01' }, 'fixture')).toThrow();
    expect(() => bound(histvBytes(receipt), manifest, { ...binding, extra: true }, 'fixture')).toThrow();
  });
});

describe('DBV-007 dispatch recovery refuses before Cloud', () => {
  it('uses original manifest/receipt and explicit binding after complete official discovery without replacing current identity', async () => {
    const fixture = await histvPrior(); const runtimeBefore = structuredClone(fixture.runtime);
    await expect(fixture.invoke()).resolves.toBeUndefined();
    expect(fixture.runtime).toEqual(runtimeBefore); expect(fixture.guardian).toHaveBeenCalledOnce();
    expect(fixture.checked).toHaveBeenCalledWith('git', ['rev-parse', 'HEAD'], { cwd: histvWorkdir });
    expect(fixture.checked).toHaveBeenCalledWith('supabase', ['--version'], { cwd: histvWorkdir });
    expect(fixture.checked).toHaveBeenCalledWith('supabase', ['link', '--project-ref', limits.projectRef, '--yes'],
      { cwd: histvWorkdir, timeoutMs: limits.nativeCleanupReserveMs });
    const link = fixture.events.indexOf(`supabase:link --project-ref ${limits.projectRef} --yes`);
    expect(fixture.events.indexOf('manifest-valid')).toBeLessThan(link);
    expect(fixture.events.indexOf('recovery-valid')).toBeLessThan(link);
    expect(fixture.events.indexOf('linked-project-read')).toBeGreaterThan(link);
    expect(fixture.events.indexOf('guardian')).toBeGreaterThan(fixture.events.indexOf('linked-project-read'));
  });
  it.each([
    { GITHUB_ACTIONS: 'false' }, { GITHUB_ACTIONS: undefined }, { GITHUB_REPOSITORY: 'attacker/gymloop' },
    { GITHUB_EVENT_NAME: 'push' }, { GITHUB_REF: 'refs/heads/feature' }, { GITHUB_WORKFLOW_REF: limits.workflowRef },
    { GITHUB_JOB: 'pgtap' }, { RUNNER_OS: 'Windows' }, { RUNNER_ENVIRONMENT: 'self-hosted' },
    { GITHUB_RUN_ID: '01' }, { GITHUB_RUN_ATTEMPT: '0' }, { GITHUB_SHA: histvFixture.currentSource.toUpperCase() },
  ])('rejects current identity %j before Cloud', async runtime => {
    const fixture = await histvPrior({ runtime }); await expect(fixture.invoke()).rejects.toBeDefined();
    expect(fixture.checked.mock.calls.filter(([command, args]) => command === 'supabase' && args[0] !== '--version')).toEqual([]);
    expect(fixture.guardian).not.toHaveBeenCalled();
  });
  it.each([
    { gitSource: histvFixture.originalSource }, { cliVersion: '2.109.0' },
    { opts: { '--source-sha': histvFixture.originalSource } }, { opts: { '--target-run-id': '01' } },
    { opts: { '--target-run-attempt': '0' } }, { opts: { '--target-run-attempt': '1.0' } },
    { run: { id: Number(histvFixture.currentRun) } }, { run: { run_attempt: 2 } },
    { run: { status: 'in_progress' } }, { run: { head_branch: 'feature' } },
    { run: { event: 'pull_request' } }, { run: { path: histvFixture.workflowPath } },
    { run: { repository: { id: histvFixture.repositoryId, full_name: 'attacker/gymloop' } } },
    { run: { head_sha: 'A'.repeat(limits.sourceShaLength) } }, { invalidManifest: true },
    { receipt: { sourceSha: histvFixture.currentSource } }, { receipt: { armed: false } },
    { receipt: { manifestSha256: '0'.repeat(limits.digestHexLength) } },
  ])('rejects invalid source, requested target, or official original evidence %j', async options => {
    const fixture = await histvPrior(options); await expect(fixture.invoke()).rejects.toBeDefined();
    expect(fixture.checked.mock.calls.filter(([command, args]) => command === 'supabase' && args[0] !== '--version')).toEqual([]);
    expect(fixture.guardian).not.toHaveBeenCalled();
  });
  it('exhausts artifact pages before linking, including unrelated entries', async () => {
    const seed = await histvPrior();
    const unrelated = { ...seed.artifacts[0], id: 92004, name: 'unrelated' };
    const fixture = await histvPrior({ artifacts: [...seed.artifacts, unrelated], pages: [[seed.artifacts[0]], [unrelated], [seed.artifacts[1]]] });
    await expect(fixture.invoke()).resolves.toBeUndefined();
    expect(fixture.api.mock.calls.map(call => call[1])).toContain(`actions/runs/${histvFixture.targetRun}/artifacts?page=3`);
  });
  it.each(['missing', 'duplicate-name', 'duplicate-id', 'expired', 'wrong-source', 'wrong-run', 'wrong-repository', 'wrong-head-repository', 'bad-digest', 'zero-size', 'unsafe-id', 'inconsistent-total'])('rejects %s artifact evidence before linking', async problem => {
    const seed = await histvPrior(); const artifacts = structuredClone(seed.artifacts);
    if (problem === 'missing') artifacts.pop();
    if (problem === 'duplicate-name') artifacts.push({ ...artifacts[0], id: 92004 });
    if (problem === 'duplicate-id') artifacts.push({ ...artifacts[0], name: 'unrelated' });
    if (problem === 'expired') artifacts[0]!.expired = true;
    if (problem === 'bad-digest') artifacts[0]!.digest = 'sha256:BAD';
    if (problem === 'zero-size') artifacts[0]!.size_in_bytes = 0;
    if (problem === 'unsafe-id') artifacts[0]!.id = Number.MAX_SAFE_INTEGER + 1;
    const provider = artifacts[0]?.workflow_run as HistvRecord;
    if (problem === 'wrong-source') provider.head_sha = histvFixture.currentSource;
    if (problem === 'wrong-run') provider.id = Number(histvFixture.currentRun);
    if (problem === 'wrong-repository') provider.repository_id = histvFixture.repositoryId + 1;
    if (problem === 'wrong-head-repository') provider.head_repository_id = histvFixture.repositoryId + 1;
    const fixture = await histvPrior({ artifacts, ...(problem === 'inconsistent-total' ? { total: -1 } : {}) });
    await expect(fixture.invoke()).rejects.toBeDefined(); expect(fixture.guardian).not.toHaveBeenCalled();
    expect(fixture.checked.mock.calls.filter(([command, args]) => command === 'supabase' && args[0] !== '--version')).toEqual([]);
  });
  it('refuses a freshly wrong link and propagates unverified guardian restoration', async () => {
    const wrong = await histvPrior({ linkedProject: 'wrong-project\n' });
    await expect(wrong.invoke()).rejects.toBeDefined(); expect(wrong.guardian).not.toHaveBeenCalled();
    const failed = await histvPrior({ guardianFailure: true }); await expect(failed.invoke()).rejects.toBeDefined();
  });
});

describe('DBV-007 reviewed cross-run restoration index is never authority', () => {
  it('requires official exact attempts, complete jobs/artifacts and verified original-bound outside receipt', async () => {
    const fixture = await histvHistorical(); await expect(fixture.invoke()).resolves.toEqual(fixture.outside.value);
    expect(fixture.getAttempt.mock.calls.map(([args]) => [String(args.run_id), String(args.attempt_number)])).toContainEqual([histvFixture.targetRun, histvFixture.targetAttempt]);
    expect(fixture.getAttempt.mock.calls.map(([args]) => [String(args.run_id), String(args.attempt_number)])).toContainEqual([histvFixture.currentRun, histvFixture.currentAttempt]);
    expect(fixture.download).toHaveBeenCalledOnce();
  });
  it.each([
    { reviews: [] }, { review: { formatVersion: 2 } }, { review: { targetRunId: '01' } },
    { review: { targetRunAttempt: '2' } }, { review: { targetSourceSha: histvFixture.currentSource } },
    { review: { recoveryRunId: '0' } }, { review: { recoveryRunAttempt: '02' } },
    { review: { recoverySourceSha: 'A'.repeat(limits.sourceShaLength) } }, { review: { guardianJobId: 0 } },
    { review: { restorationArtifactId: Number.MAX_SAFE_INTEGER + 1 } },
    { review: { privateProofSha256: 'BAD' } }, { review: { reviewedAt: '1969-01-01T00:00:00.000Z' } },
    { review: { extra: true } }, { targetRun: { head_sha: histvFixture.currentSource } },
    { recoveryRun: { status: 'in_progress' } }, { recoveryRun: { conclusion: 'failure' } },
    { recoveryRun: { event: 'push' } }, { recoveryRun: { head_branch: 'feature' } },
    { recoveryRun: { path: '.github/workflows/db.yml' } }, { recoveryRun: { run_attempt: 1 } },
    { recoveryRun: { repository: { full_name: 'attacker/gymloop', id: histvFixture.repositoryId } } },
    { recoveryRun: { head_sha: histvFixture.originalSource } }, { jobs: [] },
    { incompleteJobs: true }, { incompleteArtifacts: true },
    { job: { id: histvFixture.guardianId + 1 } }, { job: { head_sha: histvFixture.originalSource } },
    { job: { status: 'in_progress' } }, { job: { conclusion: 'failure' } },
    { job: { runner_group_name: 'private-group', labels: ['self-hosted', 'Linux'] } },
    { job: { labels: ['windows-latest'] } }, { job: { steps: [] } },
    { job: { run_id: Number(histvFixture.targetRun) } }, { job: { runner_name: 'private Linux runner' } },
    { artifacts: [] }, { artifact: { expired: true } }, { artifact: { id: histvFixture.restorationId + 1 } },
    { artifact: { name: 'native-db-restoration-unbound' } },
    { artifact: { workflow_run: { id: Number(histvFixture.targetRun), head_sha: histvFixture.currentSource,
      repository_id: histvFixture.repositoryId, head_repository_id: histvFixture.repositoryId } } },
    { artifact: { workflow_run: { id: Number(histvFixture.currentRun), head_sha: histvFixture.originalSource,
      repository_id: histvFixture.repositoryId, head_repository_id: histvFixture.repositoryId } } },
    { artifact: { workflow_run: { id: Number(histvFixture.currentRun), head_sha: histvFixture.currentSource,
      repository_id: histvFixture.repositoryId + 1, head_repository_id: histvFixture.repositoryId } } },
    { artifact: { digest: `sha256:${'0'.repeat(limits.digestHexLength)}` } },
    { download: { archiveSha256: '0'.repeat(limits.digestHexLength) } },
    { restoration: { verified: false } }, { restoration: { sourceSha: histvFixture.currentSource } },
    { restoration: { runId: `${histvFixture.currentRun}-${histvFixture.currentAttempt}` } },
    { restoration: { recoverySha256: '0'.repeat(limits.digestHexLength) } },
    { restoration: { manifestSha256: '0'.repeat(limits.digestHexLength) } },
    { restoration: { observed: { originalPresent: false, originalValue: null } } },
    { restoration: { verifiedAt: '2026-10-07T00:59:59.000Z' } },
    { restoration: { verifiedAt: '2026-10-07T01:10:00.000Z' } },
    { restoration: { verifiedAt: histvFixture.completedAt } },
    { restoration: { verifiedAt: '2026-02-30T02:00:00.000Z' } },
    { priorJobs: [] },
  ])('keeps prior armed work blocked with conflicting or incomplete evidence %j', async options => {
    const fixture = await histvHistorical(options); await expect(fixture.invoke()).rejects.toBeDefined();
  });
  it('rejects duplicate matching reviews, guardian jobs and outside artifacts across pages', async () => {
    const seed = await histvHistorical();
    for (const options of [{ reviews: [seed.review, seed.review] }, { jobs: [seed.job, { ...seed.job, id: seed.job.id as number + 1 }] },
      { artifacts: [seed.artifact, { ...seed.artifact, id: histvFixture.restorationId + 1 }] }]) {
      const fixture = await histvHistorical(options); await expect(fixture.invoke()).rejects.toBeDefined();
    }
  });
  it('requires successful mandatory post-cleanup and native-worker completion evidence', async () => {
    const seed = histvJob();
    const steps = seed.steps as HistvRecord[];
    for (const name of ['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job']) {
      const fixture = await histvHistorical({ job: { steps: steps.map(step => step.name === name ? { ...step, conclusion: 'skipped' } : step) } });
      await expect(fixture.invoke()).rejects.toBeDefined();
    }
    const unfinished = await histvHistorical({ priorJobs: [{ ...histvJob(true), completed_at: null }] });
    await expect(unfinished.invoke()).rejects.toBeDefined();
  });
});

describe('DBV-007 official restoration publication and narrow command wiring', () => {
  it('parses only the frozen restore-prior keys with an explicit original target and current source', async () => {
    const options = await histvExtract('options', {});
    const expected = { command: 'restore-prior', '--source-sha': histvFixture.currentSource,
      '--manifest': `${histvDirectory}/manifest.json`, '--receipt': `${histvDirectory}/recovery.json`,
      '--out-dir': histvDirectory, '--target-run-id': histvFixture.targetRun, '--target-run-attempt': histvFixture.targetAttempt };
    const argv = ['restore-prior', ...Object.entries(expected).filter(([key]) => key !== 'command').flat()];
    expect(options(argv, histvRuntime())).toEqual(expected);
  });
  it.each(['manifest', 'run', 'verify', 'restore'])('rejects target flags on ordinary command %s', async command => {
    const options = await histvExtract('options', {});
    for (const targetFlag of ['--target-run-id', '--target-run-attempt']) {
      expect(() => options([command, '--manifest', `${histvDirectory}/manifest.json`, '--receipt', `${histvDirectory}/recovery.json`,
        '--out-dir', histvDirectory, '--source-sha', histvFixture.currentSource, targetFlag, '1'], histvRuntime())).toThrow();
    }
  });
  it.each([
    ['--target-run-id', '0'], ['--target-run-id', '01'], ['--target-run-attempt', '0'], ['--target-run-attempt', '1.0'],
  ])('rejects noncanonical restore-prior %s=%s', async (key, value) => {
    const options = await histvExtract('options', {});
    const flags = { '--manifest': `${histvDirectory}/manifest.json`, '--receipt': `${histvDirectory}/recovery.json`,
      '--out-dir': histvDirectory, '--source-sha': histvFixture.currentSource,
      '--target-run-id': histvFixture.targetRun, '--target-run-attempt': histvFixture.targetAttempt, [key]: value };
    expect(() => options(['restore-prior', ...Object.entries(flags).flat()], histvRuntime())).toThrow();
  });
  it.each(['--target-run-id', '--target-run-attempt'])('requires %s and refuses duplicate or unknown recovery flags', async missing => {
    const options = await histvExtract('options', {});
    const flags = { '--manifest': `${histvDirectory}/manifest.json`, '--receipt': `${histvDirectory}/recovery.json`,
      '--out-dir': histvDirectory, '--source-sha': histvFixture.currentSource,
      '--target-run-id': histvFixture.targetRun, '--target-run-attempt': histvFixture.targetAttempt };
    expect(() => options(['restore-prior', ...Object.entries(flags).filter(([key]) => key !== missing).flat()], histvRuntime())).toThrow();
    expect(() => options(['restore-prior', ...Object.entries(flags).flat(), missing, '1'], histvRuntime())).toThrow();
    expect(() => options(['restore-prior', ...Object.entries(flags).flat(), '--sql', 'forbidden'], histvRuntime())).toThrow();
  });
  it('provides one dispatch-only hosted recovery job with original-target named official upload and shared serialization', async () => {
    const workflow = await readFile(resolve('.github/workflows/native-database-recovery.yml'), 'utf8').catch(() => '');
    expect(workflow).toContain('workflow_dispatch:'); expect(workflow).toMatch(/target_run_id:[\s\S]*required:\s*true/);
    expect(workflow).toMatch(/target_run_attempt:[\s\S]*required:\s*true/);
    expect(workflow).toContain('db-${{ github.ref }}'); expect(workflow).toMatch(/cancel-in-progress:\s*false/);
    expect(workflow).toMatch(/contents:\s*read/); expect(workflow).toMatch(/actions:\s*read/);
    expect(workflow).toMatch(/timeout-guardian:/); expect(workflow).toMatch(/runs-on:\s*ubuntu-latest/);
    expect(workflow).toContain('restore-prior'); expect(workflow).toContain('--target-run-id'); expect(workflow).toContain('--target-run-attempt');
    expect(workflow).toContain('actions/upload-artifact@v5'); expect(workflow).toMatch(/if-no-files-found:\s*error/);
    expect(workflow).toMatch(/native-db-restoration-.*target_run_id.*target_run_attempt.*github.run_id.*github.run_attempt/);
    expect(workflow).not.toMatch(/continue-on-error:\s*true|supabase test db|supabase db push|workflow_call:|pull_request:|^\s+seed:/m);
  });
  it('publishes future guardian canonical restoration through official upload after restore even on failure', async () => {
    const workflow = await readFile(resolve('.github/workflows/db.yml'), 'utf8');
    const job = workflow.slice(workflow.indexOf('\n  timeout-guardian:'));
    expect(job).toContain('actions/upload-artifact@v5');
    expect(job).toMatch(/if-no-files-found:\s*error/); expect(job).toContain('restoration.json');
    expect(job).toContain('native-db-restoration-'); expect(job).toContain('${{ github.run_attempt }}');
    const upload = job.slice(job.indexOf('actions/upload-artifact@v5'));
    expect(upload).toMatch(/name:\s*\$\{\{\s*steps\.recovery\.outputs\.restoration\s*\}\}/);
    expect(job).toMatch(/if:.*always\(\).*recovery/);
    expect(job).not.toMatch(/continue-on-error:\s*true/);
  });
  it('registers restore-prior in adapter routing and target flags without any runtime identity replacement', async () => {
    const source = await readFile(resolve('scripts/native-database-validation.mjs'), 'utf8');
    expect(source).toContain('restore-prior'); expect(source).toContain('--target-run-id'); expect(source).toContain('--target-run-attempt');
    expect(source).toMatch(/recoverPriorTimeout\(runtime,\s*opts,/);
    expect(source).not.toMatch(/runtime\.GITHUB_(?:RUN_ID|RUN_ATTEMPT|SHA)\s*=/);
  });
});
