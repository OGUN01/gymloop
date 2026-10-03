'use client';
import { useRef, useState } from 'react';
import { ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_STATE_WORDS, ANNOUNCEMENT_UPDATED_HINT, announcementPreview, type AnnouncementCard as Card } from '@gymloop/shared';
import { gymTimeLabel } from '../../lib/time';

export function AnnouncementCard({ card, timezone }: { card: Card; timezone: string }) {
  const [expanded, setExpanded] = useState(false); const [read, setRead] = useState(card.readState); const opened = useRef(false);
  const [imageFailed, setImageFailed] = useState(false);
  const toggle = async () => {
    setExpanded((old) => !old);
    if (!expanded && !opened.current) {
      opened.current = true;
      try { const response = await fetch(`/api/member/announcements/${card.announcementId}/read`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ versionNo: card.versionNo }) }); const result = await response.json(); if (result.ok === true && result.data?.recorded === true) setRead('read'); } catch { /* The content stays usable; read state remains honest. */ }
    }
  };
  return <article className="anc-card">
    <button type="button" className="anc-card-control" aria-label={card.title} aria-expanded={expanded} onClick={() => void toggle()}>
      <span className="anc-card-meta">{ANNOUNCEMENT_KIND_LABELS[card.kind]} · {card.versionNo > 1 ? 'Edited ' : 'Posted '}{gymTimeLabel(card.editedAt ?? card.publishedAt, timezone)}</span>
      <strong>{card.title}</strong><span className="anc-preview">{announcementPreview(card.body)}</span>
      {ANNOUNCEMENT_STATE_WORDS[read] ? <span className="cl-status" data-tone="accent"><span aria-hidden="true">● </span>{ANNOUNCEMENT_STATE_WORDS[read]}</span> : null}
    </button>
    {expanded ? <div className="anc-content">{card.readState === 'updated' ? <p>{ANNOUNCEMENT_UPDATED_HINT} {card.changeNote}</p> : null}<p className="anc-body">{card.body}</p>{card.imageUrl ? imageFailed ? <p>Image unavailable</p> : <img src={card.imageUrl} alt="" className="anc-image" onError={() => setImageFailed(true)} /> : null}</div> : null}
  </article>;
}
