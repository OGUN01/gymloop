'use client';

import { useRef, useState } from 'react';
import { freezeApproverRoleNote, freezeRequestCopy, type DeskFreezeRequestRow } from '@gymloop/shared';
import { Field, inputClass } from '../field';
import { StatusWord } from '../../status-word';
import { runFrozenCommand, type KeySlot } from '../../../lib/freeze-commands';

/**
 * The desk freeze queue (SLF-006…010, bar criterion 5). Adoption and approval
 * are two distinct actions by two distinct people: the staff member who
 * adopts a member request can never approve their own adopted pause, approval
 * belongs to the currently configured approver role read live from settings,
 * and a stale row closes its confirmation instead of deciding.
 */

export type FreezeRequestQueueProps = {
  nouns: { place: string; member: string };
  viewerRole: string;
  viewerStaffId: string;
  approverRole: string;
  requests: DeskFreezeRequestRow[];
  stale?: boolean;
};

function stateWord(copy: ReturnType<typeof freezeRequestCopy>, row: DeskFreezeRequestRow): string {
  switch (row.status) {
    case 'requested': return copy.awaitingAdoption;
    case 'desk_submitted': return copy.awaitingApproval;
    case 'approved': return copy.approved;
    case 'rejected': return copy.rejected;
    case 'cancelled': return copy.cancelled;
    case 'expired': return copy.expired;
    default: return copy.awaitingAdoption;
  }
}

export function FreezeRequestQueue({ nouns, viewerRole, viewerStaffId, approverRole, requests, stale = false }: FreezeRequestQueueProps) {
  const copy = freezeRequestCopy(nouns);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [rejectReasons, setRejectReasons] = useState<Record<string, string>>({});
  // SLF-013: one key per logical command (action + request), kept across
  // uncertain outcomes, nulled by the runner on a definitive one.
  const commandSlots = useRef<Record<string, KeySlot>>({});
  const controls = { busy, setBusy, setMessage, onOk: () => setMessage(null) };
  const slotFor = (action: string, requestId: string): KeySlot => {
    const key = `${action}:${requestId}`;
    commandSlots.current[key] = commandSlots.current[key] ?? { current: null };
    return commandSlots.current[key];
  };
  const run = (action: string, row: DeskFreezeRequestRow, baseBody: Record<string, unknown> = {}) => void runFrozenCommand(`/api/freeze-requests/${row.requestId}/${action}`, 'commandKey', { expectedRevision: row.revision, ...baseBody }, controls, slotFor(action, row.requestId), copy.uncertainDecision);
  const adopt = (row: DeskFreezeRequestRow) => run('adopt', row);
  const approve = (row: DeskFreezeRequestRow) => run('approve', row);
  const reject = (row: DeskFreezeRequestRow) => run('reject', row, { reason: rejectReasons[row.requestId] ?? '' });
  const expire = (row: DeskFreezeRequestRow) => run('expire', row);

  return <section className="member-section" aria-labelledby="freeze-queue-heading">
    <h2 id="freeze-queue-heading" className="cl-eyebrow member-eyebrow">{copy.sectionTitle}</h2>
    <p className="member-quiet">{freezeApproverRoleNote(approverRole)}</p>
    {stale ? <p className="cl-alert" role="alert">{copy.staleNote}</p> : null}
    {requests.length === 0 && !stale ? <p className="member-quiet">{copy.emptyNote}</p> : null}
    <ul className="freeze-request-list" aria-label={copy.sectionTitle}>
      {requests.map((row) => {
        // One person adopts, a different configured-role person approves (SLF-006/007).
        const ownAdoption = row.adoptedByStaffId !== null && row.adoptedByStaffId === viewerStaffId;
        const open = row.status === 'requested' || row.status === 'desk_submitted';
        return <li key={row.requestId} className="freeze-request-row">
          <p className="cl-row-title">{row.memberName} <span>{row.memberCode}</span></p>
          <p className="member-quiet"><StatusWord status={row.status} label={stateWord(copy, row)} /></p>
          <p className="member-quiet"><time dateTime={row.startsOn}>{row.startsOn}</time> – <time dateTime={row.endsOn}>{row.endsOn}</time></p>
          <p className="member-quiet">{row.reason}</p>
          {!stale && row.status === 'requested' ? <p><button className="cl-btn" disabled={busy} onClick={() => adopt(row)}>{copy.adoptCta}</button></p> : null}
          {!stale && row.status === 'desk_submitted' && ownAdoption ? <p className="member-quiet">{copy.ownAdoptionNote}</p> : null}
          {!stale && row.status === 'desk_submitted' && !ownAdoption ? <p><button className="cl-btn" disabled={busy || viewerRole !== approverRole} onClick={() => approve(row)}>{copy.approveCta}</button></p> : null}
          {!stale && row.status === 'expired' ? <p><button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => expire(row)}>{'Record expiry'}</button></p> : null}
          {row.status === 'rejected' && row.decisionReason ? <p className="member-quiet">{`${copy.shownToMember}: ${row.decisionReason}`}</p> : null}
          {!stale && open ? <div className="freeze-reject">
            <Field label={copy.shownToMember}><input type="text" value={rejectReasons[row.requestId] ?? ''} maxLength={200} onChange={(event) => setRejectReasons({ ...rejectReasons, [row.requestId]: event.target.value })} className={inputClass} /></Field>
            <p><button className="cl-btn cl-btn--quiet" disabled={busy} onClick={() => reject(row)}>{copy.rejected}</button></p>
          </div> : null}
        </li>;
      })}
    </ul>
    {message ? <p role="status">{message}</p> : null}
  </section>;
}
