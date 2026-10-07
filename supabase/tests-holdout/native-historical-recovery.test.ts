import { execFileSync as executeLocalFile } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS } from '../../packages/shared/src/config/constants';

async function executeHeldHistoricalRecovery(options: {
  port?: 'recover' | 'transport' | 'inline' | 'workflow' | 'options';
  scenario?: string;
  filename?: string;
  runtimePatch?: Record<string, string>;
  optionPatch?: Record<string, string>;
  ordinaryCommand?: string;
} = {}) {
  const port = options.port ?? 'recover';
  const scenario = options.scenario ?? 'valid';
  const adapter = readFileSync(resolve('scripts/native-database-validation.mjs'), 'utf8');
  const workflow = readFileSync(resolve('.github/workflows/db.yml'), 'utf8');
  let recoveryWorkflow = '';
  try { recoveryWorkflow = readFileSync(resolve('.github/workflows/native-database-recovery.yml'), 'utf8'); } catch { /* New frozen boundary is genuinely absent before construction. */ }
  const extract = (text: string, name: string) => {
    const match = new RegExp(`(?:async )?function ${name}\\(`).exec(text);
    if (!match) return `async function ${name}() { throw refuse('EVIDENCE_INVALID'); }`;
    const start = match.index;
    const indent = text.slice(text.lastIndexOf('\n', start) + 1, start);
    const end = text.indexOf(`\n${indent}}`, start);
    if (end === -1) throw new Error('Mechanical private function boundary is unavailable');
    return text.slice(start, end + `\n${indent}}`.length);
  };
  const hash = (bytes: string | Buffer | Uint8Array) => createHash('sha256').update(bytes).digest('hex');
  const jsonBytes = (value: unknown) => Buffer.from(`${JSON.stringify(value)}\n`);
  const exact = (value: unknown, keys: string[]) => value !== null && typeof value === 'object'
    && !Array.isArray(value) && Object.keys(value).length === keys.length
    && keys.every((key) => Object.hasOwn(value, key));
  const source = Object.assign((value: unknown) => typeof value === 'string'
    && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(value), {
    test: (value: unknown) => typeof value === 'string' && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.sourceShaLength}}$`).test(value),
  });
  const digest = Object.assign((value: unknown) => typeof value === 'string'
    && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(value), {
    test: (value: unknown) => typeof value === 'string' && new RegExp(`^[a-f0-9]{${NATIVE_DB_VALIDATION.digestHexLength}}$`).test(value),
  });
  const original = (value: unknown) => {
    if (!exact(value, ['originalPresent', 'originalValue'])) return false;
    const decoded = value as { originalPresent: unknown; originalValue: unknown };
    return decoded.originalPresent === true ? typeof decoded.originalValue === 'string' && decoded.originalValue.length > 0
      : decoded.originalPresent === false && decoded.originalValue === null;
  };
  const directory = resolve('held-historical-private');
  const workdir = resolve('held-historical-worktree');
  const targetId = '37556363035';
  const targetAttempt = '1';
  const currentId = '9837456123';
  const currentAttempt = '1';
  const targetSource = 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
  const currentSource = 'c'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
  const archivePin = 'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  const capturedAt = '2026-10-06T12:00:00.000Z';
  const nativeCompletedAt = '2026-10-06T12:01:00.000Z';
  const verifiedAt = '2026-10-07T12:00:00.000Z';
  const runtime = {
    GITHUB_ACTIONS: 'true', GITHUB_REPOSITORY: NATIVE_DB_VALIDATION.repository,
    GITHUB_REF: NATIVE_DB_VALIDATION.mainRef, GITHUB_EVENT_NAME: 'workflow_dispatch',
    GITHUB_WORKFLOW_REF: `${NATIVE_DB_VALIDATION.repository}/.github/workflows/native-database-recovery.yml@${NATIVE_DB_VALIDATION.mainRef}`,
    GITHUB_JOB: 'timeout-guardian', RUNNER_ENVIRONMENT: 'github-hosted', RUNNER_OS: 'Linux',
    GITHUB_RUN_ID: currentId, GITHUB_RUN_ATTEMPT: currentAttempt, GITHUB_SHA: currentSource,
    GITHUB_TOKEN: 'held-synthetic-token', ...options.runtimePatch,
  };
  const runtimeBefore = { ...runtime };
  const opts = {
    command: options.ordinaryCommand ?? 'restore-prior', '--manifest': join(directory, 'requested-manifest.json'),
    '--receipt': join(directory, 'requested-recovery.json'), '--out-dir': directory,
    '--source-sha': currentSource, '--target-run-id': targetId, '--target-run-attempt': targetAttempt,
    ...options.optionPatch,
  };
  let manifest = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion, sourceSha: targetSource,
    schemaIdentity: { migrationsSha256: archivePin, generatedTypesSha256: 'd'.repeat(NATIVE_DB_VALIDATION.digestHexLength) },
    files: [{ path: 'supabase/tests/held_historical_manifest.sql', sha256: archivePin, plan: 1 }],
  };
  if (scenario === 'manifest-original-source') manifest = { ...manifest, sourceSha: currentSource };
  if (scenario === 'manifest-invalid-plan') manifest.files[0].plan = 0;
  const manifestBody = jsonBytes(manifest);
  const recoveryValue = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId: `${targetId}-${targetAttempt}`,
    sourceSha: targetSource, manifestSha256: hash(manifestBody),
    target: { projectRef: NATIVE_DB_VALIDATION.projectRef, role: NATIVE_DB_VALIDATION.role, parameter: NATIVE_DB_VALIDATION.parameter },
    original: { originalPresent: true, originalValue: '0' as string | null }, capturedAt, armed: true,
  };
  if (scenario === 'recovery-unarmed') recoveryValue.armed = false;
  if (scenario === 'recovery-wrong-run') recoveryValue.runId = `${currentId}-${currentAttempt}`;
  if (scenario === 'recovery-wrong-source') recoveryValue.sourceSha = currentSource;
  if (scenario === 'recovery-wrong-manifest') recoveryValue.manifestSha256 = 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  if (scenario === 'recovery-wrong-project') recoveryValue.target.projectRef = 'other-project';
  if (scenario === 'recovery-wrong-role') recoveryValue.target.role = 'other-role';
  if (scenario === 'recovery-wrong-parameter') recoveryValue.target.parameter = 'other-parameter';
  if (scenario === 'recovery-invalid-original') recoveryValue.original.originalValue = '';
  if (scenario === 'recovery-invalid-timestamp') recoveryValue.capturedAt = '2026-10-06T12:00:00Z';
  if (scenario === 'original-absent') recoveryValue.original = { originalPresent: false, originalValue: null };
  let recoveryBody = jsonBytes(recoveryValue);
  if (scenario === 'recovery-noncanonical') recoveryBody = Buffer.from(JSON.stringify(recoveryValue));
  const targetRun = {
    id: Number(targetId), run_attempt: Number(targetAttempt), head_sha: targetSource,
    event: 'push', head_branch: 'main', status: 'completed', conclusion: 'failure', path: '.github/workflows/db.yml',
    repository: { id: 701, full_name: NATIVE_DB_VALIDATION.repository },
    head_repository: { id: 701, full_name: NATIVE_DB_VALIDATION.repository },
  };
  if (scenario === 'target-id') targetRun.id = Number(currentId);
  if (scenario === 'target-attempt') targetRun.run_attempt += 1;
  if (scenario === 'target-source') targetRun.head_sha = targetSource.toUpperCase();
  if (scenario === 'target-event') targetRun.event = 'pull_request';
  if (scenario === 'target-branch') targetRun.head_branch = 'feature';
  if (scenario === 'target-status') targetRun.status = 'in_progress';
  if (scenario === 'target-path') targetRun.path = '.github/workflows/other.yml';
  if (scenario === 'target-repository') targetRun.repository.full_name = 'other/repository';
  const recoveryRun = {
    id: Number(currentId), run_attempt: Number(currentAttempt), head_sha: currentSource,
    event: 'workflow_dispatch', head_branch: 'main', status: 'completed', conclusion: 'success',
    path: '.github/workflows/native-database-recovery.yml', repository: { id: 701, full_name: NATIVE_DB_VALIDATION.repository },
    head_repository: { id: 701, full_name: NATIVE_DB_VALIDATION.repository },
  };
  const manifestArtifact = {
    id: 801, name: `native-db-manifest-${targetId}-${targetAttempt}`, expired: false,
    digest: `sha256:${archivePin}`, size_in_bytes: 801,
    workflow_run: { id: Number(targetId), head_sha: targetSource, repository_id: 701, head_repository_id: 701 },
  };
  const recoveryArtifact = {
    ...manifestArtifact, id: 802, name: `native-db-recovery-${targetId}-${targetAttempt}`,
    workflow_run: { ...manifestArtifact.workflow_run },
  };
  let artifacts = [manifestArtifact, recoveryArtifact];
  if (scenario === 'artifact-missing') artifacts = [manifestArtifact];
  if (scenario === 'artifact-duplicate-name') artifacts = [...artifacts, { ...recoveryArtifact, id: 803 }];
  if (scenario === 'artifact-duplicate-id') artifacts = [...artifacts, { ...recoveryArtifact }];
  if (scenario === 'artifact-expired') recoveryArtifact.expired = true;
  if (scenario === 'artifact-id') recoveryArtifact.id = Number.MAX_SAFE_INTEGER + 1;
  if (scenario === 'artifact-size') recoveryArtifact.size_in_bytes = 0;
  if (scenario === 'artifact-digest') recoveryArtifact.digest = `sha256:${archivePin.toUpperCase()}`;
  if (scenario === 'artifact-run') recoveryArtifact.workflow_run.id = Number(currentId);
  if (scenario === 'artifact-source') recoveryArtifact.workflow_run.head_sha = currentSource;
  if (scenario === 'artifact-repository') recoveryArtifact.workflow_run.repository_id += 1;
  if (scenario === 'artifact-head-repository') recoveryArtifact.workflow_run.head_repository_id += 1;
  if (scenario === 'artifact-name') recoveryArtifact.name = 'native-db-recovery-other';
  const binding = { runId: targetId, runAttempt: targetAttempt, sourceSha: targetSource };
  const calls = { api: [] as string[], checked: [] as { command: string; args: string[]; cwd: string }[], guardian: [] as unknown[][],
    manifests: [] as { path: string; source: string }[], bound: [] as unknown[][], writes: [] as { path: string; bytes: Buffer }[],
    storage: [] as { url: string; init: RequestInit | undefined }[], zip: [] as { command: string; args: string[]; input: Buffer }[],
    unexpectedEffects: [] as string[] };
  const files = new Map<string, Buffer>();
  const refuse = (code: string) => Object.assign(new Error(code), { code });
  const restoration = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId: `${targetId}-${targetAttempt}`, sourceSha: targetSource,
    manifestSha256: hash(manifestBody), recoverySha256: hash(recoveryBody),
    original: { ...recoveryValue.original }, observed: { ...recoveryValue.original }, verified: true, verifiedAt,
  };
  if (scenario === 'restoration-false') restoration.verified = false;
  if (scenario === 'restoration-run') restoration.runId = `${currentId}-${currentAttempt}`;
  if (scenario === 'restoration-source') restoration.sourceSha = currentSource;
  if (scenario === 'restoration-manifest') restoration.manifestSha256 = 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  if (scenario === 'restoration-recovery') restoration.recoverySha256 = 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  if (scenario === 'restoration-original') restoration.original.originalValue = 'wrong-original';
  if (scenario === 'restoration-observed') restoration.observed.originalValue = 'wrong-observed';
  if (scenario === 'restoration-before-capture') restoration.verifiedAt = '2026-10-05T12:00:00.000Z';
  if (scenario === 'restoration-before-worker') restoration.verifiedAt = '2026-10-06T12:00:30.000Z';
  const restorationArtifact = {
    id: 902, name: `native-db-restoration-${targetId}-${targetAttempt}-${currentId}-${currentAttempt}`,
    expired: false, digest: `sha256:${archivePin}`, size_in_bytes: 902,
    workflow_run: { id: Number(currentId), head_sha: currentSource, repository_id: 701, head_repository_id: 701 },
  };
  const review = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion, targetRunId: targetId, targetRunAttempt: targetAttempt, targetSourceSha: targetSource,
    recoveryRunId: currentId, recoveryRunAttempt: currentAttempt, recoverySourceSha: currentSource,
    guardianJobId: 901, restorationArtifactId: restorationArtifact.id, restorationArchiveSha256: archivePin,
    privateProofSha256: 'f'.repeat(NATIVE_DB_VALIDATION.digestHexLength), reviewedAt: '2026-10-07T12:10:00.000Z',
  };
  if (scenario === 'review-wrong-target') review.targetSourceSha = currentSource;
  if (scenario === 'review-wrong-pin') review.restorationArchiveSha256 = 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
  if (scenario === 'review-unsafe-id') review.guardianJobId = Number.MAX_SAFE_INTEGER + 1;
  if (scenario === 'review-malformed-source') review.recoverySourceSha = currentSource.toUpperCase();
  const timeoutRecoveryReviews = scenario === 'review-missing' ? [] : scenario === 'review-duplicate' ? [review, { ...review }] : [review];
  const guardianJob = {
    id: review.guardianJobId, run_id: Number(currentId), head_sha: currentSource, name: 'timeout-guardian',
    status: 'completed', conclusion: 'success', runner_id: 901, runner_name: 'GitHub Actions 901', runner_group_name: 'GitHub Actions',
    labels: ['ubuntu-latest'], completed_at: '2026-10-07T12:05:00.000Z',
    steps: [
      { name: 'Post Run supabase/setup-cli@v3', status: 'completed', conclusion: 'success', completed_at: verifiedAt },
      { name: 'Post Run pnpm/action-setup@v6', status: 'completed', conclusion: 'success', completed_at: '2026-10-07T12:02:00.000Z' },
      { name: 'Post Run actions/checkout@v7', status: 'completed', conclusion: 'success', completed_at: '2026-10-07T12:04:00.000Z' },
      { name: 'Complete job', status: 'completed', conclusion: 'success', completed_at: '2026-10-07T12:05:00.000Z' },
    ],
  };
  if (scenario === 'guardian-failure') guardianJob.conclusion = 'failure';
  if (scenario === 'guardian-running') guardianJob.status = 'in_progress';
  if (scenario === 'guardian-source') guardianJob.head_sha = targetSource;
  if (scenario === 'guardian-self-hosted') guardianJob.runner_group_name = 'Self-hosted';
  if (scenario === 'guardian-no-post-cleanup') guardianJob.steps = guardianJob.steps.filter((step) => !step.name.startsWith('Post'));
  if (scenario === 'guardian-post-incomplete') guardianJob.steps.find((step) => step.name.startsWith('Post'))!.status = 'in_progress';
  if (scenario === 'recovery-provider-failure') recoveryRun.conclusion = 'failure';
  if (scenario === 'recovery-provider-event') recoveryRun.event = 'push';
  if (scenario === 'recovery-provider-source') recoveryRun.head_sha = targetSource;
  if (scenario === 'recovery-provider-path') recoveryRun.path = '.github/workflows/db.yml';
  if (scenario === 'recovery-provider-repository') recoveryRun.repository.full_name = 'other/repository';
  if (scenario === 'restoration-artifact-expired') restorationArtifact.expired = true;
  if (scenario === 'restoration-artifact-name') restorationArtifact.name = 'other-restoration';
  if (scenario === 'restoration-artifact-source') restorationArtifact.workflow_run.head_sha = targetSource;
  if (scenario === 'restoration-artifact-run') restorationArtifact.workflow_run.id = Number(targetId);
  if (scenario === 'restoration-artifact-repository') restorationArtifact.workflow_run.repository_id += 1;
  if (scenario === 'restoration-artifact-digest') restorationArtifact.digest = `sha256:${'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}`;
  const nativeWorker = { ...guardianJob, id: 911, run_id: Number(targetId), head_sha: targetSource,
    name: NATIVE_DB_VALIDATION.job, conclusion: 'failure', completed_at: nativeCompletedAt, boundAttempt: Number(targetAttempt) };
  const originalJobs = [nativeWorker];
  const priorJobs = new Map([[Number(targetId), originalJobs]]);
  if (scenario === 'worker-completion-missing') nativeWorker.completed_at = '';
  if (scenario === 'worker-bound-attempt') nativeWorker.boundAttempt += 1;
  let archive = Buffer.from('held-synthetic-archive');
  let wire = jsonBytes({ heldCanonicalReceipt: true });
  const filename = options.filename ?? 'manifest.json';
  if (port === 'transport') {
    if (scenario === 'wire-no-lf') wire = Buffer.from(JSON.stringify({ heldCanonicalReceipt: true }));
    if (scenario === 'wire-extra-lf') wire = Buffer.concat([wire, Buffer.from('\n')]);
    if (scenario === 'wire-whitespace') wire = Buffer.from('{ "heldCanonicalReceipt": true }\n');
    if (scenario === 'wire-malformed') wire = Buffer.from('{invalid}\n');
    archive = executeLocalFile(process.platform === 'win32' ? 'python' : 'python3', ['-c', [
      'import io,sys,zipfile,stat,struct,warnings', 'warnings.filterwarnings("ignore")',
      'name,mode,shift=sys.argv[1],sys.argv[2],int(sys.argv[3])', 'body=sys.stdin.buffer.read()', 'out=io.BytesIO()',
      'entry=zipfile.ZipInfo(name if mode!="zip-wrong-member" else "../"+name)',
      'entry.external_attr=(stat.S_IFREG|stat.S_IRUSR|stat.S_IWUSR)<<shift',
      'if mode=="zip-symlink": entry.external_attr=(stat.S_IFLNK|stat.S_IRUSR|stat.S_IWUSR)<<shift',
      'if mode=="zip-directory": entry=zipfile.ZipInfo(name+"/")',
      'entry.compress_type=zipfile.ZIP_BZIP2 if mode=="zip-unsupported" else zipfile.ZIP_STORED',
      'with zipfile.ZipFile(out,"w") as z:', ' z.writestr(entry,body)',
      ' if mode=="zip-duplicate": z.writestr(entry,body)',
      'payload=bytearray(out.getvalue())',
      'if mode=="zip-encrypted":',
      ' for sig,fmt in [(b"PK\\x03\\x04","<4sH"),(b"PK\\x01\\x02","<4sHH")]:',
      '  pos=payload.find(sig)+struct.calcsize(fmt)',
      '  flag=struct.unpack_from("<H",payload,pos)[0]',
      '  struct.pack_into("<H",payload,pos,flag|1)',
      'sys.stdout.buffer.write(payload)',
    ].join('\n'), filename, scenario, String(NATIVE_DB_VALIDATION.artifactUnixModeShiftBits)], {
      input: wire, maxBuffer: NATIVE_DB_VALIDATION.maxProcessBytes, timeout: NATIVE_DB_VALIDATION.nativeCleanupReserveMs,
    });
    if (scenario === 'zip-bad-bytes') archive = Buffer.from('invalid archive bytes');
  }
  const transportArtifact = { ...manifestArtifact, size_in_bytes: archive.length, digest: `sha256:${hash(archive)}` };
  if (scenario === 'archive-hash') transportArtifact.digest = `sha256:${'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}`;
  if (scenario === 'archive-size') transportArtifact.size_in_bytes += 1;
  if (scenario === 'transport-expired') transportArtifact.expired = true;
  if (scenario === 'transport-id') transportArtifact.id = 0;
  const targetProviderPath = `actions/runs/${targetId}/attempts/${targetAttempt}`;
  const recoveryProviderPath = `actions/runs/${currentId}/attempts/${currentAttempt}`;
  const officialResponse = (value: unknown) => new Response(jsonBytes(value), { status: NATIVE_DB_VALIDATION.artifactMetadataStatus });
  const api = async (_runtime: unknown, path: string, status: number) => {
    calls.api.push(path);
    if (path === targetProviderPath) return officialResponse(targetRun);
    if (path === recoveryProviderPath) return officialResponse(recoveryRun);
    if (path.startsWith(`actions/runs/${targetId}/artifacts?page=`)) {
      const page = Number(path.split('=').at(-1));
      const paginated = scenario === 'pagination' || scenario === 'pagination-total-conflict';
      const selected = paginated ? (page === 1 ? artifacts.slice(0, 1) : page === 1 + 1 ? artifacts.slice(1) : []) : page === 1 ? artifacts : [];
      const total = scenario === 'pagination-total-conflict' && page !== 1 ? artifacts.length + 1 : artifacts.length;
      return officialResponse({ total_count: total, artifacts: selected });
    }
    if (path === `actions/artifacts/${transportArtifact.id}/zip`) {
      const location = scenario === 'redirect-http' ? 'http://storage.held.invalid/archive.zip'
        : scenario === 'redirect-credentials' ? 'https://user:secret@storage.held.invalid/archive.zip'
          : scenario === 'redirect-fragment' ? 'https://storage.held.invalid/archive.zip#fragment' : 'https://storage.held.invalid/archive.zip';
      const response = new Response(null, { status: scenario === 'redirect-status' ? NATIVE_DB_VALIDATION.artifactMetadataStatus : status,
        headers: scenario === 'redirect-missing' ? {} : { location } });
      if (response.status !== status) throw refuse('RECEIPT_UNAVAILABLE');
      return response;
    }
    throw new Error('Unexpected authenticated provider request');
  };
  const jobs = scenario === 'guardian-duplicate' ? [guardianJob, { ...guardianJob, id: 903 }] : [guardianJob];
  const outsideArtifacts = scenario === 'restoration-artifact-duplicate' ? [restorationArtifact, { ...restorationArtifact, id: 904 }] : [restorationArtifact];
  const github = {
    rest: { actions: {
      getWorkflowRunAttempt: async (request: { run_id: number; attempt_number: number }) => {
        const path = `actions/runs/${request.run_id}/attempts/${request.attempt_number}`;
        calls.api.push(path);
        if (path === targetProviderPath) return { data: targetRun };
        if (path === recoveryProviderPath) return { data: recoveryRun };
        throw new Error('Unexpected exact attempt metadata request');
      },
      listJobsForWorkflowRunAttempt: async (request: { run_id: number; attempt_number: number }) => {
        calls.api.push(`actions/runs/${request.run_id}/attempts/${request.attempt_number}/jobs`);
        return { data: { total_count: jobs.length, jobs } };
      },
      listWorkflowRunArtifacts: async (request: { run_id: number }) => {
        calls.api.push(`actions/runs/${request.run_id}/artifacts`);
        return { data: { total_count: outsideArtifacts.length, artifacts: outsideArtifacts } };
      },
    } },
    paginate: async (method: (...args: unknown[]) => unknown, request: unknown) => {
      const result = await method(request) as { data: { jobs?: unknown[]; artifacts?: unknown[] } };
      return result.data.jobs ?? result.data.artifacts ?? [];
    },
  };
  const ports = {
    resolve, join, hash, jsonBytes, exact, source, digest, original, refuse, sourceString: source,
    NATIVE_DB_VALIDATION, PHASE8_BACKUP_LIMITS, limits: NATIVE_DB_VALIDATION,
    target: { projectRef: NATIVE_DB_VALIDATION.projectRef, role: NATIVE_DB_VALIDATION.role, parameter: NATIVE_DB_VALIDATION.parameter },
    process: { execPath: process.execPath, cwd: () => workdir }, Buffer, URL, AbortSignal,
    github, context: { repo: { owner: 'OGUN01', repo: 'gymloop' }, runId: Number(currentId), sha: currentSource },
    timeoutRecoveryReviews, priorJobs,
    artifactApi: api,
    boundedResponseBytes: async (response: Response, limit: number) => {
      const bytes = Buffer.from(await response.arrayBuffer());
      if (bytes.length > limit) throw refuse('RECEIPT_UNAVAILABLE');
      return bytes;
    },
    globalThis: { AbortSignal, fetch: async (url: string | URL, init?: RequestInit) => {
      calls.storage.push({ url: String(url), init });
      return new Response(archive, { status: scenario === 'storage-status' ? NATIVE_DB_VALIDATION.artifactRedirectStatus : NATIVE_DB_VALIDATION.artifactMetadataStatus });
    } },
    execFileSync: (command: string, args: string[], invocation: { input: Buffer; maxBuffer: number; timeout: number; stdio: string[] }) => {
      calls.zip.push({ command, args, input: Buffer.from(invocation.input) });
      if (command !== 'python3') throw new Error('Only the frozen local ZIP decoder may execute');
      return executeLocalFile(process.platform === 'win32' ? 'python' : command, args, invocation);
    },
    checked: async (command: string, args: string[], invocation: { cwd: string }) => {
      calls.checked.push({ command, args, cwd: invocation.cwd });
      if (command === 'git' && args.join(' ') === 'rev-parse HEAD') return `${scenario === 'git-head' ? targetSource : currentSource}\n`;
      if (command === 'supabase' && args.join(' ') === '--version') return `${scenario === 'cli-version' ? '0.0.0' : NATIVE_DB_VALIDATION.cliVersion}\n`;
      if (command === 'supabase' && args.join(' ') === `link --project-ref ${NATIVE_DB_VALIDATION.projectRef} --yes`) return '';
      throw new Error('Unapproved native command');
    },
    privateWrite: async (path: string, bytes: Buffer) => {
      if (files.has(path)) throw refuse('EVIDENCE_INVALID');
      calls.writes.push({ path, bytes: Buffer.from(bytes) }); files.set(path, Buffer.from(bytes));
    },
    readFile: async (path: string, _encoding?: string) => {
      if (path.replaceAll('\\', '/').endsWith('/supabase/.temp/project-ref')) return `${scenario === 'linked-project' ? 'other-project' : NATIVE_DB_VALIDATION.projectRef}\n`;
      const bytes = files.get(path); if (!bytes) throw refuse('EVIDENCE_INVALID'); return _encoding ? bytes.toString('utf8') : bytes;
    },
    readReceiptArtifact: async (_runtime: unknown, artifact: { name: string }, selectedFilename: string) => {
      if (selectedFilename === 'manifest.json' && artifact.name === manifestArtifact.name) return { value: manifest, hash: hash(manifestBody), archiveSha256: archivePin };
      if (selectedFilename === 'recovery.json' && artifact.name === recoveryArtifact.name) return { value: recoveryValue, hash: hash(recoveryBody), archiveSha256: archivePin };
      throw refuse('RECEIPT_UNAVAILABLE');
    },
    validatedManifest: async (path: string, selectedSource: string) => {
      calls.manifests.push({ path, source: selectedSource });
      const bytes = files.get(path);
      if (selectedSource !== targetSource || manifest.sourceSha !== targetSource || !bytes?.equals(manifestBody) || manifest.files.some((file) => file.plan < 1)) throw refuse('EVIDENCE_INVALID');
      return manifest;
    },
    boundRecoveryReceipt: (bytes: Buffer, selectedManifest: unknown, selectedBinding: typeof binding, _artifactName: string) => {
      calls.bound.push([bytes, selectedManifest, selectedBinding, _artifactName]);
      const r = JSON.parse(bytes.toString('utf8')) as typeof recoveryValue;
      if (!bytes.equals(jsonBytes(r)) || !exact(r, ['formatVersion', 'runId', 'sourceSha', 'manifestSha256', 'target', 'original', 'capturedAt', 'armed'])
        || r.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || r.runId !== `${selectedBinding.runId}-${selectedBinding.runAttempt}`
        || r.sourceSha !== selectedBinding.sourceSha || selectedBinding.sourceSha !== targetSource
        || r.manifestSha256 !== hash(jsonBytes(selectedManifest)) || r.armed !== true
        || !exact(r.target, ['projectRef', 'role', 'parameter']) || r.target.projectRef !== NATIVE_DB_VALIDATION.projectRef
        || r.target.role !== NATIVE_DB_VALIDATION.role || r.target.parameter !== NATIVE_DB_VALIDATION.parameter || !original(r.original)
        || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(r.capturedAt) || Date.parse(r.capturedAt) < 0) throw refuse('EVIDENCE_INVALID');
      return r;
    },
    guardian: async (...args: unknown[]) => { calls.guardian.push(args); },
    readArtifact: async (_artifact: unknown, selectedFilename: string) => {
      if (selectedFilename !== 'restoration.json') throw refuse('EVIDENCE_INVALID');
      return { value: restoration, hash: hash(jsonBytes(restoration)), archiveSha256: scenario === 'restoration-archive-hash' ? 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength) : archivePin };
    },
    query: async () => { calls.unexpectedEffects.push('query'); throw new Error('Direct Cloud query is forbidden'); },
    alterTimeout: async () => { calls.unexpectedEffects.push('alter'); throw new Error('Direct timeout alteration is forbidden'); },
    rm: async (path: string) => { files.delete(path); },
  };
  let value: unknown;
  let error: unknown;
  try {
    if (port === 'workflow') value = recoveryWorkflow;
    else {
      const name = port === 'recover' ? 'recoverPriorTimeout' : port === 'transport' ? 'readReceiptArtifact' : port === 'options' ? 'options' : 'readHistoricalRestoration';
      const body = extract(port === 'inline' ? workflow : adapter, name);
      const names = Object.keys(ports).filter((candidate) => candidate !== name);
      const callable = new Function('ports', `
        const { ${names.join(', ')} } = ports;
        ${body}
        return ${name};
      `)(ports) as (...args: unknown[]) => Promise<unknown>;
      const argv = [opts.command, ...Object.entries(opts).filter(([key]) => key !== 'command'
        && (!options.ordinaryCommand || scenario === 'options-with-targets' || !key.startsWith('--target-'))
        && !(scenario === 'options-missing-run' && key === '--target-run-id')
        && !(scenario === 'options-missing-attempt' && key === '--target-run-attempt')).flat()];
      const candidate = port === 'recover' ? await callable(runtime, opts, directory, workdir)
        : port === 'transport' ? await callable(runtime, transportArtifact, filename)
          : port === 'options' ? await callable(argv, runtime)
          : await callable(recoveryValue, { value: recoveryValue, hash: hash(recoveryBody), archiveSha256: archivePin }, targetRun);
      if (port === 'inline') {
        const decoded = candidate as typeof restoration;
        if (!exact(decoded, ['formatVersion', 'runId', 'sourceSha', 'manifestSha256', 'recoverySha256', 'original', 'observed', 'verified', 'verifiedAt'])
          || decoded.formatVersion !== NATIVE_DB_VALIDATION.formatVersion || decoded.runId !== recoveryValue.runId
          || decoded.sourceSha !== recoveryValue.sourceSha || decoded.manifestSha256 !== recoveryValue.manifestSha256
          || decoded.recoverySha256 !== hash(recoveryBody) || !original(decoded.original) || !original(decoded.observed)
          || decoded.original.originalPresent !== recoveryValue.original.originalPresent || decoded.original.originalValue !== recoveryValue.original.originalValue
          || decoded.observed.originalPresent !== recoveryValue.original.originalPresent || decoded.observed.originalValue !== recoveryValue.original.originalValue
          || decoded.verified !== true || typeof decoded.verifiedAt !== 'string'
          || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z$/.test(decoded.verifiedAt)
          || !Number.isSafeInteger(Date.parse(decoded.verifiedAt)) || Date.parse(decoded.verifiedAt) < 0
          || new Date(decoded.verifiedAt).toISOString() !== decoded.verifiedAt) throw refuse('EVIDENCE_INVALID');
      }
      value = candidate;
    }
  } catch (failure) { error = failure; }
  return { value, error, calls, runtime, runtimeBefore, opts, binding, directory, workdir, manifest, recoveryValue, restoration,
    manifestBody, recoveryBody, archive, wire, archiveSha256: hash(archive), targetProviderPath, recoveryProviderPath,
    recoveryWorkflow, guardianSource: extract(adapter, 'guardian'), workflow };
}

