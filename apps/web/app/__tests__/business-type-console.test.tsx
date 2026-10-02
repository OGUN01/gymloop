import { renderToStaticMarkup } from 'react-dom/server';
import { businessNouns, type BusinessType } from '@gymloop/shared';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const state = vi.hoisted(() => ({ type: 'gym' as BusinessType, phone: '', preview: false, count: 0 }));
const rows = () => Array.from({ length: state.count }, (_, index) => ({ id: `70000000-0000-4000-8000-00000000010${index}`, full_name: `Aarav Sharma ${index}`, phone: '+917000000101', status: 'active', member_code: `BIZ-${index}` }));
const db = { from: (table: string) => {
  const data = table === 'organizations' ? { business_type: state.type, name: 'BIZ Academy', timezone: 'Asia/Kolkata' } : table === 'members' ? [{ id: '70000000-0000-4000-8000-000000000101', full_name: 'Aarav Sharma', phone: '+917000000101', status: 'active', member_code: 'BIZ-101' }] : [];
  const result = { data, error: null };
  const single = async () => ({ data: Array.isArray(data) ? data[0] ?? null : data, error: null });
  const query = { select: () => query, eq: () => query, in: () => query, is: () => query, order: () => query, limit: () => query, maybeSingle: single, single, then: (resolve: (value: unknown) => unknown) => Promise.resolve(result).then(resolve) };
  return query;
} };
vi.mock('../../lib/identity-session', () => ({ requireAudience: async () => ({ supabase: db, identity: { kind: state.preview ? 'impersonation' : 'staff', role: 'gym_owner', tenantId: '70000000-0000-4000-8000-000000000001', userId: '70000000-0000-4000-8000-000000000901' } }) }));
vi.mock('../../lib/business-type', () => ({ loadBusinessType: async () => state.type, loadBusinessNouns: async () => businessNouns(state.type) }));
vi.mock('../../lib/members', () => ({ loadMemberSearch: async () => ({ members: rows(), phone: state.phone, errorMessage: null, nextCursor: null, pageSize: 50, filters: {}, nouns: businessNouns(state.type) }) }));
vi.mock('../../lib/supabase/server', () => ({ createServerSupabase: async () => db }));
vi.mock('../(console)/members/member-data', () => ({ loadMember: async () => ({ data: { id: '70000000-0000-4000-8000-000000000101', full_name: 'Aarav Sharma', phone: '+917000000101', status: 'active', member_code: 'BIZ-101' }, error: null }) }));
vi.mock('../../lib/membership-state', () => ({ loadMembershipStanding: async () => new Map() }));
vi.mock('../../lib/member-invite-history', () => ({ loadMemberInviteSummaries: async () => [] }));
vi.mock('../../lib/member-imports', () => ({ canImportMembers: () => true }));
vi.mock('../../lib/red-list', () => ({ loadRedList: async () => ({ cases: [], pageSize: 50, nextCursor: null, errorMessage: null, nouns: businessNouns(state.type) }) }));
const visible = (html: string) => `${html.replace(/<[^>]*>/g, ' ')} ${[...html.matchAll(/(?:aria-label|alt|title)="([^"]*)"/g)].map((match) => match[1]).join(' ')}`;
beforeEach(() => { state.type = 'gym'; state.phone = ''; state.preview = false; state.count = 0; });
describe('BIZ-013 key console renders', () => {
  it.each([
    { surface: 'roster', count: 1, noun: 'student' }, { surface: 'roster', count: 2, noun: 'students' },
    { surface: 'memberships', count: 1, noun: 'student' }, { surface: 'memberships', count: 2, noun: 'students' },
  ])('dance Tier B $surface count $count $noun', async ({ surface, count, noun }) => {
    state.type = 'dance'; state.count = count;
    const module = surface === 'roster' ? await import('../(console)/console/page') : await import('../(console)/memberships/page');
    const html = renderToStaticMarkup(await module.default({ searchParams: Promise.resolve({}) }));
    expect(visible(html)).toMatch(new RegExp(`\\b${count} ${noun}\\b`));
    expect(visible(html)).not.toMatch(new RegExp(`\\b${count} ${count === 1 ? 'students' : 'student'}\\b`));
    expect(visible(html)).not.toMatch(/\bmembers?\b/i);
  });
  it('dance membership detail backlink uses students', async () => {
    state.type = 'dance';
    const { default: Page } = await import('../(console)/memberships/[memberId]/page');
    const html = renderToStaticMarkup(await Page({ params: Promise.resolve({ memberId: '70000000-0000-4000-8000-000000000101' }), searchParams: Promise.resolve({}) }));
    expect(html).toMatch(/href="\/memberships"[^>]*>[^<]*All students|All students[\s\S]*href="\/memberships"/);
  });
  it('dance memberships phone-search recovery uses both tenant noun slots', async () => {
    state.type = 'dance'; state.phone = '7000';
    const { default: Page } = await import('../(console)/memberships/page');
    const html = renderToStaticMarkup(await Page({ searchParams: Promise.resolve({ q: state.phone }) }));
    expect(visible(html)).toContain('No student of this academy has that phone number.');
    expect(visible(html)).not.toMatch(/\b(?:gym|member)\b/i);
  });
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
