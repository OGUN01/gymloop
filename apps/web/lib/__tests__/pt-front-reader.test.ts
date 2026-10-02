import { describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
const media = vi.hoisted(() => ({ calls: [] as unknown[] }));
vi.mock('../media', () => ({ memberMediaUrl: async (...args: unknown[]) => { media.calls.push(args); return 'https://media.example/verified'; } }));
const asset = '73000000-0000-4000-8000-000000000007';
describe('PTF-003 member loader safe read seam', () => {
  it('calls all five member projections under the supplied caller and does not read private tables', async () => {
    const calls: string[] = [];
    const client = {
      rpc: async (name: string) => {
        calls.push(name);
        return { error: null, data: name === 'read_member_trainers' ? [{ trainer_key: '73000000-0000-4000-8000-000000000008', display_name: 'Rohit', qualification: 'Certified', bio: '', specialities: [], image_asset_id: asset, branch_name: null, is_profile_listed: true }] : [] };
      },
      from: () => { throw new Error('Member loader must use safe feature projections'); },
    };
    media.calls = [];
    const { loadMemberTraining } = await import('../training');
    const result = await loadMemberTraining(client as unknown as SupabaseClient);
    expect(calls.filter((name) => name === 'read_member_pt_sessions')).toHaveLength(2);
    expect(calls).toContain('read_member_trainers'); expect(calls).toContain('read_member_programmes'); expect(calls).toContain('read_member_pt_packs');
    expect(media.calls).toEqual([[client, asset]]);
    const serialized = JSON.stringify(result);
    expect(serialized).toContain('https://media.example/verified');
    for (const key of ['image_asset_id', 'storage_key', 'published_key', 'staging_key', 'etag', 'staff_id', 'user_id']) expect(serialized).not.toContain(key);
  });
  it('PTF-018 retains the expired 7-unused / 2-booked facts without inferred attendance', async () => {
    const row = { order_id: '73000000-0000-4000-8000-000000000001', programme_name: 'Strength', trainer_key: '73000000-0000-4000-8000-000000000008', trainer_name: 'Rohit', sessions_total: 10, sessions_used: 3, sessions_scheduled: 2, sessions_remaining: 7, starts_on: '2026-09-01', expires_on: '2026-09-30', state: 'expired', can_book: false, timezone: 'Asia/Kolkata' };
    const client = { rpc: async (name: string) => ({ data: name === 'read_member_pt_packs' ? [row] : [], error: null }) };
    const { loadMemberTraining } = await import('../training');
    const result = await loadMemberTraining(client as unknown as SupabaseClient);
    // Result property names are not frozen; locate the pack by its public id rather than invent a container API.
    const serialized = JSON.stringify(result);
    expect(serialized).toContain('expired'); expect(serialized).toContain(row.order_id);
    const visit = (value: unknown): Record<string, unknown>[] => {
      if (Array.isArray(value)) return value.flatMap(visit);
      if (value && typeof value === 'object') return [value as Record<string, unknown>, ...Object.values(value).flatMap(visit)];
      return [];
    };
    const pack = visit(result).find((value) => Object.values(value).includes(row.order_id));
    expect(pack).toBeDefined();
    expect(pack?.sessionsRemaining ?? pack?.sessions_remaining).toBe(7);
    expect(pack?.sessionsScheduled ?? pack?.sessions_scheduled).toBe(2);
    expect(pack?.sessionsUsed ?? pack?.sessions_used).toBe(3);
    expect(pack?.canBook ?? pack?.can_book).toBe(false);
  });
});
