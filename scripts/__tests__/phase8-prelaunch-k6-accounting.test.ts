import { readFileSync } from 'node:fs';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

import { parsePrelaunchK6Raw } from '../phase8-prelaunch-load-cloud.mjs';

const K6_SOURCE = readFileSync(new URL('../../tests/load/phase8-morning-checkin.js', import.meta.url), 'utf8');
const sourceFile = ts.createSourceFile('phase8-morning-checkin.js', K6_SOURCE, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
const declarations = new Map<string, ts.Expression>();
const collectDeclarations = (node: ts.Node): void => {
  if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.initializer) {
    declarations.set(node.name.text, node.initializer);
  }
  ts.forEachChild(node, collectDeclarations);
};
collectDeclarations(sourceFile);

const resolveExpression = (expression: ts.Expression | undefined): ts.Expression | undefined => {
  if (expression && ts.isIdentifier(expression)) return resolveExpression(declarations.get(expression.text));
  return expression;
};
const property = (expression: ts.Expression | undefined, name: string): ts.Expression | undefined => {
  const resolved = resolveExpression(expression);
  if (!resolved || !ts.isObjectLiteralExpression(resolved)) return undefined;
  const entry = resolved.properties.find((candidate) =>
    ts.isPropertyAssignment(candidate) && candidate.name.getText(sourceFile).replace(/^['"]|['"]$/g, '') === name);
  return entry && ts.isPropertyAssignment(entry) ? entry.initializer : undefined;
};
const numericValue = (expression: ts.Expression | undefined): number | undefined => {
  const resolved = resolveExpression(expression);
  if (!resolved) return undefined;
  if (ts.isNumericLiteral(resolved)) return Number(resolved.text);
  if (ts.isBinaryExpression(resolved)) {
    const left = numericValue(resolved.left);
    const right = numericValue(resolved.right);
    if (left === undefined || right === undefined) return undefined;
    if (resolved.operatorToken.kind === ts.SyntaxKind.SlashToken) return left / right;
    if (resolved.operatorToken.kind === ts.SyntaxKind.AsteriskToken) return left * right;
  }
  return undefined;
};
const textValue = (expression: ts.Expression | undefined): string | undefined => {
  const resolved = resolveExpression(expression);
  if (resolved && (ts.isStringLiteral(resolved) || ts.isNoSubstitutionTemplateLiteral(resolved))) return resolved.text;
  return undefined;
};
const point = (metric: string, value: number, tags: Record<string, string>) =>
  JSON.stringify({ metric, type: 'Point', data: { value, tags } });
const CHECK_IN_TAGS = { scenario: 'morning_check_in_spike', name: 'morning_check_in' };
const CHECK_IN_REQUEST = point('http_reqs', 1, { ...CHECK_IN_TAGS, status: '200' });
const CHECK_IN_DURATION = point('http_req_duration', 80, CHECK_IN_TAGS);
const READ_PROBE = point('checks', 1, { group: '::setup', check: 'cross-tenant member read is denied' });
const MUTATION_PROBE = point('http_reqs', 1, { group: '::setup', name: 'cross_tenant_mutation', status: '403' });
const raw = (...points: string[]) => points.join('\n');

describe('HARD-004 prelaunch k6 scenario and accounting', () => {
  it('reserves all 100 VUs for 500 check-ins each in the sole scenario', () => {
    const scenarios = resolveExpression(property(declarations.get('options'), 'scenarios'));
    expect(scenarios && ts.isObjectLiteralExpression(scenarios)).toBe(true);
    if (!scenarios || !ts.isObjectLiteralExpression(scenarios)) return;
    expect(scenarios.properties).toHaveLength(1);
    expect(scenarios.properties[0].name?.getText(sourceFile)).toBe('morning_check_in_spike');
    const spike = property(scenarios, 'morning_check_in_spike');
    expect(textValue(property(spike, 'executor'))).toBe('per-vu-iterations');
    expect(numericValue(property(spike, 'vus'))).toBe(100);
    expect(numericValue(property(spike, 'iterations'))).toBe(500);
  });

  it('runs both real tenant probes from setup before the check-in scenario', () => {
    const functionSetup = sourceFile.statements.find((statement) =>
      ts.isFunctionDeclaration(statement) && statement.name?.text === 'setup');
    const declaredSetup = resolveExpression(declarations.get('setup'));
    const body = functionSetup && ts.isFunctionDeclaration(functionSetup)
      ? functionSetup.body?.getText(sourceFile) ?? ''
      : declaredSetup && (ts.isArrowFunction(declaredSetup) || ts.isFunctionExpression(declaredSetup))
        ? declaredSetup.body.getText(sourceFile)
        : '';
    expect(body.length).toBeGreaterThan(0);
    expect(/cross.{0,30}read/i.test(body)).toBe(true);
    expect(/cross.{0,30}mutat/i.test(body)).toBe(true);
  });

  it('filters the k6 latency threshold to named check-in requests', () => {
    const thresholds = resolveExpression(property(declarations.get('options'), 'thresholds'));
    expect(thresholds && ts.isObjectLiteralExpression(thresholds)).toBe(true);
    if (!thresholds || !ts.isObjectLiteralExpression(thresholds)) return;
    const durationKeys = thresholds.properties
      .filter(ts.isPropertyAssignment)
      .map((entry) => textValue(entry.name as ts.Expression) ?? entry.name.getText(sourceFile))
      .filter((name) => name.includes('http_req_duration'));
    expect(durationKeys.length).toBeGreaterThan(0);
    expect(durationKeys.every((name) => /\bname\s*:\s*morning_check_in\b/.test(name))).toBe(true);
  });

  it('accepts setup probes and excludes refresh plus probe HTTP and latency from check-in measurements', () => {
    const measured = parsePrelaunchK6Raw(raw(
      CHECK_IN_REQUEST,
      CHECK_IN_DURATION,
      point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'auth_session_refresh', status: '200' }),
      point('http_req_duration', 9_000, { scenario: 'morning_check_in_spike', name: 'auth_session_refresh' }),
      READ_PROBE,
      MUTATION_PROBE,
      point('http_req_duration', 8_000, { group: '::setup', name: 'cross_tenant_mutation' }),
    ));
    expect(measured).toEqual({
      p95Ms: 80,
      completedCheckIns: 1,
      crossTenantReadDenied: true,
      crossTenantMutationStatus: 403,
    });
  });

  it('fails on missing, duplicate or successful setup mutation evidence', () => {
    for (const evidence of [
      [READ_PROBE],
      [READ_PROBE, MUTATION_PROBE, MUTATION_PROBE],
      [READ_PROBE, point('http_reqs', 1, { group: '::setup', name: 'cross_tenant_mutation', status: '200' })],
      [READ_PROBE, point('http_reqs', 1, { group: '::setup', name: 'cross_tenant_mutation', status: '299' })],
      [READ_PROBE, point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'cross_tenant_mutation', status: '403' })],
    ]) {
      expect(() => parsePrelaunchK6Raw(raw(CHECK_IN_REQUEST, CHECK_IN_DURATION, ...evidence))).toThrow();
    }
  });

  it('fails on missing or duplicate setup read evidence', () => {
    for (const evidence of [
      [MUTATION_PROBE],
      [READ_PROBE, READ_PROBE, MUTATION_PROBE],
      [point('checks', 1, { scenario: 'morning_check_in_spike', check: 'cross-tenant member read is denied' }), MUTATION_PROBE],
    ]) {
      expect(() => parsePrelaunchK6Raw(raw(CHECK_IN_REQUEST, CHECK_IN_DURATION, ...evidence))).toThrow();
    }
  });
});
