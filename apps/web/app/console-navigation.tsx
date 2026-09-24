'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';
import {
  Boxes, CalendarCheck, CreditCard, IdCard, House, LogIn, MessageSquare, Target, Upload, Users, type LucideIcon,
} from 'lucide-react';
import { UI_TOKENS } from '@gymloop/shared';

type NavigationItem = { href: string; label: string };

const ICONS: Record<string, LucideIcon> = {
  '/dashboard': House, '/console/check-in': LogIn, '/red-list': CalendarCheck, '/console': Users, '/memberships': IdCard,
  '/payments': CreditCard, '/messages': MessageSquare, '/add-ons': Boxes, '/leads': Target, '/imports': Upload,
};

/** Presentation-only console navigation; server loaders remain route authority. */
export function ConsoleNavigation({ items }: { items: readonly NavigationItem[] }) {
  const pathname = usePathname();
  const [open, setOpen] = useState(true);
  useEffect(() => {
    const media = window.matchMedia('(max-width: 40rem)');
    const sync = () => setOpen(!media.matches);
    sync();
    media.addEventListener('change', sync);
    return () => media.removeEventListener('change', sync);
  }, []);
  const path = /^\/members(?:\/|$)/.test(pathname) ? '/console' : pathname;
  const current = items.reduce<NavigationItem | undefined>((longest, item) => (
    path === item.href || path.startsWith(`${item.href}/`)
      ? (longest === undefined || item.href.length > longest.href.length ? item : longest)
      : longest
  ), undefined);

  return (
    <details className="owner-navigation-disclosure" open={open} onToggle={(event) => setOpen(event.currentTarget.open)}>
      <summary>{current?.label ?? 'Menu'}</summary>
      <nav className="owner-navigation" aria-label="Console navigation">
        {items.map((item) => {
          const Icon = ICONS[item.href];
          return <Link href={item.href} key={item.href} aria-current={current?.href === item.href ? 'page' : undefined}>
            {Icon === undefined ? null : <Icon aria-hidden="true" size={UI_TOKENS.icons.navigationSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />}
            {item.label}
          </Link>;
        })}
      </nav>
    </details>
  );
}
