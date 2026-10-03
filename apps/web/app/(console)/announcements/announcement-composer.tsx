'use client';
import { useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import { Constants } from '@gymloop/db';
import { ANNOUNCEMENT_LIMITS, ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_EDIT_WARNING, ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES, announcementDraftRequestSchema, announcementEditRequestSchema, announcementKindHelp, offsetInstantFromGymWallTime, humanize, type AnnouncementDetail, type BusinessNouns } from '@gymloop/shared';
import { Field, inputClass } from '../field';
import { uploadMediaFile } from '../../../lib/media-upload';
import { deskTime } from '../../../lib/time';
import { AnnouncementCommandStatus, useAnnouncementCommand } from '../../../lib/use-announcement-command';

type ComposerProps = { nouns: BusinessNouns; timezone: string; canPublish: boolean; detail?: AnnouncementDetail };
export function AnnouncementComposer(props: ComposerProps) { return <AnnouncementComposerForm key={JSON.stringify({ detail: props.detail, canPublish: props.canPublish, timezone: props.timezone })} {...props} />; }
function AnnouncementComposerForm({ nouns, timezone, canPublish, detail }: ComposerProps) {
  const command = useAnnouncementCommand(JSON.stringify({ detail, canPublish, timezone })); const router = useRouter(); const current = detail?.versions[0]; const published = detail?.announcement.status === 'published';
  const [kind, setKind] = useState(detail?.announcement.kind ?? 'transactional'); const [audience, setAudience] = useState(detail?.announcement.audience ?? 'all_members');
  const [statuses, setStatuses] = useState(detail?.announcement.segmentMemberStatuses ?? [...ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES]); const [membership, setMembership] = useState(detail?.announcement.segmentMembership ?? 'any');
  const [title, setTitle] = useState(current?.title ?? ''); const [body, setBody] = useState(current?.body ?? ''); const [note, setNote] = useState(''); const [assetId, setAssetId] = useState<string | undefined>(current?.imageAssetId ?? undefined);
  const initialExpiry = detail?.announcement.expiresAt ? deskTime(detail.announcement.expiresAt, timezone).replace(' ', 'T') : '';
  const [expiry, setExpiry] = useState(initialExpiry); const [upload, setUpload] = useState<string | null>(null); const [uploadError, setUploadError] = useState<string | null>(null);
  const contentChanged = published && (title.trim() !== current?.title || body.trim() !== current?.body || (assetId ?? null) !== current?.imageAssetId);
  const save = async (review: boolean) => {
    if (!command.isCurrent()) return;
    const expiresAt = expiry === initialExpiry && detail?.announcement.expiresAt ? detail.announcement.expiresAt : expiry ? offsetInstantFromGymWallTime(expiry, timezone) : undefined;
    if (expiresAt === null) { command.setError('Choose an unambiguous end date and time in the gym timezone.'); return; }
    const fields = { title, body, ...(expiresAt ? { expiresAt } : {}), ...(assetId ? { imageAssetId: assetId } : {}) };
    const payload = published ? { ...fields, expectedVersion: detail.announcement.currentVersion, ...(note.trim() ? { changeNote: note } : {}) } : { ...fields, kind, audience, ...(audience === 'segment' ? { segmentMemberStatuses: statuses, segmentMembership: membership } : {}) };
    const parsed = (published ? announcementEditRequestSchema : announcementDraftRequestSchema).safeParse(payload);
    if (!parsed.success || (contentChanged && note.trim().length < ANNOUNCEMENT_LIMITS.changeNoteMinChars)) { command.setError('Check the title, body, audience and change note before saving.'); return; }
    const result = await command.send(detail ? `/api/announcements/${detail.announcement.id}/${published ? 'edit' : 'draft'}` : '/api/announcements', parsed.data);
    if (result && command.isCurrent()) router.push(`/announcements/${detail?.announcement.id ?? result.announcementId}${review ? '?review=1' : ''}`);
  };
  if (command.preview) return null;
  return <form className="anc-composer" onSubmit={(event: FormEvent) => { event.preventDefault(); void save(false); }}>
    <AnnouncementCommandStatus command={command} />
    {!published ? <fieldset disabled={command.disabled}><legend>Kind</legend>{Constants.public.Enums.announcement_kind.map((value) => <label key={value} className="anc-kind"><input type="radio" name="kind" value={value} checked={kind === value} onChange={() => setKind(value)} /><strong>{ANNOUNCEMENT_KIND_LABELS[value]}</strong><span>{announcementKindHelp(value, nouns)}</span></label>)}</fieldset> : <><p>{ANNOUNCEMENT_KIND_LABELS[kind]}</p><p>{ANNOUNCEMENT_EDIT_WARNING}</p></>}
    <Field label="Title"><input className={inputClass} value={title} maxLength={ANNOUNCEMENT_LIMITS.titleMaxChars} required disabled={command.disabled} onChange={(event) => setTitle(event.target.value)} /><small>{title.length} / {ANNOUNCEMENT_LIMITS.titleMaxChars}</small></Field>
    <Field label="Body"><textarea className={inputClass} value={body} maxLength={ANNOUNCEMENT_LIMITS.bodyMaxChars} required disabled={command.disabled} onChange={(event) => setBody(event.target.value)} /><small>{body.length} / {ANNOUNCEMENT_LIMITS.bodyMaxChars}</small></Field>
    <Field label="Optional image"><input type="file" accept="image/jpeg,image/png,image/webp" disabled={command.disabled || upload !== null} onChange={async (event) => { const file = event.target.files?.[0]; if (!file || !command.isCurrent()) return; setUploadError(null); setUpload('Uploading image…'); try { const result = await uploadMediaFile(file, 'announcement', (stage) => { if (command.isCurrent()) setUpload(stage === 'verifying' ? 'Verifying image…' : 'Uploading image…'); }); if (command.isCurrent()) setAssetId(result.assetId); } catch (error) { if (command.isCurrent()) setUploadError(error instanceof Error ? error.message : 'The image could not be uploaded. Publish without it or try again.'); } finally { if (command.isCurrent()) { setUpload(null); event.target.value = ''; } } }} /><small>The image is decorative. Put essential information in the body.</small></Field>
    {upload ? <p role="status">{upload}</p> : null}{uploadError ? <p role="alert">{uploadError} You can publish without an image.</p> : null}{assetId ? <><p>Image attached</p><button type="button" className="cl-btn" disabled={command.disabled || upload !== null} onClick={() => setAssetId(undefined)}>Remove image</button></> : null}
    {!published ? <fieldset disabled={command.disabled}><legend>Audience</legend><Field label="Addressed to"><select className={inputClass} value={audience} onChange={(event) => setAudience(event.target.value as typeof audience)}><option value="all_members">All {nouns.members}</option><option value="segment">A segment</option></select></Field>{audience === 'segment' ? <>{ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES.map((value) => <label key={value}><input type="checkbox" checked={statuses.includes(value)} onChange={(event) => setStatuses((old) => event.target.checked ? [...old, value] : old.filter((status) => status !== value))} />{humanize(value)}</label>)}<Field label="Membership"><select className={inputClass} value={membership} onChange={(event) => setMembership(event.target.value as typeof membership)}>{Constants.public.Enums.announcement_membership_filter.map((value) => <option key={value} value={value}>{humanize(value)}</option>)}</select></Field></> : null}</fieldset> : null}
    <Field label={`Optional end date and time · ${timezone}`}><input type="datetime-local" className={inputClass} value={expiry} disabled={command.disabled} onChange={(event) => setExpiry(event.target.value)} /><small>Leave blank to show it until you take it down.</small></Field>
    {published ? <Field label="What changed"><textarea className={inputClass} value={note} required={contentChanged} minLength={ANNOUNCEMENT_LIMITS.changeNoteMinChars} maxLength={ANNOUNCEMENT_LIMITS.changeNoteMaxChars} disabled={command.disabled} onChange={(event) => setNote(event.target.value)} /><small>{note.length} / {ANNOUNCEMENT_LIMITS.changeNoteMaxChars}</small></Field> : null}
    <div className="cl-actions"><button type="submit" className="cl-btn" disabled={command.disabled || upload !== null}>{published ? 'Save changes' : 'Save draft'}</button>{!published && canPublish ? <button type="button" className="cl-btn cl-btn--primary" disabled={command.disabled || upload !== null} onClick={() => void save(true)}>Review and publish</button> : null}</div>
    {!canPublish ? <p>Ask an owner or manager to publish.</p> : null}
  </form>;
}
