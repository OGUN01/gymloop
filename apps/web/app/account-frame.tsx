import type { ReactNode } from 'react';
import Link from 'next/link';
import { PRODUCT_NAME } from '@gymloop/shared';
import { signOut } from '../lib/auth-actions';

/** Shared account header for the distinct gym, member and platform audiences. */
export function AccountFrame({ children, home, label }: {
  children: ReactNode; home: string; label: string;
}) {
  return (
    <div className="min-h-screen">
      <header className="flex items-center justify-between gap-4 border-b border-neutral-200 px-6 py-3">
        <Link href={home} className="font-semibold">{PRODUCT_NAME}</Link>
        <span className="text-sm text-neutral-600">{label}</span>
        <form action={signOut}>
          <button type="submit" className="text-sm text-neutral-600 underline">Sign out</button>
        </form>
      </header>
      {children}
    </div>
  );
}
