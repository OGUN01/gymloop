import { readIdentity } from '../../../lib/identity-session';
import { REPORT_DATASETS, REPORT_EXPORT_STATES } from '../../../lib/report-exports';
import { DEFAULT_TIMEZONE } from '@gymloop/shared';
import { ReportExportDownloadForm } from './download-form';

/**
 * The owner Exports screen (RPE-013, CSV-first delivery). Everything a person
 * needs to judge the file is on the page before any download: what each
 * dataset records (and refuses to pretend to be), the date basis, the zone,
 * the branch semantics, the engineering limits and the contact-data and
 * spreadsheet-protection warnings. RPE-010…012 (invoice PDF) are deferred and
 * deliberately absent.
 *
 * The gate here is presentation only — the route re-derives the owner gate and
 * reads under the caller's RLS — so the screen's refusal to show download
 * controls to other roles is truthful, not the security control.
 */
export default async function ExportsPage() {
  const session = await readIdentity();
  const isOwner = session.signedIn && session.identity.kind === 'staff' && session.identity.role === 'gym_owner';

  if (!isOwner) {
    return <main className="cl-page">
      <div className="cl-page-header">
        <div>
          <p className="cl-eyebrow">Console</p>
          <h1 className="cl-title">Exports</h1>
        </div>
      </div>
      <p className="cl-muted">Exports are available to the gym owner. Ask the owner to run any export you need.</p>
    </main>;
  }

  return <main className="cl-page">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Console</p>
        <h1 className="cl-title">Exports</h1>
        <p className="cl-lede">
          Download the gym&apos;s recorded records as CSV files. Every file is
          generated from one database snapshot and stamped with when it was made,
          what range it covers and which timezone the dates are read in.
        </p>
      </div>
    </div>

    <section className="cl-section" aria-label="What each file contains">
      <div className="cl-panel">
        <h2>{REPORT_DATASETS.payments.meaning}</h2>
        <p className="cl-muted">
          Date basis: <code>created_at</code>. Every payment record in the range
          — attempts and terminal states alike, with its own status column. This
          is <strong>not net revenue</strong>: nothing is summed, and no refunds
          are netted out here.
        </p>
        <ReportExportDownloadForm dataset="payments" />
      </div>
      <div className="cl-panel">
        <h2>{REPORT_DATASETS.attendance.meaning}</h2>
        <p className="cl-muted">
          Date basis: <code>checked_in_at</code>. Gate check-ins as they were
          recorded, one row per accepted visit — not bookings, not class
          attendance, not time inside the gym.
        </p>
        <ReportExportDownloadForm dataset="attendance" />
      </div>
      <div className="cl-panel">
        <h2>{REPORT_DATASETS.members.meaning}</h2>
        <p className="cl-muted">
          Date basis: <code>joined_on</code>. Members who joined in the range —
          a joining cohort, <strong>not a roster as of the end date</strong> and
          not a membership list. Members who joined later or left are not in it.
        </p>
        <ReportExportDownloadForm dataset="members" />
      </div>
    </section>

    <section className="cl-section" aria-label="How the files are produced">
      <h2>Before you export</h2>
      <ul className="cl-disclosure">
        <li>
          Dates are read in the gym timezone ({DEFAULT_TIMEZONE}). The chosen
          start day begins at local midnight and the day after the chosen end
          day ends it.
        </li>
        <li>
          Branch filter semantics differ by dataset: payment records are
          filtered by each member&apos;s <strong>current member branch</strong>
          {' '}— not the branch that made the sale; attendance uses the branch
          recorded on the visit; members use their current branch.
        </li>
        <li>
          Limits: a range up to <strong>366</strong> days, at most{' '}
          <strong>5,000</strong> data rows and <strong>8 MiB</strong> per file,
          generated within <strong>15</strong> seconds. If a file would exceed a
          limit, nothing is released — narrow the range and try again.
        </li>
        <li>
          These files contain member contact data (names, phone numbers, email
          addresses). Handle them under the gym&apos;s privacy obligations.
        </li>
        <li>
          Text fields are spreadsheet-protected with a leading apostrophe.
          Re-saving the file in a spreadsheet can change that protection — the
          guarantee applies to the file as emitted, not to later edits.
        </li>
      </ul>
      <h3>Outcome messages</h3>
      <ul className="cl-disclosure">
        {Object.entries(REPORT_EXPORT_STATES).map(([key, state]) => (
          <li key={key}>
            <strong>{state.label}</strong> — {state.action}
            {'hint' in state && state.hint !== undefined ? ` ${state.hint}` : ''}
          </li>
        ))}
      </ul>
    </section>
  </main>;
}