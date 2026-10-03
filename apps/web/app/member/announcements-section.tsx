import { ANNOUNCEMENT_LIMITS, announcementSectionHeading, type BusinessNouns } from '@gymloop/shared';
import { requireAudience } from '../../lib/identity-session';
import { loadMemberAnnouncementFeed } from '../../lib/member-announcements';
import { AnnouncementCards } from './announcement-cards';

export async function AnnouncementsSection({ nouns, timezone, feedPromise }: { nouns: BusinessNouns; timezone: string; feedPromise?: Promise<Awaited<ReturnType<typeof loadMemberAnnouncementFeed>> | null> }) {
  try { const feed = feedPromise ? await feedPromise : await loadMemberAnnouncementFeed((await requireAudience('member')).supabase); if (!feed) throw new Error('Unavailable'); if (!feed.announcements.length) return null;
    return <section className="anc-section" aria-label={announcementSectionHeading(nouns.place)}><h2>{announcementSectionHeading(nouns.place)}</h2><AnnouncementCards cards={feed.announcements} timezone={timezone} limit={ANNOUNCEMENT_LIMITS.homeCards} /></section>;
  } catch { return <p className="cl-alert anc-section" role="status"><a href="/member">Announcements couldn't be loaded. Try again.</a></p>; }
}
