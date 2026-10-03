import { describe, expect, it } from 'vitest';
import { MEMBER_PAGE_SIZE_DEFAULT } from '@gymloop/shared';
import { loadDeskMembers } from '../mobile-data';

type Row = { id: string; full_name: string; phone: string; status: string; member_code: string | null; tenant_id: string; private_note: string };
type Result = { data: Record<string, unknown>[] | null; error: { message: string } | null };

// This models database evaluation: predicates, ordering, then the result cap,
// regardless of the order in which a caller builds the query.
function database(rows: Row[], failure: string | null = null) {
  const selections: string[] = [];
  const predicates: ((row: Row) => boolean)[] = [];
  let columns = '*';
  let cap = rows.length;
  let sortColumn = 'id';
  let ascending = true;
  const value = (row: Row, field: string) => {
    if (field === 'tenant_id') throw new Error('A caller must not select its own tenant');
    if (!(field in row)) throw new Error(`Unknown column: ${field}`);
    return String(row[field as keyof Row] ?? '');
  };
  const matches = (actual: string, pattern: string) => {
    const unquoted = pattern.startsWith('"') ? JSON.parse(pattern) as string : pattern;
    let expression = '';
    let escaped = false;
    for (const char of unquoted) {
      if (!escaped && char === '\\') { escaped = true; continue; }
      expression += !escaped && (char === '%' || char === '*') ? '.*'
        : !escaped && char === '_' ? '.' : char.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
      escaped = false;
    }
    return new RegExp(`^${expression}$`, 'i').test(actual);
  };
  const parse = (expression: string): ((row: Row) => boolean) => {
    const match = /^([a-z_]+)\.(ilike|eq)\.(.*)$/.exec(expression);
    if (!match) throw new Error('Malformed filter grammar');
    const [, field, operator, pattern] = match;
    if (field === undefined || operator === undefined || pattern === undefined) throw new Error('Incomplete filter grammar');
    return row => operator === 'ilike' ? matches(value(row, field), pattern) : value(row, field) === pattern;
  };
  const split = (expression: string) => {
    const parts: string[] = [];
    let quoted = false;
    let escaped = false;
    let part = '';
    for (const char of expression) {
      if (char === '"' && !escaped) quoted = !quoted;
      if (char === ',' && !quoted) { parts.push(part); part = ''; }
      else part += char;
      escaped = char === '\\' && !escaped;
    }
    if (quoted) throw new Error('Malformed quoted filter');
    parts.push(part);
    return parts;
  };
  const query = {
    select(projection: string) { columns = projection; selections.push(projection); return query; },
    order(field: string, options?: { ascending?: boolean }) { sortColumn = field; ascending = options?.ascending ?? true; return query; },
    limit(count: number) { cap = count; return query; },
    range(from: number, to: number) { expect(from).toBe(0); cap = to + 1; return query; },
    ilike(field: string, pattern: string) { predicates.push(row => matches(value(row, field), pattern)); return query; },
    eq(field: string, expected: unknown) { predicates.push(row => value(row, field) === String(expected)); return query; },
    filter(field: string, operator: string, pattern: string) { predicates.push(parse(`${field}.${operator}.${pattern}`)); return query; },
    or(expression: string) { const alternatives = split(expression).map(parse); predicates.push(row => alternatives.some(predicate => predicate(row))); return query; },
    then<TResult1 = Result, TResult2 = never>(fulfilled?: ((result: Result) => TResult1 | PromiseLike<TResult1>) | null, rejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null): Promise<TResult1 | TResult2> {
      return Promise.resolve().then((): Result => {
        if (failure) return { data: null, error: { message: failure } };
        const data = rows.filter(row => predicates.every(predicate => predicate(row)))
          .sort((a, b) => value(a, sortColumn).localeCompare(value(b, sortColumn)) * (ascending ? 1 : -1))
          .slice(0, cap).map(row => Object.fromEntries((columns === '*' ? Object.keys(row) : columns.split(',').map(field => field.trim())).map(field => [field, row[field as keyof Row]])));
        return { data, error: null };
      }).then(fulfilled, rejected);
    },
  };
  const client = { from(table: string) { expect(table).toBe('members'); return query; } };
  return { client: client as unknown as Parameters<typeof loadDeskMembers>[0], selections };
}

function roster(): Row[] {
  return Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT + 12 }, (_, index): Row => ({
    id: `member-${index}`, full_name: `A Member ${String(index).padStart(3, '0')}`,
    phone: `90000${String(index).padStart(5, '0')}`, status: 'active', member_code: null,
    tenant_id: 'caller-session-only', private_note: 'must not escape projection',
  })).concat({ id: 'late', full_name: 'Zoya LateMatch', phone: '9876543210', status: 'active', member_code: 'GL-Z', tenant_id: 'caller-session-only', private_note: 'secret' });
}

describe('CLS-Q6 caller-bound native member search', () => {
  it.each(['  lAtEmAtCh  ', '  765432  '])('finds a match beyond the initial roster cap for %s', async query => {
    const { client } = database(roster());
    expect(await loadDeskMembers(client, query)).toEqual([{ id: 'late', fullName: 'Zoya LateMatch', phone: '9876543210', status: 'active', memberCode: 'GL-Z' }]);
  });

  it.each(['', '   '])('keeps an empty search bounded, name ordered and precisely projected', async query => {
    const rows = roster().reverse();
    const { client, selections } = database(rows);
    const actual = await loadDeskMembers(client, query);
    const expected = [...rows].sort((a, b) => a.full_name.localeCompare(b.full_name)).slice(0, MEMBER_PAGE_SIZE_DEFAULT)
      .map(row => ({ id: row.id, fullName: row.full_name, phone: row.phone, status: row.status, memberCode: row.member_code }));
    expect(actual).toEqual(expected);
    expect(selections.flatMap(projection => projection.split(',').map(field => field.trim())).sort())
      .toEqual(['full_name', 'id', 'member_code', 'phone', 'status']);
  });

  it('bounds broad searches too', async () => {
    const { client } = database(roster());
    expect(await loadDeskMembers(client, 'member')).toHaveLength(MEMBER_PAGE_SIZE_DEFAULT);
  });

  it('uses the supplied session audience and never manufactures members', async () => {
    const { client } = database([]);
    expect(await loadDeskMembers(client, 'late')).toEqual([]);
  });

  it.each(['', 'late'])('surfaces a failed database read for %s', async query => {
    const { client } = database(roster(), 'session read denied');
    await expect(loadDeskMembers(client, query)).rejects.toThrow('session read denied');
  });

  it.each(['missing%,full_name.ilike.%', 'missing),phone.ilike.*', 'missing"\\,full_name.ilike.*'])('does not let punctuation widen the audience: %s', async query => {
    const { client } = database(roster());
    expect(await loadDeskMembers(client, query)).toEqual([]);
  });
});
