import Link from 'next/link';
import { guardianCoverageLines, type GuardianAttentionReason } from '@gymloop/shared';
import type { GuardianCoverage } from '../../../lib/guardian';
import type { StaffRole } from '../../../lib/identity';
import { StatusWord } from '../../status-word';
import { LegacyAdultAttestationBanner } from './legacy-adult-attestation-banner';
import '../../styles/guardian.css';

export function GuardianCoverageNote({ coverage, role, readOnly, nouns }: { coverage: GuardianCoverage | null; role: StaffRole; readOnly?: boolean; nouns?: { members: string } }) {
  if (coverage === null || role === 'trainer') return null;
  const lines = guardianCoverageLines(coverage, nouns);
  const before = coverage.membersWithoutDobAttestedAdultAt === null;
  if (!before && lines.length === 0) return null;
  const categories: { reason: GuardianAttentionReason; count: number }[] = [
    { reason: 'no_birth_date', count: coverage.noBirthDate }, { reason: 'minor_no_guardian', count: coverage.minorNoGuardian },
    { reason: 'minor_consent_missing', count: coverage.minorConsentMissing }, { reason: 'handover_due', count: coverage.handoverDue },
  ];
  const off = coverage.noBirthDate + coverage.minorNoGuardian + coverage.minorConsentMissing;
  let lineIndex = off > 0 ? 1 : 0;
  return <section className="guardian-coverage" aria-label="Absence follow-up coverage">
    <StatusWord status="coverage" label="Absence follow-up coverage" />
    {before ? <LegacyAdultAttestationBanner role={role} readOnly={readOnly ?? false} /> : null}
    {off > 0 ? <p>{lines[0]}</p> : null}
    <ul>{categories.filter((category) => category.count > 0).map((category) => <li key={category.reason}><Link href={`/members/attention?reason=${category.reason}`}>{lines[lineIndex++]}</Link></li>)}</ul>
  </section>;
}
