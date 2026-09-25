import { requireAudience } from '../../../../lib/identity-session';
import { loadMemberSearch } from '../../../../lib/members';
import { loadMembershipStanding } from '../../../../lib/membership-state';
import { MemberSearchPage } from '../member-search-page';
import { CheckInGate } from './check-in-gate';

/**
 * The check-in screen. The bar is a metro gate (`docs/architecture.md`): the
 * confirmation is the design, so it is the largest thing on the page and it
 * stays up until the next one replaces it.
 *
 * Split the way every screen in this app is: the read is a Server Component
 * going straight through `supabase-js` with RLS doing the filtering, and only
 * the parts that need a camera and a keyboard are a client component.
 */
export default async function CheckInPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string; cursor?: string; limit?: string }>;
}) {
  const search = await loadMemberSearch(searchParams);
  const { supabase, identity } = await requireAudience('console');
  const { data: settings } = await supabase.from('organization_settings')
    .select('checkin_gate_mode').maybeSingle();
  // Remove the narrow assertion after CI applies the migration and DB types regenerate.
  const mode = (settings as { checkin_gate_mode: 'printed_poster' | 'rotating_screen' } | null)?.checkin_gate_mode;
  const canManageGate = identity.kind === 'staff' &&
    (identity.role === 'gym_owner' || identity.role === 'gym_manager');
  // The STATUS column says what the roster and Memberships say: the membership's
  // standing, with a blocked or cancelled account outranking it.
  const standingById = await loadMembershipStanding(search.members);
  const members = search.members.map((member) => {
    const word = standingById.get(member.id);
    return word ? { ...member, standing: { status: word.status, label: word.label } } : member;
  });

  return (
    <MemberSearchPage
      title="Check-in"
      linkHref="/console"
      linkLabel="Members"
      phone={search.phone}
      errorMessage={search.errorMessage}
      nextCursor={search.nextCursor}
      pageSize={search.pageSize}
    >
      <CheckInGate members={members} mode={mode} canManageGate={canManageGate} />
    </MemberSearchPage>
  );
}
