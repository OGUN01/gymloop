import { describe, expect, it, vi } from 'vitest';
const writes = vi.hoisted(() => vi.fn(() => { throw new Error('System category must never reach template DML'); }));
vi.mock('../../lib/identity-session', () => ({ readIdentity: async () => ({ signedIn: true, authenticatedUser: true, supabase: { from: writes }, identity: { kind: 'staff', role: 'gym_owner', tenantId: '75000000-0000-4000-8000-000000000001', userId: '75000000-0000-4000-8000-000000000901', staffId: '75000000-0000-4000-8000-000000000021' } }) }));
const { POST } = await import('../api/message-templates/route');
describe('ANC-022 feature-owned categories cannot become gym templates', () => {
  it.each(['announcement', 'class_update'])('%s is refused 422 before both create and update', async (category) => {
    writes.mockClear();
    for (const templateId of [undefined, '75000000-0000-4000-8000-000000000701']) {
      const response = await POST(new Request('https://gymloop.test/api/message-templates', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ templateId, key: 'gym_news', channel: 'in_app', locale: 'en', category, body: 'Plain template', isActive: true }) }));
      expect(response.status).toBe(422); expect(response.headers.get('cache-control')).toContain('no-store');
    }
    expect(writes).not.toHaveBeenCalled();
  });
});
