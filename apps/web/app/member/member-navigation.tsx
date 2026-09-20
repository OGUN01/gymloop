'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { Activity, CircleUserRound, Dumbbell, Home } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';

const MEMBER_DESTINATIONS = [
  { href: '/member', label: 'Home', matches: (path: string) => path === '/member' || path.startsWith('/member/check-in') },
  { href: '/member/activity', label: 'Activity', matches: (path: string) => path === '/member/activity' },
  { href: '/member/my-gym', label: 'My gym', matches: (path: string) => path === '/member/my-gym' || path.startsWith('/member/messages') || path.startsWith('/member/add-ons') },
  { href: '/member/you', label: 'You', matches: (path: string) => path === '/member/you' },
] as const;

/** Four truthful member destinations with selection derived from the route. */
export function MemberNavigation() {
  const pathname = usePathname();
  const icons = [Home, Activity, Dumbbell, CircleUserRound] as const;
  return <nav className="member-tab-bar" aria-label="Member navigation">
    {MEMBER_DESTINATIONS.map((destination, index) => { const Icon = icons[index] ?? Home; return <Link key={destination.href} href={destination.href} aria-current={destination.matches(pathname) ? 'page' : undefined}><Icon aria-hidden="true" size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><span>{destination.label}</span></Link>; })}
  </nav>;
}
