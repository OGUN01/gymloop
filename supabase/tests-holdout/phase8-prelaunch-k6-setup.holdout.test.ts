import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import ts from 'typescript'
import { describe, expect, it } from 'vitest'
import { parsePrelaunchK6Raw } from '../../scripts/phase8-prelaunch-load-cloud.mjs'

type Point = { metric: string; type: string; data: { value?: number; tags?: Record<string, string>; type?: string } }

function point(metric: string, value: number, tags: Record<string, string>): Point {
  return { metric, type: 'Point', data: { value, tags } }
}

function raw(points: Point[]) {
  return points.map((entry) => JSON.stringify(entry)).join('\n')
}

function canonicalPoints() {
  return [
    { metric: 'http_reqs', type: 'Metric', data: { type: 'counter' } },
    point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'morning_check_in', status: '200' }),
    point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'morning_check_in', status: '201' }),
    point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'morning_check_in', status: '500' }),
    point('http_req_duration', 42.5, { scenario: 'morning_check_in_spike', name: 'morning_check_in' }),
    point('http_req_duration', 42.5, { scenario: 'morning_check_in_spike', name: 'morning_check_in' }),
    point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'auth_session_refresh', status: '200' }),
    point('http_req_duration', 20_000, { scenario: 'morning_check_in_spike', name: 'auth_session_refresh' }),
    point('http_reqs', 1, { group: '::setup', name: 'cross_tenant_read', status: '403' }),
    point('checks', 1, { group: '::setup', check: 'cross-tenant member read is denied' }),
    point('http_reqs', 1, { group: '::setup', name: 'cross_tenant_mutation', status: '403' }),
    point('http_req_duration', 30_000, { group: '::setup', name: 'cross_tenant_mutation' }),
  ] satisfies Point[]
}

function refuse(points: Point[]) {
  expect(() => parsePrelaunchK6Raw(raw(points))).toThrow()
}

function syntaxOptions() {
  const source = readFileSync(resolve('tests/load/phase8-morning-checkin.js'), 'utf8')
  const syntax = ts.createSourceFile('phase8-morning-checkin.js', source, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS)
  const declarations = new Map<string, ts.Expression>()
  for (const statement of syntax.statements) {
    if (!ts.isVariableStatement(statement)) continue
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name) && declaration.initializer) {
        declarations.set(declaration.name.text, declaration.initializer)
      }
    }
  }
  const resolveExpression = (expression: ts.Expression | undefined): ts.Expression | undefined => {
    if (!expression) return undefined
    if (ts.isIdentifier(expression)) return resolveExpression(declarations.get(expression.text))
    return expression
  }
  const property = (object: ts.Expression | undefined, name: string): ts.Expression | undefined => {
    const resolved = resolveExpression(object)
    if (!resolved || !ts.isObjectLiteralExpression(resolved)) return undefined
    const item = resolved.properties.find((entry) =>
      ts.isPropertyAssignment(entry) &&
      (ts.isIdentifier(entry.name) || ts.isStringLiteral(entry.name)) &&
      entry.name.text === name,
    )
    return item && ts.isPropertyAssignment(item) ? resolveExpression(item.initializer) : undefined
  }
  const number = (expression: ts.Expression | undefined): number | undefined => {
    const resolved = resolveExpression(expression)
    if (resolved && ts.isNumericLiteral(resolved)) return Number(resolved.text)
    return undefined
  }
  const string = (expression: ts.Expression | undefined): string | undefined => {
    const resolved = resolveExpression(expression)
    if (resolved && ts.isStringLiteral(resolved)) return resolved.text
    return undefined
  }
  return { syntax, options: declarations.get('options'), property, number, string }
}

