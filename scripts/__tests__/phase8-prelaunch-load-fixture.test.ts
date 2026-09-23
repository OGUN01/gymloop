import { randomUUID } from 'node:crypto';
import { describe, expect, it } from 'vitest';

import {
  buildPrelaunchSyntheticPlan,
  parseLinkedDatabaseSize,
  renderPrelaunchCleanupSql,
  renderPrelaunchStageSql,
} from '../phase8-prelaunch-load-fixture.mjs';

const MARKER = 'PHASE8-LOAD-11111111-2222-4333-8444-555555555555';
const OTHER_MARKER = 'PHASE8-LOAD-aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
let cachedPlan: ReturnType<typeof buildPrelaunchSyntheticPlan> | undefined;
let cachedBindings: Array<{ email: string; userId: string }> | undefined;
let cachedStageSql: string | undefined;

const plan = () => cachedPlan ??= buildPrelaunchSyntheticPlan(MARKER);
const gymEmail = (gym: Record<string, unknown>) => {
  const entries = Object.entries(gym).filter(([key, value]) => /email/i.test(key) && typeof value === 'string');
  expect(entries).toHaveLength(1);
  return entries[0][1] as string;
};
const memberPairKey = (gym: Record<string, unknown>) => {
  const entries = Object.entries(gym).filter(([, value]) =>
    Array.isArray(value) && value.length === 500 && value.every((item) =>
      item !== null && typeof item === 'object' && 'memberId' in item && 'membershipId' in item));
  expect(entries).toHaveLength(1);
  return entries[0][0];
};
const memberPairs = (gym: Record<string, unknown>) =>
  gym[memberPairKey(gym)] as Array<{ memberId: string; membershipId: string }>;
const bindings = () => cachedBindings ??= plan().gyms.map((gym: Record<string, unknown>) => ({
  email: gymEmail(gym),
  userId: randomUUID(),
}));
const stageSql = () => cachedStageSql ??= renderPrelaunchStageSql(plan(), bindings());
const changedGym = (gymIndex: number, patch: Record<string, unknown>) => ({
  ...plan(),
  gyms: plan().gyms.map((gym: Record<string, unknown>, index: number) =>
    index === gymIndex ? { ...gym, ...patch } : gym),
});

describe('HARD-004 deterministic synthetic fixture plan', () => {
  it('creates 100 gyms and exactly 500 member/membership pairs for each', () => {
    const result = plan();
    expect(result.marker).toBe(MARKER);
    expect(result.gyms).toHaveLength(100);
    for (const gym of result.gyms) {
      for (const key of ['gymId', 'branchId', 'planId', 'staffId']) {
        expect(gym[key]).toMatch(UUID);
      }
      expect(memberPairs(gym)).toHaveLength(500);
      for (const member of memberPairs(gym)) {
        expect(member).toEqual({ memberId: expect.stringMatching(UUID), membershipId: expect.stringMatching(UUID) });
      }
      expect(gymEmail(gym)).toMatch(/@[^@\s]+\.invalid$/i);
    }
  });

  it('uses globally distinct IDs and emails without embedding secrets', () => {
    const result = plan();
    const ids = result.gyms.flatMap((gym: Record<string, unknown>) => [
      gym.gymId,
      gym.branchId,
      gym.planId,
      gym.staffId,
      ...memberPairs(gym).flatMap((member) => [member.memberId, member.membershipId]),
    ]);
    expect(ids).toHaveLength(100_400);
    expect(new Set(ids).size).toBe(ids.length);
    expect(new Set(result.gyms.map((gym: Record<string, unknown>) => gymEmail(gym))).size).toBe(100);
    expect(JSON.stringify(result)).not.toMatch(/password|bearer|service[_-]?key|access[_-]?token|refresh[_-]?token/i);
  });

  it('reproduces the same plan for recovery and separates another run marker', () => {
    expect(buildPrelaunchSyntheticPlan(MARKER)).toEqual(plan());
    const other = buildPrelaunchSyntheticPlan(OTHER_MARKER);
    expect(other.gyms).toHaveLength(100);
    const priorGymIds = new Set(plan().gyms.map((gym: Record<string, unknown>) => gym.gymId));
    const priorEmails = new Set(plan().gyms.map((gym: Record<string, unknown>) => gymEmail(gym)));
    expect(other.gyms.every((gym: Record<string, unknown>) => !priorGymIds.has(gym.gymId))).toBe(true);
    expect(other.gyms.every((gym: Record<string, unknown>) => !priorEmails.has(gymEmail(gym)))).toBe(true);
  });

  it('refuses absent and malformed markers', () => {
    for (const marker of ['', 'PHASE8-LOAD-reused', '11111111-2222-4333-8444-555555555555', null]) {
      expect(() => buildPrelaunchSyntheticPlan(marker)).toThrow();
    }
  });
});

