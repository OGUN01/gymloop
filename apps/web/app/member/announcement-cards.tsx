'use client';
import { useState } from 'react';
import type { AnnouncementCard } from '@gymloop/shared';
import { AnnouncementCard as Card } from './announcement-card';
export function AnnouncementCards({ cards, timezone, limit }: { cards: AnnouncementCard[]; timezone: string; limit: number }) { const [all, setAll] = useState(false); return <><div>{(all ? cards : cards.slice(0, limit)).map((card) => <Card key={`${card.announcementId}:${card.versionNo}`} card={card} timezone={timezone} />)}</div>{!all && cards.length > limit ? <button type="button" className="cl-btn" onClick={() => setAll(true)}>Show all {cards.length}</button> : null}</>; }
