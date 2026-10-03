import { beforeEach, describe, expect, it, vi } from 'vitest';

const guard = vi.hoisted(() => vi.fn());
vi.mock('../identity-session', () => ({ requireAudience: guard }));

const original = { userId: 'user-original', tenantId: 'tenant-original', memberId: 'member-original' };
function current() {
  return { identity: { kind: 'member' as const, ...original }, supabase: { marker: Symbol('fresh caller') } };
}

describe('fresh original-member action caller', () => {
  beforeEach(() => guard.mockReset());

  it('calls the member audience guard on every invocation and returns the current object', async () => {
    const { requireOriginalMember } = await import('../member-action-caller');
    const first = current();
    const second = current();
    guard.mockResolvedValueOnce(first).mockResolvedValueOnce(second);
    expect(await requireOriginalMember(original)).toBe(first);
    expect(await requireOriginalMember(original)).toBe(second);
    expect(guard.mock.calls).toEqual([['member'], ['member']]);
  });

  it.each(['userId', 'tenantId', 'memberId'] as const)('refuses an independently changed %s', async (field) => {
    const { requireOriginalMember } = await import('../member-action-caller');
    const caller = current();
    caller.identity[field] = 'changed';
    guard.mockResolvedValue(caller);
    expect(await requireOriginalMember(original)).toBeNull();
    expect(guard).toHaveBeenCalledWith('member');
  });

  it('converts fresh guard refusal into null without retaining an earlier caller', async () => {
    const { requireOriginalMember } = await import('../member-action-caller');
    const caller = current();
    guard.mockResolvedValueOnce(caller).mockRejectedValueOnce(new Error('audience refused'));
    expect(await requireOriginalMember(original)).toBe(caller);
    expect(await requireOriginalMember(original)).toBeNull();
    expect(guard.mock.calls).toEqual([['member'], ['member']]);
  });
});
