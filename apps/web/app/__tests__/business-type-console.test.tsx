import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ type: 'gym', phone: '', preview: false }));
const db = { from: () => {
  const result = { data: { business_type: state.type, name: 'BIZ Academy' }, error: null };
  const query = { select: () => query, eq: () => query, maybeSingle: async () => result, single: async () => result };
  return query;
} };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: db, identity: { kind: state.preview ? 'impersonation' : 'staff', role: 'gym_owner', tenantId: '70000000-0000-4000-8000-000000000001', userId: '70000000-0000-4000-8000-000000000901' } }) }));
vi.mock('../../lib/business-type', () => ({ loadBusinessType: async () => state.type, loadBusinessNouns: async () => businessNouns(state.type) }));
vi.mock('../../lib/members', () => ({ loadMemberSearch: async () => ({ members: [], phone: state.phone, errorMessage: null, nextCursor: null, pageSize: 50, filters: {}, nouns: businessNouns(state.type) }) }));
vi.mock('../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../../lib/member-invite-history', () => ({ loadMemberInviteSummaries: async () => new Map() }));
vi.mock('../../lib/member-imports', () => ({ canImportMembers: () => true }));
vi.mock('../../lib/red-list', () => ({ loadRedList: async () => ({ cases: [], pageSize: 50, nextCursor: null, errorMessage: null, nouns: businessNouns(state.type) }) }));
const visible = (html: string) => `${html.replace(/<[^>]*>/g, ' ')} ${[...html.matchAll(/(?:aria-label|alt|title)="([^"]*)"/g)].map((match) => match[1]).join(' ')}`;
beforeEach(() => { state.type = 'gym'; state.phone = ''; state.preview = false; });
describe('BIZ-013 key console renders', () => {
  it.each([false, true])('dance roster chrome and empty state vary in preview=%s', async (preview) => {
    state.type = 'dance'; state.preview = preview;
    const { default: Page } = await import('../(console)/console/page');
    const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({}) }));
    expect(visible(html)).not.toMatch(/\b(gym|member|members|trainer)\b/i);
    expect(html).toContain('students');
  });
  it('dance phone-search empty state varies', async () => {
    state.type = 'dance'; state.phone = '7000';
    const { default: Page } = await import('../(console)/console/page');
    const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({ q: state.phone }) }));
    expect(visible(html)).not.toMatch(/\b(gym|member|members|trainer)\b/i);
    expect(html).toContain('academy');
  });
  it.each(['already_being_contacted', 'case_closed'])('dance red-list %s sentence varies', async (error) => {
    state.type = 'dance';
    const { default: Page } = await import('../(console)/red-list/page');
    const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({ error }) }));
    expect(visible(html)).not.toMatch(/\b(gym|member|members|trainer)\b/i);
    expect(html).toContain('student');
  });
  it('gym empty roster keeps its existing sentences', async () => {
    const { default: Page } = await import('../(console)/console/page');
    const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({}) }));
    expect(html).toContain('No members yet'); expect(html).toContain('Add the first one, or import your existing list.');
    expect(html).toContain('Add a member'); expect(html).toContain('Import members');
  });
});
