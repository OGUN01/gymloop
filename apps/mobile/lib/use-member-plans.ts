import { useCallback, useEffect, useReducer, useRef } from 'react';
import * as Network from 'expo-network';
import { readPlanCatalogue, type PlanCatalogueDb } from '@gymloop/shared';
import { useMobile } from './mobile-context';
import { initialPlanCatalogueState, planCatalogueReducer, type PlanCatalogueState } from './plan-catalogue-state';

export function useMemberPlans(open: boolean): { state: PlanCatalogueState; reload(): Promise<void> } {
  const { identity, supabase } = useMobile();
  const scope = identity.kind === 'member' ? `${identity.userId}:${identity.tenantId}:${identity.memberId}` : null;
  const memberId = identity.kind === 'member' ? identity.memberId : null;
  const [state, dispatch] = useReducer(planCatalogueReducer, initialPlanCatalogueState);
  const newest = useRef<object>({});
  const stateScope = useRef(scope);
  const mounted = useRef(false);
  const eligibility = useRef({ scope, open, supabase });
  if (eligibility.current.scope !== scope || eligibility.current.open !== open || eligibility.current.supabase !== supabase) eligibility.current = { scope, open, supabase };
  const capability = eligibility.current;
  const reload = useCallback(async () => {
    const eligible = () => mounted.current && eligibility.current === capability && capability.open && capability.scope !== null;
    if (identity.kind !== 'member' || !eligible()) return;
    const request = {};
    newest.current = request;
    dispatch({ type: 'started' });
    let result;
    try { result = await readPlanCatalogue(supabase as unknown as PlanCatalogueDb, identity.memberId); } catch { result = { ok: false } as const; }
    if (!eligible() || newest.current !== request) return;
    if (result.ok) dispatch({ type: 'succeeded', view: result.view, at: new Date().toISOString() });
    else {
      let offline = false;
      try { const network = await Network.getNetworkStateAsync(); offline = !network.isConnected || !network.isInternetReachable; } catch { /* A failed network probe leaves the ordinary read error. */ }
      if (eligible() && newest.current === request) dispatch({ type: 'failed', offline });
    }
  }, [identity.kind, memberId, scope, open, supabase, capability]);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; newest.current = {}; }; }, []);
  useEffect(() => { newest.current = {}; stateScope.current = scope; dispatch({ type: 'reset' }); return () => { newest.current = {}; }; }, [scope]);
  useEffect(() => { void reload(); return () => { newest.current = {}; }; }, [reload]);
  return { state: stateScope.current === scope ? state : initialPlanCatalogueState, reload };
}
