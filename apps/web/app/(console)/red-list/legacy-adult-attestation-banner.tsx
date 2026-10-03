'use client';
import { useEffect, useRef, useState } from 'react';
import { useGuardianCommand } from '../../../lib/use-guardian-command';
import { Alert } from '../alert';
import type { StaffRole } from '../../../lib/identity';
import '../../styles/guardian.css';

const LEGACY_ADULT_ATTESTATION_COPY = 'Members without a date of birth have absence follow-ups off. The owner can confirm once that existing members without a date of birth are adults. Members added afterwards still need a date of birth.';
export function LegacyAdultAttestationBanner({ role, readOnly = false }: { role: StaffRole; readOnly?: boolean }) {
  const command = useGuardianCommand(readOnly);
  const [open, setOpen] = useState(false);
  const [confirmed, setConfirmed] = useState(false);
  const [attested, setAttested] = useState(false);
  const opener = useRef<HTMLButtonElement>(null);
  const wasOpen = useRef(false);
  useEffect(() => { if (wasOpen.current && !open) opener.current?.focus(); wasOpen.current = open; }, [open]);
  if (attested) return null;
  return <div className="guardian-form">
    <p>{LEGACY_ADULT_ATTESTATION_COPY}</p>
    {command.preview ? <p className="guardian-note">This confirmation is read-only in support preview.</p> : null}
    {!command.online ? <p role="status">You are offline. Connect to the internet to confirm.</p> : null}
    {command.error ? <Alert>{command.error}</Alert> : null}
    {role === 'gym_owner' ? !open ? <div className="cl-actions"><button ref={opener} type="button" className="cl-btn" disabled={command.disabled} onClick={() => setOpen(true)}>Confirm existing members are adults</button></div> : <form className="cl-panel guardian-confirm" onSubmit={async (event) => { event.preventDefault(); if (confirmed && await command.send('/api/member-guardian/legacy-attestation', {}, 'Adult confirmation recorded.')) setAttested(true); }}>
      <p>This confirms only existing members without a date of birth. It is saved once in the audit log and cannot be changed. Members added afterwards still need a date of birth.</p>
      <label className="guardian-check"><input type="checkbox" autoFocus required checked={confirmed} disabled={command.disabled} onChange={(event) => setConfirmed(event.target.checked)} /><span>I confirm existing members without a date of birth are adults.</span></label>
      <div className="cl-actions"><button className="cl-btn cl-btn--primary" type="submit" disabled={command.disabled || !confirmed}>{command.busy ? 'Confirming…' : 'Confirm existing members are adults'}</button><button className="cl-btn" type="button" disabled={command.busy} onClick={() => { setOpen(false); setConfirmed(false); opener.current?.focus(); }}>Cancel</button></div>
    </form> : null}
  </div>;
}
