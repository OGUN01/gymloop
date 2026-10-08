import { spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync, symlinkSync, unlinkSync, writeFileSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type HeldDependencyData = Record<string, unknown>;
type HeldDependencyFixture = {
  run: HeldDependencyData;
  nativeJobs: HeldDependencyData[];
  guardianJobs: HeldDependencyData[];
  artifactNames: string[];
  jobListingComplete: boolean;
  artifactListingComplete: boolean;
  teardownReview: HeldDependencyData;
};

const heldDependencyModuleUrl = new URL('../../scripts/pgtap/unarmed-setup-failure.mjs', import.meta.url);
let heldDependencyVerifier: ((input: unknown) => boolean) | undefined;
let heldDependencyLoadError: unknown;
try {
  const imported = await import(heldDependencyModuleUrl.href);
  heldDependencyVerifier = imported.verifyUnarmedNativeSetupFailure;
} catch (error) {
  heldDependencyLoadError = error;
}

const heldDependencyNativeRows = [
  ['Set up job', 'success'],
  ['Set up runner', 'success'],
  ['Record adapter setup start before checkout', 'success'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Install the frozen adapter dependencies', 'failure'],
  ['Install the frozen hosted adapter dependencies', 'skipped'],
  ['Use the verified Git Bash executable for the pinned CLI installer', 'skipped'],
  ['Run supabase/setup-cli@v3', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Freeze full rollback-safe file and schema metadata', 'skipped'],
  ['Run actions/upload-artifact@v5', 'skipped'],
  ['Validate the full native suite with outside-worker recovery custody', 'skipped'],
  ['Retain sanitized native receipt', 'success'],
  ['Retain client-only smoke metadata', 'success'],
  ['Retain the explicit interim timing boundary', 'success'],
  ['Retain sanitized encrypted-artifact custody verification', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
] as const;

const heldDependencyGuardianRows = [
  ['Set up job', 'success'],
  ['Run actions/checkout@v7', 'success'],
  ['Run pnpm/action-setup@v6', 'success'],
  ['Run actions/setup-node@v7', 'success'],
  ['Run pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts', 'success'],
  ['Run supabase/setup-cli@v3', 'success'],
  ['Find the exact armed receipt, including an earlier attempt of this run', 'failure'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run actions/download-artifact@v5', 'skipped'],
  ['Run supabase link --project-ref "$PROJECT_REF" --yes', 'skipped'],
  ['Restore and freshly verify only the captured role-global timeout', 'skipped'],
  ['Retain independently hosted restoration evidence', 'skipped'],
  ['Post Run supabase/setup-cli@v3', 'success'],
  ['Post Run actions/setup-node@v7', 'skipped'],
  ['Post Run pnpm/action-setup@v6', 'success'],
  ['Post Run actions/checkout@v7', 'success'],
  ['Complete job', 'success'],
] as const;

function heldDependencyFixture(): HeldDependencyFixture {
  const source = '3b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength / 2);
  const run = {
    id: '6730012844',
    attempt: '1',
    sourceSha: source,
    repositoryId: 72618491,
    repository: NATIVE_DB_VALIDATION.repository,
    headRepositoryId: 72618491,
    headRepository: NATIVE_DB_VALIDATION.repository,
    event: 'push',
    path: '.github/workflows/db.yml',
    branch: 'main',
    status: 'completed',
    conclusion: 'failure',
  };
  return {
    run,
    nativeJobs: [{
      id: 96040012,
      runId: run.id,
      attempt: run.attempt,
      sourceSha: source,
      name: 'pgtap',
      status: 'completed',
      conclusion: 'failure',
      runnerId: 640028,
      runnerName: 'held-opaque-owned-4',
      runnerGroupName: 'Default',
      labels: ['self-hosted', 'Windows', 'X64', `${NATIVE_DB_VALIDATION.labelPrefix}-${run.id}-1-${source.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`],
      steps: heldDependencyNativeRows.map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
    }],
    guardianJobs: [{
      id: 96040031,
      runId: run.id,
      attempt: run.attempt,
      sourceSha: source,
      name: 'timeout-guardian',
      status: 'completed',
      conclusion: 'failure',
      runnerId: 640033,
      runnerName: 'GitHub Actions 640033',
      runnerGroupName: 'GitHub Actions',
      labels: ['ubuntu-latest'],
      steps: heldDependencyGuardianRows.map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
    }],
    artifactNames: [`native-db-schema-${run.id}-1`, `native-db-ci-job-${run.id}-1`],
    jobListingComplete: true,
    artifactListingComplete: true,
    teardownReview: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: `${run.id}-1`,
      sourceSha: source,
      jobId: '96040012',
      runnerId: 640028,
      runnerEnvironment: 'self-hosted',
      privateProofSha256: '7d'.repeat(NATIVE_DB_VALIDATION.digestHexLength / 2),
      nativeProcessesStopped: true,
      ownedContainersStopped: true,
      runnerDeregistered: true,
      verifiedAt: '2026-10-09T05:14:33.000Z',
    },
  };
}

function heldDependencyCheck(input: unknown): boolean {
  expect(heldDependencyLoadError).toBeUndefined();
  expect(heldDependencyVerifier).toBeTypeOf('function');
  return heldDependencyVerifier!(input);
}

function heldDependencyChange(change: (fixture: HeldDependencyFixture) => void): void {
  const fixture = heldDependencyFixture();
  change(fixture);
  expect(heldDependencyCheck(fixture)).toBe(false);
}

function heldDependencyWorkflow(): string {
  return readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
}

function heldDependencyWorkflowScript(marker: string): string {
  const lines = heldDependencyWorkflow().split(/\r?\n/);
  let start = lines.findIndex(line => line.trim() === `- name: ${marker}`);
  if (start < 0) start = lines.findIndex(line => line.includes(marker));
  expect(start).toBeGreaterThanOrEqual(0);
  while (start > 0 && !/^\s*- (?:name|uses):/.test(lines[start])) start -= 1;
  const indent = lines[start].search(/\S/);
  let end = start + 1;
  while (end < lines.length) {
    const nextIndent = lines[end].search(/\S/);
    if (nextIndent >= 0 && (nextIndent < indent || (nextIndent === indent && /^\s*- /.test(lines[end])))) break;
    end += 1;
  }
  return lines.slice(start, end).join('\n');
}

function heldDependencyInstallProbe(mode: string): number {
  const step = heldDependencyWorkflowScript('Install the frozen adapter dependencies');
  const lines = step.split('\n');
  const runIndex = lines.findIndex(line => /^\s*run:\s*\|/.test(line));
  expect(runIndex).toBeGreaterThanOrEqual(0);
  const runIndent = lines[runIndex].search(/\S/);
  const bodyIndent = lines[runIndex + 1].search(/\S/);
  let end = runIndex + 1;
  while (end < lines.length && (lines[end].trim() === '' || lines[end].search(/\S/) > runIndent)) end += 1;
  const body = lines.slice(runIndex + 1, end).map(line => line.slice(bodyIndent)).join('\n');
  const temporaryRoot = realpathSync(tmpdir());
  const owned = realpathSync(mkdtempSync(join(temporaryRoot, 'gymloop-held-install-')));
  expect(dirname(owned)).toBe(temporaryRoot);
  const moduleLink = join(owned, 'node_modules', '@gymloop', 'shared');
  const directLink = join(owned, 'packages', 'shared');
  try {
    const acl = spawnSync('icacls.exe', [owned, '/inheritance:r', '/grant:r', `${userInfo().username}:(OI)(CI)F`], { encoding: 'utf8' });
    expect(acl.status).toBe(0);
    mkdirSync(dirname(moduleLink), { recursive: true });
    mkdirSync(dirname(directLink), { recursive: true });
    const shared = fileURLToPath(new URL('../../packages/shared/', import.meta.url));
    symlinkSync(shared, moduleLink, 'junction');
    symlinkSync(shared, directLink, 'junction');
    if (mode !== 'missingMetadata') {
      const setting = mode === 'ignoredSetting' ? 60 : NATIVE_DB_VALIDATION.virtualStoreDirMaxLength;
      writeFileSync(join(owned, 'node_modules', '.modules.yaml'), `virtualStoreDir: ../.p\nvirtualStoreDirMaxLength: ${setting}\n`, 'utf8');
    }
    if (mode !== 'missingStore') mkdirSync(join(owned, '.p'));
    const prelude = `$ErrorActionPreference = 'Stop'\nfunction global:pnpm { $global:LASTEXITCODE = ${mode === 'failedInstall' ? 29 : 0} }\n`;
    const outcome = spawnSync('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', `${prelude}${body}\nif ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }\nexit 0`], { cwd: owned, encoding: 'utf8' });
    return outcome.status ?? -1;
  } finally {
    if (existsSync(moduleLink)) unlinkSync(moduleLink);
    if (existsSync(directLink)) unlinkSync(directLink);
    expect(dirname(realpathSync(owned))).toBe(temporaryRoot);
    rmSync(owned, { recursive: true, force: true });
  }
}

describe('independent exact Windows dependency setup boundary', () => {
  it('retains the sole original public verifier', async () => {
    expect(heldDependencyLoadError).toBeUndefined();
    expect(Object.keys(await import(heldDependencyModuleUrl.href))).toEqual(['verifyUnarmedNativeSetupFailure']);
  });

  it.each(['push', 'workflow_dispatch'])('accepts only the complete proven dependency failure for %s', event => {
    const fixture = heldDependencyFixture();
    fixture.run.event = event;
    expect(heldDependencyCheck(fixture)).toBe(true);
  });

  it.each([0, 1, 2, 3])('accepts order-independent native labels rotation %s', offset => {
    const fixture = heldDependencyFixture();
    const labels = fixture.nativeJobs[0].labels as string[];
    fixture.nativeJobs[0].labels = [...labels.slice(offset), ...labels.slice(0, offset)];
    fixture.artifactNames.reverse();
    expect(heldDependencyCheck(fixture)).toBe(true);
  });

  it('accepts independently bound alternate identities and reversed labels', () => {
    const fixture = heldDependencyFixture();
    fixture.run.id = '7649821375';
    fixture.run.sourceSha = 'a6'.repeat(NATIVE_DB_VALIDATION.sourceShaLength / 2);
    fixture.run.repositoryId = 819437;
    fixture.run.headRepositoryId = 819437;
    fixture.nativeJobs[0].id = 37124066;
    fixture.nativeJobs[0].runnerId = 440109;
    fixture.guardianJobs[0].id = 37124071;
    fixture.guardianJobs[0].runnerId = 440112;
    fixture.guardianJobs[0].runnerName = 'GitHub Actions 440112';
    for (const job of [fixture.nativeJobs[0], fixture.guardianJobs[0]]) {
      job.runId = fixture.run.id;
      job.sourceSha = fixture.run.sourceSha;
    }
    fixture.nativeJobs[0].labels = [`${NATIVE_DB_VALIDATION.labelPrefix}-${fixture.run.id}-1-${String(fixture.run.sourceSha).slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`, 'X64', 'Windows', 'self-hosted'];
    fixture.artifactNames = [`native-db-ci-job-${fixture.run.id}-1`, `native-db-schema-${fixture.run.id}-1`];
    Object.assign(fixture.teardownReview, { runId: `${fixture.run.id}-1`, sourceSha: fixture.run.sourceSha, jobId: '37124066', runnerId: 440109 });
    expect(heldDependencyCheck(fixture)).toBe(true);
  });

  it('preserves the exact original twenty-step setup failure', () => {
    const fixture = heldDependencyFixture();
    fixture.nativeJobs[0].steps = heldDependencyNativeRows
      .filter(([name]) => !name.startsWith('Post Run '))
      .map(([name, conclusion]) => ({
        name,
        status: 'completed',
        conclusion: name === 'Set up runner' ? 'failure' : name === 'Set up job' || name.startsWith('Retain ') || name === 'Complete job' ? conclusion : 'skipped',
      }));
    expect(heldDependencyCheck(fixture)).toBe(true);
  });

  it.each(['jobListingComplete', 'artifactListingComplete'] as const)('requires literal complete %s', field => {
    for (const value of [false, undefined, null, 1, 'true', {}, []]) {
      const fixture = heldDependencyFixture();
      (fixture as unknown as HeldDependencyData)[field] = value;
      expect(heldDependencyCheck(fixture)).toBe(false);
    }
  });

  it.each([null, undefined, false, true, 1, 'evidence', [], () => true])('rejects non-record input %#', input => {
    expect(heldDependencyCheck(input)).toBe(false);
  });

  it.each(['run', 'nativeJobs', 'guardianJobs', 'artifactNames', 'jobListingComplete', 'artifactListingComplete', 'teardownReview'])('rejects absent top-level %s', field => {
    const fixture = heldDependencyFixture() as unknown as HeldDependencyData;
    delete fixture[field];
    expect(heldDependencyCheck(fixture)).toBe(false);
  });

  it.each(['run', 'nativeJobs', 'guardianJobs', 'artifactNames', 'jobListingComplete', 'artifactListingComplete', 'teardownReview'])('refuses input accessor %s without invoking it', field => {
    const fixture = heldDependencyFixture();
    let invoked = 0;
    Object.defineProperty(fixture, field, { enumerable: true, get: () => { invoked += 1; return true; } });
    expect(heldDependencyCheck(fixture)).toBe(false);
    expect(invoked).toBe(0);
  });

  it.each(['enumerable', 'nonenumerable', 'symbol', 'inherited', 'throwingProxy'])('rejects unsafe whole-input shape %s', variant => {
    const fixture = heldDependencyFixture();
    if (variant === 'throwingProxy') {
      expect(heldDependencyCheck(new Proxy(fixture, { ownKeys() { throw new Error('opaque'); } }))).toBe(false);
      return;
    }
    if (variant === 'enumerable') Object.assign(fixture, { recovery: false });
    if (variant === 'nonenumerable') Object.defineProperty(fixture, 'recovery', { value: false });
    if (variant === 'symbol') Object.defineProperty(fixture, Symbol('recovery'), { value: false });
    if (variant === 'inherited') Object.setPrototypeOf(fixture, { recovery: false });
    expect(heldDependencyCheck(fixture)).toBe(false);
  });

  it.each([
    ['id', ''], ['id', '0'], ['id', '-1'], ['id', '01'], ['id', '1.0'], ['id', '1e3'], ['id', '9007199254740992'], ['id', 6730012844],
    ['attempt', 1], ['attempt', '2'], ['attempt', '01'], ['attempt', null],
    ['sourceSha', 'A'.repeat(40)], ['sourceSha', 'b'.repeat(39)], ['sourceSha', 'b'.repeat(41)], ['sourceSha', 'g'.repeat(40)],
    ['repositoryId', 0], ['repositoryId', -1], ['repositoryId', 1.5], ['repositoryId', Number.MAX_SAFE_INTEGER + 1], ['repositoryId', '72618491'],
    ['headRepositoryId', 0], ['headRepositoryId', 72618492], ['headRepositoryId', '72618491'],
    ['repository', 'ogun01/gymloop'], ['repository', 'OGUN01/other'], ['headRepository', 'fork/gymloop'], ['headRepository', 'OGUN01/Gymloop'],
    ['event', 'pull_request'], ['event', 'schedule'], ['event', 'Push'], ['path', 'db.yml'], ['path', '.github/workflows/db.yml@refs/heads/main'],
    ['branch', 'refs/heads/main'], ['branch', 'release'], ['status', 'in_progress'], ['status', 'queued'],
    ['conclusion', 'cancelled'], ['conclusion', 'success'], ['conclusion', 'timed_out'], ['conclusion', null],
  ])('rejects altered run identity %s %#', (field, value) => {
    heldDependencyChange(fixture => { fixture.run[String(field)] = value; });
  });

  it.each(['id', 'attempt', 'sourceSha', 'repositoryId', 'repository', 'headRepositoryId', 'headRepository', 'event', 'path', 'branch', 'status', 'conclusion'])('refuses absent, hidden or accessor run field %s', field => {
    heldDependencyChange(fixture => { delete fixture.run[field]; });
    heldDependencyChange(fixture => { Object.defineProperty(fixture.run, field, { value: fixture.run[field], enumerable: false }); });
    let invoked = 0;
    heldDependencyChange(fixture => { Object.defineProperty(fixture.run, field, { enumerable: true, get: () => { invoked += 1; return 'opaque'; } }); });
    expect(invoked).toBe(0);
  });

  it.each(['extra', 'symbol', 'inherited', 'array', 'proxy'])('refuses unsafe run descriptor %s', variant => {
    heldDependencyChange(fixture => {
      if (variant === 'extra') fixture.run.armed = false;
      if (variant === 'symbol') Object.defineProperty(fixture.run, Symbol('run'), { value: true });
      if (variant === 'inherited') Object.setPrototypeOf(fixture.run, { safe: true });
      if (variant === 'array') (fixture as unknown as HeldDependencyData).run = [fixture.run];
      if (variant === 'proxy') fixture.run = new Proxy(fixture.run, { getPrototypeOf() { throw new Error('opaque'); } });
    });
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('requires one unique projected %s', field => {
    for (const variant of ['empty', 'duplicate', 'sparse', 'nonarray', 'accessor', 'extra', 'symbol', 'prototype']) {
      const fixture = heldDependencyFixture();
      const job = fixture[field][0];
      if (variant === 'empty') fixture[field] = [];
      if (variant === 'duplicate') fixture[field] = [job, { ...job }];
      if (variant === 'sparse') fixture[field] = new Array(1);
      if (variant === 'nonarray') (fixture as unknown as HeldDependencyData)[field] = { 0: job, length: 1 };
      if (variant === 'accessor') Object.defineProperty(fixture[field], '0', { enumerable: true, get: () => { throw new Error('opaque'); } });
      if (variant === 'extra') Object.assign(fixture[field], { pagination: 'complete' });
      if (variant === 'symbol') Object.defineProperty(fixture[field], Symbol('list'), { value: true });
      if (variant === 'prototype') Object.setPrototypeOf(fixture[field], Object.assign([], { partial: true }));
      expect(heldDependencyCheck(fixture)).toBe(false);
    }
  });

  for (const field of ['nativeJobs', 'guardianJobs'] as const) {
    describe(`${field} binds every projected identity`, () => {
      it.each([
        ['id', 0], ['id', -1], ['id', 1.25], ['id', Number.MAX_SAFE_INTEGER + 1], ['id', '96040012'], ['id', NaN], ['id', Infinity],
        ['runId', '6730012845'], ['runId', 6730012844], ['runId', '6730012844-1'], ['attempt', 1], ['attempt', '2'],
        ['sourceSha', '8f'.repeat(20)], ['sourceSha', '3B'.repeat(20)], ['sourceSha', null],
        ['name', 'other'], ['name', 'pgtap '], ['status', 'in_progress'], ['status', 'queued'], ['conclusion', 'success'], ['conclusion', 'cancelled'],
        ['runnerId', 0], ['runnerId', -1], ['runnerId', '640028'], ['runnerId', Number.MAX_SAFE_INTEGER + 1], ['runnerId', null],
        ['runnerName', ''], ['runnerName', null], ['runnerGroupName', 'Other'], ['labels', null], ['steps', null],
      ])('rejects projected %s mutation %#', (key, value) => {
        heldDependencyChange(fixture => { fixture[field][0][String(key)] = value; });
      });

      it.each(['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion', 'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps'])('rejects missing %s', key => {
        heldDependencyChange(fixture => { delete fixture[field][0][key]; });
      });

      it.each(['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion', 'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps'])('rejects an inert-boundary getter for %s', key => {
        let invoked = 0;
        heldDependencyChange(fixture => {
          Object.defineProperty(fixture[field][0], key, { enumerable: true, get: () => { invoked += 1; return 'opaque'; } });
        });
        expect(invoked).toBe(0);
      });

      it.each(['extra', 'symbol', 'inherited', 'hiddenRequired'])('rejects job shape %s', variant => {
        heldDependencyChange(fixture => {
          const job = fixture[field][0];
          if (variant === 'extra') Object.assign(job, { completedAt: '2026-10-09T05:14:33Z' });
          if (variant === 'symbol') Object.defineProperty(job, Symbol('job'), { value: true });
          if (variant === 'inherited') Object.setPrototypeOf(job, { approved: true });
          if (variant === 'hiddenRequired') Object.defineProperty(job, 'sourceSha', { value: job.sourceSha, enumerable: false });
        });
      });
    });
  }

  it.each(['job', 'runner'])('requires distinct native and guardian %s ids', kind => {
    heldDependencyChange(fixture => {
      const key = kind === 'job' ? 'id' : 'runnerId';
      fixture.guardianJobs[0][key] = fixture.nativeJobs[0][key];
      if (kind === 'runner') fixture.guardianJobs[0].runnerName = `GitHub Actions ${fixture.guardianJobs[0].runnerId}`;
    });
  });

  it.each([
    ['nativeJobs', 'runnerGroupName', 'GitHub Actions'],
    ['nativeJobs', 'name', 'timeout-guardian'],
    ['guardianJobs', 'runnerGroupName', 'Default'],
    ['guardianJobs', 'name', 'pgtap'],
    ['guardianJobs', 'runnerName', 'GitHub Actions'],
    ['guardianJobs', 'runnerName', 'GitHub Actions 640028'],
    ['guardianJobs', 'runnerName', 'github actions 640033'],
  ] as const)('rejects wrong selected role %s %s', (field, key, value) => {
    heldDependencyChange(fixture => { fixture[field][0][key] = value; });
  });

  it.each([0, 1, 2, 3])('refuses absent, duplicated or foreign native label at %s', index => {
    for (const variant of ['missing', 'duplicate', 'wrongCase', 'trailing', 'accessor']) {
      heldDependencyChange(fixture => {
        const labels = fixture.nativeJobs[0].labels as string[];
        if (variant === 'missing') labels.splice(index, 1);
        if (variant === 'duplicate') labels[index] = labels[(index + 1) % labels.length];
        if (variant === 'wrongCase') labels[index] = labels[index] === labels[index].toLowerCase() ? labels[index].toUpperCase() : labels[index].toLowerCase();
        if (variant === 'trailing') labels[index] += ' ';
        if (variant === 'accessor') Object.defineProperty(labels, String(index), { enumerable: true, get: () => { throw new Error('opaque'); } });
      });
    }
  });

  it.each([
    'fitcruxx-db-win-x64-6730012844-2-3b3b3b3b3b3b',
    'fitcruxx-db-win-x64-6730012845-1-3b3b3b3b3b3b',
    'fitcruxx-db-win-x64-6730012844-1-3b3b3b3b3b3',
    'fitcruxx-db-win-x64-6730012844-1-3b3b3b3b3b3b3',
    'fitcruxx-db-win-x64-6730012844-1-8f8f8f8f8f8f',
    'self-hosted',
  ])('refuses mismatched source-bound private label %#', label => {
    heldDependencyChange(fixture => { (fixture.nativeJobs[0].labels as string[])[3] = label; });
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses malformed %s label listing', field => {
    for (const variant of ['extra', 'sparse', 'inherited', 'symbol', 'nonarray']) {
      heldDependencyChange(fixture => {
        const labels = fixture[field][0].labels as string[];
        if (variant === 'extra') labels.push('verified');
        if (variant === 'sparse') delete labels[0];
        if (variant === 'inherited') Object.setPrototypeOf(labels, Object.assign([], { complete: true }));
        if (variant === 'symbol') Object.defineProperty(labels, Symbol('labels'), { value: true });
        if (variant === 'nonarray') fixture[field][0].labels = { 0: labels[0], length: labels.length };
      });
    }
  });

  it.each(['ubuntu-24.04', 'Ubuntu-latest', 'self-hosted', 'ubuntu-latest '])('requires the sole exact hosted label %#', label => {
    heldDependencyChange(fixture => { fixture.guardianJobs[0].labels = [label]; });
  });

  for (const [field, rows] of [['nativeJobs', heldDependencyNativeRows], ['guardianJobs', heldDependencyGuardianRows]] as const) {
    describe(`${field} exact ordered public vector`, () => {
      it.each(rows.flatMap(([name, expected], index) => ['success', 'failure', 'skipped', 'cancelled', 'timed_out', 'neutral', 'action_required', ''].filter(value => value !== expected).map(value => ({ name, index, value }))))('rejects $name conclusion $value', ({ index, value }) => {
        heldDependencyChange(fixture => { (fixture[field][0].steps as HeldDependencyData[])[index].conclusion = value; });
      });

      it.each(rows.map(([name], index) => ({ name, index })))('rejects altered status, spelling, missing or repeated $name', ({ index }) => {
        for (const variant of ['running', 'statusNull', 'nameSuffix', 'nameLower', 'missing', 'duplicate', 'reordered', 'sparse', 'extra', 'missingKey', 'getter', 'inherited', 'symbol', 'arrayAccessor']) {
          heldDependencyChange(fixture => {
            const steps = fixture[field][0].steps as HeldDependencyData[];
            if (variant === 'running') steps[index].status = 'in_progress';
            if (variant === 'statusNull') steps[index].status = null;
            if (variant === 'nameSuffix') steps[index].name += ' ';
            if (variant === 'nameLower') steps[index].name = String(steps[index].name).toLowerCase();
            if (variant === 'missing') steps.splice(index, 1);
            if (variant === 'duplicate') steps.splice(index, 0, { ...steps[index] });
            if (variant === 'reordered') {
              let other = (index + 1) % steps.length;
              if (steps[other].name === steps[index].name) other = (other + 1) % steps.length;
              [steps[index], steps[other]] = [steps[other], steps[index]];
            }
            if (variant === 'sparse') delete steps[index];
            if (variant === 'extra') steps[index].number = index + 1;
            if (variant === 'missingKey') delete steps[index].conclusion;
            if (variant === 'getter') Object.defineProperty(steps[index], 'name', { enumerable: true, get: () => { throw new Error('opaque'); } });
            if (variant === 'inherited') Object.setPrototypeOf(steps[index], { trusted: true });
            if (variant === 'symbol') Object.defineProperty(steps[index], Symbol('step'), { value: true });
            if (variant === 'arrayAccessor') Object.defineProperty(steps, String(index), { enumerable: true, get: () => { throw new Error('opaque'); } });
          });
        }
      });

      it.each(rows.flatMap(([name], index) => ['name', 'status', 'conclusion'].map(key => ({ name, index, key }))))('rejects missing/hidden/accessor $name property $key', ({ index, key }) => {
        heldDependencyChange(fixture => { delete (fixture[field][0].steps as HeldDependencyData[])[index][key]; });
        heldDependencyChange(fixture => {
          const step = (fixture[field][0].steps as HeldDependencyData[])[index];
          Object.defineProperty(step, key, { value: step[key], enumerable: false });
        });
        let invoked = 0;
        heldDependencyChange(fixture => { Object.defineProperty((fixture[field][0].steps as HeldDependencyData[])[index], key, { enumerable: true, get: () => { invoked += 1; return 'opaque'; } }); });
        expect(invoked).toBe(0);
      });

      it.each(['extraProperty', 'symbol', 'customPrototype', 'nonarray', 'empty', 'addedDatabaseWork'])('rejects vector container %s', variant => {
        heldDependencyChange(fixture => {
          const steps = fixture[field][0].steps as HeldDependencyData[];
          if (variant === 'extraProperty') Object.assign(steps, { listingComplete: true });
          if (variant === 'symbol') Object.defineProperty(steps, Symbol('steps'), { value: true });
          if (variant === 'customPrototype') Object.setPrototypeOf(steps, Object.assign([], { authenticated: true }));
          if (variant === 'nonarray') fixture[field][0].steps = { ...steps, length: steps.length };
          if (variant === 'empty') fixture[field][0].steps = [];
          if (variant === 'addedDatabaseWork') steps.splice(steps.length - 1, 0, { name: 'Restore database timeout', status: 'completed', conclusion: 'success' });
        });
      });
    });
  }

  it.each(heldDependencyNativeRows.filter(([name]) => !name.startsWith('Post Run ')).map(([name], index) => ({ name, index })))('preserves refusal for modified original setup step $name', ({ index }) => {
    heldDependencyChange(fixture => {
      const steps = heldDependencyNativeRows
        .filter(([name]) => !name.startsWith('Post Run '))
        .map(([name, conclusion]) => ({ name, status: 'completed', conclusion: name === 'Set up runner' ? 'failure' : name === 'Set up job' || name.startsWith('Retain ') || name === 'Complete job' ? conclusion : 'skipped' }));
      steps[index].status = 'in_progress';
      fixture.nativeJobs[0].steps = steps;
    });
  });

  it.each(['dependencyWithoutPosts', 'runnerFailureWithPosts', 'allSkippedAfterSetup'])('does not splice either public vector into an unapproved hybrid %s', variant => {
    heldDependencyChange(fixture => {
      const steps = fixture.nativeJobs[0].steps as HeldDependencyData[];
      if (variant === 'dependencyWithoutPosts') fixture.nativeJobs[0].steps = steps.filter(step => !String(step.name).startsWith('Post Run '));
      if (variant === 'runnerFailureWithPosts') {
        steps[1].conclusion = 'failure';
        for (const step of steps.slice(2, 15)) step.conclusion = 'skipped';
      }
      if (variant === 'allSkippedAfterSetup') for (const step of steps.slice(1, 15)) step.conclusion = 'skipped';
    });
  });

  it.each([
    ['formatVersion', 2], ['formatVersion', '1'], ['runId', '6730012844'], ['runId', '6730012844-2'], ['runId', '6730012845-1'],
    ['sourceSha', '8f'.repeat(20)], ['sourceSha', '3B'.repeat(20)], ['jobId', 96040012], ['jobId', '96040031'], ['jobId', '096040012'],
    ['runnerId', '640028'], ['runnerId', 640033], ['runnerId', 0], ['runnerEnvironment', 'github-hosted'], ['runnerEnvironment', 'self-hosted '],
    ['privateProofSha256', ''], ['privateProofSha256', 'a'.repeat(63)], ['privateProofSha256', 'a'.repeat(65)], ['privateProofSha256', 'G'.repeat(64)],
    ['verifiedAt', ''], ['verifiedAt', null], ['verifiedAt', '2026-10-09'], ['verifiedAt', '2026-10-09T05:14:33+00:00'], ['verifiedAt', 'not-a-time'],
  ])('requires canonical physical receipt %s %#', (field, value) => {
    heldDependencyChange(fixture => { fixture.teardownReview[String(field)] = value; });
  });

  it.each(['nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered'])('requires literal physical completion %s', field => {
    for (const value of [false, undefined, null, 1, 'true']) heldDependencyChange(fixture => { fixture.teardownReview[field] = value; });
  });

  it.each(['formatVersion', 'runId', 'sourceSha', 'jobId', 'runnerId', 'runnerEnvironment', 'privateProofSha256', 'nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered', 'verifiedAt'])('refuses missing/accessor receipt field %s', field => {
    heldDependencyChange(fixture => { delete fixture.teardownReview[field]; });
    let invoked = 0;
    heldDependencyChange(fixture => { Object.defineProperty(fixture.teardownReview, field, { enumerable: true, get: () => { invoked += 1; return true; } }); });
    expect(invoked).toBe(0);
  });

  it.each(['wrapper', 'extra', 'symbol', 'inherited', 'null', 'array', 'throwing'])('refuses ambiguous physical review shape %s', variant => {
    heldDependencyChange(fixture => {
      if (variant === 'wrapper') fixture.teardownReview = { receipt: fixture.teardownReview };
      if (variant === 'extra') fixture.teardownReview.armed = false;
      if (variant === 'symbol') Object.defineProperty(fixture.teardownReview, Symbol('review'), { value: true });
      if (variant === 'inherited') Object.setPrototypeOf(fixture.teardownReview, { verified: true });
      if (variant === 'null') (fixture as unknown as HeldDependencyData).teardownReview = null;
      if (variant === 'array') (fixture as unknown as HeldDependencyData).teardownReview = [fixture.teardownReview];
      if (variant === 'throwing') fixture.teardownReview = new Proxy(fixture.teardownReview, { getOwnPropertyDescriptor() { throw new Error('opaque'); } });
    });
  });

  it.each([
    'native-db-recovery-6730012844-1', 'native-db-final-6730012844-1', 'native-db-smoke-6730012844-1',
    'native-db-manifest-6730012844-1', 'native-db-timing-6730012844-1', 'native-db-private-custody-6730012844-1',
    'native-db-restoration-6730012844-1', 'native-db-schema-6730012844-2', 'unexpected',
  ])('refuses any additional artifact %#', name => {
    heldDependencyChange(fixture => { fixture.artifactNames.push(name); });
  });

  it.each([0, 1])('requires unique exact artifact at %s', index => {
    for (const variant of ['missing', 'duplicate', 'wrongRun', 'wrongAttempt', 'extraSpace', 'case', 'sparse', 'getter', 'nonstring']) {
      heldDependencyChange(fixture => {
        if (variant === 'missing') fixture.artifactNames.splice(index, 1);
        if (variant === 'duplicate') fixture.artifactNames[index] = fixture.artifactNames[1 - index];
        if (variant === 'wrongRun') fixture.artifactNames[index] = fixture.artifactNames[index].replace('6730012844', '6730012845');
        if (variant === 'wrongAttempt') fixture.artifactNames[index] = fixture.artifactNames[index].replace(/-1$/, '-2');
        if (variant === 'extraSpace') fixture.artifactNames[index] += ' ';
        if (variant === 'case') fixture.artifactNames[index] = fixture.artifactNames[index].toUpperCase();
        if (variant === 'sparse') delete fixture.artifactNames[index];
        if (variant === 'getter') Object.defineProperty(fixture.artifactNames, String(index), { enumerable: true, get: () => { throw new Error('opaque'); } });
        if (variant === 'nonstring') (fixture.artifactNames as unknown[])[index] = { name: fixture.artifactNames[index], expired: false };
      });
    }
  });

  it.each(['empty', 'nonarray', 'symbol', 'extra', 'customPrototype', 'throwing'])('requires exact dense artifact container %s', variant => {
    heldDependencyChange(fixture => {
      if (variant === 'empty') fixture.artifactNames = [];
      if (variant === 'nonarray') (fixture as unknown as HeldDependencyData).artifactNames = { ...fixture.artifactNames, length: 2 };
      if (variant === 'symbol') Object.defineProperty(fixture.artifactNames, Symbol('artifact'), { value: true });
      if (variant === 'extra') Object.assign(fixture.artifactNames, { expired: false });
      if (variant === 'customPrototype') Object.setPrototypeOf(fixture.artifactNames, Object.assign([], { complete: true }));
      if (variant === 'throwing') fixture.artifactNames = new Proxy(fixture.artifactNames, { ownKeys() { throw new Error('opaque'); } });
    });
  });
});

describe('independently derived frozen installation and guardian wiring', () => {
  it('uses only the effective step-local Windows setting with existing constant and successful-exit checks', () => {
    const step = heldDependencyWorkflowScript('Install the frozen adapter dependencies');
    expect(step).toMatch(/\$env:PNPM_CONFIG_VIRTUAL_STORE_DIR_MAX_LENGTH\s*=\s*\$storeLimit/);
    expect(step).toContain('--virtual-store-dir=.p');
    expect(step).toContain('NATIVE_DB_VALIDATION.virtualStoreDirMaxLength');
    expect(step).toContain('.modules.yaml');
    expect(step.match(/\$LASTEXITCODE/g)?.length ?? 0).toBeGreaterThanOrEqual(2);
    expect(step).not.toMatch(/--virtual-store-dir\s+\.p|--virtual-store-dir-max-length\s+|--config\.virtual/);
    expect(step).not.toMatch(/pnpm\s+(?:config\s+set|update|add)|--no-frozen-lockfile|--ignore-scripts=false/);
  });

  it('accepts the real central compaction metadata and actual short store after successful installation', () => {
    expect(heldDependencyInstallProbe('matching')).toBe(0);
  });

  it.each(['failedInstall', 'ignoredSetting', 'missingMetadata', 'missingStore'])('refuses actual installation guard regression %s before native work', mode => {
    expect(heldDependencyInstallProbe(mode)).not.toBe(0);
  });

  it('retains the frozen shared production-only no-lifecycle dependency installation', () => {
    const step = heldDependencyWorkflowScript('Install the frozen adapter dependencies');
    expect(step).toContain('pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts');
    const metadata = JSON.parse(readFileSync(new URL('../../package.json', import.meta.url), 'utf8'));
    expect(metadata.packageManager).toBe('pnpm@12.3.4');
  });

  it('leaves the hosted install command exactly frozen', () => {
    const step = heldDependencyWorkflowScript('Install the frozen hosted adapter dependencies');
    const commands = step.split('\n').filter(line => line.includes('pnpm install')).map(line => line.trim().replace(/^run:\s*/, ''));
    expect(commands).toEqual(['pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts']);
    expect(step).not.toMatch(/--virtual-store-dir|--config\.|\$storeLimit/);
  });

  it('retains both workflow module event filters', () => {
    const sections = heldDependencyWorkflow().match(/^ {2}(?:push|pull_request):[\s\S]*?(?=^ {2}[a-z_]+:|^permissions:|^concurrency:|^jobs:)/gm) ?? [];
    expect(sections).toHaveLength(2);
    for (const section of sections) expect(section).toContain('scripts/pgtap/unarmed-setup-failure.mjs');
  });

  it('keeps the classifier in the authenticated predecessor preflight with exactly its seven inputs', () => {
    const step = heldDependencyWorkflowScript('verifyUnarmedNativeSetupFailure');
    expect(step).toContain('unarmed-setup-failure.mjs');
    expect(step).toMatch(/\bimport(?:\s*\(|\s+\{)/);
    expect(step).toContain('projectUnarmedJob');
    const construction = step.match(/verifyUnarmedNativeSetupFailure\s*\(\s*\{([\s\S]*?)\}\s*\)/)?.[1];
    expect(construction).toBeTypeOf('string');
    for (const key of ['run', 'nativeJobs', 'guardianJobs', 'artifactNames', 'jobListingComplete', 'artifactListingComplete', 'teardownReview']) {
      expect(construction).toMatch(new RegExp(`\\b${key}(?:\\s*:|\\s*[,}]|\\s*$)`));
    }
    expect(step).toMatch(/verifiedSetupFailures\s*=\s*new Set\s*\(/);
    expect(step).toMatch(/verifiedSetupFailures\.add\s*\(/);
    expect(step).toMatch(/verifiedSetupFailures\.has\s*\(/);
    expect(step).toMatch(/verifyNativeWorkloadTeardown\s*\(/);
  });

  it('does not turn the setup exception into guardian execution or native workload permission', () => {
    const nativeStep = heldDependencyWorkflowScript('Validate the full native suite with outside-worker recovery custody');
    expect(nativeStep).not.toContain('verifiedSetupFailures');
    expect(nativeStep).not.toContain('verifyUnarmedNativeSetupFailure');
    const workflow = heldDependencyWorkflow();
    const guardian = workflow.match(/^ {2}timeout-guardian:[\s\S]*?(?=^ {2}[a-z][a-z-]*:|(?![\s\S]))/m)?.[0];
    expect(guardian).toBeTypeOf('string');
    expect(guardian).not.toContain('verifiedSetupFailures');
    expect(guardian).not.toContain('verifyUnarmedNativeSetupFailure');
    expect(guardian).toContain('Find the exact armed receipt, including an earlier attempt of this run');
    expect(guardian).toContain('Restore and freshly verify only the captured role-global timeout');
  });
});
