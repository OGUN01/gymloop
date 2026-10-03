import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { ANNOUNCEMENT_LIMITS } from '../config/constants';
import type { BusinessNouns } from '../business-type';

export const ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES = Constants.public.Enums.member_status.filter((status) => status !== 'cancelled' && status !== 'blocked');
export const ANNOUNCEMENT_READ_STATES = ['unread', 'updated', 'read'] as const;
export const ANNOUNCEMENT_DISPLAY_STATUSES = ['draft', 'live', 'ended', 'taken_down'] as const;
export const ANNOUNCEMENT_REFUSAL_REASONS = ['not_draft', 'not_live', 'not_published', 'expiry_invalid', 'image_unavailable', 'live_limit', 'publish_rate_limited', 'version_limit', 'version_conflict', 'no_change', 'invalid_transition', 'field_frozen', 'version_immutable'] as const;
export const SYSTEM_OWNED_MESSAGE_CATEGORIES = ['announcement', 'class_update'] as const;
const instant = z.iso.datetime({ offset: true });
const title = z.string().trim().min(1).max(ANNOUNCEMENT_LIMITS.titleMaxChars);
const body = z.string().trim().min(1).max(ANNOUNCEMENT_LIMITS.bodyMaxChars);
const kind = z.enum(Constants.public.Enums.announcement_kind);
const audience = z.enum(Constants.public.Enums.announcement_audience);
const membership = z.enum(Constants.public.Enums.announcement_membership_filter);
const statuses = z.array(z.enum(ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES)).min(1).max(ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES.length).refine((values) => new Set(values).size === values.length);
export const announcementDraftRequestSchema = z.strictObject({ kind, title, body, audience, segmentMemberStatuses: statuses.optional(), segmentMembership: membership.optional(), expiresAt: instant.optional(), imageAssetId: z.uuid().optional() }).refine((input) => input.audience === 'all_members' ? input.segmentMemberStatuses === undefined && input.segmentMembership === undefined : input.segmentMemberStatuses !== undefined && input.segmentMembership !== undefined, { message: 'Choose a complete audience.' });
export const announcementEditRequestSchema = z.strictObject({ expectedVersion: z.int().min(1), title, body, imageAssetId: z.uuid().optional(), expiresAt: instant.optional(), changeNote: z.string().trim().min(ANNOUNCEMENT_LIMITS.changeNoteMinChars).max(ANNOUNCEMENT_LIMITS.changeNoteMaxChars).optional() });
export const announcementReadRequestSchema = z.strictObject({ versionNo: z.int().min(1) });
export const memberFeedRequestSchema = z.strictObject({});
const cardSchema = z.strictObject({ announcementId: z.uuid(), kind, title, body, imageUrl: z.url().nullable(), versionNo: z.int().min(1), publishedAt: instant, editedAt: instant.nullable(), expiresAt: instant.nullable(), changeNote: z.string().nullable(), readState: z.enum(ANNOUNCEMENT_READ_STATES), readAt: instant.nullable() });
export type AnnouncementCard = z.infer<typeof cardSchema>;
export const memberAnnouncementFeedSchema = z.strictObject({ asOf: instant, announcements: z.array(cardSchema) });
const header = { kind, status: z.enum(Constants.public.Enums.announcement_status), displayStatus: z.enum(ANNOUNCEMENT_DISPLAY_STATUSES), audience, segmentMemberStatuses: statuses.nullable(), segmentMembership: membership.nullable(), currentVersion: z.int().min(1), createdAt: instant, publishedAt: instant.nullable(), expiresAt: instant.nullable(), closedAt: instant.nullable(), audienceCount: z.int().nonnegative().nullable(), readCurrent: z.int().nonnegative(), readAny: z.int().nonnegative() };
export const announcementListRowSchema = z.strictObject({ announcementId: z.uuid(), title, ...header });
export const announcementDetailSchema = z.strictObject({ announcement: z.strictObject({ id: z.uuid(), ...header }), versions: z.array(z.strictObject({ versionNo: z.int().min(1), title, body, imageAssetId: z.uuid().nullable(), changeNote: z.string().nullable(), createdAt: instant, createdByStaffId: z.uuid(), readCount: z.int().nonnegative() })) });
export type AnnouncementDetail = z.infer<typeof announcementDetailSchema>;
export type AnnouncementListRow = z.infer<typeof announcementListRowSchema>;
export const ANNOUNCEMENT_KIND_LABELS = { transactional: 'Notice', promotional: 'News and offers' } as const;
export const ANNOUNCEMENT_STATE_WORDS = { unread: 'New', updated: 'Updated', read: null } as const;
export const ANNOUNCEMENT_STALE_WORD = 'Saved copy';
export const ANNOUNCEMENT_UPDATED_HINT = 'You read an earlier version. This one changed.';
export const ANNOUNCEMENT_EDIT_WARNING = 'Anyone who already opened the earlier version will see this marked Updated, with your note.';
export const ANNOUNCEMENT_READ_FOOTNOTE = 'A member counts as having read an announcement when they open it in the app.';
export const ANNOUNCEMENT_PRIVACY_SENTENCE = 'When you open an announcement in the app, FitCruxx records that you opened that version. The business sees how many members opened it, not who.';
export const ANNOUNCEMENT_REFUSAL_COPY = {
  not_draft: 'This announcement is no longer a draft. Reload to see where it stands.',
  not_live: "This announcement has ended, so it can't be edited. Write a new one instead.",
  not_published: "This announcement isn't showing to members, so there is nothing to take down.",
  expiry_invalid: 'Choose an end time that is in the future and within a year.',
  image_unavailable: "That image isn't ready. Upload it again, or publish without an image.",
  live_limit: 'Too many announcements are showing right now. Take one down before publishing another.',
  publish_rate_limited: 'Too many announcements were published today. Try again tomorrow.',
  version_limit: 'This announcement has been edited as many times as allowed. Take it down and publish a new one.',
  version_conflict: 'Someone else changed this announcement while you were editing. Reload to see the latest version, then try again.',
  no_change: 'Nothing was changed, so no new version was published.',
  generic: 'The announcement could not be saved. Nothing was changed.',
  unknown_outcome: 'The result could not be confirmed. Reload to check whether the announcement was saved.',
} as const;
export function announcementRefusalMessage(reason: string): string { const key = reason === 'announcement_outcome_unknown' ? 'unknown_outcome' : reason; return Object.hasOwn(ANNOUNCEMENT_REFUSAL_COPY, key) ? ANNOUNCEMENT_REFUSAL_COPY[key as keyof typeof ANNOUNCEMENT_REFUSAL_COPY] : ANNOUNCEMENT_REFUSAL_COPY.generic; }
export function announcementKindHelp(value: AnnouncementCard['kind'], nouns: BusinessNouns): string { return value === 'transactional' ? `Reaches every ${nouns.member} this is addressed to. Use it for closures, safety and schedule changes.` : `Reaches only ${nouns.members} who agreed to hear about news and offers from your ${nouns.place}. Others will not see it.`; }
export function announcementReachSentence({ kind: value, count, nouns }: { kind: AnnouncementCard['kind']; count: number; nouns: BusinessNouns }): string { const sentence = count === 0 ? `No ${nouns.members} would see this right now.` : `${count} ${count === 1 ? nouns.member : nouns.members} will see this on their Home screen.`; return sentence + (value === 'promotional' ? ` Only ${nouns.members} who agreed to news and offers are counted.` : ''); }
export function announcementSectionHeading(place: string): string { return `From your ${place}`; }
export function announcementPreview(value: string): string { const normalized = value.replace(/\s+/g, ' ').trim(); if (normalized.length <= ANNOUNCEMENT_LIMITS.previewChars) return normalized; const cut = normalized.slice(0, ANNOUNCEMENT_LIMITS.previewChars + 1); const boundary = cut.lastIndexOf(' '); return (boundary > 0 ? cut.slice(0, boundary) : normalized.slice(0, ANNOUNCEMENT_LIMITS.previewChars)).trim() + '…'; }
