'use client';
import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { ANNOUNCEMENT_KIND_LABELS, announcementReachSentence, type AnnouncementDetail, type BusinessNouns } from '@gymloop/shared';
import { gymTimeLabel } from '../../../lib/time';
import { AnnouncementCommandStatus, useAnnouncementCommand } from '../../../lib/use-announcement-command';

type ActionProps = { detail: AnnouncementDetail; nouns: BusinessNouns; timezone: string; canPublish: boolean; review?: boolean };
export function AnnouncementActions(props: ActionProps) { return <AnnouncementActionsPanel key={JSON.stringify({ detail: props.detail, canPublish: props.canPublish, review: props.review })} {...props} />; }
function AnnouncementActionsPanel({ detail, nouns, timezone, canPublish, review = false }: ActionProps) {
  const command = useAnnouncementCommand(JSON.stringify({ detail, canPublish, review })); const router = useRouter(); const [confirm, setConfirm] = useState<'publish' | 'unpublish' | 'discard' | null>(review && canPublish && detail.announcement.status === 'draft' ? 'publish' : null);
  if (command.preview) return null;
  const header = detail.announcement;
  const run = async () => { if (!confirm || !command.isCurrent()) return; const result = await command.send(`/api/announcements/${header.id}/${confirm}`, {}); if (result && command.isCurrent()) { if (confirm === 'discard') router.push('/announcements'); else router.refresh(); setConfirm(null); } };
  return <div className="anc-actions"><AnnouncementCommandStatus command={command} />
    {!confirm ? <div className="cl-actions">{header.status === 'draft' ? <>{canPublish ? <button className="cl-btn cl-btn--primary" disabled={command.disabled} onClick={() => setConfirm('publish')}>Review and publish</button> : <p>Ask an owner or manager to publish.</p>}<button className="cl-btn" disabled={command.disabled} onClick={() => setConfirm('discard')}>Discard draft</button></> : header.status === 'published' && canPublish ? <button className="cl-btn" disabled={command.disabled} onClick={() => setConfirm('unpublish')}>Take down</button> : null}</div> : <section className="anc-confirm" aria-label={confirm === 'publish' ? 'Review announcement' : confirm === 'unpublish' ? 'Take down announcement' : 'Discard draft'}>
      <h2>{confirm === 'publish' ? 'Review announcement' : confirm === 'unpublish' ? 'Take down this announcement?' : 'Discard this draft?'}</h2>
      {confirm === 'publish' ? <><p>{ANNOUNCEMENT_KIND_LABELS[header.kind]}</p><p>{announcementReachSentence({ kind: header.kind, count: header.audienceCount ?? 0, nouns })}</p><p>{header.expiresAt ? `Ends ${gymTimeLabel(header.expiresAt, timezone)}` : 'Shows until you take it down'}</p><p>{detail.versions[0]?.imageAssetId ? 'Image attached' : 'No image attached'}</p></> : <p>{confirm === 'unpublish' ? 'It will leave Home immediately. It cannot be published again; its versions and read counts remain.' : 'This draft will be removed from the list.'}</p>}
      <div className="cl-actions"><button type="button" className="cl-btn cl-btn--primary" disabled={command.disabled} onClick={() => void run()}>{confirm === 'publish' ? 'Publish' : confirm === 'unpublish' ? 'Confirm take down' : 'Discard draft'}</button><button type="button" className="cl-btn" disabled={command.busy} onClick={() => setConfirm(null)}>Cancel</button></div>
    </section>}
  </div>;
}
