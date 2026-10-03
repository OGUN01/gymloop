import Link from 'next/link';
import { redirect } from 'next/navigation';
import { guardianScoringMessage, humanize, formatPhone } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadGuardianAttention } from '../../../../lib/guardian';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { Alert } from '../../alert';
import '../../../styles/guardian.css';

const REASONS: Record<string, string> = { no_birth_date: 'Date of birth missing', minor_no_guardian: 'Guardian details missing', minor_consent_missing: 'Guardian consent needed', handover_due: 'Account handover due' };
export default async function GuardianAttentionPage({ searchParams }: { searchParams: Promise<{ reason?: string }> }) {
  const { supabase, identity } = await requireAudience('console');
  if (identity.kind === 'staff' && identity.role === 'trainer') redirect('/console');
  const reason = (await searchParams).reason ?? '';
  if (!Object.hasOwn(REASONS, reason)) redirect('/red-list');
  const [members, nouns] = await Promise.all([loadGuardianAttention(supabase, reason), loadBusinessNouns(supabase, identity.tenantId)]);
  return <main className="cl-page"><Link href="/red-list" className="cl-btn cl-btn--quiet">Back to follow-ups</Link><h1>{REASONS[reason]}</h1>
    <p>{humanize(nouns.members)} who need age, guardian or account attention.</p>
    {members === null ? <Alert>This list could not be loaded. Reload the page to try again.</Alert> : members.length === 0 ? <p>{`No ${nouns.members} need attention for this reason.`}</p> : <ul className="guardian-ledger">{members.map((member) => <li key={member.memberId}><Link href={`/members/${member.memberId}`}>{member.memberName}</Link><span>{formatPhone(member.memberPhone)}</span><p>{guardianScoringMessage(member.scoringState)}</p></li>)}</ul>}
  </main>;
}
