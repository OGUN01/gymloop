// Independent CLS-Q6 regression from the frozen public desk-search seam.
import { describe, expect, it, vi } from 'vitest';
import { MEMBER_PAGE_SIZE_DEFAULT } from '../../packages/shared/src/config/constants';

const rootId = '74900000-0000-4000-8000-';
type StoredMember = {
  id: string; full_name: string; phone: string; status: string; member_code: string | null;
  tenant_id: string; private_note: string;
};
type PublicMember = { id: string; fullName: string; phone: string; status: string; memberCode: string | null };
type ReadResult = { data: StoredMember[] | null; error: { message: string } | null };
const member = (ordinal: number, fullName: string, phone: string, memberCode: string | null = null): StoredMember => ({
  id: rootId + String(ordinal).padStart(12, '0'), full_name: fullName, phone, member_code: memberCode,
  status: 'active', tenant_id: rootId + '000000009999', private_note: 'Held private field',
});
const roster = () => [
  ...Array.from({ length: MEMBER_PAGE_SIZE_DEFAULT + 9 }, (_, index) => member(index + 1, `A roster ${String(index).padStart(3, '0')}`, `+919001${String(index).padStart(6, '0')}`)),
  member(900, 'Z late Lotus', '+919876549876', 'CLS-LATE'),
];

function patternMatches(value: string, rawPattern: string): boolean {
  const pattern = rawPattern.startsWith('"') && rawPattern.endsWith('"')
    ? rawPattern.slice(1, -1).replace(/\\(.)/g, '$1') : rawPattern;
  let expression = '';
  let escaped = false;
  for (const character of pattern) {
    if (!escaped && character === '\\') { escaped = true; continue; }
    if (!escaped && (character === '%' || character === '*')) expression += '.*';
    else if (!escaped && character === '_') expression += '.';
    else expression += character.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    escaped = false;
  }
  return new RegExp(`^${expression}$`, 'i').test(value);
}
function splitFilters(value: string): string[] {
  const parts: string[] = [];
  let part = ''; let quoted = false; let escaped = false;
  for (const character of value) {
    if (escaped) { part += character; escaped = false; continue; }
    if (character === '\\') { part += character; escaped = true; continue; }
    if (character === '"') quoted = !quoted;
    if (character === ',' && !quoted) { parts.push(part); part = ''; }
    else part += character;
  }
  if (quoted || escaped) throw new Error('Malformed filter');
  parts.push(part); return parts;
}
// A dataset-backed PostgREST double evaluates server filters before its response cap.
// It deliberately does not require a particular fluent-call order or filter strategy.
function callerClient(rows: StoredMember[], fail = false) {
  const from = vi.fn(() => {
    const filters: Array<(row: StoredMember) => boolean> = [];
    let cap = rows.length; let sortKey: keyof StoredMember | null = null; let ascending = true;
    let invalidFilter = false;
    const chain = {
      select: () => chain,
      eq: (column: keyof StoredMember, value: unknown) => { filters.push(row => row[column] === value); return chain; },
      neq: (column: keyof StoredMember, value: unknown) => { filters.push(row => row[column] !== value); return chain; },
      is: (column: keyof StoredMember, value: unknown) => { filters.push(row => row[column] === value); return chain; },
      ilike: (column: keyof StoredMember, pattern: string) => { filters.push(row => patternMatches(String(row[column]), pattern)); return chain; },
      or: (expression: string) => {
        try {
          const alternatives = splitFilters(expression).map(part => {
            const match = /^(full_name|phone)\.ilike\.(.*)$/.exec(part);
            if (!match) throw new Error('Query grammar cannot choose an audience');
            const column = match[1] as 'full_name' | 'phone'; const pattern = match[2]!;
            return (row: StoredMember) => patternMatches(row[column], pattern);
          });
          filters.push(row => alternatives.some(predicate => predicate(row)));
        } catch { invalidFilter = true; }
        return chain;
      },
      order: (column: keyof StoredMember, options?: { ascending?: boolean }) => { sortKey = column; ascending = options?.ascending ?? true; return chain; },
      limit: (value: number) => { cap = value; return chain; },
      range: (start: number, end: number) => { cap = end - start + 1; return chain; },
      then: <TResult1 = ReadResult, TResult2 = never>(
        fulfilled?: ((value: ReadResult) => TResult1 | PromiseLike<TResult1>) | null,
        rejected?: ((reason: unknown) => TResult2 | PromiseLike<TResult2>) | null,
      ): Promise<TResult1 | TResult2> => {
        const selected = rows.filter(row => filters.every(predicate => predicate(row)));
        if (sortKey) {
          const key = sortKey;
          selected.sort((left, right) => String(left[key]).localeCompare(String(right[key])) * (ascending ? 1 : -1));
        }
        const result: ReadResult = fail || invalidFilter
          ? { data: null, error: { message: 'Held private database detail' } }
          : { data: selected.slice(0, cap), error: null };
        return Promise.resolve(result).then(fulfilled, rejected);
      },
    };
    return chain;
  });
  return { from };
}
async function search(client: ReturnType<typeof callerClient>, query: string): Promise<PublicMember[]> {
  const { loadDeskMembers } = await import('../../apps/mobile/lib/mobile-data');
  return loadDeskMembers(client as unknown as Parameters<typeof loadDeskMembers>[0], query);
}
const publicRow = (row: StoredMember): PublicMember => ({
  id: row.id, fullName: row.full_name, phone: row.phone, status: row.status, memberCode: row.member_code,
});

