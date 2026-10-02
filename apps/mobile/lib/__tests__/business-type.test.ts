import { describe, expect, it } from 'vitest';
import { BUSINESS_TYPE_STORAGE_KEY, encodePersistedBusinessType, readPersistedBusinessType, resolveBusinessType } from '../business-type';

const tenant = '70000000-0000-4000-8000-000000000001';
describe('BIZ-011 tenant-bound offline vocabulary', () => {
  it('uses one stable storage key and the exact tenant/value payload', () => {
    expect(BUSINESS_TYPE_STORAGE_KEY).toBe('gymloop.business-type');
    expect(JSON.parse(encodePersistedBusinessType(tenant, 'dance'))).toEqual({ t: tenant, b: 'dance' });
    expect(readPersistedBusinessType(encodePersistedBusinessType(tenant, 'dance'), tenant)).toBe('dance');
  });
  it.each([null, '', '{', '{}', '{"t":"other","b":"dance"}', '{"b":"dance"}', `{"t":"${tenant}","b":"custom"}`])('ignores missing, corrupt or foreign persisted data %s', (raw) => {
    expect(readPersistedBusinessType(raw, tenant)).toBeNull();
  });
  it('fresh data wins; offline preserves the known value; an empty state stays unresolved', () => {
    expect(resolveBusinessType({ fetched: 'yoga', persisted: 'dance' })).toBe('yoga');
    expect(resolveBusinessType({ fetched: null, persisted: 'dance' })).toBe('dance');
    expect(resolveBusinessType({ fetched: 'gym', persisted: null })).toBe('gym');
    expect(resolveBusinessType({ fetched: null, persisted: null })).toBeNull();
  });
});
