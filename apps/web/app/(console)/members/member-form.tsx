import { MutationForm } from '../../preview-context';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';
import { Constants } from '@gymloop/db';
import { UI_TOKENS, formatDay, humanize } from '@gymloop/shared';
import { Alert } from '../alert';
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

const FIELD_CLASS = 'cl-input';

function Field({
  label,
  hint,
  children,
}: {
  label: string;
  hint?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <label className="cl-field">
      <span>{label}</span>
      {children}
      {hint === undefined ? null : <small>{hint}</small>}
    </label>
  );
}

export async function MemberForm({
  title,
  action,
  cancelHref,
  backLabel,
  member,
  submitted,
}: {
  title: string;
  action: string;
  cancelHref: string;
  backLabel: string;
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
  const creating = member === null;

  // A gym with exactly one branch has nothing to choose: that branch is
  // preselected, the same rule the leads enquiry form follows, and the
  // "Choose a branch" prompt appears only when there is a real choice.
  const branchChoices = branches ?? [];
  const onlyBranch = branchChoices.length === 1 ? branchChoices[0] : undefined;
  const branchValue = value('branch_id') || (onlyBranch?.id ?? '');

  // The date control shows the browser's numeric pattern (04-08-2026), so an
  // edit repeats the stored day in the product's own words beneath it.
  const joined = value('joined_on');
  const joinedHint = creating
    ? 'Leave blank for today.'
    : /^\d{4}-\d{2}-\d{2}$/.test(joined) && !Number.isNaN(Date.parse(joined)) ? `Joined ${formatDay(joined)}` : undefined;

  return (
    <main className="cl-page">
      <Link href={cancelHref} className="cl-back">
        <ArrowLeft aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
        {backLabel}
      </Link>
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Members</p>
          <h1 className="cl-title">{title}</h1>
        </div>
      </div>

      <div className="member-form-layout cl-section">
        <MutationForm method="post" action={action} className="cl-form">
          {error === undefined ? null : <Alert>{error}</Alert>}

          <Field label="Full name">
            <input
              name="full_name"
              required
              defaultValue={value('full_name')}
              autoComplete="name"
              className={FIELD_CLASS}
            />
          </Field>

          <Field label="Phone" hint="Include +91, no spaces.">
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

          <Field label="Email (optional)">
            <input
              name="email"
              type="email"
              defaultValue={value('email')}
              autoComplete="email"
              className={FIELD_CLASS}
            />
          </Field>

          <Field label="Branch">
            <select name="branch_id" required defaultValue={branchValue} className={FIELD_CLASS}>
              {onlyBranch === undefined ? <option value="">Choose a branch</option> : null}
              {branchChoices.map((branch) => (
                <option key={branch.id} value={branch.id}>
                  {branch.name}
                </option>
              ))}
            </select>
          </Field>

          {/* Status and the join date are the membership-facing facts, so they
            share a row; the date field is sized for a date, not the column. */}
          <div className="member-form-pair">
            <Field label="Status">
              {/* The vocabulary comes from the generated types, so it is the
                `member_status` Postgres enum and not a copy of it (AGENTS.md
                rule 5). A new value in the migration appears here on the next
                `supabase gen types`. */}
              <select
                name="status"
                defaultValue={value('status') || Constants.public.Enums.member_status[0]}
                className={FIELD_CLASS}
              >
                {Constants.public.Enums.member_status.map((status) => (
                  <option key={status} value={status}>
                    {humanize(status)}
                  </option>
                ))}
              </select>
            </Field>

            <Field label="Joined on" hint={joinedHint}>
              <input name="joined_on" type="date" defaultValue={joined} className={FIELD_CLASS} />
            </Field>
          </div>

          <div className="member-form-actions">
            <button type="submit" className="cl-btn cl-btn--primary">
              {creating ? 'Add member' : 'Save changes'}
            </button>
            <Link href={cancelHref} className="cl-btn">
              Cancel
            </Link>
          </div>
        </MutationForm>

        {/* Adding is a sequence, so its note is numbered; editing is not, so its note is the one fact worth saying. */}
        <aside className="member-form-note" aria-labelledby="member-form-note-title">
          <h2 id="member-form-note-title" className="cl-eyebrow">
            {creating ? 'What happens next' : 'About editing'}
          </h2>
          {creating ? (
            <ol>
              <li>The member appears in Members straight away, searchable by phone.</li>
              <li>Open their page and sell a membership, so renewals and visits are tracked.</li>
            </ol>
          ) : (
            <p>Memberships, payments and visits stay on the member&apos;s page and are not changed here.</p>
          )}
        </aside>
      </div>
    </main>
  );
}
