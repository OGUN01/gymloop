'use client';
import { useEffect, useRef, useState } from 'react';
import { PT_REFUSAL_COPY, ptCopy, ptRefusalMessage, type BusinessNouns, type GymloopIdentity } from '@gymloop/shared';
type ConsoleViewer = { role: Extract<GymloopIdentity, { kind: 'staff' }>['role'] | null; staffId: string | null; readOnly: boolean; scopeKey: string };
type PtCommandOptions<TBody, TResult> = { viewer: ConsoleViewer; operationKey: string; nouns: BusinessNouns; canSubmit: (viewer: ConsoleViewer) => boolean; send: (body: TBody) => Promise<TResult>; accepted: (result: TResult) => boolean; refresh: () => void };
type PtCommandLease = { key: string; live: boolean; pending: boolean };
function commandFailureMessage(result: unknown): string {
  if (result && typeof result === 'object' && 'error' in result && result.error && typeof result.error === 'object' && 'code' in result.error && typeof result.error.code === 'string' && Object.hasOwn(PT_REFUSAL_COPY, result.error.code)) return ptRefusalMessage(result.error.code);
  return 'The result could not be confirmed. Check the latest details before trying again.';
}
export function usePtCommand<TBody, TResult>(options: PtCommandOptions<TBody, TResult>) {
  const key = JSON.stringify([options.viewer.scopeKey, options.viewer.role, options.viewer.staffId, options.viewer.readOnly, options.operationKey]);
  const latest = useRef(options); latest.current = options;
  const leaseRef = useRef<PtCommandLease>({ key, live: true, pending: false });
  if (leaseRef.current.key !== key) { leaseRef.current.live = false; leaseRef.current = { key, live: true, pending: false }; }
  const lease = leaseRef.current;
  const [feedback, setFeedback] = useState<{ lease: PtCommandLease; pending: boolean; error: string | null }>({ lease, pending: false, error: null });
  useEffect(() => { lease.live = true; return () => { lease.live = false; }; }, [lease]);
  async function submit(body: TBody): Promise<TResult | null> {
    const current = latest.current;
    if (!lease.live || leaseRef.current !== lease || lease.pending) return null;
    if (current.viewer.readOnly || !current.canSubmit(current.viewer)) { setFeedback({ lease, pending: false, error: ptRefusalMessage('not_found') }); return null; }
    if (typeof navigator !== 'undefined' && navigator.onLine === false) { setFeedback({ lease, pending: false, error: ptCopy(current.nouns).offline }); return null; }
    lease.pending = true; setFeedback({ lease, pending: true, error: null });
    try {
      const result = await current.send(body);
      if (!lease.live || leaseRef.current !== lease) return null;
      if (!latest.current.accepted(result)) { setFeedback({ lease, pending: false, error: commandFailureMessage(result) }); return null; }
      latest.current.refresh(); return result;
    } catch { if (lease.live && leaseRef.current === lease) setFeedback({ lease, pending: false, error: commandFailureMessage(null) }); return null; }
    finally { lease.pending = false; if (lease.live && leaseRef.current === lease) setFeedback(previous => previous.lease === lease ? { ...previous, pending: false } : previous); }
  }
  return { pending: feedback.lease === lease && feedback.pending, error: feedback.lease === lease ? feedback.error : null, submit };
}