describe('HARD-004 transactional synthetic stage', () => {
  it('binds one distinct Auth user to each planned synthetic email', () => {
    expect(bindings()).toHaveLength(100);
    const sql = stageSql();
    expect(typeof sql).toBe('string');
    expect(sql).toMatch(/\bbegin\s*;/i);
    expect(sql).toMatch(/\bcommit\s*;\s*$/i);
    expect(sql).toContain(plan().gyms[0].gymId);
    expect(sql).toContain(memberPairs(plan().gyms[99])[499].memberId);
    expect(sql).toContain(bindings()[0].userId);
    expect(sql).toContain(MARKER);
  });

  it('refuses missing, duplicate, foreign or malformed Auth bindings', () => {
    const good = bindings();
    const cases = [
      good.slice(1),
      [...good, { email: 'outsider@example.invalid', userId: randomUUID() }],
      good.map((binding, index) => index === 1 ? { ...binding, email: good[0].email } : binding),
      good.map((binding, index) => index === 1 ? { ...binding, userId: good[0].userId } : binding),
      good.map((binding, index) => index === 1 ? { ...binding, email: 'outsider@example.invalid' } : binding),
      good.map((binding, index) => index === 1 ? { ...binding, userId: 'not-a-uuid' } : binding),
      good.map((binding, index) => index === 1 ? { ...binding, extraSecret: 'private' } : binding),
    ];
    for (const authBindings of cases) {
      expect(() => renderPrelaunchStageSql(plan(), authBindings)).toThrow();
    }
  });

  it('revalidates the entire plan before rendering, including all 50,000 pairs', () => {
    const first = plan().gyms[0];
    const second = plan().gyms[1];
    const pairKey = memberPairKey(second);
    const firstPairs = memberPairs(first);
    const secondPairs = memberPairs(second);
    for (const alteredPlan of [
      { ...plan(), gyms: plan().gyms.slice(1) },
      changedGym(1, { gymId: first.gymId }),
      changedGym(1, { staffId: first.staffId }),
      changedGym(1, { [pairKey]: secondPairs.slice(1) }),
      changedGym(1, { [pairKey]: [{ ...secondPairs[0], memberId: firstPairs[0].memberId }, ...secondPairs.slice(1)] }),
      changedGym(1, { [pairKey]: [{ ...secondPairs[0], membershipId: firstPairs[0].membershipId }, ...secondPairs.slice(1)] }),
    ]) {
      expect(() => renderPrelaunchStageSql(alteredPlan, bindings())).toThrow();
    }
  });

  it('inserts only the new synthetic hierarchy and no priced plan or unsafe SQL escape', () => {
    const sql = stageSql();
    for (const table of ['organizations', 'organization_settings', 'branches', 'plans', 'staff', 'members', 'memberships']) {
      expect(new RegExp(`\\binsert\\s+into\\s+(?:public\\.)?${table}\\b`, 'i').test(sql), table).toBe(true);
    }
    expect(/\bfront_desk\b/i.test(sql)).toBe(true);
    expect(/\bprice_paise\b[\s\S]{0,300}\b0\b/i.test(sql)).toBe(true);
    expect(/\bactive\b/i.test(sql)).toBe(true);
    expect(/\bon\s+conflict\b|\btruncate\b|\bupdate\s+(?:public\.)?\w+\b|\balter\s+table\b[^;]*\bdisable\s+trigger\b|\binsert\s+into\s+auth\.users\b/i.test(sql)).toBe(false);
    expect(/\b(?:seed\.sql|supabase\/migrations)\b/i.test(sql)).toBe(false);
  });

  it('asserts exact staged row counts inside the transaction', () => {
    const sql = stageSql();
    expect(/\braise\s+exception\b/i.test(sql)).toBe(true);
    expect(sql).toMatch(/\b50\s*_?\s*000\b|\b50000\b/);
    expect(sql).toMatch(/\b100\b/);
  });
});

