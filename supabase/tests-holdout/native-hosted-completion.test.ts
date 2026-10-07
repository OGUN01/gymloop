import { beforeAll, describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants.ts';

type DataRecord = Record<string, unknown>;
type CompletionFixture = {
  expected: DataRecord;
  job: DataRecord;
  receipt: DataRecord;
};
type CompletionVerifier = (
  expected: unknown,
  job: unknown,
  receipt: unknown,
) => boolean;

let completionVerifier: CompletionVerifier | undefined;

beforeAll(async () => {
  // Resolve at execution time so the absent module produces counted red tests.
  const modulePath = ['..', '..', 'scripts', 'pgtap', 'hosted-completion.mjs'].join('/');
  try {
    const loaded: Record<string, unknown> = await import(modulePath);
    if (typeof loaded.verifyHostedNativeWorkloadCompletion === 'function') {
      completionVerifier = loaded.verifyHostedNativeWorkloadCompletion as CompletionVerifier;
    }
  } catch {
    completionVerifier = undefined;
  }
});

function freshCompletionFixture(): CompletionFixture {
  const sourceSha = 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
  return {
    expected: {
      runId: '47-3',
      sourceSha,
      jobId: '109',
      runnerId: 71,
      runnerEnvironment: 'github-hosted',
    },
    job: {
      id: 109,
      runId: '47',
      attempt: '3',
      sourceSha,
      name: 'pgtap',
      status: 'completed',
      conclusion: 'failure',
      runnerId: 71,
      runnerName: 'GitHub Actions 71',
      runnerGroupName: 'GitHub Actions',
      labels: ['ubuntu-latest'],
      steps: [
        { name: 'Native validation', status: 'completed', conclusion: 'failure' },
        { name: 'Post Run supabase/setup-cli@v3', status: 'completed', conclusion: 'success' },
        { name: 'Post Run pnpm/action-setup@v6', status: 'completed', conclusion: 'success' },
        { name: 'Post Run actions/checkout@v7', status: 'completed', conclusion: 'success' },
        { name: 'Complete job', status: 'completed', conclusion: 'success' },
      ],
      completedAt: '2026-10-07T03:04:05Z',
    },
    receipt: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: '47-3',
      sourceSha,
      jobId: '109',
      runnerId: 71,
      runnerEnvironment: 'github-hosted',
      privateProofSha256: 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      completionKind: 'github-hosted-job-decommission',
      verifiedAt: '2026-10-07T03:04:05.001Z',
    },
  };
}

function requireCompletion(fixture: CompletionFixture, accepted: boolean): void {
  expect(completionVerifier, 'The required pure hosted completion export must exist').toBeTypeOf('function');
  const result = completionVerifier?.(fixture.expected, fixture.job, fixture.receipt);
  expect(typeof result).toBe('boolean');
  expect(result).toBe(accepted);
}

function completionSteps(fixture: CompletionFixture): DataRecord[] {
  return fixture.job.steps as DataRecord[];
}

function selectedRecord(fixture: CompletionFixture, target: string): DataRecord {
  return target === 'step' ? completionSteps(fixture)[0]! : fixture[target as keyof CompletionFixture];
}

function replaceRecord(fixture: CompletionFixture, target: string, replacement: unknown): void {
  if (target === 'step') {
    completionSteps(fixture)[0] = replacement as DataRecord;
  } else {
    fixture[target as keyof CompletionFixture] = replacement as DataRecord;
  }
}

const recordFields = {
  expected: ['runId', 'sourceSha', 'jobId', 'runnerId', 'runnerEnvironment'],
  job: ['id', 'runId', 'attempt', 'sourceSha', 'name', 'status', 'conclusion', 'runnerId', 'runnerName', 'runnerGroupName', 'labels', 'steps', 'completedAt'],
  receipt: ['formatVersion', 'runId', 'sourceSha', 'jobId', 'runnerId', 'runnerEnvironment', 'privateProofSha256', 'completionKind', 'verifiedAt'],
  step: ['name', 'status', 'conclusion'],
};

