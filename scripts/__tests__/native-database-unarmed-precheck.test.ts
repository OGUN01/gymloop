import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';

type Data = Record<string, unknown>;
type Path = (string | number)[];
type Verification = { verified: boolean };
type VerifierModule = { verifyUnarmedNativePrecheck: (input: unknown) => Verification };
const modulePath = new URL('../pgtap/unarmed-precheck.mjs', import.meta.url).href;
let pendingModule: Promise<VerifierModule> | undefined;
const loadModule = () => pendingModule ??= import(/* @vite-ignore */ modulePath) as Promise<VerifierModule>;
const hex = (character: string) => character.repeat(NATIVE_DB_VALIDATION.digestHexLength);
const sourceSha = 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength);
const names = ['success', 'assertion-failure', 'missing-plan', 'extra-plan', 'broken-plan', 'malformed', 'truncated', 'client-error', 'connection-loss'];
const cleanup = ['Post Run supabase/setup-cli@v3', 'Post Run pnpm/action-setup@v6', 'Post Run actions/checkout@v7', 'Complete job'];
const validation = 'Validate the full native suite with outside-worker recovery custody';
const discovery = 'Find the exact armed receipt, including an earlier attempt of this run';
const linking = 'Run supabase link --project-ref "$PROJECT_REF" --yes';
const restoration = 'Restore and freshly verify only the captured role-global timeout';
const step = (name: string, conclusion = 'success') => ({ name, status: 'completed', conclusion });

const fixture = (): Data => {
  const job = (id: number, runnerId: number, name: string, steps: ReturnType<typeof step>[]) => ({ id, runId: '88', attempt: '2', sourceSha, name, status: 'completed', conclusion: 'failure', runnerId, runnerName: `GitHub Actions ${runnerId}`, runnerGroupName: 'GitHub Actions', labels: ['ubuntu-latest'], steps });
  return {
    review: { formatVersion: NATIVE_DB_VALIDATION.formatVersion, runId: '88', runAttempt: '2', sourceSha, nativeJobId: 101, guardianJobId: 102, runnerId: 201, adapterSha256: hex('b'), workflowSha256: hex('c'), smokeArtifactId: 301, smokeArchiveSha256: hex('d'), privateProofSha256: hex('e'), reviewedAt: '2026-10-07T00:00:00.000Z' },
    run: { id: '88', attempt: '2', sourceSha, event: 'push', branch: 'main', status: 'completed', conclusion: 'failure' },
    nativeJob: job(101, 201, 'pgtap', [...cleanup.map(name => step(name)), step('Retain client-only smoke metadata'), step(validation, 'failure')]),
    guardianJob: job(102, 202, 'timeout-guardian', [...cleanup.map(name => step(name)), step(discovery, 'failure'), step(linking, 'skipped'), step(restoration, 'skipped')]),
    smokeArchive: { id: 301, name: 'native-db-client-smoke-88-2', runId: '88', sourceSha, apiSha256: hex('d'), archiveSha256: hex('d'), expired: false },
    smoke: {
      formatVersion: NATIVE_DB_VALIDATION.formatVersion, sourceSha, cliVersion: NATIVE_DB_VALIDATION.cliVersion, clientDigest: NATIVE_DB_VALIDATION.clientDigest, runnerOs: 'Linux', network: 'host', nativeClientImage: NATIVE_DB_VALIDATION.nativeClientImage, nativeClientImageId: `sha256:${hex('f')}`, imageSelectionSource: 'https://github.com/supabase/cli/blob/v2.110.0/apps/cli/src/legacy/shared/legacy-docker-registry.ts', firstDirectoryCwd: true, readOnlyBinds: true, reportingLines: [...NATIVE_DB_VALIDATION.reportingLines], stubSha256: hex('f'), capturedAt: '2026-10-06T23:59:59.000Z',
      cases: names.map(name => ({
        name, exitCode: 1, completed: true, signal: null, nativeMs: 0, stdoutSha256: hex('a'), stderrSha256: hex('b'), timerCount: 0, rawTapPresent: false, inputsUnchanged: true, checkPassed: name !== 'success',
        fileMetadata: [
          { path: 'supabase/tests/.proverc', sha256: hex('c'), byteLength: 1 },
          { path: 'supabase/tests-holdout/independent.pg', sha256: hex('d'), byteLength: 1 },
          { path: `supabase/tests/${name === 'client-error' || name === 'connection-loss' ? name : 'visible'}.sql`, sha256: hex('e'), byteLength: 1 },
        ],
      })), accepted: false,
    },
    sourceHashes: { adapterSha256: hex('b'), workflowSha256: hex('c') },
    recoveryArtifactPresent: false, artifactListingComplete: true,
  };
};
const at = (input: unknown, path: Path): unknown => path.reduce<unknown>((value, key) => (value as Data)[key], input);
const set = (input: Data, path: Path, value: unknown) => { (at(input, path.slice(0, -1)) as Data)[String(path.at(-1))] = value; };
const verify = async (input: unknown, verified: boolean) => {
  const result = (await loadModule()).verifyUnarmedNativePrecheck(input);
  expect(result).toStrictEqual({ verified });
  expect(Reflect.ownKeys(result)).toEqual(['verified']);
};
const nullRecords = (value: unknown): unknown => {
  if (Array.isArray(value)) return value.map(nullRecords);
  if (value !== null && typeof value === 'object') return Object.assign(Object.create(null), Object.fromEntries(Object.entries(value).map(([key, item]) => [key, nullRecords(item)])));
  return value;
};
const freeze = (value: unknown): void => {
  if (value === null || typeof value !== 'object') return;
  Object.values(value).forEach(freeze);
  Object.freeze(value);
};
const recordPaths: Path[] = [[], ['review'], ['run'], ['nativeJob'], ['guardianJob'], ['nativeJob', 'steps', 0], ['guardianJob', 'steps', 0], ['smokeArchive'], ['smoke'], ['sourceHashes'], ['smoke', 'cases', 0], ['smoke', 'cases', 0, 'fileMetadata', 0]];
const arrayPaths: Path[] = [['nativeJob', 'labels'], ['guardianJob', 'labels'], ['nativeJob', 'steps'], ['guardianJob', 'steps'], ['smoke', 'reportingLines'], ['smoke', 'cases'], ['smoke', 'cases', 0, 'fileMetadata']];