describe('HARD-004 fixed k6 VU allocation holdout', () => {
  it('dedicates one 100-VU scenario to 500 check-ins per gym', () => {
    const { options, property, number, string } = syntaxOptions()
    const scenarios = property(options, 'scenarios')
    expect(scenarios && ts.isObjectLiteralExpression(scenarios)).toBe(true)
    const scenarioNames = ts.isObjectLiteralExpression(scenarios!)
      ? scenarios!.properties.map((entry) => entry.name?.getText().replace(/^['"]|['"]$/g, ''))
      : []
    expect(scenarioNames).toEqual(['morning_check_in_spike'])
    const spike = property(scenarios, 'morning_check_in_spike')
    expect(string(property(spike, 'executor'))).toBe('per-vu-iterations')
    expect(number(property(spike, 'vus'))).toBe(100)
    expect(number(property(spike, 'iterations'))).toBe(500)
  })

  it('runs probes through setup and filters its latency threshold to check-ins', () => {
    const { syntax, options, property } = syntaxOptions()
    const hasSetup = syntax.statements.some((statement) =>
      (ts.isFunctionDeclaration(statement) && statement.name?.text === 'setup') ||
      (ts.isVariableStatement(statement) && statement.declarationList.declarations.some((declaration) =>
        ts.isIdentifier(declaration.name) && declaration.name.text === 'setup')),
    )
    expect(hasSetup).toBe(true)
    const thresholds = property(options, 'thresholds')
    expect(thresholds && ts.isObjectLiteralExpression(thresholds)).toBe(true)
    const keys = ts.isObjectLiteralExpression(thresholds!)
      ? thresholds!.properties.map((entry) => entry.name?.getText().replace(/^['"]|['"]$/g, ''))
      : []
    expect(keys.some((key) => /^http_req_duration\{[^}]*name:morning_check_in(?:,|\})/.test(key ?? ''))).toBe(true)
  })
})

describe('HARD-004 setup probe and check-in-only raw evidence holdout', () => {
  it('excludes refresh and setup traffic from completed check-ins and p95', () => {
    const measured = parsePrelaunchK6Raw(raw(canonicalPoints()))
    expect(measured).toEqual({
      p95Ms: 42.5,
      completedCheckIns: 2,
      crossTenantReadDenied: true,
      crossTenantMutationStatus: 403,
    })
  })

  it('does not count an unlabelled request in the check-in scenario', () => {
    const points = canonicalPoints()
    points.push(point('http_reqs', 1, { scenario: 'morning_check_in_spike', status: '200' }))
    points.push(point('http_req_duration', 40_000, { scenario: 'morning_check_in_spike' }))
    const measured = parsePrelaunchK6Raw(raw(points))
    expect(measured.completedCheckIns).toBe(2)
    expect(measured.p95Ms).toBe(42.5)
  })

  it.each([
    ['missing setup read check', (points: Point[]) => points.filter((entry) => !(entry.metric === 'checks' && entry.data.tags?.group === '::setup'))],
    ['failed setup read check', (points: Point[]) => points.map((entry) => entry.metric === 'checks' && entry.data.tags?.group === '::setup' ? { ...entry, data: { ...entry.data, value: 0 } } : entry)],
    ['duplicated setup read check', (points: Point[]) => [...points, points[9]]],
    ['missing setup mutation', (points: Point[]) => points.filter((entry) => entry.data.tags?.name !== 'cross_tenant_mutation')],
    ['duplicated setup mutation', (points: Point[]) => [...points, points[10]]],
    ['successful foreign mutation', (points: Point[]) => points.map((entry) => entry.data.tags?.name === 'cross_tenant_mutation' && entry.metric === 'http_reqs' ? { ...entry, data: { ...entry.data, tags: { ...entry.data.tags, status: '204' } } } : entry)],
    ['mutation outside setup', (points: Point[]) => points.map((entry) => entry.data.tags?.name === 'cross_tenant_mutation' && entry.metric === 'http_reqs' ? { ...entry, data: { ...entry.data, tags: { scenario: 'cross_tenant_mutation_denial', name: 'cross_tenant_mutation', status: '403' } } } : entry)],
  ])('refuses %s', (_case, change) => {
    refuse(change(canonicalPoints()))
  })

  it('does not accept a scenario-tagged decoy for a missing setup read probe', () => {
    const points = canonicalPoints().filter((entry) => !(entry.metric === 'checks' && entry.data.tags?.group === '::setup'))
    points.push(point('checks', 1, { scenario: 'cross_tenant_read_denial', check: 'cross-tenant member read is denied' }))
    refuse(points)
  })

  it('does not let refresh traffic compensate for a failed check-in', () => {
    const points = canonicalPoints().filter((entry) => !(entry.metric === 'http_reqs' && entry.data.tags?.name === 'morning_check_in' && entry.data.tags?.status === '201'))
    for (let index = 0; index < 20; index += 1) {
      points.push(point('http_reqs', 1, { scenario: 'morning_check_in_spike', name: 'auth_session_refresh', status: '200' }))
    }
    const measured = parsePrelaunchK6Raw(raw(points))
    expect(measured.completedCheckIns).toBe(1)
    expect(measured.p95Ms).toBe(42.5)
  })
})
