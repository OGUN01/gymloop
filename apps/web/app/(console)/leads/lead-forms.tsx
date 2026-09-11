'use client';

import { Constants } from '@gymloop/db';
import { gymWallClockFormatter } from '@gymloop/shared';
import { useState, useRef, type FormEvent } from 'react';
import Link from 'next/link';
import { Field, inputClass } from '../field';
import { Alert } from '../alert';
import { deskTime } from '../../../lib/time';
import { UUID_PATTERN } from '../../../lib/keyset';
import type { BranchChoice, LeadListRow, LeadStage, StaffChoice } from '../../../lib/leads';

/**
 * The leads screen's client half. These components deliberately do not import
 * `preview-context`: the screen's loader has already refused every identity
 * that is not real front office — a support preview never renders this page,
 * so a preview gate here would be dead weight on a path that cannot occur.
 *
 * Every logical command carries ONE request key, minted when the command is
 * first built and reused verbatim whenever the outcome is uncertain — a
 * network failure or an unknown error code may mean the write landed, and
 * retrying those with a fresh key would record a second lead or member. Only
 * a definitive known failure, or a change to the submitted facts (a different
 * logical command), goes out under a fresh key.
 */

/**
 * The one lead command every form shares: JSON to a route, the envelope back,
 * a desk-readable problem on refusal. An unknown error code is reported as an
 * uncertain outcome rather than a friendly guess — the write may or may not
 * have landed, and the person at the desk must know which they don't know.
 */
const LEAD_ERRORS: Record<string, string> = {
  not_signed_in: 'Your session ended. Sign in again, then make the change once more.',
  malformed_body: 'That request could not be read. Re-enter the change and submit it again.',
  invalid_request: 'Check the branch, name, phone and source, then try again.',
  stale_lead: 'This lead changed while you were working on it. The form now holds the latest revision — check the facts and submit the change once more.',
  invalid_transition: 'This lead cannot move to that stage from where it is. Reload the screen.',
  invalid_lead_facts: 'That change needs different lead facts — a trial time, or a loss reason.',
  not_found: 'That lead is no longer available. Reload the screen.',
  not_permitted: 'Your staff role cannot work leads.',
  retryable: 'Another change to this lead just landed. Try again.',
  idempotency_conflict: 'This request key was already used for a different change. Reload the screen.',
  member_unavailable: 'That phone belongs to a member who cannot be linked right now.',
  link_required: 'An existing member already owns this phone. Link the lead to that member explicitly.',
  operation_failed: 'The change could not be saved. Nothing was written.',
};

function leadProblemText(code: string): string {
  return Object.hasOwn(LEAD_ERRORS, code)
    ? LEAD_ERRORS[code] ?? 'Review the details and try again.'
    : 'The outcome is uncertain. Retry the same change, or reload this screen.';
}

type LeadCommandShape = { path: string; method: 'POST' | 'PATCH'; body: Record<string, unknown> };

/**
 * A command's submitted facts, without the request key that names the
 * attempt: two commands with the same facts are the same logical command and
 * must share one key, whatever key the newer body was built carrying.
 */
function commandFacts(command: LeadCommandShape): string {
  const facts = { ...command.body };
  delete facts.requestKey;
  return JSON.stringify(facts);
}

/** The error envelope a lead route can answer with, before any code-specific facts. */
type LeadErrorEnvelope = { code?: unknown } & Record<string, unknown>;

/**
 * A stale_lead answer carries the revision to retry against (the route
 * returns it deliberately); the form adopts it so the desk resubmits against
 * the lead as it now stands instead of reloading and losing the filters.
 */
function adoptStaleRevision(error: LeadErrorEnvelope | null, setRevision: (value: string) => void): void {
  if (error === null || error.code !== 'stale_lead') return;
  const current = error.currentRevision;
  if (typeof current === 'string' && UUID_PATTERN.test(current)) setRevision(current);
}

