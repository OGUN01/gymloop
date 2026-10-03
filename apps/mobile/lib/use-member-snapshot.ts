
import { useBusinessNouns } from './use-business-nouns';
import { useCallback, useEffect, useRef, useState } from 'react';
import { loadMemberSnapshot, type MemberSnapshot } from './mobile-data';
import { useMobile } from './mobile-context';
export function useMemberSnapshot() {
  const nouns = useBusinessNouns();
  const { identity, supabase } = useMobile(); const [data, setData] = useState<MemberSnapshot | null>(null); const [error, setError] = useState<string | null>(null); const [loading, setLoading] = useState(true);
  // The client object identity can change per provider render without any of its
  // behaviour changing, so the loader reads it through a ref and re-creates only
  // on the identity facts that actually decide what to load.
  const supabaseRef = useRef(supabase); supabaseRef.current = supabase;
  const memberRef = useRef(identity);
  memberRef.current = identity;
  const member = identity.kind === 'member' ? identity : null;
  const memberKey = member !== null ? `${member.tenantId}:${member.memberId}` : '';
  const reload = useCallback(async () => {
    const active = memberRef.current;
    if (active === null || active.kind !== 'member') return;
    setLoading(true); setError(null);
    try { setData(await loadMemberSnapshot(supabaseRef.current, active)); } catch { setError(`Your ${nouns.place} information could not be loaded.`); } finally { setLoading(false); }
  }, [memberKey, nouns.place]);
  useEffect(() => { void reload(); }, [reload]); return { data, error, loading, reload };
}