describe('independent explicit provider-completion contract', () => {
  it('accepts the exact failed native hosted proof', () => {
    requireCompletion(freshCompletionFixture(), true);
  });

  it.each(['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure'])('accepts completed native failure kind %s', (conclusion) => {
    const fixture = freshCompletionFixture();
    fixture.job.conclusion = conclusion;
    requireCompletion(fixture, true);
  });

  it.each(['success', 'failure', 'skipped', 'cancelled', 'timed_out'])('accepts terminal ordinary step kind %s', (conclusion) => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture)[0]!.conclusion = conclusion;
    requireCompletion(fixture, true);
  });

  it('accepts strict ordering within a millisecond provider timestamp', () => {
    const fixture = freshCompletionFixture();
    fixture.job.completedAt = '2026-10-07T03:04:05.123Z';
    fixture.receipt.verifiedAt = '2026-10-07T03:04:05.124Z';
    requireCompletion(fixture, true);
  });

  it.each([
    { completed: '1970-01-01T00:00:00Z', verified: '1970-01-01T00:00:00.001Z' },
    { completed: '2024-02-29T23:59:59.999Z', verified: '2024-03-01T00:00:00.000Z' },
    { completed: '9999-12-31T23:59:59Z', verified: '9999-12-31T23:59:59.001Z' },
  ])('accepts canonical nonnegative UTC boundary $completed', ({ completed, verified }) => {
    const fixture = freshCompletionFixture();
    fixture.job.completedAt = completed;
    fixture.receipt.verifiedAt = verified;
    requireCompletion(fixture, true);
  });

  it('accepts different canonical identity values with all bindings updated', () => {
    const fixture = freshCompletionFixture();
    fixture.expected.runId = '1-1';
    fixture.receipt.runId = '1-1';
    fixture.job.runId = '1';
    fixture.job.attempt = '1';
    fixture.expected.jobId = String(Number.MAX_SAFE_INTEGER);
    fixture.receipt.jobId = String(Number.MAX_SAFE_INTEGER);
    fixture.job.id = Number.MAX_SAFE_INTEGER;
    fixture.expected.runnerId = Number.MAX_SAFE_INTEGER;
    fixture.receipt.runnerId = Number.MAX_SAFE_INTEGER;
    fixture.job.runnerId = Number.MAX_SAFE_INTEGER;
    fixture.job.runnerName = `GitHub Actions ${Number.MAX_SAFE_INTEGER}`;
    requireCompletion(fixture, true);
  });

  it('does not depend on the order of complete successful cleanup steps', () => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture).reverse();
    requireCompletion(fixture, true);
  });

  it('returns a boolean repeatedly without changing frozen input evidence', () => {
    const fixture = freshCompletionFixture();
    const serialized = JSON.stringify(fixture);
    completionSteps(fixture).forEach(Object.freeze);
    Object.freeze(fixture.job.steps);
    Object.freeze(fixture.job.labels);
    Object.freeze(fixture.expected);
    Object.freeze(fixture.job);
    Object.freeze(fixture.receipt);
    Object.freeze(fixture);
    requireCompletion(fixture, true);
    requireCompletion(fixture, true);
    expect(JSON.stringify(fixture)).toBe(serialized);
  });

  const incompatibleBindings = [
    { target: 'receipt', field: 'runId', value: '47-4' },
    { target: 'receipt', field: 'sourceSha', value: 'd'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'receipt', field: 'jobId', value: '110' },
    { target: 'receipt', field: 'runnerId', value: 72 },
    { target: 'receipt', field: 'runnerEnvironment', value: 'self-hosted' },
    { target: 'job', field: 'runId', value: '48' },
    { target: 'job', field: 'attempt', value: '4' },
    { target: 'job', field: 'sourceSha', value: 'd'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'job', field: 'id', value: 110 },
    { target: 'job', field: 'runnerId', value: 72 },
    { target: 'expected', field: 'runId', value: '47-4' },
    { target: 'expected', field: 'sourceSha', value: 'd'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'expected', field: 'jobId', value: '110' },
    { target: 'expected', field: 'runnerId', value: 72 },
    { target: 'expected', field: 'runnerEnvironment', value: 'self-hosted' },
  ];
  it.each(incompatibleBindings)('refuses changed $target.$field binding', ({ target, field, value }) => {
    const fixture = freshCompletionFixture();
    selectedRecord(fixture, target)[field] = value;
    requireCompletion(fixture, false);
  });

  it.each(['0-3', '47-0', '047-3', '47-03', '+47-3', '47--3', '47-3-1', '47.0-3', '47e0-3', ' 47-3', '47-3 ', '47', '', '47-3\n'])('refuses mutually matching malformed composite identity %j', (runId) => {
    const fixture = freshCompletionFixture();
    fixture.expected.runId = runId;
    fixture.receipt.runId = runId;
    const parts = runId.split('-');
    fixture.job.runId = parts[0];
    fixture.job.attempt = parts[1];
    requireCompletion(fixture, false);
  });

  it.each(['runId', 'attempt'])('requires canonical decimal provider %s', (field) => {
    for (const value of ['0', '-1', '+3', '03', '3.0', '3e0', ' 3', '3 ', '3\n', '', undefined, null, 3, true]) {
      const fixture = freshCompletionFixture();
      fixture.job[field] = value;
      requireCompletion(fixture, false);
    }
  });

  it.each(['0', '-109', '+109', '0109', '109.0', '109e0', ' 109', '109 ', '109\n', '', null, undefined, 109, true])('refuses noncanonical job IDs even when receipts agree %j', (jobId) => {
    const fixture = freshCompletionFixture();
    fixture.expected.jobId = jobId;
    fixture.receipt.jobId = jobId;
    requireCompletion(fixture, false);
  });

  it.each(['expected', 'job', 'receipt'])('requires positive safe integer runner identity in %s', (target) => {
    for (const value of [0, -1, Number.MAX_SAFE_INTEGER + 1, Number.NaN, Number.POSITIVE_INFINITY, '71', null, undefined, true, { fractional: 71.5 }.fractional]) {
      const fixture = freshCompletionFixture();
      selectedRecord(fixture, target).runnerId = value;
      requireCompletion(fixture, false);
    }
  });

  it.each([0, -1, Number.MAX_SAFE_INTEGER + 1, Number.NaN, Number.POSITIVE_INFINITY, '109', null, undefined, true, { fractional: 109.5 }.fractional])('requires positive safe integer provider job identity %j', (id) => {
    const fixture = freshCompletionFixture();
    fixture.job.id = id;
    requireCompletion(fixture, false);
  });

  it.each(['', 'B'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), 'g'.repeat(NATIVE_DB_VALIDATION.sourceShaLength), 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength - 1), `${'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)}0`, null, undefined])('refuses mutually matching malformed source digest %j', (sourceSha) => {
    const fixture = freshCompletionFixture();
    fixture.expected.sourceSha = sourceSha;
    fixture.job.sourceSha = sourceSha;
    fixture.receipt.sourceSha = sourceSha;
    requireCompletion(fixture, false);
  });

  it.each(['', 'C'.repeat(NATIVE_DB_VALIDATION.digestHexLength), 'g'.repeat(NATIVE_DB_VALIDATION.digestHexLength), 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength - 1), `${'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}0`, `${'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}\n`, null, undefined])('refuses malformed private proof digest %j', (digest) => {
    const fixture = freshCompletionFixture();
    fixture.receipt.privateProofSha256 = digest;
    requireCompletion(fixture, false);
  });

  it.each([
    { field: 'formatVersion', value: String(NATIVE_DB_VALIDATION.formatVersion) },
    { field: 'formatVersion', value: 0 },
    { field: 'formatVersion', value: NATIVE_DB_VALIDATION.formatVersion + 1 },
    { field: 'formatVersion', value: null },
    { field: 'completionKind', value: 'native-workload-teardown' },
    { field: 'completionKind', value: 'github-hosted-job-decommission ' },
    { field: 'completionKind', value: 'GitHub-hosted-job-decommission' },
    { field: 'completionKind', value: true },
    { field: 'completionKind', value: null },
  ])('refuses wrong receipt discriminator $field=$value', ({ field, value }) => {
    const fixture = freshCompletionFixture();
    fixture.receipt[field] = value;
    requireCompletion(fixture, false);
  });

  it.each(['self-hosted', 'github-hosted ', 'GitHub-hosted', 'hosted', '', null, undefined, true])('refuses matching non-hosted environment %j', (environment) => {
    const fixture = freshCompletionFixture();
    fixture.expected.runnerEnvironment = environment;
    fixture.receipt.runnerEnvironment = environment;
    requireCompletion(fixture, false);
  });

  it.each([
    { field: 'name', value: 'pgtap ' },
    { field: 'name', value: 'PGTAP' },
    { field: 'name', value: 'Native database validation' },
    { field: 'name', value: null },
    { field: 'status', value: 'queued' },
    { field: 'status', value: 'in_progress' },
    { field: 'status', value: 'Completed' },
    { field: 'status', value: 'completed ' },
    { field: 'status', value: null },
    { field: 'conclusion', value: 'success' },
    { field: 'conclusion', value: 'skipped' },
    { field: 'conclusion', value: 'neutral' },
    { field: 'conclusion', value: 'stale' },
    { field: 'conclusion', value: 'unknown' },
    { field: 'conclusion', value: 'failure ' },
    { field: 'conclusion', value: null },
    { field: 'runnerName', value: 'GitHub Actions 72' },
    { field: 'runnerName', value: 'GitHub Actions 071' },
    { field: 'runnerName', value: 'GitHub Actions 71 ' },
    { field: 'runnerName', value: 'github actions 71' },
    { field: 'runnerName', value: 'temporary-owner-runner' },
    { field: 'runnerName', value: null },
    { field: 'runnerGroupName', value: 'GitHub Actions ' },
    { field: 'runnerGroupName', value: 'Default' },
    { field: 'runnerGroupName', value: null },
    { field: 'labels', value: ['self-hosted', 'ubuntu-latest'] },
    { field: 'labels', value: ['ubuntu-latest', 'ubuntu-latest'] },
    { field: 'labels', value: ['Ubuntu-latest'] },
    { field: 'labels', value: ['ubuntu-latest '] },
    { field: 'labels', value: ['ubuntu-24.04'] },
    { field: 'labels', value: [] },
    { field: 'labels', value: 'ubuntu-latest' },
    { field: 'labels', value: null },
  ])('refuses incompatible provider evidence $field=$value', ({ field, value }) => {
    const fixture = freshCompletionFixture();
    fixture.job[field] = value;
    requireCompletion(fixture, false);
  });

  it.each([
    { field: 'name', value: '' },
    { field: 'name', value: null },
    { field: 'name', value: true },
    { field: 'status', value: 'in_progress' },
    { field: 'status', value: 'queued' },
    { field: 'status', value: null },
    { field: 'status', value: 'completed ' },
    { field: 'conclusion', value: 'action_required' },
    { field: 'conclusion', value: 'startup_failure' },
    { field: 'conclusion', value: 'neutral' },
    { field: 'conclusion', value: 'unknown' },
    { field: 'conclusion', value: 'success ' },
    { field: 'conclusion', value: null },
  ])('refuses malformed ordinary step $field=$value', ({ field, value }) => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture)[0]![field] = value;
    requireCompletion(fixture, false);
  });

  const cleanupNames = [
    'Post Run supabase/setup-cli@v3',
    'Post Run pnpm/action-setup@v6',
    'Post Run actions/checkout@v7',
    'Complete job',
  ];
  it.each(cleanupNames)('requires the cleanup %s once', (name) => {
    const fixture = freshCompletionFixture();
    fixture.job.steps = completionSteps(fixture).filter((step) => step.name !== name);
    requireCompletion(fixture, false);
  });

  it.each(cleanupNames)('refuses duplicate successful cleanup %s', (name) => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture).push({ name, status: 'completed', conclusion: 'success' });
    requireCompletion(fixture, false);
  });

  it.each(cleanupNames)('refuses conflicting duplicate cleanup %s', (name) => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture).push({ name, status: 'completed', conclusion: 'failure' });
    requireCompletion(fixture, false);
  });

  it.each(cleanupNames)('requires successful terminal cleanup %s', (name) => {
    for (const conclusion of ['failure', 'skipped', 'cancelled', 'timed_out']) {
      const fixture = freshCompletionFixture();
      completionSteps(fixture).find((step) => step.name === name)!.conclusion = conclusion;
      requireCompletion(fixture, false);
    }
    const fixture = freshCompletionFixture();
    completionSteps(fixture).find((step) => step.name === name)!.status = 'in_progress';
    requireCompletion(fixture, false);
  });

  it.each(cleanupNames)('rejects lookalike cleanup names for %s', (name) => {
    const fixture = freshCompletionFixture();
    completionSteps(fixture).find((step) => step.name === name)!.name = `${name} `;
    requireCompletion(fixture, false);
  });

  it.each([[], null, undefined, {}, 'completed'])('refuses absent or empty step accounting %j', (steps) => {
    const fixture = freshCompletionFixture();
    fixture.job.steps = steps;
    requireCompletion(fixture, false);
  });

  const malformedUtc = [
    '2026-10-07T03:04:05+00:00', '2026-10-07T03:04:05-00:00',
    '2026-10-07T03:04:05z', '2026-10-07t03:04:05Z',
    '2026-10-07 03:04:05Z', '2026-10-07',
    '2026-10-07T03:04:05.1Z', '2026-10-07T03:04:05.12Z',
    '2026-10-07T03:04:05.1234Z', '2026-10-07T03:04:05Z\n',
    '2026-10-07T24:00:00Z', '2026-10-07T03:04:60Z',
    '2026-02-29T03:04:05Z', '2026-02-30T03:04:05Z',
    '2026-04-31T03:04:05Z', '2026-00-07T03:04:05Z',
    '2026-13-07T03:04:05Z', '2026-10-00T03:04:05Z',
    '+010000-01-01T00:00:00.000Z', '-000001-01-01T00:00:00.000Z',
    '1969-12-31T23:59:59.999Z', '0000-01-01T00:00:00.000Z',
    '', 'invalid', null, undefined, true,
  ];
  it.each(malformedUtc)('rejects invalid or noncanonical provider completion UTC %j', (completedAt) => {
    const fixture = freshCompletionFixture();
    fixture.job.completedAt = completedAt;
    fixture.receipt.verifiedAt = '9999-12-31T23:59:59.999Z';
    requireCompletion(fixture, false);
  });

  it.each([...malformedUtc, '2026-10-07T03:04:06Z'])('rejects invalid or noncanonical receipt verification UTC %j', (verifiedAt) => {
    const fixture = freshCompletionFixture();
    fixture.job.completedAt = '1970-01-01T00:00:00Z';
    fixture.receipt.verifiedAt = verifiedAt;
    requireCompletion(fixture, false);
  });

  it.each(['2026-10-07T03:04:05.000Z', '2026-10-07T03:04:04.999Z', '1970-01-01T00:00:00.000Z'])('requires strictly later receipt verification %s', (verifiedAt) => {
    const fixture = freshCompletionFixture();
    fixture.receipt.verifiedAt = verifiedAt;
    requireCompletion(fixture, false);
  });

  it('rejects millisecond equality after different timestamp precision', () => {
    const fixture = freshCompletionFixture();
    fixture.job.completedAt = '2026-10-07T03:04:05.001Z';
    requireCompletion(fixture, false);
  });

  for (const [target, fields] of Object.entries(recordFields)) {
    describe(`closed ${target} record`, () => {
      it.each(fields)('rejects missing %s', (field) => {
        const fixture = freshCompletionFixture();
        delete selectedRecord(fixture, target)[field];
        requireCompletion(fixture, false);
      });

      it.each(fields)('rejects accessor %s without invoking it', (field) => {
        const fixture = freshCompletionFixture();
        let getterEffects = 0;
        Object.defineProperty(selectedRecord(fixture, target), field, {
          enumerable: true,
          get() {
            getterEffects += 1;
            throw new Error('untrusted getter must never run');
          },
        });
        expect(() => requireCompletion(fixture, false)).not.toThrow();
        expect(getterEffects).toBe(0);
      });

      it('rejects an extra own string field', () => {
        const fixture = freshCompletionFixture();
        selectedRecord(fixture, target).extraEvidence = true;
        requireCompletion(fixture, false);
      });

      it('rejects an extra nonenumerable field', () => {
        const fixture = freshCompletionFixture();
        Object.defineProperty(selectedRecord(fixture, target), 'extraEvidence', { value: true });
        requireCompletion(fixture, false);
      });

      it('rejects an own symbol field', () => {
        const fixture = freshCompletionFixture();
        Object.defineProperty(selectedRecord(fixture, target), Symbol('extraEvidence'), { value: true });
        requireCompletion(fixture, false);
      });

      it('rejects an extra getter without executing it', () => {
        const fixture = freshCompletionFixture();
        let getterEffects = 0;
        Object.defineProperty(selectedRecord(fixture, target), 'extraEvidence', {
          get() {
            getterEffects += 1;
            throw new Error('unknown getter must never run');
          },
        });
        expect(() => requireCompletion(fixture, false)).not.toThrow();
        expect(getterEffects).toBe(0);
      });

      it('rejects a nonordinary prototype', () => {
        const fixture = freshCompletionFixture();
        Object.setPrototypeOf(selectedRecord(fixture, target), { inheritedEvidence: true });
        requireCompletion(fixture, false);
      });

      it('rejects a null prototype', () => {
        const fixture = freshCompletionFixture();
        Object.setPrototypeOf(selectedRecord(fixture, target), null);
        requireCompletion(fixture, false);
      });

      it.each([undefined, null, true, 'evidence', [], new Date('2026-10-07T03:04:05Z')])('rejects nonordinary object substitute %j', (value) => {
        const fixture = freshCompletionFixture();
        replaceRecord(fixture, target, value);
        requireCompletion(fixture, false);
      });
    });
  }

  it('refuses provider-derived physical deletion booleans on a hosted receipt', () => {
    const fixture = freshCompletionFixture();
    Object.assign(fixture.receipt, {
      clientsStopped: true,
      containersRemoved: true,
      temporaryRoleRemoved: true,
      runnerDeregistered: true,
      vmDeleted: true,
    });
    requireCompletion(fixture, false);
  });

  for (const field of ['labels', 'steps']) {
    describe(`dense ordinary ${field} array`, () => {
      it('rejects a hole in existing evidence', () => {
        const fixture = freshCompletionFixture();
        const values = fixture.job[field] as unknown[];
        delete values[0];
        requireCompletion(fixture, false);
      });

      it('rejects a trailing hole', () => {
        const fixture = freshCompletionFixture();
        const values = fixture.job[field] as unknown[];
        values.length += 1;
        requireCompletion(fixture, false);
      });

      it('rejects a custom array prototype', () => {
        const fixture = freshCompletionFixture();
        Object.setPrototypeOf(fixture.job[field], Object.create(Array.prototype));
        requireCompletion(fixture, false);
      });

      it('rejects a null array prototype', () => {
        const fixture = freshCompletionFixture();
        Object.setPrototypeOf(fixture.job[field], null);
        requireCompletion(fixture, false);
      });

      it('rejects an own extra property', () => {
        const fixture = freshCompletionFixture();
        Object.defineProperty(fixture.job[field], 'extraEvidence', { value: true, enumerable: true });
        requireCompletion(fixture, false);
      });

      it('rejects a nonenumerable extra property', () => {
        const fixture = freshCompletionFixture();
        Object.defineProperty(fixture.job[field], 'extraEvidence', { value: true });
        requireCompletion(fixture, false);
      });

      it('rejects an own symbol property', () => {
        const fixture = freshCompletionFixture();
        Object.defineProperty(fixture.job[field], Symbol('extraEvidence'), { value: true });
        requireCompletion(fixture, false);
      });

      it('rejects an accessor element without reading it', () => {
        const fixture = freshCompletionFixture();
        let getterEffects = 0;
        Object.defineProperty(fixture.job[field], '0', {
          enumerable: true,
          get() {
            getterEffects += 1;
            throw new Error('array element getter must never run');
          },
        });
        expect(() => requireCompletion(fixture, false)).not.toThrow();
        expect(getterEffects).toBe(0);
      });

      it('rejects an unknown accessor without reading it', () => {
        const fixture = freshCompletionFixture();
        let getterEffects = 0;
        Object.defineProperty(fixture.job[field], 'extraEvidence', {
          get() {
            getterEffects += 1;
            throw new Error('array extra getter must never run');
          },
        });
        expect(() => requireCompletion(fixture, false)).not.toThrow();
        expect(getterEffects).toBe(0);
      });

      it('rejects an own iterator getter without reading it', () => {
        const fixture = freshCompletionFixture();
        let getterEffects = 0;
        Object.defineProperty(fixture.job[field], Symbol.iterator, {
          get() {
            getterEffects += 1;
            throw new Error('iterator getter must never run');
          },
        });
        expect(() => requireCompletion(fixture, false)).not.toThrow();
        expect(getterEffects).toBe(0);
      });

      it('rejects array-like record substitutes', () => {
        const fixture = freshCompletionFixture();
        const values = fixture.job[field] as unknown[];
        fixture.job[field] = { ...values, length: values.length };
        requireCompletion(fixture, false);
      });
    });
  }
});
