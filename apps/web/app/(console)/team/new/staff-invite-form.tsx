'use client';
import { useState, type FormEvent } from 'react';
import { STAFF_INVITE_ROLES, STAFF_INVITE_ROLE_LABELS, staffMemberInviteRequestSchema, STAFF_INVITE_LIMITS, parseStaffInviteToken } from '@gymloop/shared';
import { UUID_PATTERN } from '../../../../lib/keyset';
import { Field, inputClass } from '../../field';
import { Alert } from '../../alert';
import { AppAccessPanel } from '../../members/[memberId]/app-access-panel';
/** Atomic staff creation; the returned link stays only in this mounted view. */
export function StaffInviteForm({ branches, gymName }: { branches: { id: string; name: string }[]; gymName: string }) {
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [created, setCreated] = useState<{ id: string; inviteId: string; name: string; email: string; phone: string | null; roleLabel: string; link: string; expiresAt: string } | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (busy) return;
    const form = new FormData(event.currentTarget);
    const parsed = staffMemberInviteRequestSchema.safeParse({ fullName: form.get('fullName'), email: form.get('email'), phone: form.get('phone') || undefined, role: form.get('role'), branchId: form.get('branchId') || undefined });
    if (!parsed.success) { setError('Check the name, email, phone and role, then try again.'); return; }
    setBusy(true); setError(null);
    try {
      const response = await fetch('/api/staff-members', { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(parsed.data) });
      const payload = await response.json();
      if (!response.ok || payload.ok !== true || typeof payload.data?.staffId !== 'string' || !UUID_PATTERN.test(payload.data.staffId) || typeof payload.data?.inviteId !== 'string' || !UUID_PATTERN.test(payload.data.inviteId) || typeof payload.data?.link !== 'string' || parseStaffInviteToken(payload.data.link) === null || typeof payload.data?.expiresAt !== 'string' || Number.isNaN(Date.parse(payload.data.expiresAt))) {
        setError(payload.error?.code === 'invite_rate_limited' ? 'Too many invites from this gym this hour. Wait an hour, then try again.' : payload.error?.code === 'staff_email_taken' ? 'This email is already used by a staff member in your gym.' : 'The staff invite could not be created. Check the details and try again.'); return;
      }
      setCreated({ id: payload.data.staffId, inviteId: payload.data.inviteId, name: parsed.data.fullName, email: parsed.data.email, phone: parsed.data.phone ?? null, roleLabel: STAFF_INVITE_ROLE_LABELS[parsed.data.role], link: payload.data.link, expiresAt: payload.data.expiresAt });
    } catch { setError('Check your internet connection, then try again.'); } finally { setBusy(false); }
  }
  if (created !== null) return <AppAccessPanel memberId={created.id} memberName={created.name} email={created.email} phone={created.phone} gymName={gymName} role="gym_owner" staffRoleLabel={created.roleLabel} access={{ state: 'invite_pending', inviteId: created.inviteId, issuedAt: null, linkedAt: null, expiresAt: created.expiresAt }} initialIssued={{ link: created.link, expiresAt: created.expiresAt, replacedPrevious: false }} />;
  return <form className="cl-form" onSubmit={event => void submit(event)} aria-busy={busy}><p className="app-access-note">Use the email this staff member uses to sign in with Google. The invite is valid for {STAFF_INVITE_LIMITS.ttlHours} hours. Creating it sends nothing automatically: copy or share the link with them yourself.</p>{error === null ? null : <Alert>{error}</Alert>}<Field label="Full name"><input className={inputClass} name="fullName" required autoComplete="name" /></Field><Field label="Email"><input className={inputClass} name="email" type="email" required autoComplete="email" /></Field><Field label="Phone (optional)"><input className={inputClass} name="phone" type="tel" placeholder="+91" autoComplete="tel" /></Field><Field label="Role"><select className={inputClass} name="role" required>{STAFF_INVITE_ROLES.map(role => <option key={role} value={role}>{STAFF_INVITE_ROLE_LABELS[role]}</option>)}</select></Field><Field label="Branch (optional)"><select className={inputClass} name="branchId"><option value="">All branches</option>{branches.map(branch => <option key={branch.id} value={branch.id}>{branch.name}</option>)}</select></Field><button className="cl-btn cl-btn--primary" disabled={busy} type="submit">{busy ? 'Creating invite…' : 'Send invite'}</button></form>;
}
