import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';
import { verifyUnarmedNativeSetupFailure } from '../pgtap/unarmed-setup-failure.mjs';

type VisibleUnarmedRecord = Record<string, unknown>;

const visibleUnarmedModulePath = 'scripts/pgtap/unarmed-setup-failure.mjs';
const visibleUnarmedNativeVector = [
  ['Set up job', 'success'],
  ['Set up runner', 'failure'],
  ['Record adapter setup start before checkout', 'skipped'],
  ['Record hosted adapter setup start before checkout', 'skipped'],
  ['Run actions/checkout@v7', 'skipped'],
  ['Run pnpm/action-setup@v6', 'skipped'],
  ['Run actions/setup-node@v7', 'skipped'],
  ['Install the frozen adapter dependencies', 'skipped'],
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
  ['Complete job', 'success'],
] as const;
const visibleUnarmedGuardianVector = [
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

function visibleUnarmedFixture() {
  const run = {
    id: '37822050096',
    attempt: '1',
    sourceSha: 'db8715c0f5e20b34f753652cc01b0b4d94566872',
    repositoryId: 1144792834,
    repository: 'OGUN01/gymloop',
    headRepositoryId: 1144792834,
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
    runnerId: 4101,
    runnerName: 'fitcruxx-original-trial16',
    runnerGroupName: 'Default',
    labels: [
      'self-hosted', 'Windows', 'X64',
      `${NATIVE_DB_VALIDATION.labelPrefix}-${run.id}-1-${run.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}`,
    ],
    steps: visibleUnarmedNativeVector.map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
  };
  const guardian = {
    id: 113466555344,
    runId: run.id,
    attempt: run.attempt,
    sourceSha: run.sourceSha,
    name: 'timeout-guardian',
    status: 'completed',
    conclusion: 'failure',
    runnerId: 4102,
    runnerName: 'GitHub Actions 4102',
    runnerGroupName: 'GitHub Actions',
    labels: ['ubuntu-latest'],
    steps: visibleUnarmedGuardianVector.map(([name, conclusion]) => ({ name, status: 'completed', conclusion })),
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
      privateProofSha256: 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      nativeProcessesStopped: true,
      ownedContainersStopped: true,
      runnerDeregistered: true,
      verifiedAt: '2026-10-09T00:00:00.000Z',
    },
  };
}

const visibleUnarmedWorkflow = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8').replace(/\r\n/g, '\n');

