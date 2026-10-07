import { beforeAll, describe, expect, test } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

const hostedNativeCompletionFixture = {
  expected: {
    runId: '42-2',
    sourceSha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    jobId: '73',
    runnerId: 91,
    runnerEnvironment: 'github-hosted',
  },
  job: {
    id: 73,
    runId: '42',
    attempt: '2',
    sourceSha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    name: 'pgtap',
    status: 'completed',
    conclusion: 'failure',
    runnerId: 91,
    runnerName: 'GitHub Actions 91',
    runnerGroupName: 'GitHub Actions',
    labels: ['ubuntu-latest'],
    steps: [
      { name: 'Set up job', status: 'completed', conclusion: 'success' },
      { name: 'Run native workload', status: 'completed', conclusion: 'failure' },
      { name: 'Post Run supabase/setup-cli@v3', status: 'completed', conclusion: 'success' },
      { name: 'Post Run pnpm/action-setup@v6', status: 'completed', conclusion: 'success' },
      { name: 'Post Run actions/checkout@v7', status: 'completed', conclusion: 'success' },
      { name: 'Complete job', status: 'completed', conclusion: 'success' },
    ],
    completedAt: '2026-10-07T08:14:15Z',
  },
  receipt: {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion as number,
    runId: '42-2',
    sourceSha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    jobId: '73',
    runnerId: 91,
    runnerEnvironment: 'github-hosted',
    privateProofSha256: 'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
    completionKind: 'github-hosted-job-decommission',
    verifiedAt: '2026-10-07T08:14:15.001Z',
  },
};

const completionModuleUrl = new URL('../pgtap/hosted-completion.mjs', import.meta.url).href;
let moduleLoadError: string | undefined;
let loadedVerifier: ((expected: unknown, job: unknown, receipt: unknown) => boolean) | undefined;

beforeAll(async () => {
  try {
    const completionModule: Record<string, unknown> = await import(completionModuleUrl);
    const candidate = completionModule.verifyHostedNativeWorkloadCompletion;
    if (typeof candidate !== 'function') {
      moduleLoadError = 'The required pure verifier export is absent';
      return;
    }
    loadedVerifier = candidate as (expected: unknown, job: unknown, receipt: unknown) => boolean;
  } catch (error) {
    moduleLoadError = error instanceof Error ? error.message : String(error);
  }
});

