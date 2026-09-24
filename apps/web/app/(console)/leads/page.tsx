import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { ChevronDown, Plus } from 'lucide-react';
import { loadLeads, type LeadListRow } from '../../../lib/leads';
import { UI_TOKENS, formatDateTime, formatDay, formatPhone, humanize, toLocalDate } from '@gymloop/shared';
import { Field, inputClass } from '../field';
import { Alert } from '../alert';
import { StatusWord } from '../../status-word';
import { LeadConvertDialog, LeadEditForm, LeadEnquiryForm, LeadStageForm } from './lead-forms';

/**
 * The front-office leads pipeline: one `list_leads` snapshot, the filters the
 * desk works, and every row's derived next action. There is deliberately no
 * `GET /api/leads` — the screen is a server component reading the RPC
 * directly under RLS, so an unpermitted role never gets a JSON surface to
 * probe and the refusal happens in the loader before a single lead is read.
 */

type SearchParams = Promise<Record<string, string | undefined>>;

/** The select filters a desk can narrow by; with the search they count into the phone disclosure's label. */
const FILTER_KEYS = ['stage', 'source', 'assignee', 'branch'] as const;

/**
 * The next action a row's stage implies, in the desk's words. The labels are
 * the contract's, verbatim — they are what the front desk is trained on, and
 * a synonym here would read as a different instruction.
 */
function nextActionText(row: LeadListRow, timezone: string, now: number): string | null {
  switch (row.stage) {
    case 'new': return 'Contact lead';
    case 'contacted': return 'Schedule trial';
    case 'trial_scheduled':
      if (row.trialAt !== null && !Number.isNaN(Date.parse(row.trialAt)) && Date.parse(row.trialAt) > now) {
        return `Trial at ${formatDateTime(row.trialAt, timezone)}`;
      }
      return 'Record trial outcome';
    case 'trial_done': return 'Convert or mark lost';
    default: return null;
  }
}

/**
 * The gym-local day a lead last changed — the list's own order (`list_leads`
 * pages by `updated_at` descending) — as "21 Sep", with the year only when it
 * is not this one. Null when the instant or the zone cannot be read, so a bad
 * value drops the date instead of the row.
 */
function updatedDay(updatedAt: string, timezone: string, now: number): string | null {
  if (Number.isNaN(Date.parse(updatedAt))) return null;
  try {
    const day = formatDay(toLocalDate(updatedAt, timezone));
    const thisYear = ` ${toLocalDate(new Date(now), timezone).slice(0, 'YYYY'.length)}`;
    return day.endsWith(thisYear) ? day.slice(0, -thisYear.length) : day;
  } catch {
    return null;
  }
}

/**
 * One select filter's shape: everything the five filter controls share lives
 * in this table, so the controls cannot drift apart in markup or behavior —
 * the same reason `Field` and `inputClass` are shared imports rather than
 * five hand-rolled labels.
 */
type FilterSpec = {
  name: 'stage' | 'source' | 'assignee' | 'branch';
  label: string;
  allLabel: string;
  options: { value: string; label: string }[];
};

function filterSpecs(screen: Awaited<ReturnType<typeof loadLeads>>): FilterSpec[] {
  return [
    {
      name: 'stage',
      label: 'Stage',
      allLabel: 'All stages',
      options: Constants.public.Enums.lead_stage.map((stage) => ({ value: stage, label: humanize(stage) })),
    },
    {
      name: 'source',
      label: 'Source',
      allLabel: 'All sources',
      options: Constants.public.Enums.lead_source.map((source) => ({ value: source, label: humanize(source) })),
    },
    {
      name: 'assignee',
      label: 'Assignee',
      allLabel: 'Anyone',
      options: [
        { value: 'unassigned', label: 'Unassigned' },
        ...screen.staffChoices.map((person) => ({ value: person.id, label: person.fullName })),
      ],
    },
    {
      name: 'branch',
      label: 'Branch',
      allLabel: 'All branches',
      options: screen.branchChoices.map((branch) => ({ value: branch.id, label: branch.name })),
    },
  ];
}

