import { DEFAULT_TIMEZONE } from '@gymloop/shared';
import { AnnouncementsSection } from '../../components/announcements';
import { EmptyState, LoadingState, Screen, Title } from '../../components/ui';
import { useAnnouncements } from '../../lib/use-announcements';
import { useBusinessNouns } from '../../lib/use-business-nouns';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';

/** The full shared feed preserves the existing version-specific read lifecycle. */
export default function AnnouncementsScreen() {
  const feed = useAnnouncements();
  const nouns = useBusinessNouns();
  const snapshot = useMemberSnapshot();
  return <Screen><Title fit>Announcements</Title>
    {feed.loading && !feed.cards.length ? <LoadingState /> : null}
    <AnnouncementsSection feed={feed} timezone={snapshot.data?.gym.timezone ?? DEFAULT_TIMEZONE} showAll />
    {!feed.loading && !feed.error && !feed.cards.length ? <EmptyState title="No announcements yet.">Updates from your {nouns.place} will appear here.</EmptyState> : null}
  </Screen>;
}
