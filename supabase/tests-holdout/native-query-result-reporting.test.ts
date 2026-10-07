import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import {
  buildNativePgtapManifest,
  verifyNativePgtapRun,
} from '../../scripts/pgtap/native.mjs';

// DBV-002/004/011. Authored from the frozen public contract, independently of
// implementation, previous suites, project SQL and the visible regression author.
function queryResultHeldFixture(
  queryRows: readonly string[] = [],
  changeStdout: (stdout: string) => string = stdout => stdout,
  stderr = '',
) {
  const manifest = buildNativePgtapManifest({
    sourceSha: 'ea8d5b6779bc0d18fcbe53a567198be93c27d024',
    schemaIdentity: {
      migrationsSha256: createHash('sha256').update('held synthetic schema').digest('hex'),
      generatedTypesSha256: createHash('sha256').update('held synthetic types').digest('hex'),
    },
    files: [
      {
        path: 'supabase/tests/early.pg',
        sha256: createHash('sha256').update('synthetic early input').digest('hex'),
        literalPlans: [3],
      },
      {
        path: 'supabase/tests-holdout/late.pg',
        sha256: createHash('sha256').update('synthetic late input').digest('hex'),
        literalPlans: [2],
      },
    ],
  });
  const stdout = changeStdout([
    '[07:20:01] supabase/tests/early.pg .........',
    ...queryRows,
    '1..3',
    'ok 1 - synthetic early first point',
    ...queryRows,
    'ok 2 - synthetic early second point',
    'ok 3 - synthetic early third point',
    ...queryRows,
    'ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)',
    '[07:20:01] supabase/tests-holdout/late.pg ..',
    ...queryRows,
    '1..2',
    'ok 1 - synthetic late first point',
    ...queryRows,
    'ok 2 - synthetic late second point',
    ...queryRows,
    'ok 6 ms ( 0.00 usr  0.00 sys +  0.00 cusr  0.00 csys =  0.00 CPU)',
    '[07:20:02]',
    'All tests successful.',
    'Files=2, Tests=5,  0 wallclock secs ( 0.05 usr +  0.03 sys =  0.08 CPU)',
    'Result: PASS',
    '',
  ].join('\n'));
  const evidence = {
    formatVersion: 1,
    runId: '580-1',
    sourceSha: manifest.sourceSha,
    schemaIdentity: manifest.schemaIdentity,
    manifestSha256: createHash('sha256').update(JSON.stringify(manifest) + '\n').digest('hex'),
    native: { completed: true, exitCode: 0, signal: null, stdout, stderr, elapsedMs: 64 },
    outputs: {
      stdout: {
        path: 'C:/fr-sealed-20261007/query-result-held-20261008/synthetic-stdout.txt',
        sha256: createHash('sha256').update(stdout).digest('hex'),
        byteLength: Buffer.byteLength(stdout),
      },
      stderr: {
        path: 'C:/fr-sealed-20261007/query-result-held-20261008/synthetic-stderr.txt',
        sha256: createHash('sha256').update(stderr).digest('hex'),
        byteLength: Buffer.byteLength(stderr),
      },
    },
    afterFiles: manifest.files.map(file => ({ path: file.path, sha256: file.sha256 })),
    timings: { setupMs: 39, linkMs: 12, nativeMs: 64, jobMs: 135 },
    timeout: {
      original: { originalPresent: true, originalValue: '2min' },
      observed: { originalPresent: true, originalValue: '2min' },
      verified: true,
    },
    reporting: { restored: true, verified: true },
    preflightFailureCodes: [],
  };
  return { manifest, evidence };
}

