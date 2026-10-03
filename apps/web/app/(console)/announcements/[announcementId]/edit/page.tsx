import Link from 'next/link';
import { notFound } from 'next/navigation';
import { announcementConsole } from '../../../../../lib/announcement-console';
import { loadAnnouncementDetail } from '../../../../../lib/announcements';
import { isUuid } from '../../../../../lib/keyset';
import { AnnouncementComposer } from '../../announcement-composer';
export default async function EditAnnouncementPage({ params }: { params: Promise<{ announcementId: string }> }) { const context = await announcementConsole(); const { announcementId } = await params; if (!isUuid(announcementId)) notFound(); const detail = await loadAnnouncementDetail(context.supabase, announcementId); if (!detail || (detail.announcement.displayStatus !== 'draft' && (detail.announcement.displayStatus !== 'live' || !context.canPublish))) notFound(); return <main className="cl-page anc-page"><Link href={`/announcements/${announcementId}`}>Announcement</Link><h1 className="cl-title">Edit announcement</h1>{context.preview ? <p>Support preview is read-only.</p> : <AnnouncementComposer detail={detail} nouns={context.nouns} timezone={context.timezone} canPublish={context.canPublish} />}</main>; }