describe('held historical recovery provenance and native boundary', () => {
  it('recovers valid original evidence with only the fixed project link and explicit original guardian binding', async () => {
    const result = await executeHeldHistoricalRecovery();
    expect(result.error).toBeUndefined();
    expect(result.value).toBeUndefined();
    expect(result.calls.checked.filter((call) => call.args[0] === 'link')).toEqual([
      { command: 'supabase', args: ['link', '--project-ref', NATIVE_DB_VALIDATION.projectRef, '--yes'], cwd: result.workdir },
    ]);
    expect(result.calls.manifests[0]?.source).toBe(result.binding.sourceSha);
    expect(result.calls.guardian).toHaveLength(1);
    expect(result.calls.guardian[0]?.[0]).toEqual(result.runtimeBefore);
    expect(result.calls.guardian[0]?.[2]).toEqual(result.manifest);
    expect(result.calls.guardian[0]?.[5]).toEqual(result.binding);
    expect(result.runtime).toEqual(result.runtimeBefore);
    expect(result.calls.unexpectedEffects).toHaveLength(0);
  });

  it('exhausts a genuine paginated artifact listing before restoring', async () => {
    const result = await executeHeldHistoricalRecovery({ scenario: 'pagination' });
    expect(result.error).toBeUndefined();
    expect(result.calls.api).toContain('actions/runs/37556363035/artifacts?page=2');
    expect(result.calls.guardian).toHaveLength(1);
  });

  it('restores an originally absent timeout without replacing its captured absence', async () => {
    const result = await executeHeldHistoricalRecovery({ scenario: 'original-absent' });
    expect(result.error).toBeUndefined();
    expect(result.calls.guardian[0]?.[5]).toEqual(result.binding);
    expect(result.recoveryValue.original).toEqual({ originalPresent: false, originalValue: null });
  });

  it.each([
    { GITHUB_ACTIONS: 'false' }, { GITHUB_REPOSITORY: 'other/repository' }, { GITHUB_REF: 'refs/heads/feature' },
    { GITHUB_EVENT_NAME: 'push' }, { GITHUB_WORKFLOW_REF: NATIVE_DB_VALIDATION.workflowRef }, { GITHUB_JOB: 'pgtap' },
    { RUNNER_ENVIRONMENT: 'self-hosted' }, { RUNNER_OS: 'Windows' }, { GITHUB_RUN_ID: '01' }, { GITHUB_RUN_ATTEMPT: '0' },
  ])('refuses a false current Actions identity before Cloud effects: %j', async (runtimePatch) => {
    const result = await executeHeldHistoricalRecovery({ runtimePatch });
    expect(result.error).toBeDefined();
    expect(result.calls.checked.some((call) => call.args[0] === 'link')).toBe(false);
    expect(result.calls.guardian).toHaveLength(0);
    expect(result.calls.unexpectedEffects).toHaveLength(0);
  });

  it.each([
    'git-head', 'cli-version', 'target-id', 'target-attempt', 'target-source', 'target-event', 'target-branch', 'target-status',
    'target-path', 'target-repository', 'artifact-missing', 'artifact-duplicate-name', 'artifact-duplicate-id', 'artifact-expired',
    'artifact-id', 'artifact-size', 'artifact-digest', 'artifact-run', 'artifact-source', 'artifact-repository',
    'artifact-head-repository', 'artifact-name', 'pagination-total-conflict', 'manifest-original-source', 'manifest-invalid-plan',
    'recovery-unarmed', 'recovery-wrong-run', 'recovery-wrong-source', 'recovery-wrong-manifest', 'recovery-wrong-project',
    'recovery-wrong-role', 'recovery-wrong-parameter', 'recovery-invalid-original', 'recovery-invalid-timestamp',
  ])('refuses invalid original evidence before linking or entering the guardian: %s', async (scenario) => {
    const result = await executeHeldHistoricalRecovery({ scenario });
    expect(result.error).toBeDefined();
    expect(result.calls.checked.some((call) => call.args[0] === 'link')).toBe(false);
    expect(result.calls.guardian).toHaveLength(0);
    expect(result.calls.unexpectedEffects).toHaveLength(0);
  });

  it.each(['0', '01', '-1', ' 9', '9.0'])('refuses a noncanonical requested target identifier: %j', async (target) => {
    const result = await executeHeldHistoricalRecovery({ optionPatch: { '--target-run-id': target } });
    expect(result.error).toBeDefined();
    expect(result.calls.checked.some((call) => call.args[0] === 'link')).toBe(false);
    expect(result.calls.guardian).toHaveLength(0);
  });

  it('requires fresh literal link-state agreement before the historical guardian', async () => {
    const result = await executeHeldHistoricalRecovery({ scenario: 'linked-project' });
    expect(result.error).toBeDefined();
    expect(result.calls.guardian).toHaveLength(0);
  });
});

