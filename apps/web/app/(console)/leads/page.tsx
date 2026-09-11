import { Constants } from '@gymloop/db';
import Link from 'next/link';
import { loadLeads, type LeadListRow } from '../../../lib/leads';
import { deskTime } from '../../../lib/time';
import { Field, inputClass } from '../field';
import { Alert } from '../alert';
import { LeadConvertDialog, LeadEditForm, LeadEnquiryForm, LeadStageForm } from './lead-forms';

/**
 * The front-office leads pipeline: one `list_leads` snapshot, the filters the
 * desk works, and every row's derived next action. There is deliberately no
 * `GET /api/leads` — the screen is a server component reading the RPC
 * directly under RLS, so an unpermitted role never gets a JSON surface to
 * probe and the refusal happens in the loader before a single lead is read.
 */

type SearchParams = Promise<Record<string, string | undefined>>;

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
      options: Constants.public.Enums.lead_stage.map((stage) => ({ value: stage, label: stage.replaceAll('_', ' ') })),
    },
    {
      name: 'source',
      label: 'Source',
      allLabel: 'All sources',
      options: Constants.public.Enums.lead_source.map((source) => ({ value: source, label: source.replaceAll('_', ' ') })),
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

  return <main className="mx-auto w-full max-w-5xl px-4 py-8">
    <header className="flex flex-wrap items-baseline justify-between gap-3">
      <div>
        <h1 className="text-2xl font-semibold">Leads</h1>
        <p className="mt-1 text-sm text-neutral-600">Every enquiry from first contact to a converted member or a recorded loss.</p>
      </div>
      <Link href="/console" className="inline-flex min-h-11 items-center underline">Members</Link>
    </header>

    <form method="get" action="/leads" className="mt-6 grid grid-cols-2 gap-3 rounded-xl border border-neutral-200 p-4 sm:grid-cols-3">
      {filterSpecs(screen).map((spec) => <Field key={spec.name} label={spec.label}>
        <select name={spec.name} defaultValue={params[spec.name] ?? ''} className={inputClass}>
          <option value="">{spec.allLabel}</option>
          {spec.options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
        </select>
      </Field>)}
      <div className="col-span-2 sm:col-span-1"><Field label="Search">
        <input name="q" defaultValue={params.q ?? ''} type="search" className={inputClass} />
      </Field></div>
      <button type="submit" className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white sm:col-span-3">Apply filters</button>
    </form>

    {screen.errorMessage === null ? <section aria-labelledby="counts-heading" className="mt-6">
      <h2 id="counts-heading" className="text-lg font-semibold">Counts</h2>
      {screen.asOf !== null
        ? <p className="mt-1 text-sm text-neutral-600">Snapshot as of {deskTime(screen.asOf, screen.timezone)} ({screen.timezone}).</p>
        : null}
      <p className="mt-1 text-sm">Showing on this page: <strong className="tabular-nums">{screen.pageResultCount}</strong></p>
      <p className="text-sm">Matching leads: <strong className="tabular-nums">{screen.totalMatchingCount}</strong></p>
      <h3 className="mt-3 text-sm font-semibold">Within current filters</h3>
      <ul className="mt-1 flex flex-wrap gap-x-4 gap-y-1 text-sm">
        {Constants.public.Enums.lead_stage.map((stage) => <li key={stage}>{stage.replaceAll('_', ' ')}: <span className="tabular-nums">{screen.stageCounts[stage]}</span></li>)}
      </ul>
    </section> : null}

    {screen.errorMessage !== null ? <div className="mt-6"><Alert>{screen.errorMessage}</Alert></div> : null}

    <section aria-labelledby="pipeline-heading" className="mt-6">
      <h2 id="pipeline-heading" className="text-lg font-semibold">Pipeline</h2>
      {screen.rows.length === 0 && screen.errorMessage === null
        ? <p className="mt-2 text-sm text-neutral-600">No leads match these filters. Record an enquiry below or clear the filters.</p>
        : null}
      <ul className="mt-3 space-y-4">
        {screen.rows.map((row) => {
          const action = nextActionText(row, screen.timezone, now);
          const open = row.stage !== 'converted' && row.stage !== 'lost';
          return <li key={row.id} className="rounded-xl border border-neutral-200 p-4">
            <p className="font-semibold">{row.fullName} · {row.phone}</p>
            <p className="mt-1 text-sm text-neutral-700">
              {row.stage.replaceAll('_', ' ')} · {row.source.replaceAll('_', ' ')} · {row.branchName} · {row.assignedToName ?? 'Unassigned'}
            </p>
            {action !== null ? <p className="mt-1 text-sm font-medium">{action}</p> : null}
            {row.stage === 'converted' && row.convertedMemberId !== null
              ? <Link className="mt-2 inline-flex min-h-11 items-center underline" href={`/members/${row.convertedMemberId}`}>Open member</Link>
              : null}
            {row.stage === 'lost' && row.lostReason !== null
              ? <p className="mt-1 text-sm text-neutral-700">Lost: {row.lostReason}</p>
              : null}
            {row.stage === 'trial_done'
              ? <LeadConvertDialog leadId={row.id} revision={row.revision} fullName={row.fullName} />
              : null}
            {open ? <details className="mt-3"><summary className="min-h-11 cursor-pointer font-medium">Change stage</summary>
              <LeadStageForm leadId={row.id} revision={row.revision} stage={row.stage} timezone={screen.timezone} trialAt={row.trialAt} />
            </details> : null}
            {open ? <details className="mt-2"><summary className="min-h-11 cursor-pointer font-medium">Edit details</summary>
              <LeadEditForm leadId={row.id} revision={row.revision} lead={row} branches={screen.branchChoices} staff={screen.staffChoices} emailNotes={screen.editableText[row.id]} />
            </details> : null}
          </li>;
        })}
      </ul>
      {screen.nextCursor !== null
        ? <Link className="mt-4 inline-flex min-h-11 items-center underline" href={nextPageHref(params, screen.nextCursor)}>Next page</Link>
        : null}
    </section>

    <LeadEnquiryForm branches={screen.branchChoices} staff={screen.staffChoices} />
  </main>;
}
