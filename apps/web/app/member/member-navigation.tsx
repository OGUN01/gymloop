'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { CalendarDays, ChartNoAxesColumn, House, ShoppingBag, UserRound } from 'lucide-react';
import { UI_TOKENS, businessNouns, humanize, type BusinessNouns } from '@gymloop/shared';

/** Primary destinations own their route descendants; secondary Gym pages select none. */
const MEMBER_DESTINATIONS = [
  { href: '/member', label: 'Home', Icon: House, iconClass: undefined, matches: (path: string) => path === '/member' || path.startsWith('/member/check-in') },
  { href: '/member/classes', label: 'Classes', Icon: CalendarDays, iconClass: undefined, matches: (path: string) => path === '/member/classes' || path.startsWith('/member/classes/') },
  { href: '/member/shop', label: 'Shop', Icon: ShoppingBag, iconClass: undefined, matches: (path: string) => path === '/member/shop' || path.startsWith('/member/shop/') },
  { href: '/member/activity', label: 'Activity', Icon: ChartNoAxesColumn, iconClass: 'member-tab-bars', matches: (path: string) => path === '/member/activity' },
  { href: '/member/you', label: 'You', Icon: UserRound, iconClass: undefined, matches: (path: string) => path === '/member/you' },
] as const;

/** Five accepted member destinations with selection derived from the route. */
export function MemberNavigation({ nouns = businessNouns(null) }: { nouns?: BusinessNouns; placeLabel?: string; placeGlyph?: 'gym' | 'building' }) {
  const pathname = usePathname();
  return <nav className="member-tab-bar" aria-label={`${humanize(nouns.member)} navigation`}>
    {MEMBER_DESTINATIONS.map(({ href, label, Icon, iconClass, matches }) => <Link key={href} href={href} aria-current={matches(pathname) ? 'page' : undefined}><Icon aria-hidden="true" className={iconClass} size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /><span>{href === '/member/classes' ? humanize(nouns.classes) : label}</span></Link>)}
  </nav>;
}
