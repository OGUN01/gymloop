import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { loadLeads, type LeadListRow } from '../../../lib/leads';
import { deskTime } from '../../../lib/time';
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

/** A vocabulary value as a sentence-case word: `walk_in` → "Walk in". */
function say(value: string): string {
  const words = value.replaceAll('_', ' ');
  return words.charAt(0).toUpperCase() + words.slice(1);
}

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
        return `Trial at ${deskTime(row.trialAt, timezone)}`;
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
      options: Constants.public.Enums.lead_stage.map((stage) => ({ value: stage, label: say(stage) })),
    },
    {
      name: 'source',
      label: 'Source',
      allLabel: 'All sources',
      options: Constants.public.Enums.lead_source.map((source) => ({ value: source, label: say(source) })),
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

  return <main className="cl-page">
    <div className="cl-page-header">
      <div>
        <p className="cl-eyebrow">Front office</p>
        <h1 className="cl-title">Leads</h1>
        <p className="cl-lede">Every enquiry from first contact to a converted member or a recorded loss.</p>
      </div>
      <div className="cl-actions">
        <Link href="/console" className="cl-btn">Members</Link>
      </div>
    </div>

    <form method="get" action="/leads" className="cl-form cl-section">
      <div className="cl-form-row">
        {filterSpecs(screen).map((spec) => <Field key={spec.name} label={spec.label}>
          <select name={spec.name} defaultValue={params[spec.name] ?? ''} className={inputClass}>
            <option value="">{spec.allLabel}</option>
            {spec.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
          </select>
        </Field>)}
        <Field label="Search">
          <input name="q" defaultValue={params.q ?? ''} type="search" className={inputClass} />
        </Field>
        <button type="submit" className="cl-btn">Apply filters</button>
      </div>
    </form>

    {screen.errorMessage === null ? <section aria-labelledby="counts-heading" className="cl-section">
      <div className="cl-section-head">
        <h2 id="counts-heading" className="cl-section-title">Counts</h2>
        {screen.asOf !== null
          ? <p className="cl-muted text-sm">Snapshot as of {deskTime(screen.asOf, screen.timezone)} ({screen.timezone}).</p>
          : null}
      </div>
      <div className="cl-metrics">
        <div className="cl-metric"><span className="cl-eyebrow">Showing on this page</span><span className="cl-metric-value">{screen.pageResultCount}</span></div>
        <div className="cl-metric"><span className="cl-eyebrow">Matching leads</span><span className="cl-metric-value">{screen.totalMatchingCount}</span></div>
      </div>
      <h3 className="cl-eyebrow mt-6">Within current filters</h3>
      <ul className="mt-2 flex flex-wrap gap-x-6 gap-y-2">
        {Constants.public.Enums.lead_stage.map((stage) => <li key={stage} className="flex items-baseline gap-2">
          <StatusWord status={stage} /> <strong className="tabular-nums">{screen.stageCounts[stage]}</strong>
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
      {screen.rows.length > 0 ? <ul className="cl-rows">
        {screen.rows.map((row) => {
          const action = nextActionText(row, screen.timezone, now);
          const open = row.stage !== 'converted' && row.stage !== 'lost';
          return <li key={row.id}>
            <span>
              <span className="cl-row-title">{row.fullName} · <span className="tabular-nums">{row.phone}</span></span>
              <span className="cl-row-meta">
                {say(row.source)} · {row.branchName} · {row.assignedToName ?? 'Unassigned'}
              </span>
              {row.stage === 'lost' && row.lostReason !== null
                ? <span className="cl-row-meta">Lost: {row.lostReason}</span>
                : null}
            </span>
            <span className="flex flex-wrap items-center gap-4">
              <StatusWord status={row.stage} />
              {action !== null ? <strong>{action}</strong> : null}
              {row.stage === 'converted' && row.convertedMemberId !== null
                ? <Link className="cl-btn cl-btn--small" href={`/members/${row.convertedMemberId}`}>Open member</Link>
                : null}
            </span>
            {row.stage === 'trial_done'
              ? <div className="w-full"><LeadConvertDialog leadId={row.id} revision={row.revision} fullName={row.fullName} /></div>
              : null}
            {open ? <div className="w-full">
              <details className="cl-disclosure"><summary>Change stage</summary>
                <LeadStageForm leadId={row.id} revision={row.revision} stage={row.stage} timezone={screen.timezone} trialAt={row.trialAt} />
              </details>
              <details className="cl-disclosure"><summary>Edit details</summary>
                <LeadEditForm leadId={row.id} revision={row.revision} lead={row} branches={screen.branchChoices} staff={screen.staffChoices} emailNotes={screen.editableText[row.id]} />
              </details>
            </div> : null}
          </li>;
        })}
      </ul> : null}
      {screen.nextCursor !== null
        ? <div className="cl-pager"><Link className="cl-btn" href={nextPageHref(params, screen.nextCursor)}>Next page</Link></div>
        : null}
    </section>

    <LeadEnquiryForm branches={screen.branchChoices} staff={screen.staffChoices} />
  </main>;
}
