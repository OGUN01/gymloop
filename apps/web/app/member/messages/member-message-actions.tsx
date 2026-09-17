'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';

/**
 * The member's explicit "open this message" action (contract §5, the seam's
 * "In-app delivery" rule: "Reading a message means the member explicitly
 * opens it or acknowledges it; merely prefetching a list does not claim
 * delivery"). This is a plain click — never a form submitted on mount, never
 * an effect fired by the list rendering — and it exists only on a `sent`,
 * not-yet-delivered message; an already-delivered one has nothing to open.
 */
export function MemberMessageAck({ notificationId }: { notificationId: string }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [problem, setProblem] = useState('');

  async function open(): Promise<void> {
    if (pending) return;
    setPending(true);
    setProblem('');
    try {
      const response = await fetch(`/api/member/notifications/${notificationId}/delivered`, { method: 'POST' });
      const payload = await response.json() as { ok?: boolean };
      if (!response.ok || payload.ok !== true) {
        setProblem('This message could not be marked as read. Try again.');
        return;
      }
      router.refresh();
    } catch {
      setProblem('The connection was interrupted. Try again.');
    } finally {
      setPending(false);
    }
  }

  return <div className="mt-2">
    <button type="button" onClick={open} disabled={pending} className="min-h-11 rounded-lg border border-neutral-400 px-3 py-2 text-sm font-medium disabled:opacity-50">
      {pending ? 'Opening…' : 'Open message'}
    </button>
    {problem !== '' ? <p role="alert" className="mt-1 text-sm text-red-700">{problem}</p> : null}
  </div>;
}
