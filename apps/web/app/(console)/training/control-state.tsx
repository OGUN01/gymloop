'use client';
import { useEffect, useRef, useState } from 'react';
import type { ConsoleViewer } from '../../../lib/training-console';
import { useBrowserOnline } from '../../../lib/use-browser-online';

export function ConsoleTrainingConnectionNotice() {
  const online = useBrowserOnline();
  return online === false ? <p className="cl-alert" role="status">You're offline. Reconnect to see bookings. This view may be stale.</p> : null;
}

/** Read props are a presentation lease, never a credential. Revocation is permanent. */
export function useControlState<T>(initial: T, facts: string, viewer: ConsoleViewer) {
  const key = JSON.stringify([facts, viewer.scopeKey, viewer.role, viewer.staffId, viewer.readOnly]);
  const owner = useRef<{ key: string; active: boolean } | null>(null);
  if (owner.current?.key !== key || !owner.current.active) {
    if (owner.current) owner.current.active = false;
    owner.current = { key, active: true };
  }
  const lease = owner.current;
  const [state, setState] = useState({ lease, value: initial });
  const latest = useRef({ lease, value: initial });
  latest.current = state.lease === lease ? state : { lease, value: initial };
  useEffect(() => () => { lease.active = false; }, [lease]);
  return {
    value: state.lease === lease ? state.value : initial,
    current: (snapshot?: T) => lease.active && owner.current === lease && (snapshot === undefined || latest.current.value === snapshot),
    set: (value: T | ((old: T) => T)) => {
      if (lease.active && owner.current === lease) {
        const next = { lease, value: typeof value === 'function' ? (value as (prior: T) => T)(latest.current.value) : value };
        latest.current = next;
        setState(next);
      }
    },
    key,
  };
}
