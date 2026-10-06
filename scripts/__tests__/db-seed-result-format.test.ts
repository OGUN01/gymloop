import { spawnSync } from 'node:child_process';
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { basename, dirname, join, resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const RESULT_REFERENCE = '/tmp/batch2_seed_result.json';
const SANDBOX_PREFIX = 'gymloop-db-seed-result-';
const VALID_COUNTER = '{"failures":0,"ran":34}';
const WORKFLOW = readFileSync(new URL('../../.github/workflows/db.yml', import.meta.url), 'utf8');

// Exercise the actual workflow checker; only its input file locator is relocated.
function workflowParser() {
  const candidates = [...WORKFLOW.matchAll(
    /^[ \t]*python[^\r\n]*<<'PY'[^\r\n]*\r?\n([\s\S]*?)^[ \t]*PY[ \t]*\r?$/gm,
  )].map((match) => match[1]).filter((body) => body.includes(RESULT_REFERENCE));
  if (candidates.length !== 1) throw new Error('Expected one seed result Python heredoc');
  const body = candidates[0];
  if (body.split(RESULT_REFERENCE).length !== 2) throw new Error('Expected one result file locator');
  const lines = body.replaceAll('\r\n', '\n').split('\n');
  const indentation = Math.min(...lines.filter((line) => line.trim()).map(
    (line) => /^[ \t]*/.exec(line)?.[0].length ?? 0,
  ));
  return lines.map((line) => line.slice(indentation)).join('\n')
    .replace(RESULT_REFERENCE, 'batch2_seed_result.json');
}

const PARSER = workflowParser();

function runParser(serializedResult: string, proof = 'select plan(34);\n') {
  const sandboxRoot = resolve(tmpdir());
  const sandbox = resolve(mkdtempSync(join(sandboxRoot, SANDBOX_PREFIX)));
  if (dirname(sandbox) !== sandboxRoot || !basename(sandbox).startsWith(SANDBOX_PREFIX)) {
    throw new Error('Refusing cleanup outside the parser sandbox');
  }
  try {
    writeFileSync(join(sandbox, 'proof.sql'), proof);
    writeFileSync(join(sandbox, 'batch2_seed_result.json'), serializedResult);
    const result = spawnSync('python', ['-', 'proof.sql'], {
      cwd: sandbox,
      input: PARSER,
      encoding: 'utf8',
      timeout: 5000,
      maxBuffer: 65536,
    });
    if (result.error) throw result.error;
    expect(result.signal).toBeNull();
    expect(result.status).not.toBeNull();
    return result;
  } finally {
    rmSync(sandbox, { recursive: true, force: true });
  }
}

function expectRejected(serializedResult: string, proof = 'select plan(34);\n') {
  const result = runParser(serializedResult, proof);
  expect(result.status, result.stderr).not.toBe(0);
  expect(result.stdout).not.toContain('passed; rolled back');
}

const TRANSPORTS = [
  { name: 'plain row array', rows: (serializedRows: string) => `[${serializedRows}]` },
  { name: 'legacy rows object', rows: (serializedRows: string) => `{"rows":[${serializedRows}]}` },
];

// Keep raw JSON so Python sees floats rather than JavaScript reserializing them as integers.
const REJECTED_ROWS = [
  { name: 'null row', row: 'null' },
  { name: 'true row', row: 'true' },
  { name: 'false row', row: 'false' },
  { name: 'numeric row', row: '0' },
  { name: 'string row', row: '"counter"' },
  { name: 'array row', row: '[]' },
  { name: 'both counters missing', row: '{}' },
  { name: 'failures missing', row: '{"ran":34}' },
  { name: 'ran missing', row: '{"failures":0}' },
  { name: 'string failures', row: '{"failures":"0","ran":34}' },
  { name: 'float failures', row: '{"failures":0.0,"ran":34}' },
  { name: 'true failures', row: '{"failures":true,"ran":34}' },
  { name: 'false failures', row: '{"failures":false,"ran":34}' },
  { name: 'null failures', row: '{"failures":null,"ran":34}' },
  { name: 'negative failures', row: '{"failures":-1,"ran":34}' },
  { name: 'nonzero failures', row: '{"failures":1,"ran":34}' },
  { name: 'string ran', row: '{"failures":0,"ran":"34"}' },
  { name: 'float ran', row: '{"failures":0,"ran":34.0}' },
  { name: 'true ran', row: '{"failures":0,"ran":true}' },
  { name: 'false ran', row: '{"failures":0,"ran":false}' },
  { name: 'null ran', row: '{"failures":0,"ran":null}' },
  { name: 'negative ran', row: '{"failures":0,"ran":-1}' },
  { name: 'zero ran', row: '{"failures":0,"ran":0}' },
  { name: 'incomplete ran', row: '{"failures":0,"ran":33}' },
  { name: 'excess ran', row: '{"failures":0,"ran":35}' },
  { name: 'error-tagged counter row', row: '{"_tag":"Error","failures":0,"ran":34}' },
  { name: 'non-Error tag inside counter row', row: '{"_tag":"Success","failures":0,"ran":34}' },
  { name: 'extra counter field', row: '{"failures":0,"ran":34,"extra":null}' },
  { name: 'string error inside counter row', row: '{"error":"query failed","failures":0,"ran":34}' },
  { name: 'null error inside counter row', row: '{"error":null,"failures":0,"ran":34}' },
  { name: 'empty error inside counter row', row: '{"error":"","failures":0,"ran":34}' },
  { name: 'null errors inside counter row', row: '{"errors":null,"failures":0,"ran":34}' },
  { name: 'empty errors inside counter row', row: '{"errors":[],"failures":0,"ran":34}' },
];

describe.each(TRANSPORTS)('seed proof result: $name', ({ rows }) => {
  it('accepts one exact integer zero-failure counter matching the literal plan', () => {
    const result = runParser(rows(VALID_COUNTER));
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout).toContain('34/34 passed; rolled back');
  });

  it('rejects an empty result', () => {
    expectRejected(rows(''));
  });

  it('rejects multiple complete counter rows', () => {
    expectRejected(rows(`${VALID_COUNTER},${VALID_COUNTER}`));
  });

  it('rejects a proof without a literal plan', () => {
    expectRejected(rows(VALID_COUNTER), 'select 34;\n');
  });

  it('rejects a zero plan even when counters match it', () => {
    expectRejected(rows('{"failures":0,"ran":0}'), 'select plan(0);\n');
  });

  it.each(REJECTED_ROWS)('rejects $name without partial success', ({ row }) => {
    expectRejected(rows(row));
  });
});

