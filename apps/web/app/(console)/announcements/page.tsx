import Link from 'next/link';
import { ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_READ_FOOTNOTE } from '@gymloop/shared';
import { announcementConsole } from '../../../lib/announcement-console';
import { loadAnnouncementList } from '../../../lib/announcements';
import { gymTimeLabel } from '../../../lib/time';
import { AnnouncementOffline } from './announcement-offline';
const statuses = { live: 'Live', draft: 'Draft', ended: 'Ended', taken_down: 'Taken down' } as const;
export default async function AnnouncementsPage({ searchParams }: { searchParams?: Promise<{ cursor?: string; filter?: string }> }) {
  const context = await announcementConsole(); const query = await searchParams ?? {}; const list = await loadAnnouncementList(context.supabase, query.cursor);
  const rows = query.filter ? list.rows.filter((row) => row.displayStatus === query.filter) : list.rows;
  return <main className="cl-page anc-page"><header className="cl-page-header"><div><p className="cl-eyebrow">Home</p><h1 className="cl-title">Announcements</h1></div>{!context.preview ? <Link className="cl-btn cl-btn--primary" href="/announcements/new">New announcement</Link> : null}</header><AnnouncementOffline />
    <nav className="anc-filters" aria-label="Announcement status">{[['', 'All'], ['live', 'Live'], ['draft', 'Drafts'], ['ended', 'Ended']].map(([key, label]) => <Link key={key} href={key ? `/announcements?filter=${key}` : '/announcements'} aria-current={(query.filter ?? '') === key ? 'page' : undefined}>{label}</Link>)}</nav>
    {list.errorMessage ? <p className="cl-alert" role="alert">{list.errorMessage} <Link href="/announcements">Try again</Link></p> : rows.length ? <ul className="anc-list">{rows.map((row) => <li key={row.announcementId}><Link href={`/announcements/${row.announcementId}`}><span className="cl-status">{statuses[row.displayStatus]}</span><strong>{row.title}</strong><span>{ANNOUNCEMENT_KIND_LABELS[row.kind]} · {row.audience === 'all_members' ? `All ${context.nouns.members}` : `${row.segmentMemberStatuses?.join(', ')} · ${row.segmentMembership?.replace('_', ' ')}`}</span><span>{gymTimeLabel(row.publishedAt ?? row.createdAt, context.timezone)}</span><span>Read by {row.readCurrent}{row.audienceCount !== null ? ` of ${row.audienceCount}` : ''}</span></Link></li>)}</ul> : <p>{query.filter ? query.filter === 'live' ? 'Nothing live right now.' : 'No announcements with this status.' : "No announcements yet. Post a closure, a new class or an offer and it appears on members' Home."}</p>}
    <p className="cl-muted">{ANNOUNCEMENT_READ_FOOTNOTE}</p>{list.nextCursor ? <Link className="cl-btn" href={`/announcements?cursor=${encodeURIComponent(list.nextCursor)}${query.filter ? `&filter=${encodeURIComponent(query.filter)}` : ''}`}>Load older</Link> : null}
  </main>;
}
