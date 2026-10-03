'use client';
import { useEffect, useRef, useState, type FormEvent } from 'react';
import { useRouter } from 'next/navigation';
import {
  GUARDIAN_LIMITS, GUARDIAN_RELATIONS, GUARDIAN_RELATION_LABELS, STAFF_INVITE_EMAIL_MAX_LENGTH,
  guardianProfileRequestSchema, guardianConsentRequestSchema, guardianHandoverRequestSchema,
  guardianConsentStatement, guardianScoringMessage, toLocalDate, type GuardianRelation,
} from '@gymloop/shared';
import type { MemberGuardian } from '../../../../lib/guardian';
import type { MemberAppAccess } from '../../../../lib/member-invites';
import type { StaffRole } from '../../../../lib/identity';
import { useGuardianCommand } from '../../../../lib/use-guardian-command';
import { StatusWord } from '../../../status-word';
import { Field, inputClass } from '../../field';
import { Alert } from '../../alert';
import '../../../styles/guardian.css';

type Props = { memberId: string; memberName: string; gymName: string; timezone: string; role: StaffRole; guardian: MemberGuardian | null; access: MemberAppAccess | null; readOnly?: boolean };

export function GuardianPanel(props: Props) {
  return props.role === 'trainer' ? null : <GuardianSection {...props} />;
}
function GuardianSection({ memberId, memberName, gymName, timezone, role, guardian, access, readOnly }: Props) {
  const router = useRouter();
  const command = useGuardianCommand(readOnly);
  const [dob, setDob] = useState(guardian?.dateOfBirth ?? '');
  const [name, setName] = useState(guardian?.guardianName ?? '');
  const [relation, setRelation] = useState<GuardianRelation | ''>(guardian?.guardianRelation ?? '');
  const [phone, setPhone] = useState(guardian?.guardianPhone ?? '');
  const [email, setEmail] = useState(guardian?.guardianEmail ?? '');
  const [confirmed, setConfirmed] = useState(false);
  const [source, setSource] = useState('');
  const [withdraw, setWithdraw] = useState(false);
  const [handover, setHandover] = useState(false);
  const [reason, setReason] = useState('');
  const [fields, setFields] = useState<Record<string, string>>({});
  const withdrawButton = useRef<HTMLButtonElement>(null);
  const handoverButton = useRef<HTMLButtonElement>(null);
  const previousConfirmation = useRef({ withdraw: false, handover: false });
  useEffect(() => {
    if (previousConfirmation.current.withdraw && !withdraw) withdrawButton.current?.focus();
    if (previousConfirmation.current.handover && !handover) handoverButton.current?.focus();
    previousConfirmation.current = { withdraw, handover };
  }, [withdraw, handover]);
  if (guardian === null) return <section className="guardian-panel" aria-labelledby="guardian-heading"><h2 id="guardian-heading" className="cl-section-title">Age and guardian</h2><Alert>Age and guardian details could not be loaded. Try again.</Alert><button className="cl-btn" type="button" onClick={() => router.refresh()}>Try again</button></section>;
  const minor = guardian.ageState === 'minor';
  const canHandover = role === 'gym_owner' || role === 'gym_manager';
  let issuedDay: string | null = null;
  if (access?.issuedAt != null) {
    try { issuedDay = toLocalDate(access.issuedAt, timezone); }
    catch { try { issuedDay = toLocalDate(access.issuedAt, 'UTC'); } catch { issuedDay = null; } }
  }
  const reissue = guardian.ageState === 'adult' && guardian.adultOn !== null && issuedDay !== null && access != null
    && (access.state === 'invite_pending' || access.state === 'invite_expired')
    && issuedDay < guardian.adultOn;
  async function save(event: FormEvent) {
    event.preventDefault();
    const guardianInput = name === '' && relation === '' && phone === '' && email === '' ? null : { name, relation, phone, email };
    const parsed = guardianProfileRequestSchema.safeParse({ memberId, dateOfBirth: dob || null,
      guardian: guardianInput });
    if (!parsed.success) {
      const errors: Record<string, string> = {};
      const detail = guardianInput === null ? null : guardianProfileRequestSchema.shape.guardian.options[1].safeParse(guardianInput);
      const issues = [...parsed.error.issues.filter((issue) => issue.path[0] !== 'guardian'), ...(detail && !detail.success ? detail.error.issues : [])];
      for (const issue of issues) {
        const field = String(issue.path.at(-1) ?? 'guardian');
        errors[field] = field === 'phone' ? 'Use an international number with its country code.' : field === 'email' ? 'Enter a valid email address.' : field === 'dateOfBirth' ? 'Enter a valid date of birth.' : 'Enter a guardian name and select their relation.';
      }
      if (Object.keys(errors).length === 0) errors.guardian = 'Check the age and guardian details, then try again.';
      setFields(errors); return;
    }
    setFields({}); await command.send('/api/member-guardian', parsed.data, 'Age and guardian details saved.');
  }
  async function record(event: FormEvent) {
    event.preventDefault();
    if (!confirmed) return;
    const parsed = guardianConsentRequestSchema.safeParse({ memberId, granted: true, source });
    if (!parsed.success) { setFields({ source: 'Enter how the consent was collected.' }); return; }
    setFields({});
    if (await command.send('/api/member-guardian/consent', parsed.data, 'Consent recorded. Refreshing the member status.')) { setConfirmed(false); setSource(''); }
  }
  function closeHandover() { setHandover(false); setReason(''); handoverButton.current?.focus(); }
  async function handOver(event: FormEvent) {
    event.preventDefault();
    const parsed = guardianHandoverRequestSchema.safeParse({ memberId, reason });
    if (!parsed.success) { setFields({ reason: 'Enter a reason of at least three characters.' }); return; }
    setFields({});
    if (await command.send('/api/member-identity/handover', parsed.data, 'Guardian sign-in ended. Send a new invite for the member.')) closeHandover();
  }
  return <section className="guardian-panel" aria-labelledby="guardian-heading" aria-busy={command.busy}>
    <div className="guardian-heading"><h2 id="guardian-heading" className="cl-section-title">Age and guardian</h2><StatusWord status={minor ? 'minor' : guardian.ageState} label={minor ? 'Under 18' : guardian.ageState === 'adult' ? 'Adult' : 'Age unknown'} /></div>
    <p className="guardian-consequence">{guardianScoringMessage(guardian.scoringState)}</p>
    {guardian.legacyAttestedAdult ? <p className="guardian-note">The owner confirmed existing members without a date of birth are adults. Absence follow-ups are on.</p> : null}
    {command.preview ? <p className="guardian-note">This section is read-only in support preview.</p> : null}
    {!command.online ? <Alert>You are offline. Connect to the internet to save. Changes are not queued.</Alert> : null}
    {command.error ? <Alert>{command.error}</Alert> : null}
    <p role="status" className={command.success ? 'guardian-note' : 'sr-only'}>{command.busy ? 'Saving…' : command.success ?? ''}</p>
    <form onSubmit={save} className="guardian-form">
      {fields.guardian ? <Alert>{fields.guardian}</Alert> : null}
      <fieldset disabled={command.disabled} className="guardian-fields"><legend className="sr-only">Age and guardian details</legend>
        <Field label="Date of birth"><input className={inputClass} type="date" name="dateOfBirth" value={dob} onChange={(event) => setDob(event.target.value)} aria-invalid={Boolean(fields.dateOfBirth)} />{fields.dateOfBirth ? <span role="alert">{fields.dateOfBirth}</span> : null}</Field>
        <Field label="Guardian name"><input className={inputClass} name="name" value={name} maxLength={GUARDIAN_LIMITS.nameMaxLength} onChange={(event) => setName(event.target.value)} aria-invalid={Boolean(fields.name)} />{fields.name ? <span role="alert">{fields.name}</span> : null}</Field>
        <Field label="Relation"><select className={inputClass} name="relation" value={relation} onChange={(event) => setRelation(event.target.value as GuardianRelation)} aria-invalid={Boolean(fields.relation)}><option value="">Choose relation</option>{GUARDIAN_RELATIONS.map((value) => <option key={value} value={value}>{GUARDIAN_RELATION_LABELS[value]}</option>)}</select>{fields.relation ? <span role="alert">{fields.relation}</span> : null}</Field>
        <Field label="Guardian phone"><input className={inputClass} name="phone" type="tel" placeholder="+919876543210" value={phone} onChange={(event) => setPhone(event.target.value)} aria-invalid={Boolean(fields.phone)} />{fields.phone ? <span role="alert">{fields.phone}</span> : null}</Field>
        <Field label="Guardian email for Google sign-in"><input className={inputClass} name="email" type="email" maxLength={STAFF_INVITE_EMAIL_MAX_LENGTH} value={email} onChange={(event) => setEmail(event.target.value)} aria-invalid={Boolean(fields.email)} />{fields.email ? <span role="alert">{fields.email}</span> : null}</Field>
      </fieldset><div className="cl-actions"><button type="submit" className="cl-btn cl-btn--primary" disabled={command.disabled}>{command.busy ? 'Saving…' : 'Save'}</button></div>
    </form>
    {guardian.linkEmailInUse ? <Alert>Another member of this gym with the same address is already linked. A Google account links to one member only, so this invite will be refused if the guardian uses the same account. Enter a different address if this child should use another account.</Alert> : null}
    {minor ? <div className="guardian-consent"><h3>Guardian consent</h3><StatusWord status={guardian.consentState} label={guardian.consentState === 'granted' ? 'Consent on record' : guardian.consentState === 'withdrawn' ? 'Consent withdrawn' : guardian.consentState === 'stale' ? 'Consent needs recording again' : 'Consent not recorded'} />
      {guardian.guardianName && guardian.guardianRelation ? <p className="guardian-statement">{guardianConsentStatement({ gymName, memberName, guardianName: guardian.guardianName, relation: guardian.guardianRelation })}</p> : <p className="guardian-note">Save the guardian name and relation to show the consent statement.</p>}
      {guardian.consentState !== 'granted' ? <form onSubmit={record} className="guardian-form">
        <label className="guardian-check"><input type="checkbox" checked={confirmed} required disabled={command.disabled} onChange={(event) => setConfirmed(event.target.checked)} /><span>I have collected this consent from the parent or guardian</span></label>
        <Field label="Consent source"><input name="source" list="guardian-sources" className={inputClass} required value={source} maxLength={GUARDIAN_LIMITS.sourceMaxLength} disabled={command.disabled} onChange={(event) => setSource(event.target.value)} aria-invalid={Boolean(fields.source)} /><datalist id="guardian-sources"><option value="Paper form" /><option value="In person" /><option value="Phone call" /></datalist>{fields.source ? <span role="alert">{fields.source}</span> : null}</Field>
        <div className="cl-actions"><button type="submit" className="cl-btn cl-btn--primary" disabled={command.disabled || !confirmed || source.trim() === ''}>{command.busy ? 'Recording…' : 'Record'}</button></div>
      </form> : !withdraw ? <button ref={withdrawButton} type="button" className="cl-btn" disabled={command.disabled} onClick={() => setWithdraw(true)}>Withdraw consent</button> : <div className="cl-panel guardian-confirm" role="group" aria-label="Confirm consent withdrawal"><p>Withdraw guardian consent? Absence follow-ups stop now. Visits are still recorded and consent history is kept.</p><div className="cl-actions"><button autoFocus type="button" className="cl-btn cl-btn--danger" disabled={command.disabled} onClick={async () => { if (await command.send('/api/member-guardian/consent', { memberId, granted: false, source: 'Guardian withdrawal reported to staff' }, 'Consent withdrawn. Refreshing the member status.')) { setWithdraw(false); withdrawButton.current?.focus(); } }}>Confirm withdrawal</button><button type="button" className="cl-btn" disabled={command.busy} onClick={() => { setWithdraw(false); withdrawButton.current?.focus(); }}>Cancel</button></div></div>}
    </div> : null}
    {reissue ? <p className="guardian-note">Re-issue the invite. The member has turned 18, so even this earlier invite now requires the member&apos;s own Google account and email address.</p> : null}
    {guardian.handoverDue ? <div className="guardian-consent"><h3>Turned 18</h3><p className="guardian-note">This member still signs in through the guardian&apos;s account.</p>{canHandover ? !handover ? <button ref={handoverButton} className="cl-btn" type="button" disabled={command.disabled} onClick={() => setHandover(true)}>Hand over account</button> : <form onSubmit={handOver} className="cl-panel guardian-confirm"><h3>Hand over account?</h3><p>The guardian&apos;s sign-in to this membership ends, including their app sessions. The member&apos;s visits, payments and history stay. Send a new invite to the member&apos;s own email afterwards.</p><Field label="Reason"><textarea autoFocus name="reason" required minLength={GUARDIAN_LIMITS.reasonMinLength} maxLength={GUARDIAN_LIMITS.reasonMaxLength} className={inputClass} value={reason} disabled={command.disabled} onChange={(event) => setReason(event.target.value)} />{fields.reason ? <span role="alert">{fields.reason}</span> : null}</Field><div className="cl-actions"><button type="submit" className="cl-btn cl-btn--danger" disabled={command.disabled || reason.trim().length < GUARDIAN_LIMITS.reasonMinLength}>Confirm handover</button><button type="button" className="cl-btn" disabled={command.busy} onClick={closeHandover}>Cancel</button></div></form> : <p className="guardian-note">An owner or manager can hand over the account.</p>}</div> : null}
  </section>;
}