describe('seed proof result envelope', () => {
  it('accepts legacy agent metadata around one valid counter row', () => {
    const result = runParser(`{"boundary":"rollback proof","rows":[${VALID_COUNTER}],"warning":"","advisory":"synthetic","_tag":"Success"}`);
    expect(result.status, result.stderr).toBe(0);
    expect(result.stdout).toContain('34/34 passed; rolled back');
  });

  it.each([
    { name: 'explicit Error tag', result: '{"_tag":"Error"}' },
    { name: 'Error tag carrying valid counters', result: `{"_tag":"Error","rows":[${VALID_COUNTER}]}` },
    { name: 'string error carrying valid counters', result: `{"error":"query failed","rows":[${VALID_COUNTER}]}` },
    { name: 'object error carrying valid counters', result: `{"error":{"message":"query failed"},"rows":[${VALID_COUNTER}]}` },
    { name: 'errors array carrying valid counters', result: `{"errors":[{"message":"query failed"}],"rows":[${VALID_COUNTER}]}` },
    { name: 'null error carrying valid counters', result: `{"error":null,"rows":[${VALID_COUNTER}]}` },
    { name: 'empty error carrying valid counters', result: `{"error":"","rows":[${VALID_COUNTER}]}` },
    { name: 'false error carrying valid counters', result: `{"error":false,"rows":[${VALID_COUNTER}]}` },
    { name: 'null errors carrying valid counters', result: `{"errors":null,"rows":[${VALID_COUNTER}]}` },
    { name: 'empty errors carrying valid counters', result: `{"errors":[],"rows":[${VALID_COUNTER}]}` },
    { name: 'null', result: 'null' },
    { name: 'true', result: 'true' },
    { name: 'false', result: 'false' },
    { name: 'number', result: '34' },
    { name: 'string', result: '"success"' },
    { name: 'missing rows', result: '{}' },
    { name: 'unrecognized data wrapper', result: `{"data":[${VALID_COUNTER}]}` },
    { name: 'null rows', result: '{"rows":null}' },
    { name: 'object rows', result: '{"rows":{}}' },
    { name: 'scalar rows', result: '{"rows":34}' },
    { name: 'string rows', result: '{"rows":"counter"}' },
    { name: 'truncated JSON', result: '{"rows":[' },
    { name: 'trailing non-JSON output', result: `{"rows":[${VALID_COUNTER}]}\nquery failed` },
    { name: 'multiple top-level results', result: `{"rows":[${VALID_COUNTER}]}\n{"_tag":"Error"}` },
  ])('rejects $name without partial success', ({ result }) => {
    expectRejected(result);
  });
});
