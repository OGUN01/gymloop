import type { ReactNode } from 'react';
import Link from 'next/link';
import { LogOut } from 'lucide-react';
import { PRODUCT_NAME, UI_TOKENS } from '@gymloop/shared';
import { signOut } from '../lib/auth-actions';
import { ThemeControl } from './theme-provider';

function SignOutButton() {
  return <form action={signOut}><button type="submit" className="sign-out-button">
    <LogOut aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />Sign out
  </button></form>;
}

/** Shared account frame for the distinct gym, member and platform audiences. */
export function AccountFrame({ children, home, label, navigation, context }: {
  children: ReactNode; home: string; label: string; navigation?: ReactNode;
  context?: { primary: string; secondary: string };
}) {
  if (navigation !== undefined && context !== undefined) {
    return (
      <div className="owner-account-frame">
        <aside className="owner-sidebar">
          <Link href={home} className="brand-link">{PRODUCT_NAME}</Link>
          <div className="owner-context">
            <strong>{context.primary}</strong>
            <span>{context.secondary}</span>
          </div>
          {navigation}
          <div className="owner-account-actions">
            <ThemeControl />
            <span className="owner-account-label">{label}</span>
            <SignOutButton />
          </div>
        </aside>
        <div className="owner-shell-content">{children}</div>
      </div>
    );
  }

  return (
    <div className="min-h-screen bg-canvas text-ink">
      <header className="account-header">
        <Link href={home} className="brand-link">{PRODUCT_NAME}</Link>
        <span className="account-label">{label}</span>
        <div className="account-actions">
          <ThemeControl />
          <SignOutButton />
        </div>
      </header>
      {children}
    </div>
  );
}
