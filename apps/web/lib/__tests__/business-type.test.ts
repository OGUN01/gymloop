import { describe, expect, it, vi } from 'vitest';
import { businessNouns } from '@gymloop/shared';
import { loadBusinessType, loadBusinessNouns } from '../business-type';

const tenant = '70000000-0000-4000-8000-000000000001';
const client = (result: unknown) => {
  const chain = { select: vi.fn(), eq: vi.fn(), maybeSingle: vi.fn().mockResolvedValue(result) };
  chain.select.mockReturnValue(chain); chain.eq.mockReturnValue(chain);
  return { from: vi.fn().mockReturnValue(chain), chain };
};
describe('BIZ-010 copy lookup is safe and current', () => {
  it('reads own tenant with the provided caller session', async () => {
    const db = client({ data: { business_type: 'dance' }, error: null });
    expect(await loadBusinessType(db as never, tenant)).toBe('dance');
    expect(db.from).toHaveBeenCalledWith('organizations');
    expect(db.chain.eq).toHaveBeenCalledWith('id', tenant);
    expect(await loadBusinessNouns(db as never, tenant)).toEqual(businessNouns('dance'));
  });
  it.each([{ data: null, error: null }, { data: { business_type: 'custom' }, error: null }, { data: null, error: { code: '42501' } }])('falls back without failing the page for %j', async (result) => {
    const db = client(result);
    expect(await loadBusinessType(db as never, tenant)).toBe('gym');
    expect(await loadBusinessNouns(db as never, tenant)).toEqual(businessNouns('gym'));
  });
  it('a rejected transport also resolves gym instead of throwing', async () => {
    const db = client(null); db.chain.maybeSingle.mockRejectedValue(new Error('offline'));
    expect(await loadBusinessType(db as never, tenant)).toBe('gym');
  });
  it('a later request sees the changed type rather than a cross-request cache', async () => {
    expect(await loadBusinessType(client({ data: { business_type: 'dance' }, error: null }) as never, tenant)).toBe('dance');
    expect(await loadBusinessType(client({ data: { business_type: 'yoga' }, error: null }) as never, tenant)).toBe('yoga');
  });
});
