import type { ReactNode } from 'react';
import Link from 'next/link';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signOut } from '../lib/auth-actions';
import { ThemeControl } from './theme-provider';

/** Shared account header for the distinct gym, member and platform audiences. */
export function AccountFrame({ children, home, label }: {
  children: ReactNode; home: string; label: string;
}) {
  return (
    <div className="min-h-screen bg-[var(--gymloop-color-canvas)] text-[var(--gymloop-color-primary-text)]">
      <header className="gymloop-glass account-header">
        <Link href={home} className="brand-link">{PRODUCT_NAME}</Link>
        <span className="account-label">{label}</span>
        <div className="account-actions">
          <ThemeControl />
          <form action={signOut}><button type="submit" className="sign-out-button">Sign out</button></form>
        </div>
      </header>
      {children}
    </div>
  );
}