function useLeadCommand() {
  const [pending, setPending] = useState(false);
  const [problem, setProblem] = useState('');
  const [uncertain, setUncertain] = useState(false);
  const original = useRef<LeadCommandShape | null>(null);

  async function run(
    command: LeadCommandShape,
    onAccepted: (data: Record<string, unknown>) => void,
    onRefused?: (error: LeadErrorEnvelope | null) => void,
  ): Promise<void> {
    if (pending) return;
    // An uncertain outcome is retried as the original command, request key and
    // all: the write may already have landed, and a fresh key would turn the
    // retry into a second write. Different submitted facts name a different
    // logical command, so they go out as the new command under its own key.
    const attempt = uncertain && original.current !== null && commandFacts(original.current) === commandFacts(command)
      ? original.current
      : command;
    original.current = attempt;
    setPending(true);
    setProblem('');
    try {
      const response = await fetch(attempt.path, {
        method: attempt.method,
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify(attempt.body),
      });
      const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: LeadErrorEnvelope };
      if (response.ok && payload.ok === true && payload.data && typeof payload.data === 'object') {
        onAccepted(payload.data);
        return;
      }
      // A known code is a definitive answer — the write either happened or was
      // refused — so the next attempt is a new command with a fresh key. An
      // unknown code leaves the outcome uncertain and the key preserved.
      const code = typeof payload.error?.code === 'string' ? payload.error.code : '';
      setUncertain(!Object.hasOwn(LEAD_ERRORS, code));
      setProblem(leadProblemText(code));
      onRefused?.(payload.error ?? null);
    } catch {
      setUncertain(true);
      setProblem('The connection was interrupted. The outcome is uncertain. Retry the same change — the same request key is reused.');
    } finally {
      setPending(false);
    }
  }

  return { pending, problem, run, setProblem };
}

/**
 * The seven caller-owned facts every lead form reads out of its FormData.
 * Blank optionals become null, never empty strings: the RPC stores what the
 * desk stated, and a cleared notes field is "no notes", not a whitespace note.
 */
function leadFacts(form: FormData): Record<string, unknown> {
  const text = (name: string) => String(form.get(name) ?? '');
  return {
    branchId: text('branchId'),
    fullName: text('fullName'),
    phone: text('phone'),
    email: text('email') === '' ? null : text('email'),
    source: text('source'),
    assignedToStaffId: text('assignedToStaffId') === '' ? null : text('assignedToStaffId'),
    notes: text('notes') === '' ? null : text('notes'),
  };
}

/**
 * The gym-local wall time of an instant, in the exact `YYYY-MM-DDTHH:mm`
 * shape `datetime-local` accepts — the prefill for re-stating a trial time
 * that is already scheduled. Undefined when the instant or the zone cannot be
 * rendered; the field then starts empty.
 */
function trialLocalPrefill(trialAt: string, timezone: string): string | undefined {
  const instant = new Date(trialAt);
  if (Number.isNaN(instant.getTime())) return undefined;
  const formatter = gymWallClockFormatter(timezone);
  if (formatter === null) return undefined;
  const parts = new Map(formatter.formatToParts(instant).map((part) => [part.type, part.value]));
  const year = parts.get('year');
  const month = parts.get('month');
  const day = parts.get('day');
  const hour = parts.get('hour');
  const minute = parts.get('minute');
  if (!year || !month || !day || !hour || !minute) return undefined;
  return `${year}-${month}-${day}T${hour}:${minute}`;
}

/**
 * The enquiry and edit forms are the same seven controls, differing only in
 * whether they echo the lead's current facts. One component keeps them from
 * drifting — a field added to one and forgotten in the other is exactly the
 * silent edit bug the desk cannot see. The edit form passes the lead's
 * current email and notes as `emailNotes`, so a desk fixing a phone typo sees
 * what it is about to clear; the enquiry form passes nothing and starts blank.
 */
function LeadFactFields({ branches, staff, lead, emailNotes }: {
  branches: BranchChoice[]; staff: StaffChoice[]; lead?: LeadListRow; emailNotes?: { email: string; notes: string } | undefined;
}) {
  return <>
    <Field label="Branch"><select name="branchId" defaultValue={lead?.branchId} required className={inputClass}>
      {branches.map((branch) => <option key={branch.id} value={branch.id}>{branch.name}</option>)}
    </select></Field>
    <Field label="Full name"><input name="fullName" defaultValue={lead?.fullName} required className={inputClass} /></Field>
    {/* The pattern is byte-identical to the database's `leads_phone_format_chk`,
        so the browser refuses exactly the phones the database refuses. */}
    <Field label="Phone (E.164, e.g. +919876543210)"><input name="phone" defaultValue={lead?.phone} required inputMode="tel" pattern="\+[1-9][0-9]{7,14}" className={inputClass} /></Field>
    <Field label="Email (optional)"><input name="email" type="email" defaultValue={emailNotes?.email ?? ''} className={inputClass} /></Field>
    <Field label="Source"><select name="source" defaultValue={lead?.source} required className={inputClass}>
      {Constants.public.Enums.lead_source.map((source) => <option key={source} value={source}>{source.replaceAll('_', ' ')}</option>)}
    </select></Field>
    <Field label="Assigned staff (optional)"><select name="assignedToStaffId" defaultValue={lead?.assignedToStaffId ?? ''} className={inputClass}>
      <option value="">Unassigned</option>
      {staff.map((person) => <option key={person.id} value={person.id}>{person.fullName}</option>)}
    </select></Field>
    <Field label="Notes (optional)"><textarea name="notes" defaultValue={emailNotes?.notes ?? ''} className={inputClass} /></Field>
  </>;
}