describe('CLS-Q6 held caller-bound desk member search', () => {
  for (const query of ['lotus', '  LoTuS  ', '9876549876', '  9876549876  ']) {
    it(`finds the late matching member before cap for ${JSON.stringify(query)}`, async () => {
      const rows = roster(); const client = callerClient(rows);
      expect(await search(client, query)).toEqual([publicRow(rows.at(-1)!)]);
      expect(client.from).toHaveBeenCalledWith('members');
    });
  }
  for (const query of ['', '   ', 'roster']) {
    it(`keeps empty or broad search bounded and name ordered for ${JSON.stringify(query)}`, async () => {
      const rows = roster().reverse(); const result = await search(callerClient(rows), query);
      expect(result).toHaveLength(MEMBER_PAGE_SIZE_DEFAULT);
      const names = result.map(row => row.fullName);
      expect(names).toEqual([...names].sort((left, right) => left.localeCompare(right)));
      for (const row of result) expect(Object.keys(row).sort()).toEqual(['fullName', 'id', 'memberCode', 'phone', 'status']);
      expect(result.every(row => row.memberCode === null)).toBe(true);
    });
  }
  it('uses each supplied caller dataset independently without leaking prior results', async () => {
    const first = callerClient([member(701, 'Lotus First', '+919700000001', 'FIRST')]);
    const second = callerClient([member(702, 'Lotus Second', '+919700000002')]);
    expect(await search(first, 'lotus')).toEqual([publicRow(member(701, 'Lotus First', '+919700000001', 'FIRST'))]);
    expect(await search(second, 'lotus')).toEqual([publicRow(member(702, 'Lotus Second', '+919700000002'))]);
    expect(first.from).toHaveBeenCalledTimes(1); expect(second.from).toHaveBeenCalledTimes(1);
  });
  for (const query of ['absent,tenant_id.eq.' + rootId + '000000009999', 'absent,full_name.ilike.*', 'absent)or(full_name.ilike.*', '"absent",phone.ilike.*']) {
    it(`special query text cannot widen the caller roster: ${JSON.stringify(query)}`, async () => {
      const result = await search(callerClient(roster()), query).catch(() => []);
      expect(result).toEqual([]);
    });
  }
  it('database failure remains a rejected read rather than an empty successful roster', async () => {
    await expect(search(callerClient(roster(), true), 'lotus')).rejects.toBeDefined();
    expect(await search(callerClient(roster()), 'no matching member')).toEqual([]);
  });
});