describe('exact unarmed native runner setup failure', () => {
  it('accepts only the public original native setup failure and pre-link guardian vector with positive physical teardown', () => {
    expect(verifyUnarmedNativeSetupFailure(visibleUnarmedFixture())).toBe(true);
  });

  it('accepts workflow_dispatch and order-independent exact labels and artifact names', () => {
    const input = visibleUnarmedFixture();
    input.run.event = 'workflow_dispatch';
    input.nativeJobs[0]!.labels.reverse();
    input.artifactNames.reverse();
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(true);
  });

  it.each([undefined, null, false, true, 0, 1, 'input', [], () => undefined])('refuses a non-record boundary %s', (input) => {
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it.each(['run', 'nativeJobs', 'guardianJobs', 'artifactNames', 'jobListingComplete', 'artifactListingComplete', 'teardownReview'])('refuses a missing top-level %s', (key) => {
    const input: VisibleUnarmedRecord = visibleUnarmedFixture();
    delete input[key];
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it('refuses extra, inherited, symbol and non-enumerable top-level data', () => {
    for (const input of [
      { ...visibleUnarmedFixture(), recovery: false },
      Object.assign(Object.create({ recovery: false }), visibleUnarmedFixture()),
      Object.assign(visibleUnarmedFixture(), { [Symbol('hidden')]: true }),
      Object.defineProperty(visibleUnarmedFixture(), 'hidden', { value: true }),
    ]) expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it('refuses hostile reflection and accessors without executing them', () => {
    let accessed = false;
    const input = visibleUnarmedFixture();
    Object.defineProperty(input, 'teardownReview', { enumerable: true, get: () => { accessed = true; throw new Error('getter'); } });
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    expect(accessed).toBe(false);
    expect(verifyUnarmedNativeSetupFailure(new Proxy({}, { ownKeys: () => { throw new Error('reflection'); } }))).toBe(false);
  });

  it.each(['jobListingComplete', 'artifactListingComplete'])('requires literal complete evidence for %s', (key) => {
    for (const value of [false, undefined, null, 1, 'true', Object(true)]) {
      const input = visibleUnarmedFixture();
      Object.assign(input, { [key]: value });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs', 'artifactNames'])('refuses sparse, accessor, inherited, extra-key and ambiguous %s arrays', (key) => {
    for (const change of ['empty', 'duplicate', 'hole', 'extra', 'symbol', 'prototype', 'getter', 'not-array']) {
      const input: VisibleUnarmedRecord = visibleUnarmedFixture();
      const original = input[key] as unknown[];
      const array = [...original];
      let accessed = false;
      if (change === 'empty') array.splice(0);
      if (change === 'duplicate') array.push(array[0]);
      if (change === 'hole') delete array[0];
      if (change === 'extra') Object.assign(array, { hidden: true });
      if (change === 'symbol') Object.assign(array, { [Symbol('hidden')]: true });
      if (change === 'prototype') Object.setPrototypeOf(array, Object.create(Array.prototype));
      if (change === 'getter') Object.defineProperty(array, '0', { enumerable: true, get: () => { accessed = true; throw new Error('array getter'); } });
      input[key] = change === 'not-array' ? { ...array } : array;
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
      expect(accessed).toBe(false);
    }
  });

  it.each(['run', 'nativeJobs', 'guardianJobs', 'teardownReview'])('refuses malformed exact nested %s records', (kind) => {
    for (const change of ['missing', 'extra', 'symbol', 'prototype', 'getter', 'not-record']) {
      const input = visibleUnarmedFixture();
      const record = kind === 'run' ? input.run : kind === 'teardownReview' ? input.teardownReview : kind === 'nativeJobs' ? input.nativeJobs[0]! : input.guardianJobs[0]!;
      const firstKey = Object.keys(record)[0]!;
      let accessed = false;
      if (change === 'missing') delete (record as VisibleUnarmedRecord)[firstKey];
      if (change === 'extra') Object.assign(record, { hidden: true });
      if (change === 'symbol') Object.assign(record, { [Symbol('hidden')]: true });
      if (change === 'prototype') Object.setPrototypeOf(record, { hidden: true });
      if (change === 'getter') Object.defineProperty(record, firstKey, { enumerable: true, get: () => { accessed = true; throw new Error('record getter'); } });
      if (change === 'not-record') {
        if (kind === 'nativeJobs' || kind === 'guardianJobs') (input[kind] as unknown[])[0] = [];
        else Object.assign(input, { [kind]: [] });
      }
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
      expect(accessed).toBe(false);
    }
  });

  it.each([
    ['id', '0'], ['id', '-1'], ['id', '01'], ['id', '1e3'], ['id', '9007199254740992'], ['id', 37822050096],
    ['attempt', '2'], ['attempt', 1], ['sourceSha', 'DB8715C0F5E20B34F753652CC01B0B4D94566872'], ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength - 1)],
    ['repositoryId', 0], ['repositoryId', -1], ['repositoryId', 1.5], ['repositoryId', Number.MAX_SAFE_INTEGER + 1],
    ['headRepositoryId', 0], ['headRepositoryId', 1144792835], ['repository', 'OGUN01/other'], ['repository', 'ogun01/gymloop'],
    ['headRepository', 'fork/gymloop'], ['event', 'pull_request'], ['event', 'schedule'], ['path', '.github/workflows/other.yml'],
    ['branch', 'feature'], ['status', 'in_progress'], ['conclusion', 'success'], ['conclusion', 'cancelled'], ['conclusion', 'timed_out'],
  ])('refuses run identity or status mutation %s=%s', (key, value) => {
    const input = visibleUnarmedFixture();
    Object.assign(input.run, { [key]: value });
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it.each(Object.keys(visibleUnarmedFixture().run))('refuses run missing exact field %s', (key) => {
    const input = visibleUnarmedFixture();
    delete (input.run as VisibleUnarmedRecord)[key];
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('requires each original %s projected job identity and status', (kind) => {
    for (const [key, value] of [
      ['id', 0], ['id', -1], ['id', 1.5], ['id', Number.MAX_SAFE_INTEGER + 1], ['id', '113466344205'],
      ['runId', '37822050097'], ['attempt', '2'], ['attempt', 1], ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
      ['status', 'in_progress'], ['conclusion', 'success'], ['conclusion', 'cancelled'],
      ['runnerId', 0], ['runnerId', -1], ['runnerId', 1.5], ['runnerId', Number.MAX_SAFE_INTEGER + 1], ['runnerId', '4101'],
      ['runnerName', ''], ['runnerGroupName', 'Other'], ['name', 'other'],
    ]) {
      const input = visibleUnarmedFixture();
      Object.assign(input[kind][0]!, { [key as string]: value });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses every missing exact original %s field', (kind) => {
    for (const key of Object.keys(visibleUnarmedFixture()[kind][0]!)) {
      const input = visibleUnarmedFixture();
      delete (input[kind][0] as VisibleUnarmedRecord)[key];
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it('requires distinct original native and guardian job and runner ids', () => {
    const sameJob = visibleUnarmedFixture();
    sameJob.guardianJobs[0]!.id = sameJob.nativeJobs[0]!.id;
    expect(verifyUnarmedNativeSetupFailure(sameJob)).toBe(false);
    const sameRunner = visibleUnarmedFixture();
    sameRunner.guardianJobs[0]!.runnerId = sameRunner.nativeJobs[0]!.runnerId;
    sameRunner.guardianJobs[0]!.runnerName = `GitHub Actions ${sameRunner.guardianJobs[0]!.runnerId}`;
    expect(verifyUnarmedNativeSetupFailure(sameRunner)).toBe(false);
  });

  it.each(['name', 'runnerName', 'runnerGroupName', 'labels'])('requires canonical hosted guardian %s', (key) => {
    const input = visibleUnarmedFixture();
    Object.assign(input.guardianJobs[0]!, { [key]: key === 'labels' ? ['self-hosted', 'ubuntu-latest'] : 'pgtap' });
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it('refuses changed, missing, duplicate, stale or extra native labels', () => {
    const input = visibleUnarmedFixture();
    const labels = input.nativeJobs[0]!.labels;
    for (const candidate of [
      labels.slice(1), [...labels, 'extra'], [...labels, labels[0]!], labels.map((label) => label === 'Windows' ? 'windows' : label),
      labels.map((label) => label.startsWith(NATIVE_DB_VALIDATION.labelPrefix) ? label.replace('-1-', '-2-') : label),
      labels.map((label) => label.startsWith(NATIVE_DB_VALIDATION.labelPrefix) ? `${NATIVE_DB_VALIDATION.labelPrefix}-37822050097-1-${input.run.sourceSha.slice(0, NATIVE_DB_VALIDATION.labelShaLength)}` : label),
      labels.map((label) => label.startsWith(NATIVE_DB_VALIDATION.labelPrefix) ? `${NATIVE_DB_VALIDATION.labelPrefix}-${input.run.id}-1-${'a'.repeat(NATIVE_DB_VALIDATION.labelShaLength)}` : label),
    ]) {
      const changed = visibleUnarmedFixture();
      changed.nativeJobs[0]!.labels = candidate;
      expect(verifyUnarmedNativeSetupFailure(changed)).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses hostile %s labels and steps without invoking accessors', (kind) => {
    for (const property of ['labels', 'steps'] as const) {
      for (const change of ['hole', 'extra', 'symbol', 'prototype', 'getter', 'record']) {
        const input = visibleUnarmedFixture();
        const array = input[kind][0]![property];
        let accessed = false;
        if (change === 'hole') delete array[0];
        if (change === 'extra') Object.assign(array, { hidden: true });
        if (change === 'symbol') Object.assign(array, { [Symbol('hidden')]: true });
        if (change === 'prototype') Object.setPrototypeOf(array, Object.create(Array.prototype));
        if (change === 'getter') Object.defineProperty(array, '0', { enumerable: true, get: () => { accessed = true; throw new Error('nested array getter'); } });
        if (change === 'record') Object.assign(input[kind][0]!, { [property]: { ...array } });
        expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
        expect(accessed).toBe(false);
      }
    }
  });

  it.each(visibleUnarmedNativeVector.map(([name], index) => [index, name] as const))('requires exact native provider step %s: %s', (index) => {
    for (const [key, value] of [['name', 'Unknown native step'], ['status', 'in_progress'], ['status', 'queued'], ['status', 'cancelled'], ['status', 'skipped'], ['conclusion', 'cancelled'], ['conclusion', 'neutral']]) {
      const input = visibleUnarmedFixture();
      Object.assign(input.nativeJobs[0]!.steps[index]!, { [key!]: value });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(visibleUnarmedGuardianVector.map(([name], index) => [index, name] as const))('requires exact guardian provider step %s: %s', (index) => {
    for (const [key, value] of [['name', 'Unknown guardian step'], ['status', 'in_progress'], ['status', 'queued'], ['status', 'cancelled'], ['status', 'skipped'], ['conclusion', 'cancelled'], ['conclusion', 'neutral']]) {
      const input = visibleUnarmedFixture();
      Object.assign(input.guardianJobs[0]!.steps[index]!, { [key!]: value });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses removed, reordered, duplicated and extra %s steps', (kind) => {
    for (const change of ['removed', 'reversed', 'duplicate', 'extra']) {
      const input = visibleUnarmedFixture();
      const steps = input[kind][0]!.steps;
      if (change === 'removed') steps.pop();
      if (change === 'reversed') steps.reverse();
      if (change === 'duplicate') steps.splice(1, 0, { ...steps[0]! });
      if (change === 'extra') steps.push({ name: 'Unexpected work', status: 'completed', conclusion: 'success' });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses hostile exact step records in %s', (kind) => {
    for (const change of ['missing', 'extra', 'symbol', 'prototype', 'getter', 'array']) {
      const input = visibleUnarmedFixture();
      const step = input[kind][0]!.steps[0]!;
      let accessed = false;
      if (change === 'missing') delete (step as VisibleUnarmedRecord).status;
      if (change === 'extra') Object.assign(step, { number: 1 });
      if (change === 'symbol') Object.assign(step, { [Symbol('hidden')]: true });
      if (change === 'prototype') Object.setPrototypeOf(step, { hidden: true });
      if (change === 'getter') Object.defineProperty(step, 'name', { enumerable: true, get: () => { accessed = true; throw new Error('step getter'); } });
      if (change === 'array') (input[kind][0]!.steps as unknown[])[0] = [];
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
      expect(accessed).toBe(false);
    }
  });

  it.each(['nativeJobs', 'guardianJobs'] as const)('refuses any attempted work or unexpected skipped required step in %s', (kind) => {
    const reference = kind === 'nativeJobs' ? visibleUnarmedNativeVector : visibleUnarmedGuardianVector;
    for (const [index, [, expected]] of reference.entries()) {
      for (const conclusion of ['success', 'failure', 'skipped']) {
        if (conclusion === expected) continue;
        const input = visibleUnarmedFixture();
        input[kind][0]!.steps[index]!.conclusion = conclusion;
        expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
      }
    }
  });

  it.each([
    'native-db-recovery', 'native-db-final', 'native-db-smoke', 'native-db-manifest', 'native-db-timing',
    'native-db-private-custody', 'native-db-restoration', 'unexpected',
  ])('refuses armed or unexpected artifact %s even beside exact schema and job artifacts', (name) => {
    const input = visibleUnarmedFixture();
    input.artifactNames.push(`${name}-${input.run.id}-1`);
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it('refuses incomplete, duplicate and wrong-source artifact identity', () => {
    for (const names of [
      ['native-db-schema-37822050096-1'], ['native-db-ci-job-37822050096-1'],
      ['native-db-schema-37822050096-1', 'native-db-schema-37822050096-1'],
      ['native-db-schema-37822050096-2', 'native-db-ci-job-37822050096-1'],
      ['native-db-schema-37822050097-1', 'native-db-ci-job-37822050096-1'],
      ['native-db-schema-37822050096-1 ', 'native-db-ci-job-37822050096-1'],
    ]) {
      const input = visibleUnarmedFixture();
      input.artifactNames = names;
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each(['nativeProcessesStopped', 'ownedContainersStopped', 'runnerDeregistered'])('requires literal positive physical teardown %s', (key) => {
    for (const value of [false, undefined, null, 1, 'true']) {
      const input = visibleUnarmedFixture();
      Object.assign(input.teardownReview, { [key]: value });
      expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
    }
  });

  it.each([
    ['formatVersion', '1'], ['formatVersion', 2], ['runId', '37822050096'], ['runId', '37822050096-2'],
    ['sourceSha', 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)], ['sourceSha', 'DB8715C0F5E20B34F753652CC01B0B4D94566872'],
    ['jobId', '113466555344'], ['jobId', 113466344205], ['runnerId', 4102], ['runnerId', '4101'],
    ['runnerEnvironment', 'github-hosted'], ['privateProofSha256', 'a'.repeat(NATIVE_DB_VALIDATION.digestHexLength - 1)], ['privateProofSha256', 'A'.repeat(NATIVE_DB_VALIDATION.digestHexLength)],
    ['privateProofSha256', 'g'.repeat(NATIVE_DB_VALIDATION.digestHexLength)], ['verifiedAt', '2026-10-09T00:00:00Z'],
    ['verifiedAt', '2026-10-09T05:30:00.000+05:30'], ['verifiedAt', '2026-02-30T00:00:00.000Z'], ['verifiedAt', 'invalid'],
  ])('requires canonical bound physical receipt %s=%s', (key, value) => {
    const input = visibleUnarmedFixture();
    Object.assign(input.teardownReview, { [key]: value });
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });

  it.each(Object.keys(visibleUnarmedFixture().teardownReview))('refuses receipt missing canonical field %s', (key) => {
    const input = visibleUnarmedFixture();
    delete (input.teardownReview as VisibleUnarmedRecord)[key];
    expect(verifyUnarmedNativeSetupFailure(input)).toBe(false);
  });
});

describe('public workflow preserves the narrow unarmed guardian exception', () => {
  it('includes the exact helper path in both push and pull request filters', () => {
    for (const event of ['push', 'pull_request']) {
      const block = visibleUnarmedWorkflow.match(new RegExp(`^  ${event}:\\r?\\n([\\s\\S]*?)(?=^  [a-zA-Z_]+:|$(?![\\s\\S]))`, 'm'));
      expect(block, `${event} event block`).not.toBeNull();
      expect(block![1]).toContain(visibleUnarmedModulePath);
    }
  });

  it('imports and uses the exact registered verifier with complete original evidence projections', () => {
    expect(visibleUnarmedWorkflow).toMatch(/(?:import\s*\{\s*verifyUnarmedNativeSetupFailure\s*\}\s*from\s*['"]\.\/scripts\/pgtap\/unarmed-setup-failure\.mjs['"]|const\s*\{\s*verifyUnarmedNativeSetupFailure\s*\}\s*=\s*await\s+import\([^\r\n;]*\/scripts\/pgtap\/unarmed-setup-failure\.mjs[^\r\n;]*\))/);
    expect(visibleUnarmedWorkflow).toMatch(/verifyUnarmedNativeSetupFailure\s*\(\s*\{[\s\S]*?run[\s\S]*?nativeJobs[\s\S]*?guardianJobs[\s\S]*?artifactNames[\s\S]*?jobListingComplete[\s\S]*?artifactListingComplete[\s\S]*?teardownReview[\s\S]*?\}\s*\)/);
    expect(visibleUnarmedWorkflow.match(/projectUnarmedJob/g)?.length).toBeGreaterThan(1);
  });

  it('keeps a separate exact guardian exception set and requires unique indexed physical proof before recording it', () => {
    expect(visibleUnarmedWorkflow).toMatch(/(?:const|let)\s+verifiedSetupFailures\s*=\s*new\s+Set\s*\(/);
    const call = visibleUnarmedWorkflow.search(/verifyUnarmedNativeSetupFailure\s*\(/);
    expect(call).toBeGreaterThan(0);
    const index = visibleUnarmedWorkflow.lastIndexOf('operatorReceipts.filter', call);
    expect(index).toBeGreaterThan(0);
    const record = visibleUnarmedWorkflow.indexOf('verifiedSetupFailures.add', call);
    expect(record).toBeGreaterThan(call);
    const admission = visibleUnarmedWorkflow.slice(index, record);
    expect(admission).toMatch(/\.length\s*(?:===|!==|!=|==)\s*1/);
    expect(admission).toContain('teardownReview');
    expect(admission).toContain('github.rest.actions.getWorkflowRunAttempt');
    expect(admission).toContain('github.rest.actions.listJobsForWorkflowRunAttempt');
    expect(admission).toContain('github.rest.actions.listWorkflowRunArtifacts');
    expect(admission).toMatch(/jobListingComplete\s*:\s*Number\.isSafeInteger\([\s\S]*?total_count[\s\S]*?total_count\s*===\s*attemptJobs\.length/);
    expect(admission).toMatch(/artifactListingComplete\s*:\s*Number\.isSafeInteger\([\s\S]*?total_count[\s\S]*?total_count\s*===\s*artifacts\.length/);
    expect(admission).toMatch(/expired\s*===\s*false/);
    expect(visibleUnarmedWorkflow.slice(record).match(/^verifiedSetupFailures\.add\s*\([^\n]*\)/)?.[0]).toMatch(/boundRunAttempt[\s\S]*guardianJobs[\s\S]*\.id/);
  });

  it('consults this set once in the final guardian no-recovery refusal and never the native physical proof loop', () => {
    const references = [...visibleUnarmedWorkflow.matchAll(/verifiedSetupFailures\.has\s*\(/g)];
    expect(references).toHaveLength(1);
    const noRecovery = visibleUnarmedWorkflow.match(/if\s*\(recoveries\.length\s*===\s*0\)\s*\{[\s\S]*?continue;\s*\}/)?.[0];
    expect(noRecovery).toContain("job.name === 'timeout-guardian'");
    expect(noRecovery).toContain('Previous attempted guardian has no recovery receipt');
    expect(noRecovery).toMatch(/!verifiedSetupFailures\.has\s*\(\s*`\$\{run\.id\}-\$\{job\.boundAttempt\}-\$\{job\.id\}`\s*\)/);
    const physicalLoop = visibleUnarmedWorkflow.match(/^ {16}for \(const job of attemptJobs\) \{[\s\S]*?^ {16}\}/m)?.[0];
    expect(physicalLoop).toContain('verifyNativeWorkloadTeardown(expected,receipt)');
    expect(physicalLoop).not.toContain('verifiedSetupFailures');
    expect(createHash('sha256').update(physicalLoop!).digest('hex')).toBe('a15751477e173397cc6f164ca573f574b36362e42c84fc5b62c6ad1e367f552a');
  });
});