describe('the frozen explicit hosted worker completion contract', () => {
  test('accepts an exact completed hosted proof and leaves its inputs unchanged', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    const snapshot = structuredClone(fixture);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(true);
    expect(fixture).toEqual(snapshot);
  });

  test.each(['failure', 'cancelled', 'timed_out', 'action_required', 'startup_failure'])(
    'accepts the specified completed native job conclusion %s',
    (conclusion) => {
      const fixture = structuredClone(hostedNativeCompletionFixture);
      fixture.job.conclusion = conclusion;
      expect(moduleLoadError).toBeUndefined();
      expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(true);
    },
  );

  test.each(['success', 'failure', 'skipped', 'cancelled', 'timed_out'])(
    'accepts the specified ordinary completed step conclusion %s',
    (conclusion) => {
      const fixture = structuredClone(hostedNativeCompletionFixture);
      fixture.job.steps[0]!.conclusion = conclusion;
      expect(moduleLoadError).toBeUndefined();
      expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(true);
    },
  );

  test.each([
    { completedAt: '2026-10-07T08:14:15Z', verifiedAt: '2026-10-07T08:14:15.001Z' },
    { completedAt: '2026-10-07T08:14:15.100Z', verifiedAt: '2026-10-07T08:14:15.101Z' },
    { completedAt: '2026-12-31T23:59:59.999Z', verifiedAt: '2027-01-01T00:00:00.000Z' },
    { completedAt: '1970-01-01T00:00:00Z', verifiedAt: '1970-01-01T00:00:00.001Z' },
    { completedAt: '2024-02-29T23:59:59Z', verifiedAt: '2024-03-01T00:00:00.000Z' },
    { completedAt: '9999-12-31T23:59:59.998Z', verifiedAt: '9999-12-31T23:59:59.999Z' },
  ])('accepts canonical ordered UTC timestamps $completedAt / $verifiedAt', (timestamps) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.assign(fixture.job, { completedAt: timestamps.completedAt });
    Object.assign(fixture.receipt, { verifiedAt: timestamps.verifiedAt });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(true);
  });

  test('accepts a reordered complete cleanup list', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps.reverse();
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(true);
  });

  test.each([
    { target: 'expected', key: 'runId', value: '43-2' },
    { target: 'expected', key: 'sourceSha', value: 'c'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'expected', key: 'jobId', value: '74' },
    { target: 'expected', key: 'runnerId', value: 92 },
    { target: 'expected', key: 'runnerEnvironment', value: 'self-hosted' },
    { target: 'job', key: 'id', value: 74 },
    { target: 'job', key: 'runId', value: '43' },
    { target: 'job', key: 'attempt', value: '3' },
    { target: 'job', key: 'sourceSha', value: 'c'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'job', key: 'runnerId', value: 92 },
    { target: 'receipt', key: 'runId', value: '43-2' },
    { target: 'receipt', key: 'sourceSha', value: 'c'.repeat(NATIVE_DB_VALIDATION.sourceShaLength) },
    { target: 'receipt', key: 'jobId', value: '74' },
    { target: 'receipt', key: 'runnerId', value: 92 },
    { target: 'receipt', key: 'runnerEnvironment', value: 'self-hosted' },
    { target: 'receipt', key: 'formatVersion', value: 0 },
    { target: 'receipt', key: 'formatVersion', value: '1' },
    { target: 'receipt', key: 'completionKind', value: 'self-hosted-runner-deregistered' },
    { target: 'receipt', key: 'completionKind', value: 'github-hosted-job-decommission ' },
  ] as const)('rejects a mismatched $target.$key binding', ({ target, key, value }) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture[target], key, value);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['0-2', '42-0', '-42-2', '42--2', '042-2', '42-02', '+42-2', '42-+2', '42.0-2',
    '42-2.0', '4e1-2', '42-2e0', '42', '42-2-1', '42-2\n', ' 42-2', '42-2 ', '٤٢-2', ''])(
    'rejects noncanonical expected and receipt run identity %j', (runId) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.expected.runId = runId;
    fixture.receipt.runId = runId;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['0', '-73', '073', '+73', '73.0', '7.3e1', '73\n', '73 ', ' 73', '٧٣', ''])(
    'rejects noncanonical expected and receipt job identity %j', (jobId) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.expected.jobId = jobId;
    fixture.receipt.jobId = jobId;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([
    { key: 'runId', value: '042' }, { key: 'runId', value: '0' },
    { key: 'runId', value: '42\n' }, { key: 'runId', value: 42 },
    { key: 'attempt', value: '02' }, { key: 'attempt', value: '0' },
    { key: 'attempt', value: '2\n' }, { key: 'attempt', value: 2 },
    { key: 'id', value: '73' }, { key: 'id', value: 0 }, { key: 'id', value: -1 },
    { key: 'id', value: 73.5 }, { key: 'id', value: Number.NaN },
    { key: 'id', value: Number.POSITIVE_INFINITY }, { key: 'id', value: Number.MAX_SAFE_INTEGER + 1 },
  ])('rejects an invalid provider numeric identity $key = $value', ({ key, value }) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job, key, value);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([0, -1, 91.5, Number.NaN, Number.POSITIVE_INFINITY, Number.MAX_SAFE_INTEGER + 1, '91', null, true])(
    'rejects an invalid runner identity even when all bindings agree: %j', (runnerId) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.expected, 'runnerId', runnerId);
    Reflect.set(fixture.job, 'runnerId', runnerId);
    Reflect.set(fixture.receipt, 'runnerId', runnerId);
    fixture.job.runnerName = `GitHub Actions ${String(runnerId)}`;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['A'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength - 1),
    'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength + 1),
    'g'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    `${'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)}\n`, ''])(
    'rejects invalid source syntax even with identical bindings: %j', (sourceSha) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.expected.sourceSha = sourceSha;
    fixture.job.sourceSha = sourceSha;
    fixture.receipt.sourceSha = sourceSha;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['B'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
    'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength - 1),
    'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength + 1),
    'g'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
    `${'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength)}\n`, ''])(
    'rejects invalid independently reviewed packet digest %j', (privateProofSha256) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.receipt.privateProofSha256 = privateProofSha256;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([
    { key: 'name', value: 'pgtap-holdout' }, { key: 'name', value: 'pgtap ' },
    { key: 'status', value: 'in_progress' }, { key: 'status', value: 'queued' },
    { key: 'status', value: 'Completed' }, { key: 'status', value: null },
    { key: 'conclusion', value: 'success' }, { key: 'conclusion', value: 'skipped' },
    { key: 'conclusion', value: 'neutral' }, { key: 'conclusion', value: 'unknown' },
    { key: 'conclusion', value: null },
    { key: 'runnerName', value: 'GitHub Actions 92' },
    { key: 'runnerName', value: 'GitHub Actions 091' },
    { key: 'runnerName', value: 'github actions 91' },
    { key: 'runnerName', value: 'GitHub Actions 91 ' },
    { key: 'runnerGroupName', value: 'Default' },
    { key: 'runnerGroupName', value: 'GitHub Actions ' },
    { key: 'labels', value: [] }, { key: 'labels', value: ['self-hosted'] },
    { key: 'labels', value: ['ubuntu-24.04'] },
    { key: 'labels', value: ['ubuntu-latest', 'ubuntu-latest'] },
    { key: 'labels', value: ['ubuntu-latest', 'Linux'] },
    { key: 'labels', value: 'ubuntu-latest' },
  ])('rejects missing or conflicting provider evidence $key = $value', ({ key, value }) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job, key, value);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects a coherent self-hosted-looking worker as a provider completion proof', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.expected.runnerEnvironment = 'self-hosted';
    fixture.receipt.runnerEnvironment = 'self-hosted';
    fixture.job.runnerName = 'temporary-native-owner-91';
    fixture.job.runnerGroupName = 'Default';
    fixture.job.labels = ['self-hosted', 'Linux', 'X64'];
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6',
    'Post Run actions/checkout@v7', 'Complete job'])('requires cleanup evidence exactly once: %s', (name) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps = fixture.job.steps.filter((step) => step.name !== name);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6',
    'Post Run actions/checkout@v7', 'Complete job'])('rejects duplicate cleanup evidence: %s', (name) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps.push({ name, status: 'completed', conclusion: 'success' });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6',
    'Post Run actions/checkout@v7', 'Complete job'])('rejects unsuccessful cleanup evidence: %s', (name) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps.find((step) => step.name === name)!.conclusion = 'failure';
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6',
    'Post Run actions/checkout@v7', 'Complete job'])('requires the literal cleanup spelling: %s', (name) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps.find((step) => step.name === name)!.name = `${name} `;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([
    { key: 'name', value: '' }, { key: 'name', value: null }, { key: 'name', value: 0 },
    { key: 'status', value: 'in_progress' }, { key: 'status', value: 'queued' },
    { key: 'status', value: null }, { key: 'conclusion', value: 'action_required' },
    { key: 'conclusion', value: 'startup_failure' }, { key: 'conclusion', value: 'neutral' },
    { key: 'conclusion', value: 'unknown' }, { key: 'conclusion', value: null },
  ])('rejects nonterminal or unnamed ordinary steps: $key = $value', ({ key, value }) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job.steps[0]!, key, value);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['success', 'skipped', 'cancelled', 'timed_out'])('requires success for cleanup, not %s', (conclusion) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.steps.find((step) => step.name === 'Complete job')!.conclusion = conclusion;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(conclusion === 'success');
  });

  test.each([
    '2026-10-07T08:14:15Z', '2026-10-07T08:14:15.000Z', '2026-10-07T08:14:14.999Z',
    '2026-10-07T08:14:16.000+00:00', '2026-10-07T08:14:16.000',
    '2026-10-07 08:14:16.000Z', '2026-10-07T08:14:16.000z',
    '2026-10-07T08:14:16.00Z', '2026-10-07T08:14:16.0000Z',
    '2026-10-07T08:14:16.000Z\n', ' 2026-10-07T08:14:16.000Z',
    '2026-02-29T08:14:16.000Z', '2026-04-31T08:14:16.000Z',
    '2026-13-07T08:14:16.000Z', '2026-10-00T08:14:16.000Z',
    '2026-10-07T24:00:00.000Z', '2026-10-07T08:60:16.000Z',
    '2026-10-07T08:14:60.000Z', '+010000-10-07T08:14:16.000Z',
    '1969-12-31T23:59:59.999Z', '0000-01-01T00:00:00.000Z', '',
  ])('rejects invalid, noncanonical, or unordered review UTC %j', (verifiedAt) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.receipt.verifiedAt = verifiedAt;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([
    '2026-10-07T08:14:15.001Z', '2026-10-07T08:14:15.002Z',
    '2026-10-07T08:14:15+00:00', '2026-10-07T08:14:15.000+00:00',
    '2026-10-07T08:14:15', '2026-10-07 08:14:15Z',
    '2026-10-07T08:14:15z', '2026-10-07T08:14:15.1Z',
    '2026-10-07T08:14:15.0000Z', '2026-10-07T08:14:15Z\n',
    ' 2026-10-07T08:14:15Z', '2026-02-29T08:14:15Z',
    '2026-04-31T08:14:15Z', '2026-13-07T08:14:15Z',
    '2026-10-00T08:14:15Z', '2026-10-07T24:00:00Z',
    '2026-10-07T08:60:15Z', '2026-10-07T08:14:60Z',
    '+010000-10-07T08:14:15Z', '1969-12-31T23:59:59.999Z',
    '0000-01-01T00:00:00Z', '',
  ])('rejects invalid, noncanonical, or unordered provider UTC %j', (completedAt) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    fixture.job.completedAt = completedAt;
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each([
    { target: 'expected', keys: Object.keys(hostedNativeCompletionFixture.expected) },
    { target: 'job', keys: Object.keys(hostedNativeCompletionFixture.job) },
    { target: 'receipt', keys: Object.keys(hostedNativeCompletionFixture.receipt) },
  ] as const)('requires every own field in $target', ({ target, keys }) => {
    expect(moduleLoadError).toBeUndefined();
    for (const key of keys) {
      const fixture = structuredClone(hostedNativeCompletionFixture);
      Reflect.deleteProperty(fixture[target], key);
      expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    }
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects unknown data fields in %s', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture[target], 'workerDeleted', true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects unknown nonenumerable fields in %s', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.defineProperty(fixture[target], 'workerDeleted', { value: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects symbol fields in %s', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture[target], Symbol('provider-deletion'), true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects null-prototype data records in %s', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture[target], null);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects custom-prototype data records in %s', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture[target], { providerTrusted: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects accessors in %s without invoking them', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    let getterEffects = 0;
    const key = Object.keys(fixture[target])[0]!;
    Object.defineProperty(fixture[target], key, {
      enumerable: true,
      get() { getterEffects += 1; throw new Error('Getter must remain untouched'); },
    });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    expect(getterEffects).toBe(0);
  });

  test.each(['expected', 'job', 'receipt'] as const)('rejects unknown accessors in %s without invoking them', (target) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    let getterEffects = 0;
    Object.defineProperty(fixture[target], 'unknown', {
      enumerable: true,
      get() { getterEffects += 1; throw new Error('Unknown getter must remain untouched'); },
    });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    expect(getterEffects).toBe(0);
  });

  test.each([null, undefined, false, 1, 'record', []])('rejects non-record root input %j', (invalid) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(invalid, fixture.job, fixture.receipt)).toBe(false);
    expect(loadedVerifier?.(fixture.expected, invalid, fixture.receipt)).toBe(false);
    expect(loadedVerifier?.(fixture.expected, fixture.job, invalid)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects an empty %s array', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job, key, []);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects sparse %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.deleteProperty(fixture.job[key], '0');
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects custom-prototype %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture.job[key], Object.create(Array.prototype));
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects null-prototype %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture.job[key], null);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects unknown own properties on %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job[key], 'providerTrusted', true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects nonenumerable unknown properties on %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.defineProperty(fixture.job[key], 'providerTrusted', { value: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects symbol properties on %s arrays', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job[key], Symbol('providerTrusted'), true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['labels', 'steps'] as const)('rejects element accessors on %s arrays without invoking them', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    let getterEffects = 0;
    Object.defineProperty(fixture.job[key], '0', {
      enumerable: true,
      get() { getterEffects += 1; throw new Error('Array getter must remain untouched'); },
    });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    expect(getterEffects).toBe(0);
  });

  test.each(['labels', 'steps'] as const)('rejects unknown accessors on %s arrays without invoking them', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    let getterEffects = 0;
    Object.defineProperty(fixture.job[key], 'unknown', {
      enumerable: true,
      get() { getterEffects += 1; throw new Error('Unknown array getter must remain untouched'); },
    });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    expect(getterEffects).toBe(0);
  });

  test.each([null, undefined, false, 'array', { length: 1, 0: 'ubuntu-latest' }])(
    'rejects non-array labels or steps input %j', (invalid) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    expect(moduleLoadError).toBeUndefined();
    Reflect.set(fixture.job, 'labels', invalid);
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    fixture.job.labels = ['ubuntu-latest'];
    Reflect.set(fixture.job, 'steps', invalid);
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['name', 'status', 'conclusion'])('requires the own step field %s', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.deleteProperty(fixture.job.steps[0]!, key);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects unknown step fields', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job.steps[0]!, 'providerTrusted', true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects nonenumerable unknown step fields', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.defineProperty(fixture.job.steps[0]!, 'providerTrusted', { value: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects step symbol fields', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job.steps[0]!, Symbol('providerTrusted'), true);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects a null-prototype step record', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture.job.steps[0]!, null);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('rejects a custom-prototype step record', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.setPrototypeOf(fixture.job.steps[0]!, { providerTrusted: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test.each(['name', 'status', 'conclusion'])('rejects step %s accessors without invoking them', (key) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    let getterEffects = 0;
    Object.defineProperty(fixture.job.steps[0]!, key, {
      enumerable: true,
      get() { getterEffects += 1; throw new Error('Step getter must remain untouched'); },
    });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
    expect(getterEffects).toBe(0);
  });

  test.each([null, undefined, false, 1, 'step', []])('rejects non-record step input %j', (invalid) => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Reflect.set(fixture.job.steps, '0', invalid);
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });

  test('refuses literal worker-deletion boolean evidence on the provider receipt', () => {
    const fixture = structuredClone(hostedNativeCompletionFixture);
    Object.assign(fixture.receipt, { workerDeleted: true, runnerDeregistered: true });
    expect(moduleLoadError).toBeUndefined();
    expect(loadedVerifier?.(fixture.expected, fixture.job, fixture.receipt)).toBe(false);
  });
});
