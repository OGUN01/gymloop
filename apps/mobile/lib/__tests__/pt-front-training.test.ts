import { describe, expect, it, vi } from 'vitest';
import type { SupabaseClient } from '@supabase/supabase-js';
vi.mock('../api', () => ({ api: { post: async () => ({ ok: false, error: { code: 'asset_not_found', message: "That isn't available." } }) } }));

describe('PTF-003/028 native caller-bound reads', () => {
  it('uses the passed member client for the five projections and never private tables', async () => {
    const calls: string[] = [];
    const client = {
      rpc: async (name: string) => { calls.push(name); return { data: [], error: null }; },
      from: () => { throw new Error('Private trainer lookup is outside the member boundary'); },
    };
    const { loadTraining } = await import('../training');
    await loadTraining(client as unknown as SupabaseClient);
    expect(calls).toContain('read_member_trainers'); expect(calls).toContain('read_member_programmes'); expect(calls).toContain('read_member_pt_packs');
    expect(calls.filter((name) => name === 'read_member_pt_sessions')).toHaveLength(2);
  });
  it('does not return a previous member pack when a new caller loads', async () => {
    const pack = { order_id: '73000000-0000-4000-8000-000000000001', programme_name: 'Strength', trainer_key: '73000000-0000-4000-8000-000000000008', trainer_name: 'Rohit', sessions_total: 10, sessions_used: 3, sessions_scheduled: 2, sessions_remaining: 7, starts_on: '2026-09-01', expires_on: '2026-09-30', state: 'expired', can_book: false, timezone: 'Asia/Kolkata' };
    const first = { rpc: async (name: string) => ({ data: name === 'read_member_pt_packs' ? [pack] : [], error: null }) };
    const second = { rpc: async () => ({ data: [], error: null }) };
    const { loadTraining } = await import('../training');
    const a = await loadTraining(first as unknown as SupabaseClient);
    const b = await loadTraining(second as unknown as SupabaseClient);
    expect(JSON.stringify(a)).toContain(pack.order_id);
    expect(JSON.stringify(b)).not.toContain(pack.order_id);
    expect(JSON.stringify(b)).not.toContain('Strength');
  });
});
