import { createServerSupabase } from '../../../lib/supabase/server';

export default async function MembersPage({
  searchParams,
}: {
  searchParams: Promise<{ q?: string }>;
}) {
  const { q } = await searchParams;
  const phone = q?.trim() ?? '';

  const supabase = await createServerSupabase();

  // There is deliberately no `.eq('tenant_id', …)` here, and adding one
  // would be a defect rather than an optimisation. The client carries the
  // caller's own session, so the row-security policy on `members` does the
  // filtering. An application-side tenant predicate would return the right
  // rows even if the policy were broken or missing, which is precisely the
  // failure the pgTAP suite exists to catch — it would hide it behind the
  // screen instead.
  const query = supabase.from('members').select('id, full_name, phone, status');
  const { data: members, error } = await (
    phone ? query.ilike('phone', `%${phone}%`) : query
  ).order('full_name');

  return (
    <main className="mx-auto max-w-3xl px-6 py-8">
      <h1 className="text-xl font-semibold">Members</h1>

      <form method="get" className="mt-4 flex gap-2">
        <input
          type="search"
          name="q"
          defaultValue={phone}
          placeholder="Search by phone number"
          aria-label="Search by phone number"
          className="w-full rounded-md border border-neutral-300 px-3 py-2 text-base outline-none focus:border-neutral-900"
        />
        <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
          Search
        </button>
      </form>

      {error ? (
        <p role="alert" className="mt-6 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          The member list could not be loaded. {error.message}
        </p>
      ) : null}

      {members && members.length > 0 ? (
        <table className="mt-6 w-full border-collapse text-left text-sm">
          <thead>
            <tr className="border-b border-neutral-200 text-neutral-600">
              <th scope="col" className="py-2 font-medium">
                Name
              </th>
              <th scope="col" className="py-2 font-medium">
                Phone
              </th>
              <th scope="col" className="py-2 font-medium">
                Status
              </th>
            </tr>
          </thead>
          <tbody>
            {members.map((member) => (
              <tr key={member.id} className="border-b border-neutral-100">
                <td className="py-2">{member.full_name}</td>
                <td className="py-2 tabular-nums">{member.phone}</td>
                <td className="py-2">{member.status}</td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : null}

      {!error && members?.length === 0 ? (
        <p className="mt-6 text-sm text-neutral-600">
          {phone ? 'No member of this gym has that phone number.' : 'No members yet.'}
        </p>
      ) : null}
    </main>
  );
}