/** The next page of the same filters: every truthy filter travels, the cursor rides along, and nothing else is invented. */
function nextPageHref(params: Record<string, string | undefined>, cursor: string): string {
  const query = new URLSearchParams();
  for (const key of ['stage', 'source', 'assignee', 'branch', 'q', 'limit']) {
    const value = params[key];
    if (value) query.set(key, value);
  }
  query.set('cursor', cursor);
  return `/leads?${query.toString()}`;
}

export default async function LeadsPage({ searchParams }: { searchParams: SearchParams }) {
  const [params, screen] = await Promise.all([searchParams, loadLeads(searchParams)]);
  const now = Date.now();

  const searching = (params.q?.trim() ?? '') !== '';
  const activeFilters = FILTER_KEYS.filter((key) => Boolean(params[key])).length + (searching ? 1 : 0);
  const countsMatch = screen.pageResultCount === screen.totalMatchingCount;

  return <main className="cl-page leads-page">
    {/* The header is a grid (leads.css) so the one action sits on the title's
        row, top-aligned with it, at every width — on a phone too. */}
    <div className="cl-page-header leads-header">
      <div>
        <p className="cl-eyebrow">Front office</p>
        <h1 className="cl-title">Leads</h1>
        <p className="cl-lede">Every enquiry from first contact to a converted member or a recorded loss.</p>
      </div>
      <div className="cl-actions">
        <a href="#record-enquiry" className="cl-btn"><Plus aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />New enquiry</a>
      </div>
    </div>

    <form method="get" action="/leads" className="leads-filters cl-section">
      {/* On a phone the whole bar — four selects, the search and its button —
          folds behind one disclosure row so the first number is on screen;
          wider layouts dissolve the disclosure into the bar (leads.css). */}
      <details className="leads-filter-more" open={activeFilters > 0 ? true : undefined}>
        <summary>
          <span>Search and filters{activeFilters > 0 ? <span className="leads-filter-count"> ({activeFilters})</span> : null}</span>
          <ChevronDown aria-hidden="true" className="leads-chevron" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
        </summary>
        {filterSpecs(screen).map((spec) => <Field key={spec.name} label={spec.label}>
          <select name={spec.name} defaultValue={params[spec.name] ?? ''} className={inputClass}>
            <option value="">{spec.allLabel}</option>
            {spec.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </Field>)}
        <div className="leads-filter-span">
          <Field label="Search">
            <input name="q" defaultValue={params.q ?? ''} type="search" placeholder="Name or phone" className={inputClass} />
          </Field>
        </div>
        <button type="submit" className="cl-btn leads-filter-span">Apply filters</button>
      </details>
    </form>

    {screen.errorMessage === null ? <section aria-labelledby="counts-heading" className="cl-section leads-counts-block">
      <div className="cl-section-head">
        <h2 id="counts-heading" className="cl-eyebrow">Within current filters</h2>
        <p className="leads-counts-meta">
          {countsMatch
            ? <><span className="tabular-nums">{screen.totalMatchingCount}</span> leads</>
            : <>Showing on this page: <span className="tabular-nums">{screen.pageResultCount}</span> · Matching leads: <span className="tabular-nums">{screen.totalMatchingCount}</span></>}
          {screen.asOf !== null ? <> · Updated {formatDateTime(screen.asOf, screen.timezone)}</> : null}
        </p>
      </div>
      <ul className="leads-counts">
        {Constants.public.Enums.lead_stage.map((stage) => <li key={stage}>
          <strong className="leads-count-value">{screen.stageCounts[stage]}</strong>
          <StatusWord status={stage} />
        </li>)}
      </ul>
    </section> : null}

    {screen.errorMessage !== null ? <div className="cl-section"><Alert>{screen.errorMessage}</Alert></div> : null}

    <section aria-labelledby="pipeline-heading" className="cl-section">
      <div className="cl-section-head leads-section-head">
        <h2 id="pipeline-heading" className="cl-section-title">Pipeline</h2>
        {screen.rows.length > 1 ? <p className="leads-section-note">Recently updated first</p> : null}
      </div>
      {screen.rows.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No leads here</strong><p>No leads match these filters. Record an enquiry below or clear the filters.</p></div>
        : null}
      {screen.rows.length > 0 ? <div className="leads-ledger">
        {/* Five labelled columns when the page is wide, starting on the filter
            and count lines above (leads.css): who the lead is, where they came
            from, who owns them, where they stand with the step that follows,
            and the one thing to do. Narrower, source and owner fold under the
            lead, with the owner labelled in words. */}
        <div className="leads-ledger-head" aria-hidden="true">
          <span>Lead</span><span>Source · Branch</span><span>Assignee</span><span>Stage</span><span>Action</span>
        </div>
        <ul>
          {screen.rows.map((row) => {
            const action = nextActionText(row, screen.timezone, now);
            const open = row.stage !== 'converted' && row.stage !== 'lost';
            const member = row.stage === 'converted' && row.convertedMemberId !== null ? row.convertedMemberId : null;
            const updated = updatedDay(row.updatedAt, screen.timezone, now);
            // A terminal stage says only what is true of it — the loss reason
            // when one was recorded — and otherwise nothing, never a dash.
            const detail = row.stage === 'lost'
              ? (row.lostReason !== null ? `Reason: ${row.lostReason}` : null)
              : action !== null ? `Next: ${action}` : null;
            return <li key={row.id} className="leads-row" data-stage={row.stage}>
              <span className="leads-cell-lead">
                <span className="cl-row-title">{row.fullName}</span>
                <span className="leads-sub">
                  <span className="tabular-nums">{formatPhone(row.phone)}</span>
                  {updated !== null ? <> · <time className="leads-updated" dateTime={row.updatedAt}><span className="sr-only">updated </span>{updated}</time></> : null}
                </span>
              </span>
              <span className="leads-cell-source">{humanize(row.source)} · {row.branchName}</span>
              <span className="leads-cell-assignee"><span className="leads-assignee-label">Assignee: </span>{row.assignedToName ?? 'Unassigned'}</span>
              <span className="leads-cell-stage">
                <StatusWord status={row.stage} />
                {detail !== null ? <span className="leads-sub leads-cell-next">{detail}</span> : null}
              </span>
              <span className="leads-cell-action">
                {member !== null
                  ? <Link className="cl-btn cl-btn--small" href={`/members/${member}`}>Open member</Link>
                  : null}
                {open ? <details className="leads-toggle leads-toggle--act">
                  <summary className="cl-btn cl-btn--small">{row.stage === 'trial_done' ? 'Convert' : 'Change stage'}</summary>
                </details> : null}
                {open ? <details className="leads-toggle leads-toggle--edit">
                  <summary className="leads-edit-summary">Edit<ChevronDown aria-hidden="true" className="leads-chevron" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></summary>
                </details> : null}
              </span>
              {open ? <div className="leads-panel leads-panel--act">
                {row.stage === 'trial_done'
                  ? <LeadConvertDialog leadId={row.id} revision={row.revision} fullName={row.fullName} />
                  : null}
                <LeadStageForm leadId={row.id} revision={row.revision} stage={row.stage} timezone={screen.timezone} trialAt={row.trialAt} />
              </div> : null}
              {open ? <div className="leads-panel leads-panel--edit">
                <LeadEditForm leadId={row.id} revision={row.revision} lead={row} branches={screen.branchChoices} staff={screen.staffChoices} emailNotes={screen.editableText[row.id]} />
              </div> : null}
            </li>;
          })}
        </ul>
      </div> : null}
      {screen.nextCursor !== null
        ? <div className="cl-pager"><Link className="cl-btn" href={nextPageHref(params, screen.nextCursor)}>Next page</Link></div>
        : null}
    </section>

    <LeadEnquiryForm branches={screen.branchChoices} staff={screen.staffChoices} />
  </main>;
}
