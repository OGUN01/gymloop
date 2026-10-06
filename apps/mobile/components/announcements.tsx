import { useState } from 'react';
import { Image, Text, View } from 'react-native';
import { ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_LIMITS, ANNOUNCEMENT_STATE_WORDS, ANNOUNCEMENT_STALE_WORD, ANNOUNCEMENT_UPDATED_HINT, announcementPreview, announcementSectionHeading, UI_TOKENS } from '@gymloop/shared';
import { useMobile } from '../lib/mobile-context';
import { useAnnouncements } from '../lib/use-announcements';
import { ActionButton, Body, Eyebrow, FONT, Row, RowAction, StateMessage, Status } from './ui';

export function AnnouncementsSection({ feed, timezone, previewLimit = ANNOUNCEMENT_LIMITS.homeCards, onViewAll, showAll = false }: { feed: ReturnType<typeof useAnnouncements>; timezone: string; previewLimit?: number; onViewAll?: () => void; showAll?: boolean }) {
  const { nouns, identity, palette } = useMobile(); const scopeKey = identity?.kind === 'member' ? `${identity.tenantId}:${identity.userId}:${identity.memberId}` : ''; const [allScope, setAllScope] = useState<string | null>(null); const all = showAll || allScope === scopeKey; const [opened, setOpened] = useState<{ scope: string; keys: Set<string>; hints: Set<string> }>(() => ({ scope: scopeKey, keys: new Set(), hints: new Set() }));
  if (feed.loading && !feed.cards.length) return null;
  if (feed.error && !feed.cards.length) return <View><StateMessage>{feed.error}</StateMessage><ActionButton secondary onPress={() => void feed.reload()}>Try again</ActionButton></View>;
  if (!feed.cards.length) return null;
  const date = (iso: string) => { try { return onViewAll && !showAll ? new Date(iso).toLocaleDateString('en-IN', { timeZone: timezone, day: 'numeric', month: 'short' }) : new Date(iso).toLocaleString('en-IN', { timeZone: timezone }); } catch { return `${nouns.place} timezone unavailable`; } };
  return <View><View style={{ flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[2] }}><Eyebrow>{announcementSectionHeading(nouns.place)}</Eyebrow>{onViewAll && !showAll ? <RowAction onPress={onViewAll}>View all</RowAction> : null}</View>{feed.stale ? <Body muted>{ANNOUNCEMENT_STALE_WORD} · {feed.fetchedAt ? date(feed.fetchedAt) : ''}</Body> : null}
    {feed.error ? <View><StateMessage>{feed.error}</StateMessage><ActionButton secondary onPress={() => void feed.reload()}>Try again</ActionButton></View> : null}
    {(all ? feed.cards : feed.cards.slice(0, previewLimit)).map((card) => {
      const key = `${card.announcementId}:${card.versionNo}`; const expanded = opened.scope === scopeKey && opened.keys.has(key);
      return <View key={key}><Row title={card.title} meta={`${ANNOUNCEMENT_KIND_LABELS[card.kind]} · ${card.versionNo > 1 ? 'Edited' : 'Posted'} ${date(card.editedAt ?? card.publishedAt)}`} expanded={expanded} accessibilityLabel={card.title} status={ANNOUNCEMENT_STATE_WORDS[card.readState] ? <Status tone="accent">{ANNOUNCEMENT_STATE_WORDS[card.readState]}</Status> : undefined} onPress={() => { setOpened((previous) => { const keys = new Set(previous.scope === scopeKey ? previous.keys : []); const hints = new Set(previous.scope === scopeKey ? previous.hints : []); if (keys.has(key)) keys.delete(key); else { keys.add(key); if (card.readState === 'updated') hints.add(key); } return { scope: scopeKey, keys, hints }; }); if (!expanded) void feed.markRead(card.announcementId, card.versionNo); }} />
        <Text numberOfLines={2} style={{ color: palette.secondaryText, fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight }}>{announcementPreview(card.body)}</Text>
        {expanded ? <View>{opened.scope === scopeKey && opened.hints.has(key) && card.changeNote ? <Body muted>{ANNOUNCEMENT_UPDATED_HINT} {card.changeNote}</Body> : null}<Body>{card.body}</Body>{card.imageUrl ? <Image source={{ uri: card.imageUrl }} accessible={false} style={{ width: '100%', aspectRatio: 1, borderRadius: UI_TOKENS.geometry.radii.section }} resizeMode="contain" /> : null}</View> : null}
      </View>;
    })}
    {!all && !onViewAll && feed.cards.length > previewLimit ? <ActionButton secondary onPress={() => setAllScope(scopeKey)}>Show all {feed.cards.length}</ActionButton> : null}
  </View>;
}
