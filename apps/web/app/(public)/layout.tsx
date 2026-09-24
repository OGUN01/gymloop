import Link from 'next/link';
import type { ReactNode } from 'react';
import { PRODUCT_NAME, PUBLISHER_NAME, PUBLIC_PAGE_PATHS, SUPPORT_EMAIL } from '@gymloop/shared';
import '../styles/public.css';

export default function PublicLayout({ children }: { children: ReactNode }) {
  return <div className="public-shell">
    <header className="public-header">
      <div className="public-header-inner">
        <Link href="/" className="brand-link">{PRODUCT_NAME}</Link>
        <Link href="/sign-in" className="public-header-link">Sign in</Link>
      </div>
    </header>
    {children}
    <footer className="public-footer">
      <div className="public-footer-inner">
        <nav aria-label="Legal and help" className="public-footer-nav">
          <Link href={PUBLIC_PAGE_PATHS.privacy}>Privacy</Link>
          <Link href={PUBLIC_PAGE_PATHS.terms}>Terms</Link>
          <Link href={PUBLIC_PAGE_PATHS.deleteAccount}>Delete account</Link>
          <Link href={PUBLIC_PAGE_PATHS.support}>Support</Link>
        </nav>
        <div className="public-footer-meta">
          <span>© 2026 {PUBLISHER_NAME}</span>
          <a href={`mailto:${SUPPORT_EMAIL}`}>{SUPPORT_EMAIL}</a>
        </div>
      </div>
    </footer>
  </div>;
}
