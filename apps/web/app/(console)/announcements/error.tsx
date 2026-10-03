'use client';
export default function AnnouncementsError({ reset }: { reset: () => void }) { return <main className="cl-page anc-page"><h1 className="cl-title">Announcements</h1><p className="cl-alert" role="alert">Announcements couldn't be loaded.</p><button type="button" className="cl-btn" onClick={reset}>Try again</button></main>; }
