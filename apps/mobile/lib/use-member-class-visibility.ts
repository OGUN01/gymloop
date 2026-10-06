import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState } from 'react-native';
import { useFocusEffect, usePathname } from 'expo-router';
import { useMobile } from './mobile-context';
import { loadMemberClassVisibility } from './classes';
import { clearMemberClassVisibilityCache, memberClassVisibilityCache as cache } from './member-class-visibility-cache';

export function useMemberClassVisibility(): { enabled: boolean | null; loading: boolean; error: string | null; reload: () => Promise<void> } {
  const { identity, ready, session, supabase } = useMobile();
  const pathname = usePathname();
  const key = ready && session !== null && identity.kind === 'member'
    ? `${identity.userId}:${identity.tenantId}:${identity.memberId}`
    : null;
  if (cache.scope !== key) {
    void clearMemberClassVisibilityCache();
    cache.scope = key;
  }
  const authority = useRef({ key, session, supabase, revision: cache.revision, active: true });
  if (authority.current.key !== key || authority.current.session !== session || authority.current.supabase !== supabase || authority.current.revision !== cache.revision || !authority.current.active) {
    authority.current.active = false;
    authority.current = { key, session, supabase, revision: cache.revision, active: true };
  }
  const scope = authority.current;
  const [state, setState] = useState<{ scope: typeof scope | null; enabled: boolean | null; loading: boolean; error: string | null }>({ scope, enabled: key !== null ? cache.enabled : null, loading: key !== null, error: null });
  const newest = useRef<object>({});
  const isCurrent = useCallback(() => scope.active && scope.key !== null && authority.current === scope && cache.revision === scope.revision && cache.scope === scope.key, [scope]);
  const reload = useCallback(async () => {
    if (!isCurrent()) return;
    const request = {};
    newest.current = request;
    setState(old => ({ scope, enabled: old.scope === scope ? old.enabled : cache.enabled, loading: true, error: null }));
    let enabled: boolean | null = null;
    try { enabled = await loadMemberClassVisibility(supabase); } catch { /* The saved value remains available through a temporary read failure. */ }
    if (!isCurrent() || newest.current !== request) return;
    if (typeof enabled === 'boolean') {
      cache.enabled = enabled;
      setState({ scope, enabled, loading: false, error: null });
    } else {
      setState(old => ({ scope, enabled: old.scope === scope ? old.enabled : cache.enabled, loading: false, error: 'Classes visibility could not be loaded. Check your connection and try again.' }));
    }
  }, [isCurrent, scope, supabase]);
  useEffect(() => {
    // A StrictMode replay creates a new lifetime rather than reviving its revoked read.
    if (!scope.active) { setState(old => ({ ...old, scope: null })); return; }
    void reload();
    const subscription = AppState.addEventListener('change', next => { if (next === 'active') void reload(); });
    return () => { scope.active = false; newest.current = {}; subscription.remove(); };
  }, [reload, scope]);
  useFocusEffect(useCallback(() => { void reload(); }, [pathname, reload]));
  const shown = state.scope === scope ? state : { enabled: key !== null ? cache.enabled : null, loading: key !== null, error: null };
  return { enabled: key === null ? null : shown.enabled, loading: shown.loading, error: shown.error, reload };
}
