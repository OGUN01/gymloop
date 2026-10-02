import { describe, expect, it } from 'vitest';
import * as shared from '../../index';
import {
  GUARDIAN_RELATIONS, GUARDIAN_RELATION_LABELS, GUARDIAN_SCORING_COPY,
  guardianScoringMessage, guardianProfileRequestSchema, guardianConsentRequestSchema,
  guardianHandoverRequestSchema, guardianConsentStatement, guardianInviteShareMessage,
  guardianCoverageLines,
} from '../guardian';
import { GUARDIAN_CONSENT_VERSION, GUARDIAN_LIMITS } from '../../config/constants';

// Independent visible author: frozen GRD-004/022/025 contract, no implementation read.
const MEMBER = '69000000-0000-4000-8000-000000000001';
const profile = { memberId: MEMBER, dateOfBirth: '2012-02-29', guardian: {
  name: '  Mira Rao  ', relation: 'mother', phone: '+919876543210', email: 'mira@example.com',
} };

describe('GRD public shared boundary', () => {
  it('exposes the specified schemas and copy through the package barrel', () => {
    for (const name of ['guardianProfileRequestSchema', 'guardianConsentRequestSchema',
      'guardianHandoverRequestSchema', 'guardianConsentStatement', 'guardianScoringMessage',
      'guardianCoverageLines', 'guardianInviteShareMessage']) expect(shared).toHaveProperty(name);
    expect(GUARDIAN_LIMITS).toEqual({ nameMaxLength: 120, sourceMaxLength: 200,
      reasonMinLength: 3, reasonMaxLength: 200, attentionListMax: 100 });
    expect([...GUARDIAN_RELATIONS]).toEqual(['mother', 'father', 'grandparent', 'sibling', 'legal_guardian', 'other']);
    expect(GUARDIAN_RELATION_LABELS.legal_guardian).toBe('legal guardian');
    expect(GUARDIAN_RELATION_LABELS.other).toBe('guardian');
  });
  it('accepts an unknown DOB, a real leap day and a guardian without invite email', () => {
    expect(guardianProfileRequestSchema.parse({ memberId: MEMBER, dateOfBirth: null, guardian: null }))
      .toEqual({ memberId: MEMBER, dateOfBirth: null, guardian: null });
    expect(guardianProfileRequestSchema.parse(profile).guardian?.name).toBe('Mira Rao');
    expect(guardianProfileRequestSchema.parse({ ...profile, guardian: { ...profile.guardian, phone: '', email: '' } }).guardian)
      .toEqual({ name: 'Mira Rao', relation: 'mother', phone: undefined, email: undefined });
  });
  it.each(['2011-02-29', '2012-02-30', '2026-13-01', '2026-01-01T00:00:00Z', ' 2012-02-29 '])('refuses invalid calendar input %s without doing age arithmetic', (dateOfBirth) => {
    expect(guardianProfileRequestSchema.safeParse({ ...profile, dateOfBirth }).success).toBe(false);
  });
  it('does not impose an unapproved under-13 or future-date client rule', () => {
    expect(guardianProfileRequestSchema.safeParse({ ...profile, dateOfBirth: '2026-10-03' }).success).toBe(true);
  });
  it.each([
    { ...profile, tenantId: MEMBER }, { ...profile, guardianLinkedAt: '2026-10-02' },
    { ...profile, guardian: { ...profile.guardian, userId: MEMBER } },
    { ...profile, guardian: { ...profile.guardian, name: ' ' } },
    { ...profile, guardian: { ...profile.guardian, relation: 'friend' } },
    { ...profile, guardian: { ...profile.guardian, phone: '9876543210' } },
    { ...profile, guardian: { ...profile.guardian, email: 'mira @example.com' } },
    { ...profile, guardian: { ...profile.guardian, email: 'mira@example' } },
    { ...profile, memberId: 'not-a-uuid' },
  ])('refuses forged or incomplete profile request %#', (body) => {
    expect(guardianProfileRequestSchema.safeParse(body).success).toBe(false);
  });
  it('measures trimmed name, source and handover boundaries', () => {
    const name = 'n'.repeat(GUARDIAN_LIMITS.nameMaxLength);
    expect(guardianProfileRequestSchema.safeParse({ ...profile, guardian: { ...profile.guardian, name: ` ${name} ` } }).success).toBe(true);
    expect(guardianProfileRequestSchema.safeParse({ ...profile, guardian: { ...profile.guardian, name: `${name}x` } }).success).toBe(false);
    const source = 's'.repeat(GUARDIAN_LIMITS.sourceMaxLength);
    expect(guardianConsentRequestSchema.parse({ memberId: MEMBER, granted: false, source: ` ${source} ` }).source).toBe(source);
    expect(guardianConsentRequestSchema.safeParse({ memberId: MEMBER, granted: true, source: `${source}x` }).success).toBe(false);
    const reason = 'r'.repeat(GUARDIAN_LIMITS.reasonMaxLength);
    expect(guardianHandoverRequestSchema.safeParse({ memberId: MEMBER, reason }).success).toBe(true);
    for (const invalid of ['ab', '   ', `${reason}x`]) expect(guardianHandoverRequestSchema.safeParse({ memberId: MEMBER, reason: invalid }).success).toBe(false);
  });
  it.each(['version', 'guardianName', 'guardianRelation', 'recordedAt', 'recordedByStaffId', 'tenantId'])('never accepts client-owned consent metadata %s', (key) => {
    expect(guardianConsentRequestSchema.safeParse({ memberId: MEMBER, granted: true, source: 'Paper form', [key]: 'forged' }).success).toBe(false);
  });
  it.each([null, 'true', 1, undefined])('requires a real boolean for consent %s', (granted) => {
    expect(guardianConsentRequestSchema.safeParse({ memberId: MEMBER, granted, source: 'Paper form' }).success).toBe(false);
  });
});

