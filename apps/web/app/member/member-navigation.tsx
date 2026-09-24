'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { ChartNoAxesColumn, Dumbbell, House, UserRound } from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';

/** `iconClass` names the glyph's own current-state treatment: the dumbbell sits level, the line bars thicken when current. */
const MEMBER_DESTINATIONS = [
  { href: '/member', label: 'Home', Icon: House, iconClass: undefined, matches: (path: string) => path === '/member' || path.startsWith('/member/check-in') },
  { href: '/member/activity', label: 'Activity', Icon: ChartNoAxesColumn, iconClass: 'member-tab-bars', matches: (path: string) => path === '/member/activity' },
  { href: '/member/my-gym', label: 'My gym', Icon: Dumbbell, iconClass: 'member-tab-level', matches: (path: string) => path === '/member/my-gym' || path.startsWith('/member/messages') || path.startsWith('/member/add-ons') },
  { href: '/member/you', label: 'You', Icon: UserRound, iconClass: undefined, matches: (path: string) => path === '/member/you' },
] as const;

/** Four truthful member destinations with selection derived from the route. */
export function MemberNavigation() {
  const pathname = usePathname();
  return <nav className="member-tab-bar" aria-label="Member navigation">
    {MEMBER_DESTINATIONS.map(({ href, label, Icon, iconClass, matches }) => <Link key={href} href={href} aria-current={matches(pathname) ? 'page' : undefined}><Icon aria-hidden="true" className={iconClass} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><span>{label}</span></Link>)}
  </nav>;
}