describe('held historical CLI scope', () => {
  it('accepts the new bounded command with both exact positive target flags', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'options' });
    expect(result.error).toBeUndefined();
    expect(result.value).toEqual(result.opts);
  });

  it.each(['options-missing-run', 'options-missing-attempt'])('requires both target identity inputs: %s', async (scenario) => {
    const result = await executeHeldHistoricalRecovery({ port: 'options', scenario });
    expect(result.error).toBeDefined();
  });

  it.each(['0', '01', '-1', ' 9', '9.0'])('refuses a noncanonical target flag in the parser: %j', async (target) => {
    const result = await executeHeldHistoricalRecovery({ port: 'options', optionPatch: { '--target-run-id': target } });
    expect(result.error).toBeDefined();
  });

  it.each(['manifest', 'run', 'verify', 'restore'])('preserves %s and refuses historical target flags on it', async (ordinaryCommand) => {
    const ordinary = await executeHeldHistoricalRecovery({ port: 'options', ordinaryCommand });
    expect(ordinary.error).toBeUndefined();
    expect(ordinary.value).toMatchObject({ command: ordinaryCommand });
    const scoped = await executeHeldHistoricalRecovery({ port: 'options', ordinaryCommand, scenario: 'options-with-targets' });
    expect(scoped.error).toBeDefined();
  });
});

