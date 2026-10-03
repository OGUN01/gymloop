
import { useBusinessNouns } from './use-business-nouns';
import { useCallback, useEffect, useState } from 'react';
import { loadMemberSnapshot, type MemberSnapshot } from './mobile-data';
import { useMobile } from './mobile-context';
export function useMemberSnapshot() {
  const nouns = useBusinessNouns();
  const { identity, supabase } = useMobile(); const [data, setData] = useState<MemberSnapshot | null>(null); const [error, setError] = useState<string | null>(null); const [loading, setLoading] = useState(true);
  const reload = useCallback(async () => { if (identity.kind !== 'member') return; setLoading(true); setError(null); try { setData(await loadMemberSnapshot(supabase, identity)); } catch { setError(`Your ${nouns.place} information could not be loaded.`); } finally { setLoading(false); } }, [identity, supabase, nouns.place]);
  useEffect(() => { void reload(); }, [reload]); return { data, error, loading, reload };
}
