'use client';

import { Constants } from '@gymloop/db';
import { MESSAGE_TEMPLATE_LOCALES, UI_TOKENS, humanize, type MessageTemplateLocale } from '@gymloop/shared';
import { ChevronRight } from 'lucide-react';
import { useState, type FormEvent } from 'react';
import { Alert } from '../alert';
import { Field, inputClass } from '../field';
import { MutationForm } from '../../preview-context';
import type { MemberChoice } from '../../../lib/messages';

/**
 * The staff `/messages` screen's client half: recording a consent decision,
 * opening a source message's WhatsApp link, and — for gym admin — saving a
 * template and adjusting the wallet. Every form is mounted through
 * `MutationForm` (`apps/web/app/preview-context.tsx`), which renders nothing
 * during a support preview — the same boundary every other console screen
 * with a mutation already uses, so a read-only preview cannot post any of
 * these actions even before hydration.
 *
 * Commands retain one logical request key across an uncertain retry. A key is
 * replaced only after a received response or after the user changes facts.
 */

const COMMS_ERRORS: Record<string, string> = {
  not_signed_in: 'Your session ended. Sign in again, then try once more.',
  not_permitted: 'Your role cannot perform this action.',
  invalid_request: 'Check the fields and try again.',
  invalid_consent: 'That consent could not be recorded — check the version and source.',
  invalid_notification: 'That message cannot make that move right now.',
  insufficient_credits: 'This credit movement would put the wallet below zero.',
  idempotency_conflict: 'This request key was already used for different facts. Try again.',
  invalid_provider_evidence: 'That request lacks valid evidence.',
  invalid_adjustment: 'Enter a nonzero delta and a reason.',
  credits_out_of_range: 'That delta is outside the supported credit range.',
  not_found: 'That record is not available. Reload the screen.',
  retryable: 'Another change just landed. Try again.',
  communication_opted_out: 'This member has opted out or is no longer eligible. No message link was created.',
  operation_failed: 'The change could not be saved. Nothing was written.',
};

/** A template locale code as its language name in English ("hi" → "Hindi"). */
const LANGUAGES = new Intl.DisplayNames(['en'], { type: 'language' });

function commsProblemText(code: string): string {
  return Object.hasOwn(COMMS_ERRORS, code) ? COMMS_ERRORS[code] ?? 'Review the details and try again.' : 'The outcome is uncertain. Retry, or reload this screen.';
}

async function postJson(path: string, body?: unknown): Promise<{ ok: boolean; data: Record<string, unknown> | null; errorCode: string }> {
  const response = await fetch(path, {
    method: 'POST', headers: { 'content-type': 'application/json' },
    ...(body === undefined ? {} : { body: JSON.stringify(body) }),
  });
  const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: { code?: unknown } };
  return {
    ok: response.ok && payload.ok === true,
    data: (payload.data ?? null) as Record<string, unknown> | null,
    errorCode: typeof payload.error?.code === 'string' ? payload.error.code : '',
  };
}

/**
 * The pending/problem/submit shape every comms form shares: validate first
 * (a non-null return is shown as the problem and the request never runs),
 * then run the request, showing either its error code's text or a fixed
 * interrupted-connection message, and always clear `pending` after.
 */
function useMutationSubmit(
  validate: () => string | null,
  request: () => Promise<{ ok: boolean; data: Record<string, unknown> | null; errorCode: string }>,
  onSuccess: (data: Record<string, unknown> | null) => void,
  onResponse: (() => void) | undefined,
  interruptedText: string,
): { pending: boolean; problem: string; submit: (event: FormEvent<HTMLFormElement>) => Promise<void> } {
  const [pending, setPending] = useState(false);
  const [problem, setProblem] = useState('');

  async function submit(event: FormEvent<HTMLFormElement>): Promise<void> {
    event.preventDefault();
    const validationProblem = validate();
    if (validationProblem !== null) {
      setProblem(validationProblem);
      return;
    }
    setPending(true);
    setProblem('');
    try {
      const result = await request();
      onResponse?.();
      if (result.ok) { onSuccess(result.data); return; }
      setProblem(commsProblemText(result.errorCode));
    } catch {
      setProblem(interruptedText);
    } finally {
      setPending(false);
    }
  }

  return { pending, problem, submit };
}