describe('held bounded canonical receipt archive transport', () => {
  it.each(['manifest.json', 'recovery.json'])('decodes only the actual canonical %s ZIP member and archive hash', async (filename) => {
    const result = await executeHeldHistoricalRecovery({ port: 'transport', filename });
    expect(result.error).toBeUndefined();
    expect(result.value).toEqual({ value: { heldCanonicalReceipt: true }, hash: createHash('sha256').update(result.wire).digest('hex'), archiveSha256: result.archiveSha256 });
    expect(result.calls.storage).toHaveLength(1);
    expect(result.calls.storage[0]?.init?.redirect).toBe('error');
    expect(result.calls.storage[0]?.init?.headers).toBeUndefined();
    expect(result.calls.storage[0]?.init?.signal).toBeDefined();
    expect(result.calls.zip[0]?.command).toBe('python3');
    expect(result.calls.zip[0]?.input).toEqual(result.archive);
  });

  it.each([
    'redirect-http', 'redirect-credentials', 'redirect-fragment', 'redirect-status', 'redirect-missing', 'storage-status',
    'archive-hash', 'archive-size', 'zip-bad-bytes', 'zip-wrong-member', 'zip-directory', 'zip-symlink', 'zip-duplicate',
    'zip-unsupported', 'zip-encrypted', 'wire-no-lf', 'wire-extra-lf', 'wire-whitespace', 'wire-malformed', 'transport-expired', 'transport-id',
  ])('retains receipt unavailability for invalid transport or bytes: %s', async (scenario) => {
    const result = await executeHeldHistoricalRecovery({ port: 'transport', scenario });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.value).toBeUndefined();
    expect(result.calls.checked).toHaveLength(0);
    expect(result.calls.guardian).toHaveLength(0);
  });

  it('refuses receipt names outside the two frozen channels', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'transport', filename: 'arbitrary.json' });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.calls.storage).toHaveLength(0);
  });

  it('requires hosted Linux for receipt decoding', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'transport', runtimePatch: { RUNNER_OS: 'Windows' } });
    expect(result.error).toMatchObject({ code: 'RECEIPT_UNAVAILABLE' });
    expect(result.calls.storage).toHaveLength(0);
  });
});