describe('GRD consequence-first copy', () => {
  const copy = {
    on_adult: 'Absence follow-ups are on.',
    on_consent: "Absence follow-ups are on, with the guardian's consent on record.",
    off_age_unknown: 'Absence follow-ups are off. Add a date of birth to turn them on.',
    off_no_guardian: "Absence follow-ups are off. Add the guardian's name, relation and phone.",
    off_no_consent: "Absence follow-ups are off until the guardian's consent is recorded.",
    off_consent_withdrawn: 'The guardian withdrew consent, so absence follow-ups are off. Visits are still recorded.',
    off_consent_stale: "The guardian's details changed after consent was recorded, so absence follow-ups are off. Record consent again.",
  };
  it.each(Object.entries(copy))('pins %s', (state, sentence) => {
    expect(guardianScoringMessage(state)).toBe(sentence);
    expect(GUARDIAN_SCORING_COPY).toHaveProperty(state, sentence);
  });
  it.each(['constructor', '__proto__', 'unknown', 'ON_ADULT'])('fails safe for unrecognized state %s', (state) => {
    expect(guardianScoringMessage(state)).toBe('Absence follow-ups are off.');
  });
  it('pins the consent statement and version together', () => {
    expect(GUARDIAN_CONSENT_VERSION).toBe('guardian-absence-v1');
    expect(guardianConsentStatement({ gymName: 'River Studio', memberName: 'Asha Rao', guardianName: 'Mira Rao', relation: 'legal_guardian' }))
      .toBe("I, Mira Rao, am Asha Rao's legal guardian. I agree that River Studio may use Asha Rao's visit records to notice when they stop coming, and may contact me about it. Asha Rao's visits are recorded either way. I can withdraw this at any time by telling River Studio.");
  });
  it('directs the guardian to their specified Google account, using first names only', () => {
    expect(guardianInviteShareMessage({ guardianName: 'Mira Rao', memberName: 'Asha Rao', gymName: 'River Studio', email: 'mira@example.com', link: 'https://example.com/invite/link' }))
      .toBe("Hi Mira, River Studio invited Asha to join on FitCruxx. Open this link and sign in with Google using mira@example.com so Asha's membership connects: https://example.com/invite/link");
  });
  it('excludes tracked members from the off count and uses caller business nouns', () => {
    expect(guardianCoverageLines({ tracked: 90, noBirthDate: 1, minorNoGuardian: 2, minorConsentMissing: 1, handoverDue: 1 }, { members: 'students' }))
      .toEqual(['Absence follow-ups are off for 4 students with a live membership.', '1 has no date of birth.',
        '2 are under 18 without a guardian on file.', '1 is under 18 without current guardian consent.',
        "1 turned 18 and still signs in through a guardian's account."]);
    expect(guardianCoverageLines({ tracked: 90, noBirthDate: 0, minorNoGuardian: 0, minorConsentMissing: 0, handoverDue: 0 })).toEqual([]);
    expect(guardianCoverageLines({ tracked: 0, noBirthDate: 0, minorNoGuardian: 0, minorConsentMissing: 0, handoverDue: 2 }))
      .toEqual(["2 turned 18 and still sign in through a guardian's account."]);
  });
});