/** The four member facts a duplicate-phone conflict is allowed to show the desk. */
type LinkMember = { memberId: string; fullName: string; phone: string; status: string };

/**
 * Converting a `trial_done` lead. Two submissions, deliberately: the first
 * asks the RPC to create the member, and only a same-gym duplicate-phone
 * conflict turns the dialog into an explicit link decision — the member
 * facts the conflict carries are the ones the desk confirms against, never
 * anything the RPC did not disclose. Each decision keeps its own request
 * key: a retry of the same decision after an uncertain outcome replays the
 * original write, never a second member.
 */
export function LeadConvertDialog({ leadId, revision, fullName }: { leadId: string; revision: string; fullName: string }) {
  const [member, setMember] = useState<LinkMember | null>(null);
  const [mode, setMode] = useState<'create' | 'link_existing'>('create');
  const [pending, setPending] = useState(false);
  const [problem, setProblem] = useState('');
  const [notice, setNotice] = useState('');
  // The revision this dialog last submitted against; a stale_lead answer
  // replaces it with the returned current revision so the retry is a new
  // command under a fresh key instead of a loop of the same conflict.
  const [rev, setRev] = useState(revision);
  // One request key per logical command: 'create' and the explicit 'link_existing'
  // decision each name one write, and an uncertain retry reuses the key so the
  // RPC answers a replay instead of writing again.
  const keys = useRef<{ create: string | null; link_existing: string | null }>({ create: null, link_existing: null });

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (pending) return;
    // Without a disclosed member there is nothing to link to: the request is
    // a create no matter what an old dialog state might say.
    const effective = member !== null ? mode : 'create';
    setPending(true);
    setProblem('');
    const requestKey = keys.current[effective] ?? crypto.randomUUID();
    keys.current[effective] = requestKey;
    try {
      const response = await fetch(`/api/leads/${leadId}/convert`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({
          requestKey,
          expectedRevision: rev,
          mode: effective,
          ...(effective === 'link_existing' && member !== null ? { memberId: member.memberId } : {}),
        }),
      });
      const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: LeadErrorEnvelope & { member?: LinkMember } };
      if (response.ok && payload.ok === true && payload.data && typeof payload.data === 'object') {
        const memberId = payload.data.memberId;
        if (typeof memberId === 'string' && UUID_PATTERN.test(memberId)) window.location.assign(`/members/${memberId}`);
        else window.location.reload();
        return;
      }
      const code = typeof payload.error?.code === 'string' ? payload.error.code : '';
      adoptStaleRevision(payload.error ?? null, setRev);
      const disclosed = payload.error?.member;
      if (code === 'link_required' &&
        disclosed !== null && typeof disclosed === 'object' &&
        typeof disclosed.memberId === 'string' && typeof disclosed.fullName === 'string' &&
        typeof disclosed.phone === 'string' && typeof disclosed.status === 'string') {
        setMember(disclosed);
        setMode('link_existing');
        setNotice(`An existing member already owns this phone. Confirm the explicit link for ${fullName}.`);
        return;
      }
      if (code === 'link_required') {
        // The conflict says a member exists but the disclosable facts did not
        // arrive: the desk cannot confirm a link it cannot see, and the
        // honest answer is to start over rather than guess.
        setProblem('An existing member already owns this phone, but their details could not be shown here. Reload the screen and start the conversion again.');
        keys.current[effective] = null;
        return;
      }
      // A known failure is definitive — nothing was written — so the next
      // attempt of this decision mints a fresh key. An unknown code leaves the
      // outcome uncertain and this key preserved for the retry.
      if (Object.hasOwn(LEAD_ERRORS, code)) keys.current[effective] = null;
      setProblem(leadProblemText(code));
    } catch {
      setProblem('The connection was interrupted. The outcome is uncertain. Retry the conversion — the same request key is reused.');
    } finally {
      setPending(false);
    }
  }

  return <form method="post" onSubmit={submit} className="mt-3 space-y-3 rounded-lg border border-neutral-200 p-3">
    <p className="text-sm">Convert {fullName} to a member. One request key per decision — an uncertain retry replays the original conversion, never a second member.</p>
    {notice !== '' ? <p role="status" className="text-sm text-amber-900">{notice}</p> : null}
    {member !== null ? <p className="text-sm font-medium">Existing member: {member.fullName} · {member.phone} · {member.status}</p> : null}
    {problem !== '' ? <Alert>{problem}</Alert> : null}
    <div className="flex flex-wrap items-center gap-2">
      <button type="submit" disabled={pending} className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white disabled:opacity-50">
        {pending ? 'Converting…' : member !== null
          ? `Connect ${member.fullName} to this lead explicitly`
          : `Convert ${fullName} to a member`}
      </button>
      {member !== null ? <Link href="/leads" className="inline-flex min-h-11 items-center underline">Leave without converting</Link> : null}
    </div>
  </form>;
}