describe('held cross-run restoration provenance', () => {
  it('returns a verified outside restoration only after both exact attempt proofs', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'inline' });
    expect(result.error).toBeUndefined();
    expect(result.value).toEqual(result.restoration);
    expect(result.calls.api).toContain(result.targetProviderPath);
    expect(result.calls.api).toContain(result.recoveryProviderPath);
  });

  it.each([
    'review-missing', 'review-duplicate', 'review-wrong-target', 'review-wrong-pin', 'review-unsafe-id', 'review-malformed-source',
    'recovery-provider-failure', 'recovery-provider-event', 'recovery-provider-source', 'recovery-provider-path',
    'recovery-provider-repository', 'guardian-failure', 'guardian-running', 'guardian-source', 'guardian-self-hosted',
    'guardian-no-post-cleanup', 'guardian-post-incomplete', 'guardian-duplicate', 'restoration-artifact-expired',
    'restoration-artifact-name', 'restoration-artifact-source', 'restoration-artifact-run', 'restoration-artifact-repository',
    'restoration-artifact-digest', 'restoration-artifact-duplicate', 'restoration-archive-hash', 'restoration-false',
    'restoration-run', 'restoration-source', 'restoration-manifest', 'restoration-recovery', 'restoration-original',
    'restoration-observed', 'restoration-before-capture', 'restoration-before-worker', 'worker-completion-missing', 'worker-bound-attempt',
  ])('keeps the shared project blocked on conflicting cross-run evidence: %s', async (scenario) => {
    const result = await executeHeldHistoricalRecovery({ port: 'inline', scenario });
    expect(result.error).toBeDefined();
    expect(result.value).toBeUndefined();
    expect(result.calls.checked).toHaveLength(0);
    expect(result.calls.guardian).toHaveLength(0);
  });

  it('does not let a matching review index override an actual failed provider recovery attempt', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'inline', scenario: 'recovery-provider-failure' });
    expect(result.calls.api).toContain(result.targetProviderPath);
    expect(result.calls.api).toContain(result.recoveryProviderPath);
    expect(result.error).toBeDefined();
    expect(result.value).toBeUndefined();
  });
});

