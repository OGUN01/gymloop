import Link from 'next/link';
import type { ReactNode } from 'react';

/** Recoverable route failure: says what happened in plain words and offers the framework retry. */
export function RouteError({ reset, home, homeLabel, className = 'cl-page' }: { reset: () => void; home: string; homeLabel: string; className?: string }) {
  return <main className={className}>
    <div className="route-state-message" role="alert">
      <p className="cl-eyebrow">Something went wrong</p>
      <h1 className="cl-title">This page did not load</h1>
      <p className="cl-lede">Nothing was changed. Check the connection and try again; if it keeps happening, tell the gym&rsquo;s administrator.</p>
      <div className="cl-actions"><button type="button" className="cl-btn cl-btn--primary" onClick={reset}>Try again</button><Link className="cl-btn" href={home}>{homeLabel}</Link></div>
    </div>
  </main>;
}

/** Missing route or record, with a real way back. */
export function RouteNotFound({ home, homeLabel, title = 'Page not found', className = 'cl-page', brand, footer }: { home: string; homeLabel: string; title?: string; className?: string; brand?: ReactNode; footer?: ReactNode }) {
  return <main className={className}>
    {brand}
    <div className="route-state-message">
      <p className="cl-eyebrow">404</p>
      <h1 className="cl-title">{title}</h1>
      <p className="cl-lede">The address may be old, or the record may belong to a different gym.</p>
      <div className="cl-actions"><Link className="cl-btn cl-btn--primary" href={home}>{homeLabel}</Link></div>
    </div>
    {footer}
  </main>;
}
