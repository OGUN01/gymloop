import { MutationForm } from '../../preview-context';
import Link from 'next/link';
import { Constants } from '@gymloop/db';
import { formatDay, humanize } from '@gymloop/shared';
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

/** A `YYYY-MM-DD` value `formatDay` can read; anything else gets no echo. */
const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/;

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
  const joinedOn = value('joined_on');

  return (
    <main className="cl-page">
      <Link href={cancelHref} className="cl-back">
        ← {backLabel}
      </Link>
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">{creating ? 'New member' : 'Member details'}</p>
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

          <div className="cl-form-row">
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
                className={FIELD_CLASS}
              >
                {Constants.public.Enums.member_status.map((status) => (
                  <option key={status} value={status}>
                    {humanize(status)}
                  </option>
                ))}
              </select>
            </Field>
          </div>

          <Field
            label="Joined on"
            hint={
              creating ? (
                'Leave blank for today.'
              ) : ISO_DAY.test(joinedOn) ? (
                <span className="member-form-echo">{formatDay(joinedOn)}</span>
              ) : undefined
            }
          >
            <input name="joined_on" type="date" defaultValue={joinedOn} className={FIELD_CLASS} />
          </Field>

          <div className="member-form-actions">
            <button type="submit" className="cl-btn cl-btn--primary">
              {creating ? 'Add member' : 'Save changes'}
            </button>
            <Link href={cancelHref} className="cl-btn">
              Cancel
            </Link>
          </div>
        </MutationForm>

        <aside className="member-form-note" aria-labelledby="member-form-next">
          <h2 id="member-form-next" className="cl-eyebrow">
            What happens next
          </h2>
          {creating ? (
            <ol>
              <li>The member appears in Members straight away, searchable by phone.</li>
              <li>Open their page and sell a membership, so renewals and visits are tracked.</li>
            </ol>
          ) : (
            <ol>
              <li>Changes apply as soon as you save.</li>
              <li>
                Memberships, payments and visits stay on the member&apos;s page and are not changed here.
              </li>
            </ol>
          )}
        </aside>
      </div>
    </main>
  );
}
