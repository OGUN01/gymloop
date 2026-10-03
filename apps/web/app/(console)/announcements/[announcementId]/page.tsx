import Link from 'next/link';
import { notFound } from 'next/navigation';
import { ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_READ_FOOTNOTE, announcementReachSentence } from '@gymloop/shared';
import { announcementConsole } from '../../../../lib/announcement-console';
import { loadAnnouncementDetail } from '../../../../lib/announcements';
import { isUuid } from '../../../../lib/keyset';
import { mediaDisplayUrl } from '../../../../lib/media';
import { gymTimeLabel } from '../../../../lib/time';
import { AnnouncementActions } from '../announcement-actions';
import { AnnouncementOffline } from '../announcement-offline';
export default async function AnnouncementDetailPage({ params, searchParams }: { params: Promise<{ announcementId: string }>; searchParams?: Promise<{ review?: string }> }) {
  const context = await announcementConsole(); const { announcementId } = await params; if (!isUuid(announcementId)) notFound();
  const detail = await loadAnnouncementDetail(context.supabase, announcementId); if (!detail) notFound();
  const query = await searchParams; const header = detail.announcement; const current = detail.versions[0]; if (!current) notFound();
  let imageUrl: string | null = null; if (current.imageAssetId) { try { imageUrl = await mediaDisplayUrl(context.supabase, current.imageAssetId); } catch { /* Released historic images keep their placeholder. */ } }
  return <main className="cl-page anc-page"><Link href="/announcements">Announcements</Link><h1 className="cl-title">{current.title}</h1><AnnouncementOffline /><p className="cl-status">{header.displayStatus === 'taken_down' ? 'Taken down' : header.displayStatus === 'live' ? 'Live' : header.displayStatus === 'draft' ? 'Draft' : 'Ended'}</p>
    <section className="anc-content" aria-label="Member preview"><p>{ANNOUNCEMENT_KIND_LABELS[header.kind]} · {header.currentVersion > 1 ? 'Edited' : 'Posted'} {gymTimeLabel(header.currentVersion > 1 ? current.createdAt : header.publishedAt ?? header.createdAt, context.timezone)}</p><h2>{current.title}</h2><p className="anc-body">{current.body}</p>{imageUrl ? <img src={imageUrl} alt="" className="anc-image" /> : current.imageAssetId ? <p>Image unavailable</p> : null}</section>
    {header.audienceCount !== null ? <p>{announcementReachSentence({ kind: header.kind, count: header.audienceCount, nouns: context.nouns })}</p> : null}<p>Read by {header.readCurrent}{header.audienceCount !== null ? ` of ${header.audienceCount}` : ''} · {header.readAny} opened any version</p><p className="cl-muted">{ANNOUNCEMENT_READ_FOOTNOTE}</p>
    {!context.preview ? <>{header.displayStatus === 'draft' || (header.displayStatus === 'live' && context.canPublish) ? <Link className="cl-btn" href={`/announcements/${announcementId}/edit`}>Edit {header.status === 'draft' ? 'draft' : 'announcement'}</Link> : null}<AnnouncementActions detail={detail} nouns={context.nouns} timezone={context.timezone} canPublish={context.canPublish} review={query?.review === '1'} /></> : null}
    <section aria-label="Version history"><h2>Versions</h2>{detail.versions.map((version) => <article key={version.versionNo} className="anc-version"><h3>Version {version.versionNo} · {version.title}</h3><p>{gymTimeLabel(version.createdAt, context.timezone)}</p>{version.changeNote ? <p>{version.changeNote}</p> : null}<p className="anc-body">{version.body}</p><p>Read by {version.readCount}</p>{version.imageAssetId && version.versionNo !== header.currentVersion ? <p>Historical image</p> : null}</article>)}</section>
  </main>;
}
