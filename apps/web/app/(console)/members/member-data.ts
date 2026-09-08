import { createServerSupabase } from '../../../lib/supabase/server';

/**
 * One member, read as the caller.
 *
 * Shared by the detail screen and the edit form so that both ask for the same
 * columns — otherwise the form quietly stops offering a field the detail screen
 * shows, which is how an edit starts blanking a column nobody meant to touch.
 *
 * There is no `.eq('tenant_id', …)` and there must never be one: the client
 * carries the caller's session, `members_tenant_select` does the filtering, and
 * a member id from another gym therefore reads as absent. An application-side
 * tenant predicate would return the right row even with that policy broken,
 * which is exactly the defect the pgTAP suite exists to catch — it would hide
 * it behind the screen instead.
 *
 * `maybeSingle()` rather than `single()`: a member of another gym is not an
 * error, it is a 404, and it must be indistinguishable from a member who does
 * not exist at all.
 */
export async function loadMember(memberId: string) {
  const supabase = await createServerSupabase();

  return supabase
    .from('members')
    .select('id, full_name, phone, email, status, branch_id, joined_on, member_code, erased_at')
    .eq('id', memberId)
    .maybeSingle();
}
