import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { NATIVE_DB_VALIDATION } from '../../packages/shared/src/config/constants';
import { buildNativePgtapManifest, verifyNativePgtapRun } from '../pgtap/native.mjs';

// DBV-002/004/011: independent synthetic streams, derived from the frozen
// public contract. No implementation, existing tests or project SQL was read.
function queryResultVisibleFixture(stdout?: string, stderr = '') {
  const manifest = buildNativePgtapManifest({
    sourceSha: 'a'.repeat(NATIVE_DB_VALIDATION.sourceShaLength),
    schemaIdentity: {
      migrationsSha256: 'b'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
      generatedTypesSha256: 'c'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
    },
    files: [
      {
        path: 'supabase/tests/ordinary.sql',
        sha256: 'd'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
        literalPlans: [3],
      },
      {
        path: 'supabase/tests-holdout/independent.pg',
        sha256: 'e'.repeat(NATIVE_DB_VALIDATION.digestHexLength),
        literalPlans: [2],
      },
    ],
  });
  const nativeStdout = stdout ?? [
    '[01:02:03] supabase/tests-holdout/independent.pg ..',
    'TAP version 13',
    '1..2',
    'ok 1 - synthetic alpha',
    'ok 2 - synthetic beta',
    'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)',
    '[01:02:04]',
    '[01:02:04] supabase/tests/ordinary.sql ..',
    '1..3',
    'ok 1 - synthetic gamma',
    'ok 2 - synthetic delta',
    'ok 3 - synthetic epsilon',
    'ok 34 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)',
    '[01:02:05]',
    'All tests successful.',
    'Files=2, Tests=5, 0 wallclock secs ( 0.01 usr 0.01 sys + 0.01 cusr 0.01 csys = 0.04 CPU)',
    'Result: PASS',
    '',
  ].join('\n');
  const evidence = {
    formatVersion: NATIVE_DB_VALIDATION.formatVersion,
    runId: '91001-1',
    sourceSha: manifest.sourceSha,
    schemaIdentity: { ...manifest.schemaIdentity },
    manifestSha256: createHash('sha256').update(`${JSON.stringify(manifest)}\n`).digest('hex'),
    native: {
      completed: true,
      exitCode: 0 as number | null,
      signal: null as string | null,
      stdout: nativeStdout,
      stderr,
      elapsedMs: 1500,
    },
    outputs: {
      stdout: {
        path: 'C:/private-synthetic/native-stdout.tap',
        sha256: createHash('sha256').update(nativeStdout).digest('hex'),
        byteLength: Buffer.byteLength(nativeStdout),
      },
      stderr: {
        path: 'C:/private-synthetic/native-stderr.tap',
        sha256: createHash('sha256').update(stderr).digest('hex'),
        byteLength: Buffer.byteLength(stderr),
      },
    },
    afterFiles: manifest.files.map(({ path, sha256 }: { path: string; sha256: string }) => ({ path, sha256 })),
    timings: { setupMs: 200, linkMs: 100, nativeMs: 1500, jobMs: 2000 },
    timeout: {
      original: { originalPresent: false, originalValue: null as string | null },
      observed: { originalPresent: false, originalValue: null as string | null },
      verified: true,
    },
    reporting: { restored: true, verified: true },
    preflightFailureCodes: [] as string[],
  };
  return { manifest, evidence };
}

