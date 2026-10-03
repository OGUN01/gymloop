import { Constants } from '@gymloop/db';
import { businessNouns } from '../../business-type';
import { describe, expect, it } from 'vitest';
import { ANNOUNCEMENT_KIND_LABELS, ANNOUNCEMENT_STATE_WORDS, ANNOUNCEMENT_STALE_WORD, ANNOUNCEMENT_UPDATED_HINT, ANNOUNCEMENT_EDIT_WARNING, ANNOUNCEMENT_READ_FOOTNOTE, ANNOUNCEMENT_PRIVACY_SENTENCE, ANNOUNCEMENT_REFUSAL_COPY, ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES, SYSTEM_OWNED_MESSAGE_CATEGORIES, announcementDraftRequestSchema, announcementEditRequestSchema, announcementReadRequestSchema, memberFeedRequestSchema, memberAnnouncementFeedSchema, announcementKindHelp, announcementReachSentence, announcementSectionHeading, announcementRefusalMessage, announcementPreview } from '../announcements';
import { ANNOUNCEMENT_LIMITS } from '../../config/constants';
const valid = { kind: 'transactional', title: ' Closure ', body: ' Plain body ', audience: 'all_members' };
describe('ANC-001/018 schema and generated vocabulary', () => {
  it('enum-backed request and derived status set match the generated source', () => {
    expect(ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES).toEqual(Constants.public.Enums.member_status.filter((status) => !['cancelled', 'blocked'].includes(status)));
    for (const kind of Constants.public.Enums.announcement_kind) expect(announcementDraftRequestSchema.safeParse({ ...valid, kind }).success).toBe(true);
    expect(SYSTEM_OWNED_MESSAGE_CATEGORIES).toEqual(['announcement', 'class_update']);
  });
  it('trims and counts characters rather than bytes', () => {
    expect(announcementDraftRequestSchema.parse(valid)).toMatchObject({ title: 'Closure', body: 'Plain body' });
    expect(announcementDraftRequestSchema.safeParse({ ...valid, title: '字'.repeat(80), body: '字'.repeat(1500) }).success).toBe(true);
    for (const [field, value] of [['title', ' '], ['title', 'x'.repeat(81)], ['body', ' '], ['body', 'x'.repeat(1501)]] as const) expect(announcementDraftRequestSchema.safeParse({ ...valid, [field]: value }).success).toBe(false);
  });
  it('requires exact segment shape, distinct good-standing statuses, offsets and UUIDs', () => {
    const segment = { ...valid, audience: 'segment', segmentMemberStatuses: ['active', 'paused'], segmentMembership: 'live' };
    expect(announcementDraftRequestSchema.safeParse(segment).success).toBe(true);
    for (const input of [{ ...valid, tenantId: 'foreign' }, { ...valid, segmentMembership: 'any' }, { ...segment, segmentMemberStatuses: [] }, { ...segment, segmentMemberStatuses: ['active', 'active'] }, { ...segment, segmentMemberStatuses: ['blocked'] }, { ...segment, segmentMembership: undefined }, { ...valid, expiresAt: '2026-10-02T10:00:00' }, { ...valid, imageAssetId: 'asset-key' }]) expect(announcementDraftRequestSchema.safeParse(input).success).toBe(false);
    expect(announcementDraftRequestSchema.safeParse({ ...valid, expiresAt: '2026-10-02T10:00:00+05:30' }).success).toBe(true);
  });
  it('edit/read/feed cannot inject tenant, kind, audience, time or unknown fields', () => {
    const edit = { expectedVersion: 1, title: 'Title', body: 'Body', changeNote: ' note ' };
    expect(announcementEditRequestSchema.parse(edit).changeNote).toBe('note');
    for (const extra of [{ expectedVersion: 0 }, { changeNote: ' x ' }, { changeNote: 'x'.repeat(201) }, { kind: 'transactional' }, { audience: 'all_members' }, { tenantId: 'x' }]) expect(announcementEditRequestSchema.safeParse({ ...edit, ...extra }).success).toBe(false);
    expect(announcementReadRequestSchema.parse({ versionNo: 1 })).toEqual({ versionNo: 1 });
    expect(announcementReadRequestSchema.safeParse({ versionNo: 1, readAt: '2026-10-02T00:00:00Z' }).success).toBe(false);
    expect(memberFeedRequestSchema.safeParse({}).success).toBe(true); expect(memberFeedRequestSchema.safeParse({ tenantId: 'x' }).success).toBe(false);
  });
  it('typed member envelope never permits private object metadata', () => {
    const card = { announcementId: '75000000-0000-4000-8000-000000000001', kind: 'transactional', title: 'Notice', body: 'Plain', imageUrl: null, versionNo: 1, publishedAt: '2026-10-02T00:00:00Z', editedAt: null, expiresAt: null, changeNote: null, readState: 'unread', readAt: null };
    const envelope = { asOf: '2026-10-02T00:00:00Z', announcements: [card] };
    expect(memberAnnouncementFeedSchema.safeParse(envelope).success).toBe(true);
    for (const key of ['objectKey', 'stagingObjectKey', 'publishedEtag', 'mime', 'memberId']) expect(memberAnnouncementFeedSchema.safeParse({ ...envelope, announcements: [{ ...card, [key]: 'private' }] }).success).toBe(false);
  });
});
describe('ANC-019/023 pinned consent and state copy', () => {
  const nouns = businessNouns('dance');
  it('kind explanations and counts use tenant nouns and distinguish marketing consent', () => {
    expect(ANNOUNCEMENT_KIND_LABELS).toEqual({ transactional: 'Notice', promotional: 'News and offers' });
    expect(announcementKindHelp('transactional', nouns)).toBe('Reaches every student this is addressed to. Use it for closures, safety and schedule changes.');
    expect(announcementKindHelp('promotional', nouns)).toBe('Reaches only students who agreed to hear about news and offers from your academy. Others will not see it.');
    expect(announcementReachSentence({ kind: 'transactional', count: 0, nouns })).toBe('No students would see this right now.');
    expect(announcementReachSentence({ kind: 'transactional', count: 1, nouns })).toBe('1 student will see this on their Home screen.');
    expect(announcementReachSentence({ kind: 'promotional', count: 3, nouns })).toBe('3 students will see this on their Home screen. Only students who agreed to news and offers are counted.');
    expect(announcementSectionHeading(nouns.place)).toBe('From your academy');
  });
  it('read state, edited warning and privacy sentence are exact', () => {
    expect(ANNOUNCEMENT_STATE_WORDS).toEqual({ unread: 'New', updated: 'Updated', read: null }); expect(ANNOUNCEMENT_STALE_WORD).toBe('Saved copy');
    expect(ANNOUNCEMENT_UPDATED_HINT).toBe('You read an earlier version. This one changed.');
    expect(ANNOUNCEMENT_EDIT_WARNING).toBe('Anyone who already opened the earlier version will see this marked Updated, with your note.');
    expect(ANNOUNCEMENT_READ_FOOTNOTE).toBe('A member counts as having read an announcement when they open it in the app.');
    expect(ANNOUNCEMENT_PRIVACY_SENTENCE).toBe('When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.');
  });
  it('all refusal sentences are exact and inherited object keys fail closed', () => {
    expect(ANNOUNCEMENT_REFUSAL_COPY).toMatchObject({ not_draft: 'This announcement is no longer a draft. Reload to see where it stands.', not_live: "This announcement has ended, so it can't be edited. Write a new one instead.", not_published: "This announcement isn't showing to members, so there is nothing to take down.", expiry_invalid: 'Choose an end time that is in the future and within a year.', image_unavailable: "That image isn't ready. Upload it again, or publish without an image.", live_limit: 'Too many announcements are showing right now. Take one down before publishing another.', publish_rate_limited: 'Too many announcements were published today. Try again tomorrow.', version_limit: 'This announcement has been edited as many times as allowed. Take it down and publish a new one.', version_conflict: 'Someone else changed this announcement while you were editing. Reload to see the latest version, then try again.', no_change: 'Nothing was changed, so no new version was published.' });
    for (const value of ['unknown', 'constructor', '__proto__', 'toString']) expect(announcementRefusalMessage(value)).toBe('The announcement could not be saved. Nothing was changed.');
  });
  it('shared limits and word-safe preview are fixed', () => {
    expect(ANNOUNCEMENT_LIMITS).toEqual({ titleMaxChars: 80, bodyMaxChars: 1500, changeNoteMinChars: 3, changeNoteMaxChars: 200, maxLivePerTenant: 10, publishesPerDay: 20, maxVersions: 10, maxExpiryDays: 365, homeCards: 3, listPageSize: 50, previewChars: 140 });
    expect(announcementPreview('  Two\n\twords  ')).toBe('Two words');
    const body = 'word '.repeat(40); const preview = announcementPreview(body); expect(preview).toBe('word '.repeat(28).trim() + '…');
  });
});
