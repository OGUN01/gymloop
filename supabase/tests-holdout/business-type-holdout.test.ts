import { describe, expect, it } from 'vitest';
import { Constants } from '../../packages/db/types/database';
import {
  BUSINESS_TYPES, BUSINESS_TYPE_LABELS, BUSINESS_TYPE_SUMMARIES, businessNouns,
  businessRoleLabel, businessTypeCommandSchema, isBusinessType, setGymBusinessTypeRequestSchema,
} from '../../packages/shared/src/business-type';
import {
  encodePersistedBusinessType, readPersistedBusinessType, resolveBusinessType,
} from '../../apps/mobile/lib/business-type';
import { loadBusinessNouns, loadBusinessType } from '../../apps/web/lib/business-type';

// Independent tests of the frozen public seams. No feature source or visible suite read.
const golden = {
  gym: ['gym', 'session', 'sessions', 'class', 'classes', 'member', 'members', 'trainer'],
  dance: ['academy', 'class', 'classes', 'batch', 'batches', 'student', 'students', 'instructor'],
  yoga: ['studio', 'class', 'classes', 'class', 'classes', 'member', 'members', 'teacher'],
  martial_arts: ['academy', 'class', 'classes', 'class', 'classes', 'student', 'students', 'instructor'],
  studio: ['studio', 'session', 'sessions', 'class', 'classes', 'member', 'members', 'trainer'],
} as const;
const keys = ['place', 'session', 'sessions', 'class', 'classes', 'member', 'members', 'trainer'] as const;

describe('BIZ independent vocabulary and account-scoped fallback', () => {
  it('BIZ-009 uses the generated enum and exactly eight golden nouns', () => {
    expect(BUSINESS_TYPES).toEqual(Constants.public.Enums.business_type);
    for (const [type, values] of Object.entries(golden)) {
      const nouns = businessNouns(type as keyof typeof golden);
      expect(Object.keys(nouns).sort()).toEqual([...keys].sort());
      expect(keys.map((key) => nouns[key])).toEqual(values);
      expect(isBusinessType(type)).toBe(true);
      expect(BUSINESS_TYPE_LABELS[type as keyof typeof golden]).toBeTruthy();
      expect(BUSINESS_TYPE_SUMMARIES[type as keyof typeof golden]).toBeTruthy();
    }
  });
  it('BIZ-009 unknown, empty, prototype keys and absent types fall back safely', () => {
    for (const type of [null, undefined, '', 'constructor', '__proto__', 'DANCE', {}, 0]) {
      expect(businessNouns(type as never)).toEqual(businessNouns('gym'));
      expect(isBusinessType(type)).toBe(false);
    }
    const nouns = businessNouns('dance');
    try { Reflect.set(nouns, 'place', 'corrupted'); } catch { /* frozen is permitted */ }
    expect(businessNouns('dance').place).toBe('academy');
  });
  it('BIZ-009 role labels vary nouns without changing roles', () => {
    expect(businessRoleLabel('gym_owner', businessNouns('dance'))).toBe('academy owner');
    expect(businessRoleLabel('gym_manager', businessNouns('dance'))).toBe('academy manager');
    expect(businessRoleLabel('front_desk', businessNouns('dance'))).toBe('front desk');
    expect(businessRoleLabel('trainer', businessNouns('yoga'))).toBe('teacher');
  });
  it('BIZ-009 command schemas reject tenant/actor injection and request-key misuse', () => {
    expect(businessTypeCommandSchema.safeParse({ businessType: 'dance' }).success).toBe(true);
    for (const value of [null, 'DANCE', 'custom', '__proto__']) {
      expect(businessTypeCommandSchema.safeParse({ businessType: value }).success).toBe(false);
    }
    expect(businessTypeCommandSchema.safeParse({ businessType: 'dance', tenantId: 'another' }).success).toBe(false);
    const request = { expectedBusinessType: 'gym', businessType: 'studio', requestKey: '70900000-0000-4000-8000-000000000701' };
    expect(setGymBusinessTypeRequestSchema.safeParse(request).success).toBe(true);
    expect(setGymBusinessTypeRequestSchema.safeParse({ ...request, actorUserId: 'spoof' }).success).toBe(false);
    expect(setGymBusinessTypeRequestSchema.safeParse({ ...request, requestKey: 'not-a-key' }).success).toBe(false);
  });
  it('BIZ-011 persisted values cannot cross a tenant or accept corrupt input', () => {
    const raw = encodePersistedBusinessType('tenant-A', 'dance');
    expect(JSON.parse(raw)).toEqual({ t: 'tenant-A', b: 'dance' });
    expect(readPersistedBusinessType(raw, 'tenant-A')).toBe('dance');
    expect(readPersistedBusinessType(raw, 'tenant-B')).toBeNull();
    for (const corrupt of [null, '', '{', 'null', '[]', '{"t":"tenant-A","b":"custom"}', '{"b":"gym"}']) {
      expect(readPersistedBusinessType(corrupt, 'tenant-A')).toBeNull();
    }
    expect(resolveBusinessType({ fetched: 'yoga', persisted: 'dance' })).toBe('yoga');
    expect(resolveBusinessType({ fetched: null, persisted: 'dance' })).toBe('dance');
    expect(resolveBusinessType({ fetched: null, persisted: null })).toBeNull();
  });
  it('BIZ-010 per-call lookup preserves freshness and masks failures', async () => {
    let value: unknown = 'dance';
    let error: unknown = null;
    const reads: unknown[][] = [];
    const db = {
      from: (table: string) => ({ select: (columns: string) => ({ eq: (key: string, id: string) => ({
        maybeSingle: async () => {
          reads.push([table, columns, key, id]);
          if (error instanceof Error) throw error;
          return { data: value === null ? null : { business_type: value }, error };
        },
      }) }) }),
    };
    expect(await loadBusinessType(db as never, 'tenant-A')).toBe('dance');
    value = 'yoga';
    expect(await loadBusinessNouns(db as never, 'tenant-A')).toEqual(businessNouns('yoga'));
    value = 'constructor';
    expect(await loadBusinessType(db as never, 'tenant-A')).toBe('gym');
    error = { message: 'private database diagnostic' };
    expect(await loadBusinessType(db as never, 'tenant-A')).toBe('gym');
    error = new Error('private thrown diagnostic');
    expect(await loadBusinessType(db as never, 'tenant-A')).toBe('gym');
    expect(reads.every(([table, columns, key, id]) => table === 'organizations' && columns === 'business_type' && key === 'id' && id === 'tenant-A')).toBe(true);
  });
});
