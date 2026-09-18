'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { useEffect, useState } from 'react';

type NavigationItem = { href: string; label: string };

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
  const current = items.reduce<NavigationItem | undefined>((longest, item) => (
    pathname === item.href || pathname.startsWith(`${item.href}/`)
      ? (longest === undefined || item.href.length > longest.href.length ? item : longest)
      : longest
  ), undefined);

  return (
    <details className="owner-navigation-disclosure" open={open} onToggle={(event) => setOpen(event.currentTarget.open)}>
      <summary>{current?.label ?? 'Console navigation'}</summary>
      <nav className="owner-navigation" aria-label="Console navigation">
        {items.map((item) => <Link href={item.href} key={item.href} aria-current={current?.href === item.href ? 'page' : undefined}>
          {item.label}
        </Link>)}
      </nav>
    </details>
  );
}
