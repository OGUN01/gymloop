import { describe, expect, it, vi } from 'vitest';
const media = vi.hoisted(() => ({ resolve: vi.fn(async () => 'https://images.test/published/photo') }));
vi.mock('server-only', () => ({}));
vi.mock('../media', () => ({ memberMediaUrl: media.resolve }));
import { loadMemberShop } from '../shop';
const id = '72000000-0000-4000-8000-000000000001';
const item = { item_id: id, section: 'products', name: 'Protein', description: 'Tub', price_paise: '9007199254740993', currency: 'INR', gst_rate_bp: 1800, validity_days: 30, cancellation_terms: 'Ask desk', quote_version: id, category_id: null, category_name: null, image_asset_id: id, availability: 'available', available_quantity: 2 };
describe('SHP member read adapter', () => {
  it('uses caller RPCs, preserves money text and returns imageUrl only', async () => {
    const rpc = vi.fn(async (name: string) => ({ data: name === 'read_member_shop' ? [item] : [], error: null }));
    const from = vi.fn(() => { throw new Error('member must not query private media metadata'); });
    const client = { rpc, from };
    const response = await loadMemberShop(client as never, id);
    expect(rpc.mock.calls.map(([name]) => name).sort()).toEqual(['read_member_shop', 'read_member_shop_reservations']); expect(from).not.toHaveBeenCalled();
    expect(media.resolve).toHaveBeenCalledWith(client, id); expect(response.items[0]).toMatchObject({ itemId: id, pricePaise: '9007199254740993', imageUrl: 'https://images.test/published/photo' });
    for (const forbidden of ['objectKey', 'object_key', 'staging_object_key', 'published_etag', 'verified_source_etag', 'image_asset_id', 'stock_quantity', 'staff_id']) expect(response.items[0]).not.toHaveProperty(forbidden);
  });
  it('truncates at 200 without changing server order', async () => {
    const rows = Array.from({ length: 201 }, (_, index) => ({ ...item, name: `Product ${index}`, image_asset_id: null }));
    const response = await loadMemberShop({ rpc: async (name: string) => ({ data: name === 'read_member_shop' ? rows : [], error: null }) } as never, id);
    expect(response.truncated).toBe(true); expect(response.items).toHaveLength(200); expect(response.items.at(-1)?.name).toBe('Product 199');
  });
  it('a failed catalogue RPC remains an error instead of a misleading empty success', async () => {
    await expect(loadMemberShop({ rpc: async () => ({ data: null, error: { code: '42501', message: 'private' } }) } as never, id)).rejects.toThrow();
  });
});
