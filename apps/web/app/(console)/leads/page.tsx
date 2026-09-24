import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { ChevronDown, Plus } from 'lucide-react';
import { loadLeads, type LeadListRow } from '../../../lib/leads';
import { UI_TOKENS, formatDateTime, humanize } from '@gymloop/shared';
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

/** The select filters a desk can narrow by; their count labels the phone disclosure. */
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

  const activeFilters = FILTER_KEYS.filter((key) => Boolean(params[key])).length;
  const countsMatch = screen.pageResultCount === screen.totalMatchingCount;

  return <main className="cl-page">
    {/* The header is a grid (leads.css) so the one action sits on the title's
        row instead of drifting down to the subtitle. */}
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
      {/* On a phone the four selects fold behind one disclosure so the first lead
          is on screen; wider layouts show them inline (leads.css). */}
      <details className="leads-filter-more" open={activeFilters > 0 ? true : undefined}>
        <summary className="cl-btn">Filters{activeFilters > 0 ? ` (${activeFilters})` : ''}<ChevronDown aria-hidden="true" className="leads-chevron" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} /></summary>
        {filterSpecs(screen).map((spec) => <Field key={spec.name} label={spec.label}>
          <select name={spec.name} defaultValue={params[spec.name] ?? ''} className={inputClass}>
            <option value="">{spec.allLabel}</option>
            {spec.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </Field>)}
      </details>
      <Field label="Search">
        <input name="q" defaultValue={params.q ?? ''} type="search" placeholder="Name or phone" className={inputClass} />
      </Field>
      <button type="submit" className="cl-btn">Apply filters</button>
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
      <div className="cl-section-head">
        <h2 id="pipeline-heading" className="cl-section-title">Pipeline</h2>
      </div>
      {screen.rows.length === 0 && screen.errorMessage === null
        ? <div className="cl-empty"><strong>No leads here</strong><p>No leads match these filters. Record an enquiry below or clear the filters.</p></div>
        : null}
      {screen.rows.length > 0 ? <div className="leads-ledger">
        {/* Four labelled tracks wherever the ledger has room (leads.css): who the
            lead is, where they came from and who owns them, where they stand
            with the step that follows, and the one thing to do. */}
        <div className="leads-ledger-head" aria-hidden="true">
          <span>Lead</span><span>Source · Assignee</span><span>Stage</span><span>Action</span>
        </div>
        <ul>
          {screen.rows.map((row) => {
            const action = nextActionText(row, screen.timezone, now);
            const open = row.stage !== 'converted' && row.stage !== 'lost';
            const member = row.stage === 'converted' && row.convertedMemberId !== null ? row.convertedMemberId : null;
            return <li key={row.id} className="leads-row" data-stage={row.stage}>
              <span className="leads-cell-lead">
                <span className="cl-row-title">{row.fullName}</span>
                <span className="leads-phone tabular-nums">{row.phone}</span>
              </span>
              <span className="leads-cell-meta">
                <span>{humanize(row.source)} · {row.branchName}</span>
                <span className="leads-assignee">{row.assignedToName ?? 'Unassigned'}</span>
              </span>
              <span className="leads-cell-stage">
                <StatusWord status={row.stage} />
                {/* One empty-value treatment: a secondary dash wherever a row has nothing to say. */}
                {row.stage === 'lost' && row.lostReason !== null
                  ? <span className="leads-cell-next">Reason: {row.lostReason}</span>
                  : action !== null
                    ? <span className="leads-cell-next">Next: {action}</span>
                    : <span className="leads-cell-next leads-empty"><span aria-hidden="true">—</span><span className="sr-only">No next step</span></span>}
              </span>
              <span className="leads-cell-action">
                {member !== null
                  ? <Link className="cl-btn cl-btn--small" href={`/members/${member}`}>Open member</Link>
                  : null}
                {!open && member === null
                  ? <span className="leads-empty"><span aria-hidden="true">—</span><span className="sr-only">No action</span></span>
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
