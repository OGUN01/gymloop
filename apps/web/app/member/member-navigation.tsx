'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';

const MEMBER_DESTINATIONS = [
  { href: '/member', label: 'Home', matches: (path: string) => path === '/member' },
  { href: '/member/activity', label: 'Activity', matches: (path: string) => path === '/member/activity' },
  { href: '/member/my-gym', label: 'My gym', matches: (path: string) => path === '/member/my-gym' || path.startsWith('/member/messages') || path.startsWith('/member/add-ons') },
  { href: '/member/you', label: 'You', matches: (path: string) => path === '/member/you' },
] as const;

/** Four truthful member destinations with selection derived from the route. */
export function MemberNavigation() {
  const pathname = usePathname();
  return <nav className="member-tab-bar" aria-label="Member navigation">
    {MEMBER_DESTINATIONS.map((destination) => <Link key={destination.href} href={destination.href} aria-current={destination.matches(pathname) ? 'page' : undefined}>{destination.label}</Link>)}
  </nav>;
}
