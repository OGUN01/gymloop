import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type HeldSetupData = Record<string, unknown>;
type HeldSetupFixture = ReturnType<typeof heldSetupFixture>;

const heldSetupModuleUrl = new URL('../../scripts/pgtap/unarmed-setup-failure.mjs', import.meta.url);
let heldSetupLoadError: unknown;
let heldSetupVerifier: ((input: unknown) => boolean) | undefined;
try {
  const loaded = await import(heldSetupModuleUrl.href);
  heldSetupVerifier = loaded.verifyUnarmedNativeSetupFailure;
} catch (error) {
  heldSetupLoadError = error;
}

function heldSetupRequireVerifier(): (input: unknown) => boolean {
  expect(heldSetupLoadError, 'HSF_MODULE_LOAD').toBeUndefined();
  expect(heldSetupVerifier, 'HSF_BOOLEAN_API').toBeTypeOf('function');
  return heldSetupVerifier as (input: unknown) => boolean;
}

function heldSetupFixture() {
  const run = {
    id: '37822050096',
    attempt: '1',
    sourceSha: 'db8715c0f5e20b34f753652cc01b0b4d94566872',
    repositoryId: 1190090911,
    repository: 'OGUN01/gymloop',
    headRepositoryId: 1190090911,
    headRepository: 'OGUN01/gymloop',
    event: 'push',
    path: '.github/workflows/db.yml',
    branch: 'main',
    status: 'completed',
    conclusion: 'failure',
  };
  const native = {
    id: 113466344205,
    runId: run.id,
    attempt: run.attempt,
    sourceSha: run.sourceSha,
    name: 'pgtap',
    status: 'completed',
    conclusion: 'failure',
    runnerId: 441177,
    runnerName: 'held-original-windows',
    runnerGroupName: 'Default',
    labels: [
      'self-hosted',
      'Windows',
      'X64',
      `${NATIVE_DB_VALIDATION.labelPrefix}-${run.id}-1-${run.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`,
    ],
    steps: [
      { name: 'Set up job', status: 'completed', conclusion: 'success' },
      { name: 'Set up runner', status: 'completed', conclusion: 'failure' },
      { name: 'Record adapter setup start before checkout', status: 'completed', conclusion: 'skipped' },
      { name: 'Record hosted adapter setup start before checkout', status: 'completed', conclusion: 'skipped' },
      { name: 'Run actions/checkout@v7', status: 'completed', conclusion: 'skipped' },
      { name: 'Run pnpm/action-setup@v6', status: 'completed', conclusion: 'skipped' },
      { name: 'Run actions/setup-node@v7', status: 'completed', conclusion: 'skipped' },
      { name: 'Install the frozen adapter dependencies', status: 'completed', conclusion: 'skipped' },
      { name: 'Install the frozen hosted adapter dependencies', status: 'completed', conclusion: 'skipped' },
      { name: 'Use the verified Git Bash executable for the pinned CLI installer', status: 'completed', conclusion: 'skipped' },
      { name: 'Run supabase/setup-cli@v3', status: 'completed', conclusion: 'skipped' },
      { name: 'Run actions/download-artifact@v5', status: 'completed', conclusion: 'skipped' },
      { name: 'Freeze full rollback-safe file and schema metadata', status: 'completed', conclusion: 'skipped' },
      { name: 'Run actions/upload-artifact@v5', status: 'completed', conclusion: 'skipped' },
      { name: 'Validate the full native suite with outside-worker recovery custody', status: 'completed', conclusion: 'skipped' },
      { name: 'Retain sanitized native receipt', status: 'completed', conclusion: 'success' },
      { name: 'Retain client-only smoke metadata', status: 'completed', conclusion: 'success' },
      { name: 'Retain the explicit interim timing boundary', status: 'completed', conclusion: 'success' },
      { name: 'Retain sanitized encrypted-artifact custody verification', status: 'completed', conclusion: 'success' },
      { name: 'Complete job', status: 'completed', conclusion: 'success' },
    ],
  };
  const guardian = {
    id: 113466555344,
    runId: run.id,
    attempt: run.attempt,
    sourceSha: run.sourceSha,
    name: 'timeout-guardian',
    status: 'completed',
    conclusion: 'failure',
    runnerId: 559988,
    runnerName: 'GitHub Actions 559988',
    runnerGroupName: 'GitHub Actions',
    labels: ['ubuntu-latest'],
    steps: [
      { name: 'Set up job', status: 'completed', conclusion: 'success' },
      { name: 'Run actions/checkout@v7', status: 'completed', conclusion: 'success' },
      { name: 'Run pnpm/action-setup@v6', status: 'completed', conclusion: 'success' },
      { name: 'Run actions/setup-node@v7', status: 'completed', conclusion: 'success' },
      { name: 'Run pnpm install --frozen-lockfile --filter "@gymloop/shared..." --prod --ignore-scripts', status: 'completed', conclusion: 'success' },
      { name: 'Run supabase/setup-cli@v3', status: 'completed', conclusion: 'success' },
      { name: 'Find the exact armed receipt, including an earlier attempt of this run', status: 'completed', conclusion: 'failure' },
      { name: 'Run actions/download-artifact@v5', status: 'completed', conclusion: 'skipped' },
      { name: 'Run actions/download-artifact@v5', status: 'completed', conclusion: 'skipped' },
      { name: 'Run supabase link --project-ref "$PROJECT_REF" --yes', status: 'completed', conclusion: 'skipped' },
      { name: 'Restore and freshly verify only the captured role-global timeout', status: 'completed', conclusion: 'skipped' },
      { name: 'Retain independently hosted restoration evidence', status: 'completed', conclusion: 'skipped' },
      { name: 'Post Run supabase/setup-cli@v3', status: 'completed', conclusion: 'success' },
      { name: 'Post Run actions/setup-node@v7', status: 'completed', conclusion: 'skipped' },
      { name: 'Post Run pnpm/action-setup@v6', status: 'completed', conclusion: 'success' },
      { name: 'Post Run actions/checkout@v7', status: 'completed', conclusion: 'success' },
      { name: 'Complete job', status: 'completed', conclusion: 'success' },
    ],
  };
  return {
    run,
    nativeJobs: [native],
    guardianJobs: [guardian],
    artifactNames: [`native-db-schema-${run.id}-1`, `native-db-ci-job-${run.id}-1`],
    jobListingComplete: true,
    artifactListingComplete: true,
    teardownReview: {
      formatVersion: 1,
      runId: `${run.id}-1`,
      sourceSha: run.sourceSha,
      jobId: String(native.id),
      runnerId: native.runnerId,
      runnerEnvironment: 'self-hosted',
      privateProofSha256: 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      nativeProcessesStopped: true,
      ownedContainersStopped: true,
      runnerDeregistered: true,
      verifiedAt: '2026-10-08T12:34:56.000Z',
    },
  };
}

