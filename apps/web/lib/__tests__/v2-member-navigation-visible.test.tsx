import { renderToStaticMarkup } from 'react-dom/server';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { MemberNavigation } from '../../app/member/member-navigation';
import { ClassesSegments } from '../../app/member/classes/segments';

const location = vi.hoisted(() => ({ pathname: '/member' }));
vi.mock('next/navigation', () => ({ usePathname: () => location.pathname }));

function links() {
  const markup = renderToStaticMarkup(<MemberNavigation />);
  return [...markup.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map(match => ({
    href: /href="([^"]+)"/.exec(match[1] ?? '')?.[1],
    label: (match[2] ?? '').replace(/<[^>]*>/g, '').trim(),
    current: /aria-current="page"/.test(match[1] ?? ''),
  }));
}

describe('accepted member information architecture — web', () => {
  beforeEach(() => { location.pathname = '/member'; });

  it('mounts the five accepted destinations in their fixed order', () => {
    expect(links().map(link => [link.label, link.href])).toEqual([
      ['Home', '/member'], ['Classes', '/member/classes'], ['Shop', '/member/shop'],
      ['Activity', '/member/activity'], ['You', '/member/you'],
    ]);
  });

  it.each([
    ['/member', 'Home'], ['/member/classes', 'Classes'],
    ['/member/classes/training', 'Classes'],
    ['/member/classes/training/book/73000000-0000-4000-8000-000000000001', 'Classes'],
    ['/member/shop', 'Shop'], ['/member/activity', 'Activity'], ['/member/you', 'You'],
  ])('selects exactly the owning destination for %s', (pathname, label) => {
    location.pathname = pathname;
    expect(links().filter(link => link.current).map(link => link.label)).toEqual([label]);
  });
});

describe('accepted Classes and Training route control — web', () => {
  it.each(['classes', 'training'] as const)('mounts both real routes with %s selected', current => {
    const markup = renderToStaticMarkup(<ClassesSegments current={current} />);
    const anchors = [...markup.matchAll(/<a\b([^>]*)>([\s\S]*?)<\/a>/g)].map(match => ({
      href: /href="([^"]+)"/.exec(match[1] ?? '')?.[1],
      label: (match[2] ?? '').replace(/<[^>]*>/g, '').trim(),
      current: /aria-current="page"/.test(match[1] ?? ''),
    }));
    expect(anchors.map(anchor => [anchor.label, anchor.href])).toEqual([
      ['Classes', '/member/classes'], ['Training', '/member/classes/training'],
    ]);
    expect(anchors.filter(anchor => anchor.current).map(anchor => anchor.label))
      .toEqual([current === 'classes' ? 'Classes' : 'Training']);
  });
});
