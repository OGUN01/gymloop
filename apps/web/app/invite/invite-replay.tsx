'use client';
import { useEffect, useRef, useState } from 'react';
import { inviteRefusalMessage } from '@gymloop/shared';
import { InviteRecovery, refusalCodeFor } from './invite-parts';

/** POST once after mounting; the existing cookie API refreshes claims before confirming replay. */
export function InviteReplay({ token, email }: { token: string; email: string | null }) {
  const started = useRef<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  useEffect(() => {
    if (started.current === token) return;
    started.current = token;
    void (async () => {
      try {
        const response = await fetch('/api/member-invites/redeem', {
          method: 'POST', credentials: 'same-origin', cache: 'no-store',
          headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token }),
        });
        const payload = await response.json() as { ok?: unknown; data?: { outcome?: unknown }; error?: { code?: unknown } };
        if (started.current !== token) return;
        if (response.ok && payload.ok === true && payload.data?.outcome === 'already_linked_here') {
          window.location.replace('/member');
          return;
        }
        setMessage(inviteRefusalMessage(refusalCodeFor(payload.ok === true ? payload.data?.outcome : payload.error?.code)));
      } catch {
        if (started.current !== token) return;
        setMessage('The invite could not be checked. Check your connection, then try again.');
      }
    })();
  }, [token]);
  return <InviteRecovery token={token} email={email} title={message === null ? 'Checking invite' : 'Invite could not be opened'} message={message ?? 'Checking whether this invite is already linked to your account.'} checking={message === null} />;
}