function heldSetupAlter(input: HeldSetupFixture, path: string[], value: unknown): HeldSetupFixture {
  let target = input as unknown as HeldSetupData;
  for (const key of path.slice(0, -1)) target = target[key] as HeldSetupData;
  const key = path.at(-1);
  if (key === undefined) throw new Error('HSF_FIXTURE_PATH');
  Object.defineProperty(target, key, { value, enumerable: true, configurable: true, writable: true });
  return input;
}

function heldSetupWorkflowScript() {
  const workflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');
  for (const match of workflow.matchAll(/^( *)script:\s*\|\s*\r?\n/gm)) {
    const tail = workflow.slice((match.index ?? 0) + match[0].length);
    const lines: string[] = [];
    for (const line of tail.split(/\r?\n/)) {
      if (line.trim().length > 0 && (line.match(/^ */)?.[0].length ?? 0) <= match[1].length) break;
      lines.push(line);
    }
    const script = lines.join('\n');
    if (script.includes('projectUnarmedJob') && script.includes('verifyNativeWorkloadTeardown')) return { workflow, script };
  }
  throw new Error('HSF_PREFLIGHT_SCRIPT');
}

describe('held exact unarmed setup failure', () => {
  it('accepts the complete original allocated failure pair and returns a literal boolean', () => {
    const result = heldSetupRequireVerifier()(heldSetupFixture());
    expect(result).toBe(true);
    expect(typeof result).toBe('boolean');
  });

  it('accepts workflow_dispatch and permutation of the exact unique labels and artifacts', () => {
    const value = heldSetupFixture();
    value.run.event = 'workflow_dispatch';
    value.nativeJobs[0].labels.reverse();
    value.artifactNames.reverse();
    expect(heldSetupRequireVerifier()(value)).toBe(true);
  });

  for (const value of [null, undefined, false, true, '', 'failure', 0, 1, [], new Date(), new Map()]) {
    it(`refuses a non-record input ${String(value)}`, () => {
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });
  }

  for (const path of [
    [], ['run'], ['nativeJobs'], ['guardianJobs'], ['artifactNames'], ['nativeJobs', '0'],
    ['guardianJobs', '0'], ['nativeJobs', '0', 'steps'], ['guardianJobs', '0', 'steps'],
    ['nativeJobs', '0', 'steps', '0'], ['guardianJobs', '0', 'steps', '0'], ['teardownReview'],
  ]) {
    it(`refuses extra own evidence at ${path.join('.') || 'input'}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path) target = target[key] as HeldSetupData;
      Object.defineProperty(target, 'untrusted', { value: true, enumerable: false });
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });

    it(`refuses symbol evidence at ${path.join('.') || 'input'}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path) target = target[key] as HeldSetupData;
      Object.defineProperty(target, Symbol('held-extra'), { value: true });
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });

    it(`refuses inherited evidence at ${path.join('.') || 'input'}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path) target = target[key] as HeldSetupData;
      Object.setPrototypeOf(target, { forged: true });
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });
  }

  for (const path of [
    ['run'], ['run', 'id'], ['nativeJobs'], ['nativeJobs', '0'], ['nativeJobs', '0', 'labels', '0'],
    ['nativeJobs', '0', 'steps', '1', 'conclusion'], ['guardianJobs', '0', 'runnerId'],
    ['guardianJobs', '0', 'steps', '6', 'conclusion'], ['artifactNames', '0'],
    ['jobListingComplete'], ['artifactListingComplete'], ['teardownReview'],
    ['teardownReview', 'nativeProcessesStopped'], ['teardownReview', 'privateProofSha256'],
  ]) {
    it(`does not invoke an accessor at ${path.join('.')}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path.slice(0, -1)) target = target[key] as HeldSetupData;
      const key = path.at(-1);
      if (key === undefined) throw new Error('HSF_FIXTURE_PATH');
      const original = target[key];
      let observed = false;
      Object.defineProperty(target, key, { enumerable: true, configurable: true, get() { observed = true; return original; } });
      expect(heldSetupRequireVerifier()(value)).toBe(false);
      expect(observed).toBe(false);
    });
  }

  for (const path of [[], ['run'], ['nativeJobs'], ['nativeJobs', '0'], ['teardownReview']]) {
    it(`contains reflection exceptions at ${path.join('.') || 'input'}`, () => {
      const original = heldSetupFixture();
      let target: unknown = original;
      for (const key of path) target = (target as HeldSetupData)[key];
      const hostile = new Proxy(target as object, { ownKeys() { throw new Error('held-reflection'); } });
      const value = path.length === 0 ? hostile : heldSetupAlter(original, path, hostile);
      const verify = heldSetupRequireVerifier();
      expect(() => verify(value)).not.toThrow();
      expect(verify(value)).toBe(false);
    });
  }

  for (const [path, keys] of [
    [[], Object.keys(heldSetupFixture())],
    [['run'], Object.keys(heldSetupFixture().run)],
    [['nativeJobs', '0'], Object.keys(heldSetupFixture().nativeJobs[0])],
    [['guardianJobs', '0'], Object.keys(heldSetupFixture().guardianJobs[0])],
    [['nativeJobs', '0', 'steps', '0'], ['name', 'status', 'conclusion']],
    [['guardianJobs', '0', 'steps', '0'], ['name', 'status', 'conclusion']],
    [['teardownReview'], Object.keys(heldSetupFixture().teardownReview)],
  ] as [string[], string[]][]) {
    for (const key of keys) {
      it(`requires own data field ${[...path, key].join('.')}`, () => {
        const value = heldSetupFixture();
        let target = value as unknown as HeldSetupData;
        for (const part of path) target = target[part] as HeldSetupData;
        Reflect.deleteProperty(target, key);
        expect(heldSetupRequireVerifier()(value)).toBe(false);
      });
    }
  }

  for (const path of [
    ['nativeJobs'], ['guardianJobs'], ['artifactNames'], ['nativeJobs', '0', 'labels'],
    ['guardianJobs', '0', 'labels'], ['nativeJobs', '0', 'steps'], ['guardianJobs', '0', 'steps'],
  ]) {
    it(`requires a dense ordinary array at ${path.join('.')}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path) target = target[key] as HeldSetupData;
      Reflect.deleteProperty(target, '0');
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });

    it(`refuses an array-like record at ${path.join('.')}`, () => {
      const value = heldSetupFixture();
      let target = value as unknown as HeldSetupData;
      for (const key of path) target = target[key] as HeldSetupData;
      heldSetupAlter(value, path, { ...target });
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });
  }

  for (const [path, invalid] of [
    [['run', 'id'], '0'], [['run', 'id'], '-1'], [['run', 'id'], '037822050096'],
    [['run', 'id'], '9007199254740992'], [['run', 'id'], 37822050096],
    [['run', 'attempt'], '2'], [['run', 'attempt'], 1],
    [['run', 'sourceSha'], 'DB8715C0F5E20B34F753652CC01B0B4D94566872'],
    [['run', 'sourceSha'], 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength - 1)],
    [['run', 'repositoryId'], 0], [['run', 'repositoryId'], '1190090911'],
    [['run', 'headRepositoryId'], 1190090912], [['run', 'headRepositoryId'], '1190090911'],
    [['run', 'repository'], 'OGUN01/other'], [['run', 'headRepository'], 'outsider/gymloop'],
    [['run', 'event'], 'pull_request'], [['run', 'event'], 'schedule'],
    [['run', 'path'], '.github/workflows/native-runner-readiness.yml'],
    [['run', 'branch'], 'release'], [['run', 'status'], 'in_progress'],
    [['run', 'conclusion'], 'cancelled'], [['run', 'conclusion'], 'success'],
    [['nativeJobs', '0', 'id'], '113466344205'], [['nativeJobs', '0', 'id'], 0],
    [['nativeJobs', '0', 'id'], Number.MAX_SAFE_INTEGER + 1],
    [['nativeJobs', '0', 'runnerId'], null], [['nativeJobs', '0', 'runnerId'], '441177'],
    [['nativeJobs', '0', 'runnerId'], 0], [['nativeJobs', '0', 'runnerId'], 1.5],
    [['nativeJobs', '0', 'runId'], '37822050097'], [['nativeJobs', '0', 'attempt'], '2'],
    [['nativeJobs', '0', 'sourceSha'], 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    [['nativeJobs', '0', 'name'], 'timeout-guardian'], [['nativeJobs', '0', 'status'], 'queued'],
    [['nativeJobs', '0', 'conclusion'], 'cancelled'], [['nativeJobs', '0', 'runnerName'], ''],
    [['nativeJobs', '0', 'runnerGroupName'], 'GitHub Actions'],
    [['guardianJobs', '0', 'id'], '113466555344'], [['guardianJobs', '0', 'id'], 113466344205],
    [['guardianJobs', '0', 'runnerId'], 441177], [['guardianJobs', '0', 'runnerId'], -1],
    [['guardianJobs', '0', 'runId'], '37822050097'], [['guardianJobs', '0', 'attempt'], '2'],
    [['guardianJobs', '0', 'sourceSha'], 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    [['guardianJobs', '0', 'name'], 'pgtap'], [['guardianJobs', '0', 'status'], 'in_progress'],
    [['guardianJobs', '0', 'conclusion'], 'timed_out'],
    [['guardianJobs', '0', 'runnerName'], 'GitHub Actions 559989'],
    [['guardianJobs', '0', 'runnerGroupName'], 'Default'],
    [['jobListingComplete'], false], [['jobListingComplete'], 'true'],
    [['artifactListingComplete'], false], [['artifactListingComplete'], 1],
    [['teardownReview', 'formatVersion'], '1'], [['teardownReview', 'formatVersion'], 2],
    [['teardownReview', 'runId'], '37822050096'], [['teardownReview', 'runId'], '37822050096-2'],
    [['teardownReview', 'sourceSha'], 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    [['teardownReview', 'jobId'], 113466344205], [['teardownReview', 'jobId'], '113466555344'],
    [['teardownReview', 'runnerId'], 559988], [['teardownReview', 'runnerId'], '441177'],
    [['teardownReview', 'runnerEnvironment'], 'github-hosted'],
    [['teardownReview', 'privateProofSha256'], 'C'.repeat(NATIVE_DB_VALIDATION.digestHexLength)],
    [['teardownReview', 'privateProofSha256'], 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength - 1)],
    [['teardownReview', 'nativeProcessesStopped'], false], [['teardownReview', 'ownedContainersStopped'], false],
    [['teardownReview', 'runnerDeregistered'], false], [['teardownReview', 'runnerDeregistered'], 'true'],
    [['teardownReview', 'verifiedAt'], '2026-10-08T18:04:56.000+05:30'],
    [['teardownReview', 'verifiedAt'], '2026-02-30T12:34:56.000Z'],
    [['teardownReview', 'verifiedAt'], '2026-10-08T12:34:56.000Z '],
  ] as [string[], unknown][]) {
    it(`refuses inconsistent or malformed ${path.join('.')} = ${String(invalid)}`, () => {
      expect(heldSetupRequireVerifier()(heldSetupAlter(heldSetupFixture(), path, invalid))).toBe(false);
    });
  }

  for (const path of [['nativeJobs'], ['guardianJobs']]) {
    it(`refuses missing or duplicate original jobs in ${path.join('.')}`, () => {
      const empty = heldSetupFixture();
      heldSetupAlter(empty, path, []);
      expect(heldSetupRequireVerifier()(empty)).toBe(false);
      const duplicate = heldSetupFixture();
      const jobs = (duplicate as unknown as HeldSetupData)[path[0]] as unknown[];
      jobs.push(structuredClone(jobs[0]));
      expect(heldSetupRequireVerifier()(duplicate)).toBe(false);
    });
  }

  for (const labels of [
    [], ['self-hosted', 'Windows', 'X64'], ['self-hosted', 'Windows', 'X64', 'self-hosted'],
    ['self-hosted', 'windows', 'X64', heldSetupFixture().nativeJobs[0].labels.at(-1)],
    ['self-hosted', 'Windows', 'ARM64', heldSetupFixture().nativeJobs[0].labels.at(-1)],
    ['self-hosted', 'Windows', 'X64', `${NATIVE_DB_VALIDATION.labelPrefix}-37822050096-2-db8715c0f5e2`],
    ['self-hosted', 'Windows', 'X64', `${NATIVE_DB_VALIDATION.labelPrefix}-37822050097-1-db8715c0f5e2`],
    ['self-hosted', 'Windows', 'X64', `${NATIVE_DB_VALIDATION.labelPrefix}-37822050096-1-aaaaaaaaaaaa`],
    [...heldSetupFixture().nativeJobs[0].labels, 'gpu'],
  ]) {
    it(`refuses native label substitution ${String(labels)}`, () => {
      expect(heldSetupRequireVerifier()(heldSetupAlter(heldSetupFixture(), ['nativeJobs', '0', 'labels'], labels))).toBe(false);
    });
  }

  for (const labels of [[], ['ubuntu-24.04'], ['ubuntu-latest', 'self-hosted'], ['ubuntu-latest', 'ubuntu-latest']]) {
    it(`refuses guardian label substitution ${String(labels)}`, () => {
      expect(heldSetupRequireVerifier()(heldSetupAlter(heldSetupFixture(), ['guardianJobs', '0', 'labels'], labels))).toBe(false);
    });
  }

  for (const unexpected of [
    'native-db-recovery-37822050096-1', 'native-db-final-37822050096-1',
    'native-db-smoke-37822050096-1', 'native-db-manifest-37822050096-1',
    'native-db-timing-37822050096-1', 'native-db-private-custody-37822050096-1',
    'native-db-restoration-37822050096-1', 'unrelated-public-file',
    'native-db-schema-37822050096-2', 'native-db-schema-37822050097-1',
  ]) {
    it(`refuses conflicting or extra custody ${unexpected}`, () => {
      const value = heldSetupFixture();
      value.artifactNames.push(unexpected);
      expect(heldSetupRequireVerifier()(value)).toBe(false);
    });
  }

  it('refuses absent, replaced, or duplicate retained artifact evidence', () => {
    const verify = heldSetupRequireVerifier();
    expect(verify(heldSetupAlter(heldSetupFixture(), ['artifactNames'], []))).toBe(false);
    expect(verify(heldSetupAlter(heldSetupFixture(), ['artifactNames'], ['native-db-schema-37822050096-1']))).toBe(false);
    expect(verify(heldSetupAlter(heldSetupFixture(), ['artifactNames'], ['native-db-schema-37822050096-1', 'native-db-schema-37822050096-1']))).toBe(false);
    expect(verify(heldSetupAlter(heldSetupFixture(), ['artifactNames'], ['native-db-schema-37822050096-1', 'native-db-ci-job-37822050096-2']))).toBe(false);
  });

  it('refuses teardown wrappers, multiple reviews, and unallocated review evidence', () => {
    const value = heldSetupFixture();
    const verify = heldSetupRequireVerifier();
    expect(verify({ ...value, teardownReview: { review: value.teardownReview } })).toBe(false);
    expect(verify({ ...value, teardownReview: [value.teardownReview] })).toBe(false);
    expect(verify({ ...value, teardownReview: { ...value.teardownReview, kind: 'unallocated-cancellation' } })).toBe(false);
  });

  for (const jobKey of ['nativeJobs', 'guardianJobs'] as const) {
    for (const [index, step] of heldSetupFixture()[jobKey][0].steps.entries()) {
      it(`requires exact ${jobKey} step ${index}: ${step.name}`, () => {
        const value = heldSetupFixture();
        value[jobKey][0].steps[index].name += ' substituted';
        expect(heldSetupRequireVerifier()(value)).toBe(false);
      });

      it(`rejects executing ${jobKey} step ${index}: ${step.name}`, () => {
        const value = heldSetupFixture();
        value[jobKey][0].steps[index].status = 'in_progress';
        expect(heldSetupRequireVerifier()(value)).toBe(false);
      });

      it(`requires exact ${jobKey} conclusion ${index}: ${step.conclusion}`, () => {
        const value = heldSetupFixture();
        value[jobKey][0].steps[index].conclusion = step.conclusion === 'success' ? 'skipped' : 'success';
        expect(heldSetupRequireVerifier()(value)).toBe(false);
      });
    }

    for (const mutation of ['missing', 'extra', 'reordered', 'cancelled'] as const) {
      it(`refuses ${mutation} ${jobKey} ordered execution vector`, () => {
        const value = heldSetupFixture();
        const steps = value[jobKey][0].steps;
        if (mutation === 'missing') steps.pop();
        if (mutation === 'extra') steps.push({ ...steps[0] });
        if (mutation === 'reordered') [steps[0], steps[1]] = [steps[1], steps[0]];
        if (mutation === 'cancelled') steps[0].conclusion = 'cancelled';
        expect(heldSetupRequireVerifier()(value)).toBe(false);
      });
    }
  }
});

describe('held actual workflow setup-failure integration', () => {
  for (const event of ['push', 'pull_request']) {
    it(`includes the exact classifier module in the ${event} path filter`, () => {
      const { workflow } = heldSetupWorkflowScript();
      const match = workflow.match(new RegExp(`^  ${event}:\\s*\\r?\\n([\\s\\S]*?)(?=^  [a-zA-Z_]+:|^\\S|(?![\\s\\S]))`, 'm'));
      expect(match, 'HSF_EVENT_FILTER').not.toBeNull();
      expect(match?.[1].match(/['"]scripts\/pgtap\/unarmed-setup-failure\.mjs['"]/g), 'HSF_EXACT_MODULE_FILTER').toHaveLength(1);
    });
  }

  it('imports and uses the dedicated verifier in the actual predecessor preflight', () => {
    const { script } = heldSetupWorkflowScript();
    expect(script, 'HSF_IMPORT').toMatch(/import\([^;\n]*scripts\/pgtap\/unarmed-setup-failure\.mjs/);
    expect(script.match(/\bverifyUnarmedNativeSetupFailure\s*\(/g), 'HSF_ACTUAL_CALL').toHaveLength(1);
    expect(script, 'HSF_SEPARATE_SET').toMatch(/\bconst\s+verifiedSetupFailures\s*=\s*new Set\s*\(/);
    expect(script.match(/\bverifiedSetupFailures\.add\s*\(/g), 'HSF_SINGLE_GUARDIAN_RECORD').toHaveLength(1);
    expect(script, 'HSF_NATIVE_PROJECTION').toMatch(/projectUnarmedJob/);
    expect(script, 'HSF_COMPLETE_JOB_OBSERVATION').toMatch(/jobListingComplete/);
    expect(script, 'HSF_COMPLETE_ARTIFACT_OBSERVATION').toMatch(/artifactListingComplete/);
    expect(script, 'HSF_PHYSICAL_REVIEW').toMatch(/teardownReview/);
  });

  it('keeps the sole setup exemption after the original allocated physical gate in the guardian scan', () => {
    const { script } = heldSetupWorkflowScript();
    const physicalGate = script.indexOf('verifyNativeWorkloadTeardown(');
    const exemption = script.indexOf('verifiedSetupFailures.has(');
    expect(physicalGate, 'HSF_ORIGINAL_ALLOCATED_GATE').toBeGreaterThanOrEqual(0);
    expect(exemption, 'HSF_GUARDIAN_ONLY_POSITION').toBeGreaterThan(physicalGate);
    expect(script.match(/\bverifiedSetupFailures\.has\s*\(/g), 'HSF_NO_NATIVE_EXEMPTION').toHaveLength(1);
    expect(script.slice(physicalGate, exemption), 'HSF_GUARDIAN_SCAN').toMatch(/timeout-guardian/);
    expect(script.slice(0, physicalGate), 'HSF_NO_EARLY_EXEMPTION').not.toMatch(/verifiedSetupFailures\.has\s*\(/);
    expect(script, 'HSF_CANONICAL_PHYSICAL_IMPORT').toMatch(/import\([^;\n]*scripts\/pgtap\/workload-teardown\.mjs/);
  });
});