describe('DBV-002/004/011 ordinary native query-result reporting', () => {
  it('retains the complete old receipt baseline without query rows', () => {
    const { manifest, evidence } = queryResultVisibleFixture();
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt).toEqual({
      formatVersion: NATIVE_DB_VALIDATION.formatVersion,
      runId: evidence.runId,
      sourceSha: manifest.sourceSha,
      schemaIdentity: manifest.schemaIdentity,
      manifestSha256: evidence.manifestSha256,
      accepted: true,
      native: { completed: true, exitCode: 0, signal: null },
      files: [
        { path: 'supabase/tests-holdout/independent.pg', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 12 },
        { path: 'supabase/tests/ordinary.sql', plan: 3, executed: 3, failed: 0, verdict: 'PASS', durationMs: 34 },
      ],
      aggregate: { files: 2, tests: 5, failed: 0, verdict: 'PASS' },
      timings: evidence.timings,
      timeout: evidence.timeout,
      reporting: evidence.reporting,
      failureCodes: [],
    });
  });

  it.each(['before plan', 'between assertions', 'after assertions', 'all three positions'])(
    'accepts ordinary rows %s with the exact old counts and timers', position => {
      const baseline = queryResultVisibleFixture();
      const rows = [
        '{"synthetic":"query-result","value":7}',
        '["synthetic",3,false]',
        '17',
        'false',
        '11111111-2222-4333-8444-555555555555',
        '2026-10-08 01:02:03+00',
        'ordinary synthetic query result',
      ].join('\n');
      let stdout = baseline.evidence.native.stdout;
      if (position === 'before plan' || position === 'all three positions') stdout = stdout.replace('1..2', `${rows}\n1..2`);
      if (position === 'between assertions' || position === 'all three positions') stdout = stdout.replace('ok 2 - synthetic beta', `${rows}\nok 2 - synthetic beta`);
      if (position === 'after assertions' || position === 'all three positions') stdout = stdout.replace('ok 12 ms', `${rows}\nok 12 ms`);
      const { manifest, evidence } = queryResultVisibleFixture(stdout);
      const before = JSON.stringify({ manifest, evidence });
      const receipt = verifyNativePgtapRun(manifest, evidence);
      expect(receipt.accepted).toBe(true);
      expect(receipt).toEqual(verifyNativePgtapRun(baseline.manifest, baseline.evidence));
      expect(JSON.stringify({ manifest, evidence })).toBe(before);
      expect(JSON.stringify(receipt)).not.toContain('query-result');
    },
  );

  it.each([
    ['missing plan', '1..2\n', ''],
    ['duplicate plan', '1..2\n', '1..2\n1..2\n'],
    ['extra plan', 'ok 2 - synthetic beta\n', 'ok 2 - synthetic beta\n1..2\n'],
    ['wrong plan', '1..2\n', '1..3\n'],
    ['malformed plan control', '1..2\n', '1.2\n'],
    ['incomplete plan control', '1..2\n', '1..\n'],
    ['malformed version control', 'TAP version 13\n', 'TAP version nonsense\n'],
    ['duplicate version', 'TAP version 13\n', 'TAP version 13\nTAP version 13\n'],
    ['missing point', 'ok 2 - synthetic beta\n', ''],
    ['duplicate point', 'ok 2 - synthetic beta\n', 'ok 2 - synthetic beta\nok 2 - synthetic beta\n'],
    ['extra point', 'ok 2 - synthetic beta\n', 'ok 2 - synthetic beta\nok 3 - synthetic excess\n'],
    ['nonsequential point', 'ok 2 - synthetic beta\n', 'ok 9 - synthetic beta\n'],
    ['malformed point control', 'ok 2 - synthetic beta\n', 'ok malformed point\n'],
    ['incomplete not-ok control', 'ok 2 - synthetic beta\n', 'not ok\n'],
    ['failed point', 'ok 2 - synthetic beta\n', 'not ok 2 - synthetic beta\n'],
    ['missing timer', 'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n', ''],
    ['duplicate timer', 'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n', 'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\nok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n'],
    ['malformed timer', 'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n', 'ok twelve ms ( 0.00 CPU)\n'],
    ['negative timer', 'ok 12 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n', 'ok -12 ms ( 0.00 CPU)\n'],
    ['missing file', '[01:02:04] supabase/tests/ordinary.sql ..\n1..3\nok 1 - synthetic gamma\nok 2 - synthetic delta\nok 3 - synthetic epsilon\nok 34 ms ( 0.00 usr 0.00 sys + 0.00 cusr 0.00 csys = 0.00 CPU)\n[01:02:05]\n', ''],
    ['duplicate file', '[01:02:04] supabase/tests/ordinary.sql ..\n', '[01:02:04] supabase/tests-holdout/independent.pg ..\n'],
    ['extra file', 'All tests successful.\n', '[01:02:05] supabase/tests/unmanifested.sql ..\n1..1\nok 1 - synthetic outside\nok 1 ms ( 0.00 CPU)\n[01:02:06]\nAll tests successful.\n'],
    ['missing success framing', 'All tests successful.\n', ''],
    ['duplicate success framing', 'All tests successful.\n', 'All tests successful.\nAll tests successful.\n'],
    ['malformed success framing', 'All tests successful.\n', 'All tests successful maybe.\n'],
    ['wrong aggregate tests', 'Files=2, Tests=5', 'Files=2, Tests=6'],
    ['wrong aggregate files', 'Files=2, Tests=5', 'Files=3, Tests=5'],
    ['missing aggregate', 'Files=2, Tests=5, 0 wallclock secs ( 0.01 usr 0.01 sys + 0.01 cusr 0.01 csys = 0.04 CPU)\n', ''],
    ['duplicate aggregate', 'Result: PASS\n', 'Files=2, Tests=5, 0 wallclock secs ( 0.01 usr 0.01 sys + 0.01 cusr 0.01 csys = 0.04 CPU)\nResult: PASS\n'],
    ['malformed aggregate control', 'Files=2, Tests=5', 'Files=two, Tests=five'],
    ['missing final PASS', 'Result: PASS\n', ''],
    ['duplicate final PASS', 'Result: PASS\n', 'Result: PASS\nResult: PASS\n'],
    ['malformed final control', 'Result: PASS\n', 'Result: PASS extra\n'],
    ['native FAIL result', 'Result: PASS\n', 'Result: FAIL\n'],
    ['server error', 'ok 12 ms', 'ERROR: synthetic statement failure\nok 12 ms'],
    ['client error', 'ok 12 ms', 'psql: error: synthetic connection loss\nok 12 ms'],
    ['fatal error', 'ok 12 ms', 'FATAL: synthetic server refusal\nok 12 ms'],
    ['bailout', 'ok 12 ms', 'Bail out! synthetic refusal\nok 12 ms'],
  ])('ordinary rows cannot conceal %s', (_name, from, to) => {
    const baseline = queryResultVisibleFixture();
    const withoutRows = queryResultVisibleFixture(baseline.evidence.native.stdout.replace(from, to));
    expect(verifyNativePgtapRun(withoutRows.manifest, withoutRows.evidence).accepted).toBe(false);
    const stdout = baseline.evidence.native.stdout
      .replace('ok 1 - synthetic alpha\n', 'ok 1 - synthetic alpha\n{"synthetic":"query-result"}\n')
      .replace(from, to);
    const { manifest, evidence } = queryResultVisibleFixture(stdout);
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes.length).toBeGreaterThan(0);
    expect(stdout).not.toBe(baseline.evidence.native.stdout.replace('ok 1 - synthetic alpha\n', 'ok 1 - synthetic alpha\n{"synthetic":"query-result"}\n'));
  });

  it.each(['before first file', 'after final PASS'])(
    'refuses query rows outside any file: %s', position => {
      const baseline = queryResultVisibleFixture();
      const rows = '{"synthetic":"outside-file"}\n';
      const stdout = position === 'before first file' ? rows + baseline.evidence.native.stdout : baseline.evidence.native.stdout + rows;
      const { manifest, evidence } = queryResultVisibleFixture(stdout);
      const receipt = verifyNativePgtapRun(manifest, evidence);
      expect(receipt.accepted).toBe(false);
      expect(receipt.failureCodes).toContain('TAP_INCOMPLETE');
    },
  );

  it.each(['nonzero', 'incomplete', 'signal', 'missing status', 'stderr server error', 'stderr client error'])(
    'retains native failure with query rows: %s', failure => {
      const baseline = queryResultVisibleFixture();
      const stdout = baseline.evidence.native.stdout.replace('1..2\n', '{"synthetic":"query-result"}\n1..2\n');
      const stderr = failure === 'stderr server error' ? 'ERROR: synthetic failure\n' : failure === 'stderr client error' ? 'psql: error: synthetic connection loss\n' : '';
      const { manifest, evidence } = queryResultVisibleFixture(stdout, stderr);
      if (failure === 'nonzero') evidence.native.exitCode = 1;
      if (failure === 'incomplete') evidence.native.completed = false;
      if (failure === 'signal') { evidence.native.exitCode = null; evidence.native.signal = 'SIGTERM'; }
      if (failure === 'missing status') evidence.native.exitCode = null;
      const receipt = verifyNativePgtapRun(manifest, evidence);
      expect(receipt.accepted).toBe(false);
      expect(receipt.failureCodes.length).toBeGreaterThan(0);
      if (failure === 'nonzero') expect(receipt.failureCodes).toContain('NATIVE_FAILED');
      if (failure === 'incomplete' || failure === 'missing status') expect(receipt.failureCodes).toContain('NATIVE_INCOMPLETE');
    },
  );

  it.each(['input hash', 'retained stdout hash', 'retained stderr hash', 'timeout restored', 'timeout verification', 'reporting restored', 'reporting verification'])(
    'retains independent custody and cleanup refusal with query rows: %s', failure => {
      const baseline = queryResultVisibleFixture();
      const stdout = baseline.evidence.native.stdout.replace('1..2\n', '{"synthetic":"query-result"}\n1..2\n');
      const { manifest, evidence } = queryResultVisibleFixture(stdout);
      if (failure === 'input hash') evidence.afterFiles[0]!.sha256 = 'f'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
      if (failure === 'retained stdout hash') evidence.outputs.stdout.sha256 = 'f'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
      if (failure === 'retained stderr hash') evidence.outputs.stderr.sha256 = 'f'.repeat(NATIVE_DB_VALIDATION.digestHexLength);
      if (failure === 'timeout restored') evidence.timeout.observed = { originalPresent: true, originalValue: NATIVE_DB_VALIDATION.temporaryTimeout };
      if (failure === 'timeout verification') evidence.timeout.verified = false;
      if (failure === 'reporting restored') evidence.reporting.restored = false;
      if (failure === 'reporting verification') evidence.reporting.verified = false;
      const receipt = verifyNativePgtapRun(manifest, evidence);
      expect(receipt.accepted).toBe(false);
      if (failure === 'input hash') expect(receipt.failureCodes).toContain('INPUT_CHANGED');
      if (failure.startsWith('retained')) expect(receipt.failureCodes).toContain('HASH_CHANGED');
      if (failure.startsWith('timeout')) expect(receipt.failureCodes).toContain('TIMEOUT_NOT_RESTORED');
      if (failure.startsWith('reporting')) expect(receipt.failureCodes).toContain('REPORTING_NOT_RESTORED');
    },
  );
});