/** Record a new enquiry. The branch, name, E.164 phone and source are the desk's to state; stage and revision are not. */
export function LeadEnquiryForm({ branches, staff }: { branches: BranchChoice[]; staff: StaffChoice[] }) {
  const command = useLeadCommand();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await command.run({
      path: '/api/leads',
      method: 'POST',
      body: { requestKey: crypto.randomUUID(), ...leadFacts(new FormData(event.currentTarget)) },
    // A reload keeps the filters and cursor the desk is working from; a jump
    // to /leads would silently drop them.
    }, () => { window.location.reload(); });
  }

  return <section aria-labelledby="enquiry-heading" className="mt-8 rounded-xl border border-neutral-200 p-4">
    <h2 id="enquiry-heading" className="text-xl font-semibold">Record an enquiry</h2>
    <p className="mt-1 text-sm text-neutral-600">A new lead starts at the New stage with you as the acting staff member.</p>
    {command.problem !== '' ? <div className="mt-2"><Alert>{command.problem}</Alert></div> : null}
    <form method="post" onSubmit={submit} className="mt-4 grid grid-cols-1 gap-4 md:grid-cols-2">
      <LeadFactFields branches={branches} staff={staff} />
      <button type="submit" disabled={command.pending} className="min-h-11 rounded-lg bg-neutral-900 px-4 py-2 font-semibold text-white disabled:opacity-50 md:col-span-2">
        {command.pending ? 'Recording…' : 'Record enquiry'}
      </button>
    </form>
  </section>;
}

/**
 * The stage moves the contract's graph allows from where this lead stands.
 * `converted` is absent because conversion is the convert dialog's atomic
 * command, and a terminal stage has no outgoing edge at all.
 */
const NEXT_STAGES: Record<LeadStage, readonly LeadStage[]> = {
  new: ['contacted', 'lost'],
  contacted: ['trial_scheduled', 'lost'],
  trial_scheduled: ['trial_done', 'lost'],
  trial_done: ['lost'],
  converted: [],
  lost: [],
};