describe('DBV-002/004/011 held native result-row compatibility', () => {
  it('establishes an independently complete native control transcript', () => {
    const { manifest, evidence } = queryResultHeldFixture();
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(true);
    expect(receipt.failureCodes).toEqual([]);
    expect(receipt.files).toEqual([
      { path: 'supabase/tests-holdout/late.pg', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 6 },
      { path: 'supabase/tests/early.pg', plan: 3, executed: 3, failed: 0, verdict: 'PASS', durationMs: 29 },
    ]);
    expect(receipt.aggregate).toEqual({ files: 2, tests: 5, failed: 0, verdict: 'PASS' });
    expect(receipt.timings).toEqual(evidence.timings);
  });

  it.each([
    '{"synthetic":true,"message":"ok 999 is ordinary embedded text"}',
    '["synthetic",7,false]',
    '{8,16,32}',
    '8d5e1234-6789-4abc-8def-0123456789ab',
    '-17.0625',
    't',
    'false',
    '2026-10-08 07:20:01.123+00',
    'synthetic ordinary query result',
  ])('accepts result-row form %s at all three file positions without inventing evidence', row => {
    const { manifest, evidence } = queryResultHeldFixture([row]);
    const before = JSON.stringify({ manifest, evidence });
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(true);
    expect(receipt.failureCodes).toEqual([]);
    expect(receipt.files).toEqual([
      { path: 'supabase/tests-holdout/late.pg', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 6 },
      { path: 'supabase/tests/early.pg', plan: 3, executed: 3, failed: 0, verdict: 'PASS', durationMs: 29 },
    ]);
    expect(receipt.aggregate).toEqual({ files: 2, tests: 5, failed: 0, verdict: 'PASS' });
    expect(receipt.timings).toEqual({ setupMs: 39, linkMs: 12, nativeMs: 64, jobMs: 135 });
    expect(JSON.stringify({ manifest, evidence })).toBe(before);
  });

  it('accepts mixed and multiline result rows while preserving per-file native facts', () => {
    const { manifest, evidence } = queryResultHeldFixture([
      '{',
      '  "synthetic": [7, false, "Result: FAIL"],',
      '  "nested": {"plan": "1..500", "point": "not ok 88"}',
      '}',
      '{8,16,32}',
      '8d5e1234-6789-4abc-8def-0123456789ab',
      '-17.0625',
      'f',
      '2026-10-08 07:20:01.123+00',
      'synthetic complete query result',
    ]);
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(true);
    expect(receipt.failureCodes).toEqual([]);
    expect(receipt.files).toEqual([
      { path: 'supabase/tests-holdout/late.pg', plan: 2, executed: 2, failed: 0, verdict: 'PASS', durationMs: 6 },
      { path: 'supabase/tests/early.pg', plan: 3, executed: 3, failed: 0, verdict: 'PASS', durationMs: 29 },
    ]);
    expect(receipt.aggregate).toEqual({ files: 2, tests: 5, failed: 0, verdict: 'PASS' });
  });

  it.each([
    'ok frosted',
    'not ok synthetic malformed',
    '1..froze',
    '1.3',
    'TAP version frosted',
    'ok -2 ms ( 0.00 usr  0.00 sys = 0.00 CPU)',
    'not ok frosted ms ( synthetic timer text )',
    'All tests successful. trailing synthetic text',
    'Files=2, Tests=frosted, 0 wallclock secs',
    'Result: PASS trailing synthetic text',
  ])('does not demote a malformed control record into an ordinary row: %s', record => {
    const { manifest, evidence } = queryResultHeldFixture([
      '{"synthetic":"noise before control"}',
      record,
      'synthetic noise after control',
    ]);
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain('TAP_INCOMPLETE');
  });

  it.each([
    { name: 'missing file', change: (stdout: string) => stdout.replace(/\[07:20:01\] supabase\/tests-holdout\/late\.pg \.\.[\s\S]*?(?=\[07:20:02\])/, '') },
    { name: 'duplicate file', change: (stdout: string) => stdout.replace('[07:20:02]', stdout.match(/\[07:20:01\] supabase\/tests-holdout\/late\.pg \.\.[\s\S]*?(?=\[07:20:02\])/)?.[0] + '[07:20:02]') },
    { name: 'extra file', change: (stdout: string) => stdout.replace('[07:20:02]', '[07:20:01] supabase/tests/extra.pg ..\n1..1\nok 1 - synthetic extra point\nok 1 ms ( 0.00 usr 0.00 sys = 0.00 CPU)\n[07:20:02]') },
    { name: 'missing plan', change: (stdout: string) => stdout.replace('1..3\n', '') },
    { name: 'duplicate plan', change: (stdout: string) => stdout.replace('1..3\n', '1..3\n1..3\n') },
    { name: 'extra plan', change: (stdout: string) => stdout.replace('ok 3 - synthetic early third point\n', 'ok 3 - synthetic early third point\n1..1\n') },
    { name: 'wrong per-file plans with conserved total', change: (stdout: string) => stdout.replace('1..3\n', '1..1\n').replace('1..2\n', '1..4\n') },
    { name: 'missing point', change: (stdout: string) => stdout.replace('ok 2 - synthetic early second point\n', '') },
    { name: 'duplicate point', change: (stdout: string) => stdout.replace('ok 2 - synthetic early second point\n', 'ok 1 - synthetic early second point\n') },
    { name: 'extra point', change: (stdout: string) => stdout.replace('ok 3 - synthetic early third point\n', 'ok 3 - synthetic early third point\nok 4 - synthetic extra point\n') },
    { name: 'out-of-sequence point', change: (stdout: string) => stdout.replace('ok 1 - synthetic early first point\n', 'ok 2 - synthetic early first point\n').replace('ok 2 - synthetic early second point\n', 'ok 1 - synthetic early second point\n') },
    { name: 'missing timer', change: (stdout: string) => stdout.replace('ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\n', '') },
    { name: 'duplicate timer', change: (stdout: string) => stdout.replace('ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\n', 'ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\nok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\n') },
    { name: 'timer before complete points', change: (stdout: string) => stdout.replace('ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\n', '').replace('ok 2 - synthetic early second point\n', 'ok 29 ms ( 0.01 usr  0.01 sys +  0.00 cusr  0.00 csys =  0.02 CPU)\nok 2 - synthetic early second point\n') },
    { name: 'version after points', change: (stdout: string) => stdout.replace('ok 2 - synthetic early second point\n', 'TAP version 13\nok 2 - synthetic early second point\n') },
    { name: 'duplicate version', change: (stdout: string) => stdout.replace('1..3\n', 'TAP version 13\nTAP version 13\n1..3\n') },
    { name: 'wrong aggregate tests', change: (stdout: string) => stdout.replace('Tests=5,', 'Tests=4,') },
    { name: 'wrong aggregate files', change: (stdout: string) => stdout.replace('Files=2,', 'Files=3,') },
    { name: 'missing aggregate', change: (stdout: string) => stdout.replace('Files=2, Tests=5,  0 wallclock secs ( 0.05 usr +  0.03 sys =  0.08 CPU)\n', '') },
    { name: 'duplicate aggregate', change: (stdout: string) => stdout.replace('Files=2, Tests=5,', 'Files=2, Tests=5,  0 wallclock secs ( 0.05 usr +  0.03 sys =  0.08 CPU)\nFiles=2, Tests=5,') },
    { name: 'missing success marker', change: (stdout: string) => stdout.replace('All tests successful.\n', '') },
    { name: 'duplicate success marker', change: (stdout: string) => stdout.replace('All tests successful.\n', 'All tests successful.\nAll tests successful.\n') },
    { name: 'missing final result', change: (stdout: string) => stdout.replace('Result: PASS\n', '') },
    { name: 'duplicate final result', change: (stdout: string) => stdout + 'Result: PASS\n' },
    { name: 'aggregate before file facts complete', change: (stdout: string) => stdout.replace('Files=2, Tests=5,  0 wallclock secs ( 0.05 usr +  0.03 sys =  0.08 CPU)\n', '').replace('ok 2 - synthetic late second point\n', 'Files=2, Tests=5,  0 wallclock secs ( 0.05 usr +  0.03 sys =  0.08 CPU)\nok 2 - synthetic late second point\n') },
    { name: 'unknown output before any file', change: (stdout: string) => 'synthetic unowned row\n' + stdout },
    { name: 'unknown output between block and aggregate', change: (stdout: string) => stdout.replace('[07:20:02]\n', '[07:20:02]\nsynthetic unowned row\n') },
    { name: 'unknown output after final result', change: (stdout: string) => stdout + 'synthetic unowned row\n' },
  ])('query noise cannot conceal $name', ({ change }) => {
    const { manifest, evidence } = queryResultHeldFixture([
      '{"synthetic":"noise"}',
      '{8,16}',
      '-17.0625',
      't',
      '2026-10-08 07:20:01+00',
      'synthetic ordinary row',
    ], change);
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain('TAP_INCOMPLETE');
  });

  it.each([
    'ERROR: synthetic query rejected',
    'FATAL: synthetic connection rejected',
    'PANIC: synthetic server refusal',
    'psql: synthetic client connection lost',
    'Bail out! synthetic stop',
  ])('retains native refusal for %s after passing points with ordinary rows present', record => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row'], stdout => stdout.replace('ok 3 - synthetic early third point\n', 'ok 3 - synthetic early third point\n' + record + '\n'));
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
    if (record !== 'psql: synthetic client connection lost') {
      expect(receipt.failureCodes).toContain('TAP_FAILED');
    }
  });

  it('cannot hide a failed assertion behind ordinary result rows and success framing', () => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row'], stdout => stdout.replace('ok 2 - synthetic early second point', 'not ok 2 - synthetic early second point'));
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain('TAP_FAILED');
    expect(receipt.files.find(file => file.path === 'supabase/tests/early.pg')?.failed).toBe(1);
  });

  it.each([
    { completed: true, exitCode: 7, signal: null, code: 'NATIVE_FAILED' },
    { completed: false, exitCode: null, signal: null, code: 'NATIVE_INCOMPLETE' },
    { completed: false, exitCode: null, signal: 'SIGTERM', code: 'NATIVE_INCOMPLETE' },
  ])('requires native process completion and zero exit with query rows: $code', status => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row']);
    const receipt = verifyNativePgtapRun(manifest, {
      ...evidence,
      native: { ...evidence.native, completed: status.completed, exitCode: status.exitCode, signal: status.signal },
    });
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain(status.code);
  });

  it('requires error-free retained stderr despite passing native stdout and query rows', () => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row'], stdout => stdout, 'psql: ERROR: synthetic late client failure\n');
    const receipt = verifyNativePgtapRun(manifest, evidence);
    expect(receipt.accepted).toBe(false);
  });

  it('requires unchanged input hashes with ordinary result rows', () => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row']);
    const receipt = verifyNativePgtapRun(manifest, {
      ...evidence,
      afterFiles: evidence.afterFiles.map(file => ({ ...file, sha256: createHash('sha256').update('synthetic drift').digest('hex') })),
    });
    expect(receipt.accepted).toBe(false);
  });

  it('requires unchanged retained output hashes with ordinary result rows', () => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row']);
    const receipt = verifyNativePgtapRun(manifest, {
      ...evidence,
      outputs: { ...evidence.outputs, stdout: { ...evidence.outputs.stdout, sha256: createHash('sha256').update('synthetic output drift').digest('hex') } },
    });
    expect(receipt.accepted).toBe(false);
  });

  it('requires independently verified exact timeout restoration with ordinary result rows', () => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row']);
    const receipt = verifyNativePgtapRun(manifest, {
      ...evidence,
      timeout: { ...evidence.timeout, observed: { originalPresent: true, originalValue: '10min' } },
    });
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain('TIMEOUT_NOT_RESTORED');
  });

  it.each([
    { restored: false, verified: true },
    { restored: true, verified: false },
  ])('requires reporting cleanup receipt $restored/$verified with query rows', reporting => {
    const { manifest, evidence } = queryResultHeldFixture(['{"synthetic":true}', 'synthetic row']);
    const receipt = verifyNativePgtapRun(manifest, { ...evidence, reporting });
    expect(receipt.accepted).toBe(false);
    expect(receipt.failureCodes).toContain('REPORTING_NOT_RESTORED');
  });
});