/**
 * Record a consent grant or withdrawal for a named member (contract §3, front
 * office). A member is chosen for the desk only when the search left exactly
 * one; with a longer list the select starts on a prompt, so a decision is
 * never recorded against whoever happened to sort first.
 */
export function ConsentForm({ members }: { members: MemberChoice[] }) {
  const [memberId, setMemberId] = useState(members.length === 1 ? members[0]?.id ?? '' : '');
  const [purpose, setPurpose] = useState<(typeof Constants.public.Enums.consent_purpose)[number]>('marketing');
  const [granted, setGranted] = useState(true);
  const [version, setVersion] = useState('2026-09-01');
  const [source, setSource] = useState('front_desk_form');
  const [requestKey, setRequestKey] = useState(() => crypto.randomUUID());
  const replaceRequestKey = () => setRequestKey(crypto.randomUUID());
  const { pending, problem, submit } = useMutationSubmit(
    () => memberId === '' ? 'Choose the member first. Search by phone to find them.'
      : (version.trim() === '' || source.trim() === '') ? 'Enter the version and source, then try again.' : null,
    () => postJson('/api/consents', { memberId, purpose, granted, version, source, requestKey }),
    () => {},
    replaceRequestKey,
    'The connection was interrupted. The outcome is uncertain. Retry recording this consent.',
  );

  const decide = (next: boolean) => { setGranted(next); replaceRequestKey(); };

  return <MutationForm onSubmit={submit} className="cl-form comms-consent">
    <div className="cl-form-row">
    <Field label="Member">
      <select value={memberId} disabled={members.length === 0} onChange={(event) => { setMemberId(event.target.value); replaceRequestKey(); }} className={inputClass}>
        {members.length === 1 ? null : <option value="" disabled>{members.length === 0 ? 'No member matches that search' : 'Search to choose a member'}</option>}
        {members.map((member) => <option key={member.id} value={member.id}>{member.name}</option>)}
      </select>
    </Field>
    <Field label="Purpose">
      <select value={purpose} onChange={(event) => { setPurpose(event.target.value as typeof purpose); replaceRequestKey(); }} className={inputClass}>
        {Constants.public.Enums.consent_purpose.map((value) => <option key={value} value={value}>{humanize(value)}</option>)}
      </select>
    </Field>
    </div>
    <fieldset className="comms-decision">
      <legend>Decision</legend>
      <label className="cl-check"><input type="radio" name="consent-decision" checked={granted} onChange={() => decide(true)} /> Granted</label>
      <label className="cl-check"><input type="radio" name="consent-decision" checked={!granted} onChange={() => decide(false)} /> Withdrawn</label>
    </fieldset>
    <div className="cl-form-row">
    <Field label="Version"><input value={version} onChange={(event) => { setVersion(event.target.value); replaceRequestKey(); }} className={inputClass} /></Field>
    <Field label="Source"><input value={source} onChange={(event) => { setSource(event.target.value); replaceRequestKey(); }} className={inputClass} /></Field>
    </div>
    {problem !== '' ? <Alert>{problem}</Alert> : null}
    <button type="submit" disabled={pending} className="cl-btn cl-btn--primary">
      {pending ? 'Recording…' : 'Record consent'}
    </button>
  </MutationForm>;
}

/** Open the WhatsApp deep link for one already-sent in-app source message (contract §5). */
export function WhatsAppOpenButton({ notificationId }: { notificationId: string }) {
  const [url, setUrl] = useState<string | null>(null);
  const { pending, problem, submit } = useMutationSubmit(
    () => null,
    () => postJson(`/api/notifications/${notificationId}/whatsapp`),
    (data) => { if (typeof data?.url === 'string') setUrl(data.url); },
    undefined,
    'The connection was interrupted. The outcome is uncertain. Retry opening WhatsApp.',
  );

  return <MutationForm onSubmit={submit} className="inline-block">
    <button type="submit" disabled={pending} className="comms-text-action">
      {pending ? 'Opening…' : 'Open in WhatsApp'}<ChevronRight aria-hidden="true" size={UI_TOKENS.icons.controlSize} strokeWidth={UI_TOKENS.icons.strokeWidth} />
    </button>
    {url !== null ? <p className="comms-whatsapp-url"><a href={url} target="_blank" rel="noreferrer">{url}</a></p> : null}
    {problem !== '' ? <Alert>{problem}</Alert> : null}
  </MutationForm>;
}

