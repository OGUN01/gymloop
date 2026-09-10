import { MutationForm } from '../../preview-context';
import Link from 'next/link';
import { Constants } from '@gymloop/db';
import { createServerSupabase } from '../../../lib/supabase/server';

/**
 * The one member form — used to add a member and to change one.
 *
 * A real `<MutationForm method="post">` posting to a Route Handler, with no client
 * component anywhere in it, so it submits before any JavaScript has loaded.
 *
 * Two things it deliberately does not do.
 *
 * **It does not re-state the phone rule.** There is no `pattern` attribute
 * carrying a copy of `members_phone_format_chk`'s regex. The database is the
 * only place that rule lives; a second copy here would be one more thing to
 * keep in step, and the interesting path — a bad number coming back as a
 * sentence rather than a stack trace — is the one that would then never run.
 * The placeholder shows the shape instead.
 *
 * **It does not name a gym.** There is no tenant field, hidden or otherwise:
 * the branch list below is whatever RLS returns for this session, and the
 * handler stamps the tenant from the verified claim.
 *
 * `submitted` is the echo of a rejected submission, so a typo in the phone
 * number does not cost the front desk the other five fields.
 */

type MemberDefaults = {
  full_name: string;
  phone: string;
  email: string | null;
  status: string;
  branch_id: string;
  joined_on: string;
};

const FIELD_CLASS =
  'mt-1 w-full rounded-md border border-neutral-300 px-3 py-2 text-base outline-none focus:border-neutral-900';

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="text-sm font-medium text-neutral-700">{label}</span>
      {children}
      {hint === undefined ? null : <span className="mt-1 block text-xs text-neutral-500">{hint}</span>}
    </label>
  );
}

export async function MemberForm({
  title,
  action,
  cancelHref,
  member,
  submitted,
}: {
  title: string;
  action: string;
  cancelHref: string;
  member: MemberDefaults | null;
  submitted: Record<string, string | undefined>;
}) {
  // No `.eq('tenant_id', …)`: the policy on `branches` decides which gym's
  // branches this session can see, and it is also what the foreign key will
  // check when the row is written.
  const supabase = await createServerSupabase();
  const { data: branches } = await supabase.from('branches').select('id, name').order('name');

  const value = (name: keyof MemberDefaults) =>
    submitted[name] ?? (member === null ? '' : (member[name] ?? ''));

  const error = submitted.error;

  return (
    <main className="mx-auto max-w-lg px-6 py-8">
      <div className="flex items-baseline justify-between">
        <h1 className="text-xl font-semibold">{title}</h1>
        <Link href={cancelHref} className="text-sm text-neutral-600 underline">
          Cancel
        </Link>
      </div>

      {error === undefined ? null : (
        <p role="alert" className="mt-4 rounded-md bg-red-50 px-3 py-2 text-sm text-red-700">
          {error}
        </p>
      )}

      <MutationForm method="post" action={action} className="mt-6 space-y-4">
        <Field label="Full name">
          <input
            name="full_name"
            required
            defaultValue={value('full_name')}
            autoComplete="name"
            className={FIELD_CLASS}
          />
        </Field>

        <Field label="Phone" hint="International form — country code first, as in +919876543210.">
          <input
            name="phone"
            type="tel"
            inputMode="tel"
            required
            defaultValue={value('phone')}
            placeholder="+919876543210"
            autoComplete="tel"
            className={FIELD_CLASS}
          />
        </Field>

        <Field label="Email" hint="Optional.">
          <input
            name="email"
            type="email"
            defaultValue={value('email')}
            autoComplete="email"
            className={FIELD_CLASS}
          />
        </Field>

        <Field label="Branch">
          <select name="branch_id" required defaultValue={value('branch_id')} className={FIELD_CLASS}>
            <option value="">Choose a branch</option>
            {(branches ?? []).map((branch) => (
              <option key={branch.id} value={branch.id}>
                {branch.name}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Status">
          {/* The vocabulary comes from the generated types, so it is the
              `member_status` Postgres enum and not a copy of it (AGENTS.md
              rule 5). A new value in the migration appears here on the next
              `supabase gen types`. */}
          <select
            name="status"
            defaultValue={value('status') || Constants.public.Enums.member_status[0]}
            className={`${FIELD_CLASS} capitalize`}
          >
            {Constants.public.Enums.member_status.map((status) => (
              <option key={status} value={status} className="capitalize">
                {status}
              </option>
            ))}
          </select>
        </Field>

        <Field label="Joined on" hint="Leave blank for today.">
          <input name="joined_on" type="date" defaultValue={value('joined_on')} className={FIELD_CLASS} />
        </Field>

        <button type="submit" className="rounded-md bg-neutral-900 px-4 py-2 text-white">
          Save
        </button>
      </MutationForm>
    </main>
  );
}