describe('HARD-004 partial-safe exact-ID cleanup', () => {
  it('refuses a damaged recovery plan before generating deletion SQL', () => {
    expect(() => renderPrelaunchCleanupSql({ ...plan(), marker: 'unmarked' })).toThrow();
    expect(() => renderPrelaunchCleanupSql(changedGym(1, { gymId: plan().gyms[0].gymId }))).toThrow();
  });

  it('uses one transaction, the plan marker, and only planned gym identities', () => {
    const sql = renderPrelaunchCleanupSql(plan());
    expect(sql).toMatch(/\bbegin\s*;/i);
    expect(sql).toMatch(/\bcommit\s*;\s*$/i);
    expect(sql).toContain(MARKER);
    expect(sql).toContain(plan().gyms[0].gymId);
    expect(sql).toContain(plan().gyms[99].gymId);
    expect(sql).not.toContain('00000000-0000-4000-8000-000000000000');
    expect(/\braise\s+exception\b/i.test(sql)).toBe(true);
    expect(/\bauth\.users\b/i.test(sql)).toBe(false);
  });

  it('deletes dependent rows before parents with a scope on every delete', () => {
    const sql = renderPrelaunchCleanupSql(plan());
    const tables = ['attendance', 'memberships', 'members', 'plans', 'staff', 'branches', 'organization_settings', 'organizations'];
    const positions = Object.fromEntries(tables.map((table) => {
      const match = new RegExp(`\\bdelete\\s+from\\s+(?:public\\.)?${table}\\b`, 'i').exec(sql);
      expect(match, `${table} must be cleaned by exact plan IDs`).not.toBeNull();
      return [table, match!.index];
    })) as Record<string, number>;
    for (const [child, parent] of [
      ['attendance', 'memberships'],
      ['attendance', 'members'],
      ['memberships', 'members'],
      ['memberships', 'plans'],
      ['members', 'branches'],
      ['staff', 'branches'],
      ['branches', 'organizations'],
      ['plans', 'organizations'],
      ['organization_settings', 'organizations'],
    ]) {
      expect(positions[child], `${child} must precede ${parent}`).toBeLessThan(positions[parent]);
    }
    const deletes = [...sql.matchAll(/\bdelete\s+from\s+(?:public\.)?\w+\b[^;]*;/gi)];
    expect(deletes.length).toBeGreaterThanOrEqual(tables.length);
    for (const match of deletes) {
      expect(/\bwhere\b/i.test(match[0]), 'each delete needs an exact-ID condition').toBe(true);
      expect(/\b(?:tenant_id|id)\b/i.test(match[0]), 'each delete must bind planned identities').toBe(true);
    }
    expect(/\btruncate\b|\bon\s+conflict\b|^\s*update\s+/im.test(sql)).toBe(false);
  });

  it('verifies zero remaining planned database identities after partial cleanup', () => {
    const sql = renderPrelaunchCleanupSql(plan());
    expect(/\braise\s+exception\b/i.test(sql)).toBe(true);
    expect(/\b(?:exists|count)\s*\(/i.test(sql)).toBe(true);
    expect(/\borganization_settings\b/i.test(sql)).toBe(true);
  });
});

describe('HARD-004 linked database size parser', () => {
  it('returns the only nonnegative safe integer from CLI JSON', () => {
    expect(parseLinkedDatabaseSize('[{"database_bytes":34000000}]')).toBe(34_000_000);
    expect(parseLinkedDatabaseSize('[{"database_bytes":0}]')).toBe(0);
    expect(parseLinkedDatabaseSize(`[{"database_bytes":${Number.MAX_SAFE_INTEGER}}]`)).toBe(Number.MAX_SAFE_INTEGER);
  });

  it('rejects missing, malformed, error, ambiguous and unsafe sizes', () => {
    for (const raw of [
      '',
      'not-json',
      '[]',
      '[{}]',
      '{"error":"query failed"}',
      '[{"database_bytes":1},{"database_bytes":2}]',
      '[{"database_bytes":1},{"database_bytes":1}]',
      '[{"database_bytes":-1}]',
      '[{"database_bytes":1.5}]',
      '[{"database_bytes":"34"}]',
      `[{"database_bytes":${Number.MAX_SAFE_INTEGER + 1}}]`,
      null,
      undefined,
    ]) {
      expect(() => parseLinkedDatabaseSize(raw)).toThrow();
    }
  });
});
