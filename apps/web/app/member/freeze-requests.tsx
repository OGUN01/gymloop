'use client';

import { useRef, useState } from 'react';
import { formatMoney, freezeRequestCancellable, freezeRequestCopy, freezeRequestStateWord, type MemberFreezeRequestRow } from '@gymloop/shared';
import { StatusWord } from '../status-word';
import { Field, inputClass } from '../(console)/field';
import { runFrozenCommand, type KeySlot } from '../../lib/freeze-commands';

/**
 * The member freeze surface (SLF-001/002/016/017/018). The membership facts
 * and every request state are disclosed before any action; the request is an
 * intent only — "This is a request. Your gym must approve it." Nothing here
 * sets a membership status, grants a pause or promises an approval, and
 * offline the surface shows its last good read and refuses every command
 * without queueing anything (SLF-017).
 */

type FreezeMembership = {
  planName: string | null;
  status: string;
  startsOn: string | null;
  endsOn: string | null;
  recordedAgreedPricePaise: string | null;
  currency: string;
} | null;

export type MemberFreezeRequestsSurfaceProps = {
  nouns: { place: string; member: string };
  membership: FreezeMembership;
  membershipId?: string | null;
  requests: MemberFreezeRequestRow[];
  offline: boolean;
  loadedAt: string | null;
  permissionDenied?: boolean;
};


// The props parameter is optional so the surface also satisfies a bare
// component slot; every real mount passes the full prop set.
export default function MemberFreezeRequestsSurface(props?: MemberFreezeRequestsSurfaceProps) {
  const { nouns = { place: 'gym', member: 'member' }, membership = null, membershipId = null, requests = [], offline = false, loadedAt = null, permissionDenied = false } = props ?? {};
  const copy = freezeRequestCopy(nouns);
  const [formOpen, setFormOpen] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [startsOn, setStartsOn] = useState('');
  const [endsOn, setEndsOn] = useState('');
  const [reason, setReason] = useState('');
  // SLF-013: one key per logical command, kept across uncertain outcomes and
  // nulled by the runner on a definitive one — a retry after an unknown
  // commit reconciles the same request, it never mints a second one.
  const createSlot = useRef<KeySlot>({ current: null });
  const cancelSlots = useRef<Record<string, KeySlot>>({});
  const controls = { busy, setBusy, setMessage, onOk: () => setMessage(null) };

  if (permissionDenied) {
    return <section className="member-section" aria-labelledby="freeze-heading">
      <h2 id="freeze-heading" className="cl-eyebrow member-eyebrow">{copy.sectionTitle}</h2>
      <p className="cl-alert" role="alert">{copy.permissionNote}</p>
    </section>;
  }

  const pendingMembership = membership?.status === 'pending';
  const canRequest = membership !== null && !pendingMembership && (membership.status === 'active' || membership.status === 'frozen') && !offline;

  const submit = () => void runFrozenCommand('/api/member/freeze-requests', 'requestKey', { membershipId: membershipId ?? '', startsOn, endsOn, reason }, controls, createSlot.current, copy.uncertainCreate);
  const cancel = (requestId: string) => {
    const slot = cancelSlots.current[requestId] ?? { current: null };
    cancelSlots.current[requestId] = slot;
    void runFrozenCommand(`/api/member/freeze-requests/${requestId}/cancel`, 'commandKey', {}, controls, slot, copy.uncertainCancel);
  };

  return <section className="member-section" aria-labelledby="freeze-heading">
    <h2 id="freeze-heading" className="cl-eyebrow member-eyebrow">{copy.sectionTitle}</h2>
    <p className="member-quiet">{copy.requestNotice}</p>
    {membership ? <dl className="member-facts">
      {membership.planName ? <div><dt>Plan</dt><dd>{membership.planName}</dd></div> : null}
      <div><dt>Status</dt><dd><StatusWord status={membership.status} /></dd></div>
      {membership.startsOn ? <div><dt>Started</dt><dd><time dateTime={membership.startsOn}>{membership.startsOn}</time></dd></div> : null}
      {membership.endsOn ? <div><dt>Ends</dt><dd><time dateTime={membership.endsOn}>{membership.endsOn}</time></dd></div> : null}
      {membership.recordedAgreedPricePaise !== null ? <div><dt>Price when sold</dt><dd className="plan-price-amount">{formatMoney(membership.recordedAgreedPricePaise, membership.currency)} <span>{membership.currency}</span></dd></div> : null}
    </dl> : null}
    {pendingMembership ? <p className="member-quiet">{copy.pendingMembershipNote}</p> : null}
    {!pendingMembership && membership !== null && !offline ? <p><a href="/member/buy" className="cl-btn cl-btn--quiet">{copy.renewCta}</a></p> : null}
    {canRequest && !formOpen ? <p><button className="cl-btn" onClick={() => setFormOpen(true)}>{copy.requestCta}</button></p> : null}
    {canRequest && formOpen ? <div className="freeze-request-form">
      <p className="member-quiet">{copy.datesNote}</p>
      <Field label={copy.startsOnLabel}><input type="date" value={startsOn} onChange={(event) => setStartsOn(event.target.value)} className={inputClass} /></Field>
      <Field label={copy.endsOnLabel}><input type="date" value={endsOn} onChange={(event) => setEndsOn(event.target.value)} className={inputClass} /></Field>
      <Field label={copy.reasonLabel}><input type="text" value={reason} maxLength={2000} onChange={(event) => setReason(event.target.value)} className={inputClass} /></Field>
      <p><button className="cl-btn" disabled={busy} onClick={submit}>{copy.sendCta}</button></p>
    </div> : null}
    {offline ? <p className="cl-alert" role="status">{`${copy.offlineNotice}${loadedAt ? ` ${copy.lastLoadedLabel} ${loadedAt}.` : ''}`}</p> : null}
    {requests.length === 0 && !offline ? <p className="member-quiet">{copy.emptyNote}</p> : null}
    <ul className="freeze-request-list" aria-label={copy.sectionTitle}>
      {requests.map((row) => <li key={row.requestId} className="freeze-request-row">
        <p className="cl-row-title"><StatusWord status={row.status} label={freezeRequestStateWord(copy, row.status, row.effective)} /></p>
        <p className="member-quiet"><time dateTime={row.startsOn}>{row.startsOn}</time> – <time dateTime={row.endsOn}>{row.endsOn}</time></p>
        {row.reason ? <p className="member-quiet">{row.reason}</p> : null}
        {row.status === 'rejected' && row.decisionReason ? <p className="member-quiet">{row.decisionReason}</p> : null}
        {!offline && freezeRequestCancellable(row.status) ? <p><button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => cancel(row.requestId)}>{copy.cancelCta}</button></p> : null}
      </li>)}
    </ul>
    {message ? <p role="status">{message}</p> : null}
  </section>;
}