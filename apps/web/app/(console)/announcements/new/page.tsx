import { announcementConsole } from '../../../../lib/announcement-console';
import { AnnouncementComposer } from '../announcement-composer';
import Link from 'next/link';
export default async function NewAnnouncementPage() { const context = await announcementConsole(); return <main className="cl-page anc-page"><Link href="/announcements">Announcements</Link><h1 className="cl-title">New announcement</h1>{context.preview ? <p>Support preview is read-only.</p> : <AnnouncementComposer nouns={context.nouns} timezone={context.timezone} canPublish={context.canPublish} />}</main>; }
