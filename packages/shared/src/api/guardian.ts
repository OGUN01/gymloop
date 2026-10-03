import { Constants, type Database } from '@gymloop/db';
import { z } from 'zod';
import { GUARDIAN_LIMITS, PRODUCT_NAME, STAFF_INVITE_EMAIL_MAX_LENGTH } from '../config/constants';

export const GUARDIAN_RELATIONS = Constants.public.Enums.guardian_relation;
export type GuardianRelation = Database['public']['Enums']['guardian_relation'];
export const GUARDIAN_RELATION_LABELS: Record<GuardianRelation, string> = {
  mother: 'mother', father: 'father', grandparent: 'grandparent', sibling: 'sibling', legal_guardian: 'legal guardian', other: 'guardian',
};
export const GUARDIAN_AGE_STATES = ['unknown', 'minor', 'adult'] as const;
export type GuardianAgeState = (typeof GUARDIAN_AGE_STATES)[number];
export const GUARDIAN_CONSENT_STATES = ['none', 'granted', 'withdrawn', 'stale'] as const;
export type GuardianConsentState = (typeof GUARDIAN_CONSENT_STATES)[number];
export const GUARDIAN_SCORING_STATES = ['on_adult', 'on_consent', 'off_age_unknown', 'off_no_guardian', 'off_no_consent', 'off_consent_withdrawn', 'off_consent_stale'] as const;
export type GuardianScoringState = (typeof GUARDIAN_SCORING_STATES)[number];
export const GUARDIAN_ATTENTION_REASONS = ['no_birth_date', 'minor_no_guardian', 'minor_consent_missing', 'handover_due'] as const;
export type GuardianAttentionReason = (typeof GUARDIAN_ATTENTION_REASONS)[number];
export const GUARDIAN_SCORING_COPY: Record<GuardianScoringState, string> = {
  on_adult: 'Absence follow-ups are on.',
  on_consent: "Absence follow-ups are on, with the guardian's consent on record.",
  off_age_unknown: 'Absence follow-ups are off. Add a date of birth to turn them on.',
  off_no_guardian: "Absence follow-ups are off. Add the guardian's name, relation and phone.",
  off_no_consent: "Absence follow-ups are off until the guardian's consent is recorded.",
  off_consent_withdrawn: 'The guardian withdrew consent, so absence follow-ups are off. Visits are still recorded.',
  off_consent_stale: "The guardian's details changed after consent was recorded, so absence follow-ups are off. Record consent again.",
};
export function guardianScoringMessage(state: string): string {
  return Object.hasOwn(GUARDIAN_SCORING_COPY, state) ? GUARDIAN_SCORING_COPY[state as GuardianScoringState] : 'Absence follow-ups are off.';
}
export const guardianProfileRequestSchema = z.strictObject({
  memberId: z.uuid(), dateOfBirth: z.union([z.iso.date(), z.null()]),
  guardian: z.union([z.null(), z.strictObject({
    name: z.string().trim().min(1).max(GUARDIAN_LIMITS.nameMaxLength), relation: z.enum(GUARDIAN_RELATIONS),
    phone: z.union([z.literal('').transform((): undefined => undefined), z.string().regex(/^\+[1-9][0-9]{7,14}$/)]).optional(),
    email: z.union([z.literal('').transform((): undefined => undefined), z.string().max(STAFF_INVITE_EMAIL_MAX_LENGTH).regex(/^[^\s@]+@[^\s@]+\.[^\s@]+$/)]).optional(),
  })]),
});
export const guardianConsentRequestSchema = z.strictObject({ memberId: z.uuid(), granted: z.boolean(), source: z.string().trim().min(1).max(GUARDIAN_LIMITS.sourceMaxLength) });
export const guardianHandoverRequestSchema = z.strictObject({ memberId: z.uuid(), reason: z.string().trim().min(GUARDIAN_LIMITS.reasonMinLength).max(GUARDIAN_LIMITS.reasonMaxLength) });
export const guardianLegacyAttestationRequestSchema = z.strictObject({});
export function guardianConsentStatement(input: { gymName: string; memberName: string; guardianName: string; relation: GuardianRelation }): string {
  return `I, ${input.guardianName}, am ${input.memberName}'s ${GUARDIAN_RELATION_LABELS[input.relation]}. I agree that ${input.gymName} may use ${input.memberName}'s visit records to notice when they stop coming, and may contact me about it. ${input.memberName}'s visits are recorded either way. I can withdraw this at any time by telling ${input.gymName}.`;
}
export function guardianInviteShareMessage(input: { guardianName: string; memberName: string; gymName: string; email: string; link: string }): string {
  const guardianFirst = input.guardianName.trim().split(/\s+/)[0] ?? '';
  const memberFirst = input.memberName.trim().split(/\s+/)[0] ?? '';
  return `Hi ${guardianFirst}, ${input.gymName} invited ${memberFirst} to join on ${PRODUCT_NAME}. Open this link and sign in with Google using ${input.email} so ${memberFirst}'s membership connects: ${input.link}`;
}
export function guardianCoverageLines(counts: { tracked: number; noBirthDate: number; minorNoGuardian: number; minorConsentMissing: number; handoverDue: number }, nouns?: { members: string }): string[] {
  const lines: string[] = [];
  const off = counts.noBirthDate + counts.minorNoGuardian + counts.minorConsentMissing;
  if (off > 0) lines.push(`Absence follow-ups are off for ${off} ${nouns?.members ?? 'members'} with a live membership.`);
  if (counts.noBirthDate > 0) lines.push(`${counts.noBirthDate} ${counts.noBirthDate === 1 ? 'has' : 'have'} no date of birth.`);
  if (counts.minorNoGuardian > 0) lines.push(`${counts.minorNoGuardian} ${counts.minorNoGuardian === 1 ? 'is' : 'are'} under 18 without a guardian on file.`);
  if (counts.minorConsentMissing > 0) lines.push(`${counts.minorConsentMissing} ${counts.minorConsentMissing === 1 ? 'is' : 'are'} under 18 without current guardian consent.`);
  if (counts.handoverDue > 0) lines.push(`${counts.handoverDue} turned 18 and still ${counts.handoverDue === 1 ? 'signs' : 'sign'} in through a guardian's account.`);
  return lines;
}
