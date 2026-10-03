import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { PUSH_TOKEN_MAX_CHARS } from '../config/constants';

/**
 * NTF — Android push delivery request boundaries (frozen contract:
 * `openspec/changes/push-notifications/proposal.md`, serial declarations).
 *
 * These schemas pin the request shape of the six frozen POST routes; every
 * result envelope carries only opaque ids and status facts — never a device
 * token, provider id or lease (NTF-013). The transport itself stays in SQL
 * and the protected `push-dispatch` Edge adapter; nothing here talks to FCM.
 */

const uuid = z.uuid();

/** The canonical `message_category` vocabulary exactly as the DB enum pins it. */
export const PUSH_CATEGORY_VALUES = Constants.public.Enums.message_category;
const pushCategory = z.enum(Constants.public.Enums.message_category);

export const PUSH_EVENT_EVENTS = ['received', 'opened'] as const;

export const registerMemberPushDeviceRequestSchema = z.strictObject({
  installationId: uuid,
  pushToken: z.string().min(1).max(PUSH_TOKEN_MAX_CHARS),
  platform: z.literal('android'),
});
export type RegisterMemberPushDeviceRequest = z.infer<typeof registerMemberPushDeviceRequestSchema>;

export const unregisterMemberPushDeviceRequestSchema = z.strictObject({ installationId: uuid });
export type UnregisterMemberPushDeviceRequest = z.infer<typeof unregisterMemberPushDeviceRequestSchema>;

export const setMemberPushPreferenceRequestSchema = z.strictObject({
  category: pushCategory,
  enabled: z.boolean(),
});
export type SetMemberPushPreferenceRequest = z.infer<typeof setMemberPushPreferenceRequestSchema>;

export const acknowledgeMemberPushRequestSchema = z.strictObject({
  deviceId: uuid,
  tokenRevision: z.int().min(1),
  event: z.enum(PUSH_EVENT_EVENTS),
});
export type AcknowledgeMemberPushRequest = z.infer<typeof acknowledgeMemberPushRequestSchema>;

export const reviewAnnouncementPushRequestSchema = z.strictObject({
  versionNo: z.int().min(1),
  requestKey: uuid,
});
export type ReviewAnnouncementPushRequest = z.infer<typeof reviewAnnouncementPushRequestSchema>;

/** A cancel carries no body facts — the campaign id in the path is the command. */
export const cancelAnnouncementPushRequestSchema = z.strictObject({});

/** `read_member_push_settings()`'s safe projection: categories and device facts only. */
export type MemberPushSettings = {
  preferences: Array<{ category: (typeof PUSH_CATEGORY_VALUES)[number]; enabled: boolean }>;
  devices: Array<{ id: string; lastSeenAt: string; active: boolean }>;
};

/** `read_push_campaigns()`'s count-only review row; never a token or recipient. */
export type PushCampaignSummary = {
  campaignId: string;
  announcementId: string;
  versionNo: number;
  reviewedAt: string | null;
  cancelledAt: string | null;
  eligibleCount: number | null;
  counts: { accepted: number | null; received: number | null; opened: number | null; failed: number | null; uncertain: number | null } | null;
};

export type PushCampaignPage = { campaigns: PushCampaignSummary[]; nextBefore: string | null; nextBeforeId: string | null };