describe('DBV-005/007 verified hosted unarmed precheck refusal', () => {
  it('exports only the frozen synchronous pure verifier', async () => {
    expect(Object.keys(await loadModule())).toEqual(['verifyUnarmedNativePrecheck']);
  });
  it.each(['push', 'workflow_dispatch'])('accepts the exact reviewed failed hosted %s attempt', async event => {
    const input = fixture();
    set(input, ['run', 'event'], event);
    await verify(input, true);
  });
  it('accepts null-prototype data records while preserving ordinary arrays', async () => {
    await verify(nullRecords(fixture()), true);
  });
  it('accepts reordered file metadata and repeated optional skipped step names', async () => {
    const input = fixture();
    for (const item of at(input, ['smoke', 'cases']) as Data[]) (item.fileMetadata as unknown[]).reverse();
    (at(input, ['guardianJob', 'steps']) as unknown[]).push(step('Download artifacts', 'skipped'), step('Download artifacts', 'skipped'));
    await verify(input, true);
  });
  it('accepts frozen evidence without modifying any nested input', async () => {
    const input = fixture();
    const before = JSON.stringify(input);
    freeze(input);
    await verify(input, true);
    expect(JSON.stringify(input)).toBe(before);
  });
  it('leaves ordinary accepted and refused evidence unchanged', async () => {
    for (const valid of [true, false]) {
      const input = fixture();
      if (!valid) set(input, ['run', 'branch'], 'topic');
      const before = JSON.stringify(input);
      await verify(input, valid);
      expect(JSON.stringify(input)).toBe(before);
    }
  });

  it.each([
    ['wrong review version', ['review', 'formatVersion'], 0],
    ['noncanonical review run', ['review', 'runId'], '088'],
    ['noncanonical review attempt', ['review', 'runAttempt'], '02'],
    ['unbound native job id', ['review', 'nativeJobId'], 103],
    ['unbound guardian job id', ['review', 'guardianJobId'], 103],
    ['unbound native runner id', ['review', 'runnerId'], 203],
    ['unbound artifact id', ['review', 'smokeArtifactId'], 302],
    ['invalid proof hash', ['review', 'privateProofSha256'], hex('e').toUpperCase()],
    ['noncanonical review timestamp', ['review', 'reviewedAt'], '2026-10-07T00:00:00Z'],
    ['invalid calendar review timestamp', ['review', 'reviewedAt'], '2026-02-30T00:00:00.000Z'],
    ['different observed run', ['run', 'id'], '89'],
    ['latest rather than selected attempt', ['run', 'attempt'], '3'],
    ['source identity drift', ['run', 'sourceSha'], 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['untrusted event', ['run', 'event'], 'pull_request'],
    ['non-main branch', ['run', 'branch'], 'refs/heads/main'],
    ['unfinished run', ['run', 'status'], 'in_progress'],
    ['cancelled run', ['run', 'conclusion'], 'cancelled'],
    ['timed-out run', ['run', 'conclusion'], 'timed_out'],
    ['successful run', ['run', 'conclusion'], 'success'],
    ['historical adapter hash mismatch', ['sourceHashes', 'adapterSha256'], hex('f')],
    ['historical workflow hash mismatch', ['sourceHashes', 'workflowSha256'], hex('f')],
    ['different smoke run', ['smokeArchive', 'runId'], '89'],
    ['wrong exact smoke artifact name', ['smokeArchive', 'name'], 'native-db-client-smoke-88-1'],
    ['archive source mismatch', ['smokeArchive', 'sourceSha'], 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['API/archive hash mismatch', ['smokeArchive', 'apiSha256'], hex('f')],
    ['downloaded/review hash mismatch', ['smokeArchive', 'archiveSha256'], hex('f')],
    ['expired smoke artifact', ['smokeArchive', 'expired'], true],
    ['truthy artifact expiry', ['smokeArchive', 'expired'], 0],
    ['conflicting armed recovery', ['recoveryArtifactPresent'], true],
    ['coerced recovery absence', ['recoveryArtifactPresent'], 0],
    ['incomplete artifact listing', ['artifactListingComplete'], false],
    ['coerced artifact listing completion', ['artifactListingComplete'], 1],
    ['nonpositive native id', ['nativeJob', 'id'], 0],
    ['different native attempt', ['nativeJob', 'attempt'], '1'],
    ['different guardian source', ['guardianJob', 'sourceSha'], 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['incorrect native job name', ['nativeJob', 'name'], 'test'],
    ['incorrect guardian job name', ['guardianJob', 'name'], 'guardian'],
    ['unfinished native job', ['nativeJob', 'status'], 'queued'],
    ['skipped guardian', ['guardianJob', 'conclusion'], 'skipped'],
    ['unsafe native runner id', ['nativeJob', 'runnerId'], Number.MAX_SAFE_INTEGER + 1],
    ['self-hosted group', ['nativeJob', 'runnerGroupName'], 'Default'],
    ['noncanonical provider runner name', ['guardianJob', 'runnerName'], 'GitHub Actions 202 '],
    ['extra native runner label', ['nativeJob', 'labels'], ['ubuntu-latest', 'self-hosted']],
    ['incorrect guardian runner label', ['guardianJob', 'labels'], ['self-hosted']],
    ['wrong smoke source', ['smoke', 'sourceSha'], 'b'.repeat(NATIVE_DB_VALIDATION.sourceShaLength)],
    ['wrong CLI pin', ['smoke', 'cliVersion'], '2.110.1'],
    ['wrong client digest', ['smoke', 'clientDigest'], `sha256:${hex('f')}`],
    ['wrong official native image', ['smoke', 'nativeClientImage'], NATIVE_DB_VALIDATION.clientImage],
    ['malformed native image id', ['smoke', 'nativeClientImageId'], hex('f')],
    ['untrusted image selection source', ['smoke', 'imageSelectionSource'], 'https://example.com/selection'],
    ['self-hosted OS', ['smoke', 'runnerOs'], 'Windows'],
    ['wrong network', ['smoke', 'network'], 'none'],
    ['wrong first-directory cwd', ['smoke', 'firstDirectoryCwd'], false],
    ['writable mounts', ['smoke', 'readOnlyBinds'], false],
    ['unapproved reporting flags', ['smoke', 'reportingLines'], [...NATIVE_DB_VALIDATION.reportingLines, '--ignore-exit']],
    ['invalid smoke timestamp', ['smoke', 'capturedAt'], 'not-a-time'],
    ['accepted smoke', ['smoke', 'accepted'], true],
  ] satisfies [string, Path, unknown][])('refuses %s', async (_label, path, value) => {
    const input = fixture();
    set(input, path, value);
    await verify(input, false);
  });

  it.each(['nativeJob', 'guardianJob'])('requires every actual mandatory cleanup step for %s', async job => {
    for (const name of cleanup) {
      for (const mode of ['absent', 'skipped', 'duplicate']) {
        const input = fixture();
        const original = at(input, [job, 'steps']) as Data[];
        set(input, [job, 'steps'], mode === 'absent' ? original.filter(item => item.name !== name) : mode === 'duplicate' ? [...original, step(name)] : original.map(item => item.name === name ? step(name, 'skipped') : item));
        await verify(input, false);
      }
    }
  });
  it.each([
    ['nativeJob', validation, 'success'], ['nativeJob', 'Retain client-only smoke metadata', 'skipped'],
    ['guardianJob', discovery, 'success'], ['guardianJob', linking, 'success'], ['guardianJob', restoration, 'success'],
  ])('requires exactly one expected %s step and verdict for %s', async (job, name, conclusion) => {
    for (const mode of ['wrong-verdict', 'absent', 'duplicate']) {
      const input = fixture();
      const original = at(input, [job, 'steps']) as Data[];
      const expected = original.find(item => item.name === name);
      set(input, [job, 'steps'], mode === 'absent' ? original.filter(item => item.name !== name) : mode === 'duplicate' ? [...original, expected] : original.map(item => item.name === name ? step(name, conclusion) : item));
      await verify(input, false);
    }
  });
  it('refuses extra failure/cancellation or unfinished optional steps', async () => {
    for (const job of ['nativeJob', 'guardianJob']) for (const damaged of [step('optional', 'failure'), step('optional', 'cancelled'), { name: 'optional', status: 'in_progress', conclusion: null }]) {
      const input = fixture();
      (at(input, [job, 'steps']) as unknown[]).push(damaged);
      await verify(input, false);
    }
  });

  it.each([
    ['exitCode', 2], ['completed', false], ['signal', 'SIGTERM'], ['nativeMs', -1], ['nativeMs', Number.NaN], ['timerCount', 0.5],
    ['stdoutSha256', hex('a').toUpperCase()], ['stderrSha256', 'short'], ['inputsUnchanged', false], ['rawTapPresent', 1], ['checkPassed', 'false'],
  ] satisfies [string, unknown][])('refuses malformed case %s', async (key, value) => {
    const input = fixture();
    set(input, ['smoke', 'cases', 0, key], value);
    await verify(input, false);
  });
  it('requires nine exact case names/order and the independently failed positive case', async () => {
    for (const mode of ['missing', 'reordered', 'duplicate', 'positive-passed']) {
      const input = fixture();
      const cases = at(input, ['smoke', 'cases']) as Data[];
      if (mode === 'missing') cases.pop();
      else if (mode === 'reordered') cases.reverse();
      else if (mode === 'duplicate') cases[1] = structuredClone(cases[0]) as Data;
      else { set(input, ['smoke', 'cases', 0, 'checkPassed'], true); set(input, ['smoke', 'cases', 1, 'checkPassed'], false); }
      await verify(input, false);
    }
  });
  it('requires exactly the correct three unique synthetic file records in every case', async () => {
    for (const index of names.keys()) for (const mode of ['missing', 'duplicate', 'wrong-path', 'zero-bytes', 'invalid-hash', 'unknown-property']) {
      const input = fixture();
      const files = at(input, ['smoke', 'cases', index, 'fileMetadata']) as Data[];
      if (mode === 'missing') files.pop();
      else if (mode === 'duplicate') files[1] = structuredClone(files[0]) as Data;
      else set(input, ['smoke', 'cases', index, 'fileMetadata', 0, mode === 'wrong-path' ? 'path' : mode === 'zero-bytes' ? 'byteLength' : mode === 'invalid-hash' ? 'sha256' : 'extra'], mode === 'wrong-path' ? '../escape.sql' : mode === 'zero-bytes' ? 0 : mode === 'invalid-hash' ? 'invalid' : true);
      await verify(input, false);
    }
  });

  it.each(['missing-key', 'unknown-key', 'symbol', 'wrong-prototype'])('refuses %s at every record projection', async mode => {
    for (const path of recordPaths) {
      const input = fixture();
      const record = at(input, path) as Data;
      if (mode === 'missing-key') delete record[Object.keys(record)[0] ?? ''];
      else if (mode === 'unknown-key') record.extra = true;
      else if (mode === 'symbol') Object.defineProperty(record, Symbol('extra'), { value: true, enumerable: true });
      else Object.setPrototypeOf(record, { inherited: true });
      await verify(input, false);
    }
  });
  it('refuses accessors at every record without invoking them', async () => {
    for (const path of recordPaths) {
      const input = fixture();
      const record = at(input, path) as Data;
      let calls = 0;
      Object.defineProperty(record, Object.keys(record)[0] ?? '', { enumerable: true, get: () => { calls += 1; throw new Error('Getter must remain inert.'); } });
      await verify(input, false);
      expect(calls).toBe(0);
    }
  });
  it.each(['sparse', 'extra-index', 'symbol', 'accessor', 'wrong-prototype'])('refuses %s in every array projection', async mode => {
    for (const path of arrayPaths) {
      const input = fixture();
      const array = at(input, path) as unknown[];
      let calls = 0;
      if (mode === 'sparse') delete array[0];
      else if (mode === 'extra-index') Object.defineProperty(array, '01', { value: true, enumerable: true });
      else if (mode === 'symbol') Object.defineProperty(array, Symbol('extra'), { value: true });
      else if (mode === 'accessor') Object.defineProperty(array, '0', { enumerable: true, get: () => { calls += 1; throw new Error('Array getter must remain inert.'); } });
      else Object.setPrototypeOf(array, Object.create(Array.prototype));
      await verify(input, false);
      expect(calls).toBe(0);
    }
  });
  it.each(['ownKeys', 'getPrototypeOf', 'getOwnPropertyDescriptor'])('contains %s reflection failures without throwing', async trap => {
    for (const path of [['review'], ['smoke', 'cases'], ['smoke', 'cases', 0, 'fileMetadata', 0]] satisfies Path[]) {
      const input = fixture();
      const target = at(input, path) as object;
      const proxy = new Proxy(target, { [trap]: () => { throw new Error('Synthetic reflection failure.'); } });
      set(input, path, proxy);
      await verify(input, false);
    }
  });
  it('refuses primitive, array and empty top-level inputs', async () => {
    for (const input of [undefined, null, true, 1, 'evidence', [], {}]) await verify(input, false);
  });
});
