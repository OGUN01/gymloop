import { GUARDIAN_AGE_STATES, GUARDIAN_CONSENT_STATES, GUARDIAN_SCORING_STATES, GUARDIAN_ATTENTION_REASONS,
  type GuardianAgeState, type GuardianConsentState, type GuardianScoringState, type GuardianRelation } from '@gymloop/shared';
import type { createServerSupabase } from './supabase/server';

type Client = Awaited<ReturnType<typeof createServerSupabase>>;
export type MemberGuardian = {
  ageState: GuardianAgeState; dateOfBirth: string | null; adultOn: string | null; gymToday: string | null;
  guardianName: string | null; guardianRelation: GuardianRelation | null; guardianPhone: string | null; guardianEmail: string | null;
  guardianComplete: boolean; linkEmail: string | null; linkEmailInUse: boolean;
  consentState: GuardianConsentState; consentRecordedAt: string | null; consentVersion: string | null; scoringState: GuardianScoringState;
  guardianLinkedAt: string | null; handoverDue: boolean; legacyAttestedAdult: boolean;
};
export type GuardianCoverage = {
  tracked: number; noBirthDate: number; minorNoGuardian: number; minorConsentMissing: number; handoverDue: number;
  membersWithoutDobAttestedAdultAt: string | null;
};
export type GuardianAttentionMember = { memberId: string; memberName: string; memberPhone: string; scoringState: string };

/** Reads only through the caller's session; age and eligibility stay database decisions. */
export async function loadMemberGuardian(supabase: Client, memberId: string): Promise<MemberGuardian | null> {
  try {
    const { data, error } = await supabase.rpc('read_member_guardian', { p_member_id: memberId });
    const row = error ? null : data?.[0];
    if (!row) return null;
    const ageState = GUARDIAN_AGE_STATES.find((state) => state === row.age_state);
    const consentState = GUARDIAN_CONSENT_STATES.find((state) => state === row.consent_state);
    const scoringState = GUARDIAN_SCORING_STATES.find((state) => state === row.scoring_state);
    if (ageState === undefined || consentState === undefined || scoringState === undefined) return null;
    return { ageState, dateOfBirth: row.date_of_birth, adultOn: row.adult_on, gymToday: row.gym_today,
      guardianName: row.guardian_name, guardianRelation: row.guardian_relation, guardianPhone: row.guardian_phone, guardianEmail: row.guardian_email,
      guardianComplete: row.guardian_complete, linkEmail: row.link_email, linkEmailInUse: row.link_email_in_use,
      consentState, consentRecordedAt: row.consent_recorded_at, consentVersion: row.consent_version,
      scoringState, guardianLinkedAt: row.guardian_linked_at, handoverDue: row.handover_due, legacyAttestedAdult: row.legacy_attested_adult };
  } catch { return null; }
}
export async function loadGuardianCoverage(supabase: Client): Promise<GuardianCoverage | null> {
  try {
    const { data, error } = await supabase.rpc('read_guardian_coverage');
    const row = error ? null : data?.[0];
    return row ? { tracked: row.tracked, noBirthDate: row.no_birth_date, minorNoGuardian: row.minor_no_guardian,
      minorConsentMissing: row.minor_consent_missing, handoverDue: row.handover_due, membersWithoutDobAttestedAdultAt: row.members_without_dob_attested_adult_at } : null;
  } catch { return null; }
}
export async function loadGuardianAttention(supabase: Client, reason: string): Promise<GuardianAttentionMember[] | null> {
  if (!(GUARDIAN_ATTENTION_REASONS as readonly string[]).includes(reason)) return null;
  try {
    const { data, error } = await supabase.rpc('list_guardian_attention', { p_reason: reason });
    return error || data === null ? null : data.map((row) => ({ memberId: row.member_id, memberName: row.member_name, memberPhone: row.member_phone, scoringState: row.scoring_state }));
  } catch { return null; }
}
