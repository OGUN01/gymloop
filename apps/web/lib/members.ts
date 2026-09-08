import { createServerSupabase } from './supabase/server';

/**
 * The member list both console screens read — the roster and the check-in gate.
 *
 * One function rather than the same six lines twice, because the interesting
 * part of it is what is *absent*: there is deliberately no `.eq('tenant_id', …)`.
 * The client carries the caller's own session, so `members_tenant_select` does
 * the filtering; an application-side tenant predicate would return the right
 * rows even with the policy broken or missing, which is precisely the defect the
 * pgTAP suite exists to catch — it would hide it behind the screen instead. A
 * second copy of this query is a second place for somebody to be helpful and add
 * one.
 *
 * Phone is matched as a substring so a front desk can type the last four digits
 * of a number read aloud, which is how a person at a counter identifies the
 * person in front of them.
 *
 * It takes the page's `searchParams` promise rather than a string so that the
 * trimming, the empty-search case and the error shape are decided once too.
 */
export async function loadMemberSearch(searchParams: Promise<{ q?: string }>) {
  const { q } = await searchParams;
  const phone = q?.trim() ?? '';

  const supabase = await createServerSupabase();
  const query = supabase.from('members').select('id, full_name, phone, status');
  const { data, error } = await (phone ? query.ilike('phone', `%${phone}%`) : query).order(
    'full_name',
  );

  return { phone, members: data ?? [], errorMessage: error ? error.message : null };
}
