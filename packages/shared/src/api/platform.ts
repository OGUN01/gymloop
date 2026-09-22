import { z } from 'zod';
import { Constants } from '@gymloop/db';
import { GYM_PRESET_SETTINGS, PLAN_TIER_PRICES_PAISE } from '../config/constants';

const uuid = z.uuid();
const nonBlank = z.string().trim().min(1);
export const ORGANIZATION_STATUSES = Constants.public.Enums.organization_status;
export const PLAN_TIERS = Object.keys(PLAN_TIER_PRICES_PAISE) as [keyof typeof PLAN_TIER_PRICES_PAISE, ...(keyof typeof PLAN_TIER_PRICES_PAISE)[]];
export const GYM_PRESETS = Object.keys(GYM_PRESET_SETTINGS) as [keyof typeof GYM_PRESET_SETTINGS, ...(keyof typeof GYM_PRESET_SETTINGS)[]];

const status = z.enum(ORGANIZATION_STATUSES);
const tier = z.enum(PLAN_TIERS).nullable();
const preset = z.enum(GYM_PRESETS);

export const organizationResultSchema = z.object({
  tenantId: uuid, name: nonBlank, gymCode: nonBlank, status, tier,
  timezone: nonBlank, currency: z.literal('INR'), trialEndsAt: z.string().nullable(), activatedAt: z.string().nullable(),
}).strict();
export type OrganizationResult = z.infer<typeof organizationResultSchema>;

export const onboardGymRequestSchema = z.object({
  name: nonBlank, timezone: nonBlank, currency: z.literal('INR'), preset,
  branchName: nonBlank, ownerName: nonBlank,
  ownerEmail: z.preprocess((value) => typeof value === 'string' && value.trim() === '' ? null : value, z.string().trim().email().nullable()), requestKey: uuid,
}).strict();
export type OnboardGymRequest = z.infer<typeof onboardGymRequestSchema>;

export const setGymStatusRequestSchema = z.object({ expectedStatus: status, status, reason: z.preprocess((value) => typeof value === 'string' && value.trim() === '' ? null : value, z.string().trim().nullable()), requestKey: uuid }).strict();
export type SetGymStatusRequest = z.infer<typeof setGymStatusRequestSchema>;
export const setGymTierRequestSchema = z.object({ expectedTier: tier, tier, requestKey: uuid }).strict();
export type SetGymTierRequest = z.infer<typeof setGymTierRequestSchema>;
export const linkGymOwnerRequestSchema = z.object({ ownerStaffId: uuid, expectedUserId: uuid.nullable(), ownerEmail: z.string().trim().email(), requestKey: uuid }).strict();
export type LinkGymOwnerRequest = z.infer<typeof linkGymOwnerRequestSchema>;
export const deactivateGymOwnerRequestSchema = z.object({ ownerStaffId: uuid, expectedUserId: uuid, requestKey: uuid }).strict();
export type DeactivateGymOwnerRequest = z.infer<typeof deactivateGymOwnerRequestSchema>;
export const startGymPreviewRequestSchema = z.object({ tenantId: uuid, reason: nonBlank, requestKey: uuid }).strict();
export type StartGymPreviewRequest = z.infer<typeof startGymPreviewRequestSchema>;

export const readinessSchema = z.object({ settingsComplete: z.boolean(), missingSettings: z.array(nonBlank), ownerAccessPending: z.boolean(), providerReadiness: z.record(z.string(), z.unknown()) }).strict();
export type Readiness = z.infer<typeof readinessSchema>;

export const onboardGymResultSchema = z.object({ organization: organizationResultSchema, branchId: uuid, ownerStaffId: uuid, ownerAccessPending: z.literal(true) }).strict();
export const previewResultSchema = z.object({ sessionId: uuid, tenantId: uuid, startedAt: z.string(), expiresAt: z.string() }).strict();
export const endPreviewResultSchema = z.object({ sessionId: uuid, endedAt: z.string() }).strict();

export function platformRpcArgs(request: OnboardGymRequest) {
  return { p_request_key: request.requestKey, p_name: request.name, p_timezone: request.timezone, p_currency: request.currency, p_preset: request.preset, p_branch_name: request.branchName, p_owner_name: request.ownerName, p_owner_email: request.ownerEmail };
}