/** Create a template, or edit an existing one's category/body/active state (contract §2, §8, gym admin only). */
export function MessageTemplateForm({ template }: { template?: { id: string; key: string; channel: string; locale: string; category: string; body: string; isActive: boolean } }) {
  const [channel, setChannel] = useState<(typeof Constants.public.Enums.notification_channel)[number]>(
    (template?.channel as (typeof Constants.public.Enums.notification_channel)[number] | undefined) ?? 'push',
  );
  const [locale, setLocale] = useState<MessageTemplateLocale>((template?.locale as MessageTemplateLocale | undefined) ?? 'en');
  const [category, setCategory] = useState<(typeof Constants.public.Enums.message_category)[number]>(
    (template?.category as (typeof Constants.public.Enums.message_category)[number] | undefined)
      ?? Constants.public.Enums.message_category[0],
  );
  const [body, setBody] = useState(template?.body ?? '');
  const [isActive, setIsActive] = useState(template?.isActive ?? true);
  const [keyInput, setKeyInput] = useState(template?.key ?? '');
  const { pending, problem, submit } = useMutationSubmit(
    () => (keyInput.trim() === '' || category.trim() === '' || body.trim() === '') ? 'Enter an internal name, category and body, then try again.' : null,
    () => postJson('/api/message-templates', {
      ...(template ? { templateId: template.id } : {}),
      key: keyInput, channel, locale, category, body, isActive,
    }),
    () => {},
    undefined,
    'The connection was interrupted. The outcome is uncertain. Retry saving this template.',
  );

  const categoryField = <Field label="Category">
    <select value={category} onChange={(event) => setCategory(event.target.value as typeof category)} className={inputClass}>
      {Constants.public.Enums.message_category.map((value) => <option key={value} value={value}>{humanize(value)}</option>)}
    </select>
  </Field>;

  // An existing template's key, channel and language are fixed (contract §8):
  // its row already names them, so only the editable facts are controls here.
  return <MutationForm onSubmit={submit} className="cl-form comms-editor">
    {template !== undefined ? <div className="comms-editor-grid">{categoryField}</div> : <div className="comms-editor-grid">
      <Field label="Internal name"><input value={keyInput} onChange={(event) => setKeyInput(event.target.value)} className={inputClass} /><small>How it appears in your template list, for example “Birthday wish”.</small></Field>
      <Field label="Channel">
        <select value={channel} onChange={(event) => setChannel(event.target.value as typeof channel)} className={inputClass}>
          {Constants.public.Enums.notification_channel.map((value) => <option key={value} value={value}>{humanize(value)}</option>)}
        </select>
      </Field>
      <Field label="Locale">
        <select value={locale} onChange={(event) => setLocale(event.target.value as MessageTemplateLocale)} className={inputClass}>
          {MESSAGE_TEMPLATE_LOCALES.map((value) => <option key={value} value={value}>{LANGUAGES.of(value) ?? value}</option>)}
        </select>
      </Field>
      {categoryField}
    </div>}
    <Field label="Body"><textarea value={body} onChange={(event) => setBody(event.target.value)} className={`${inputClass} comms-body`} /><small>Plain text, sent exactly as written. Placeholders such as {'{{name}}'} are not filled in.</small></Field>
    <label className="cl-check">
      <input type="checkbox" checked={isActive} onChange={(event) => setIsActive(event.target.checked)} /> Active
    </label>
    {problem !== '' ? <Alert>{problem}</Alert> : null}
    <button type="submit" disabled={pending} className="cl-btn cl-btn--primary">
      {pending ? 'Saving…' : template ? 'Save template' : 'Create template'}
    </button>
  </MutationForm>;
}