/** Move a lead one step along the graph, with the evidence the step requires. */
export function LeadStageForm({ leadId, revision, stage, timezone, trialAt }: {
  leadId: string; revision: string; stage: LeadStage; timezone: string; trialAt: string | null;
}) {
  const options = NEXT_STAGES[stage];
  const [toStage, setToStage] = useState<LeadStage>(options[0] ?? stage);
  const [rev, setRev] = useState(revision);
  const command = useLeadCommand();
  const needsTrial = toStage === 'trial_scheduled' || toStage === 'trial_done';
  const prefill = needsTrial && trialAt !== null ? trialLocalPrefill(trialAt, timezone) : undefined;
  if (options.length === 0) return null;

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = new FormData(event.currentTarget);
    const trialLocal = String(form.get('trialLocal') ?? '');
    const lostReason = String(form.get('lostReason') ?? '');
    if (needsTrial && trialLocal === '') {
      command.setProblem('Choose the gym-local trial time for this stage move.');
      return;
    }
    if (toStage === 'lost' && lostReason.trim() === '') {
      command.setProblem('A lost lead needs a short reason. Enter it and submit again.');
      return;
    }
    await command.run({
      path: `/api/leads/${leadId}`,
      method: 'PATCH',
      body: {
        command: 'transition',
        expectedRevision: rev,
        toStage,
        ...(needsTrial ? { trialLocal } : {}),
        ...(toStage === 'lost' ? { lostReason } : {}),
      },
    // A reload keeps the filters and cursor; a jump to /leads would drop them.
    }, () => { window.location.reload(); }, (error) => { adoptStaleRevision(error, setRev); });
  }

  return <form method="post" onSubmit={submit} className="mt-3 space-y-3 rounded-lg border border-neutral-200 p-3">
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <Field label="Move to"><select name="toStage" value={toStage} onChange={(event) => setToStage(event.target.value as LeadStage)} className={inputClass}>
        {options.map((option) => <option key={option} value={option}>{option.replaceAll('_', ' ')}</option>)}
      </select></Field>
      {needsTrial
        ? <Field label="Trial time (gym-local)"><input name="trialLocal" type="datetime-local" required defaultValue={prefill} className={inputClass} /></Field>
        : null}
      {toStage === 'lost' ? <Field label="Loss reason"><input name="lostReason" required className={inputClass} /></Field> : null}
    </div>
    {needsTrial && trialAt !== null
      ? <p className="text-xs text-neutral-600">Currently scheduled: {deskTime(trialAt, timezone)} ({timezone}). The field holds that same time — correct it only if the plan changed.</p>
      : null}
    <p className="text-xs text-neutral-600">Gym timezone: {timezone}. A trial time that does not exist or is ambiguous in that zone is refused, never shifted.</p>
    {command.problem !== '' ? <Alert>{command.problem}</Alert> : null}
    <button type="submit" disabled={command.pending} className="min-h-11 rounded-lg border border-neutral-500 px-4 py-2 font-medium disabled:opacity-50">
      {command.pending ? 'Saving…' : 'Save stage change'}
    </button>
  </form>;
}

/** Edit the caller-owned facts of one lead, prefilled with the facts it stands at now. */
export function LeadEditForm({ leadId, revision, lead, branches, staff, emailNotes }: {
  leadId: string; revision: string; lead: LeadListRow; branches: BranchChoice[]; staff: StaffChoice[];
  emailNotes: { email: string; notes: string } | undefined;
}) {
  const [rev, setRev] = useState(revision);
  const command = useLeadCommand();

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await command.run({
      path: `/api/leads/${leadId}`,
      method: 'PATCH',
      body: { command: 'update_details', expectedRevision: rev, ...leadFacts(new FormData(event.currentTarget)) },
    // A reload keeps the filters and cursor; a jump to /leads would drop them.
    }, () => { window.location.reload(); }, (error) => { adoptStaleRevision(error, setRev); });
  }

  // Without the current email and notes there is no honest edit: a blank
  // prefill would let an innocent-looking save clear facts the desk never
  // saw. The loader leaves an entry out only when the read failed, and this
  // form refuses instead of guessing.
  if (emailNotes === undefined) {
    return <div className="mt-3 rounded-lg border border-neutral-200 p-3">
      <Alert>The lead's current email and notes could not be read, so editing is closed — a save here could clear them. Reload the screen and open the edit again.</Alert>
    </div>;
  }

  return <form method="post" onSubmit={submit} className="mt-3 space-y-3 rounded-lg border border-neutral-200 p-3">
    <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
      <LeadFactFields branches={branches} staff={staff} lead={lead} emailNotes={emailNotes} />
    </div>
    <p className="text-xs text-neutral-600">The lead's current email and notes are shown as they stand. A blank email or notes field sets it to none — submitting clears it. Everything is saved against the revision you loaded; a change made meanwhile is refused as a conflict, and the form then adopts the latest revision for one more submission.</p>
    {command.problem !== '' ? <Alert>{command.problem}</Alert> : null}
    <button type="submit" disabled={command.pending} className="min-h-11 rounded-lg border border-neutral-500 px-4 py-2 font-medium disabled:opacity-50">
      {command.pending ? 'Saving…' : 'Save lead details'}
    </button>
  </form>;
}