describe('held recovery publication workflow discipline', () => {
  it('provides only the dispatch recovery workflow with the fixed concurrency and read permissions', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'workflow' });
    expect(result.recoveryWorkflow).toMatch(/workflow_dispatch:/);
    expect(result.recoveryWorkflow).toMatch(/target_run_id:/);
    expect(result.recoveryWorkflow).toMatch(/target_run_attempt:/);
    expect(result.recoveryWorkflow).toContain('db-${{ github.ref }}');
    expect(result.recoveryWorkflow).toMatch(/cancel-in-progress:\s*false/);
    expect(result.recoveryWorkflow).toMatch(/contents:\s*read/);
    expect(result.recoveryWorkflow).toMatch(/actions:\s*read/);
    expect(result.recoveryWorkflow).toMatch(/timeout-guardian:/);
    expect(result.recoveryWorkflow).toMatch(/runs-on:\s*ubuntu-latest/);
    expect(result.recoveryWorkflow).not.toMatch(/\b(?:schedule|push|pull_request|migration|seed):/);
  });

  it('publishes historical restoration through official v5 after restoration with the target and real current identity', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'workflow' });
    expect(result.recoveryWorkflow).toContain('restore-prior');
    expect(result.recoveryWorkflow).toContain('actions/upload-artifact@v5');
    expect(result.recoveryWorkflow.indexOf('restore-prior')).toBeLessThan(result.recoveryWorkflow.indexOf('actions/upload-artifact@v5'));
    expect(result.recoveryWorkflow).toContain('native-db-restoration-');
    expect(result.recoveryWorkflow).toContain('github.run_id');
    expect(result.recoveryWorkflow).toContain('github.run_attempt');
    expect(result.recoveryWorkflow).toMatch(/if-no-files-found:\s*error/);
    expect(result.recoveryWorkflow).not.toMatch(/continue-on-error:\s*true/);
  });

  it('keeps current guardian publication outside the private native guardian and after the restore action', async () => {
    const result = await executeHeldHistoricalRecovery({ port: 'workflow' });
    expect(result.guardianSource).not.toContain('uploadArtifact(');
    const guardianJob = result.workflow.slice(result.workflow.indexOf('\n  timeout-guardian:'));
    expect(guardianJob).toContain('actions/upload-artifact@v5');
    expect(guardianJob).toMatch(/if-no-files-found:\s*error/);
    expect(guardianJob).toContain('native-db-restoration-');
    expect(guardianJob).not.toMatch(/continue-on-error:\s*true/);
  });
});
