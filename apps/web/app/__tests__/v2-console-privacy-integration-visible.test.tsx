import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';
import { ANNOUNCEMENT_PRIVACY_SENTENCE, type GymloopIdentity } from '@gymloop/shared';

// Frozen CLS/ANC/BIZ integration contract; no implementation consulted.
const state = vi.hoisted(() => ({ identity: null as GymloopIdentity | null, businessType: 'gym' as string, pathname: '/console/check-in' }));
const supabase = vi.hoisted(() => ({ from: (table: string) => {
  const builder = {
    select: () => builder, eq: () => builder,
    maybeSingle: async () => ({ data: table === 'organizations'
      ? { name: 'Integration Business', gym_code: 'INT001', timezone: 'Asia/Kolkata', business_type: state.businessType }
      : { expires_at: '2099-01-01T00:00:00Z' }, error: null }),
  };
  return builder;
} }));
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ identity: state.identity, supabase }) }));
vi.mock('next/navigation', () => ({ usePathname: () => state.pathname, redirect: () => { throw new Error('unexpected redirect'); } }));
async function links(identity: GymloopIdentity) {
  state.identity = identity;
  const Layout = (await import('../(console)/layout')).default;
  const html = renderToStaticMarkup(await Layout({ children: 'Integration content' }));
  const nav = /<nav\b[^>]*aria-label="Console navigation"[^>]*>([\s\S]*?)<\/nav>/.exec(html)?.[1];
  expect(nav, 'actual console navigation landmark').toBeDefined();
  return { html, items: [...(nav ?? '').matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map(match => ({
    href: /href="([^"]+)"/.exec(match[1] ?? '')?.[1],
    label: (match[2] ?? '').replace(/<[^>]*>/g, '').trim(),
    current: /aria-current="page"/.test(match[1] ?? ''),
  })) };
}
const staff = (role: 'gym_owner' | 'gym_manager' | 'front_desk' | 'trainer'): GymloopIdentity =>
  ({ kind: 'staff', userId: 'integration-user', tenantId: 'integration-tenant', staffId: 'integration-staff', role });
const preview: GymloopIdentity = { kind: 'impersonation', userId: 'integration-support', tenantId: 'integration-tenant', impersonationSessionId: 'integration-preview' };
const verticals = [['gym', 'Classes'], ['dance', 'Batches'], ['yoga', 'Classes'], ['martial_arts', 'Classes'], ['studio', 'Classes']] as const;
describe('frozen console Classes and Announcements integration', () => {
  it.each(['gym_owner', 'gym_manager', 'front_desk', 'trainer'] as const)('preserves %s feature visibility', async role => {
    state.businessType = 'gym'; state.pathname = '/console/check-in';
    const { items } = await links(staff(role));
    expect(items.find(item => item.href === '/classes')?.label).toBe('Classes');
    expect(items.findIndex(item => item.href === '/classes')).toBe(items.findIndex(item => item.href === '/console/check-in') + 1);
    expect(items.some(item => item.href === '/announcements')).toBe(role !== 'trainer');
    if (role !== 'trainer') expect(items.find(item => item.href === '/announcements')?.label).toBe('Announcements');
  });
  it.each(verticals)('uses the %s class noun in actual navigation', async (businessType, label) => {
    state.businessType = businessType;
    expect((await links(staff('gym_owner'))).items.find(item => item.href === '/classes')?.label).toBe(label);
  });
  it('keeps preview read-only while exposing the permitted announcement reader', async () => {
    state.businessType = 'gym';
    const { html, items } = await links(preview);
    expect(items.find(item => item.href === '/announcements')?.label).toBe('Announcements');
    expect(html).toMatch(/Read-only preview|End preview/);
    expect(items.some(item => item.href === '/team')).toBe(false);
    expect(items.some(item => item.href === '/imports')).toBe(false);
  });
  it.each(['/classes', '/classes/session-1', '/announcements', '/announcements/item-1'])('selects the feature destination at %s', async pathname => {
    state.businessType = 'gym'; state.pathname = pathname;
    const { items } = await links(staff('gym_owner'));
    expect(items.filter(item => item.current).map(item => item.href)).toEqual([pathname.startsWith('/classes') ? '/classes' : '/announcements']);
  });
});
describe('public announcement read privacy disclosure', () => {
  it('renders the exact frozen ANC sentence on the public policy', async () => {
    const Page = (await import('../(public)/privacy/page')).default;
    const html = renderToStaticMarkup(await Page());
    const text = html.replace(/<[^>]*>/g, '').replace(/&#x27;/g, "'").replace(/&quot;/g, '"').replace(/&amp;/g, '&');
    const sentence = 'When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.';
    expect(ANNOUNCEMENT_PRIVACY_SENTENCE).toBe(sentence);
    expect(text).toContain(sentence);
  });
});
