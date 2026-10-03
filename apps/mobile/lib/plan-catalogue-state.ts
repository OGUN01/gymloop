import { formatDateTime, type PlanCatalogueCopy, type PlanCatalogueView } from '@gymloop/shared';
export type PlanCatalogueState = { phase: 'idle' | 'loading' | 'ready' | 'failed'; view: PlanCatalogueView | null; loadedAt: string | null; staleReason: 'offline' | 'refresh_failed' | null; offline: boolean };
export const initialPlanCatalogueState: PlanCatalogueState = { phase: 'idle', view: null, loadedAt: null, staleReason: null, offline: false };
type Event = { type: 'reset' } | { type: 'started' } | { type: 'succeeded'; view: PlanCatalogueView; at: string } | { type: 'failed'; offline: boolean };
export function planCatalogueReducer(state: PlanCatalogueState, event: Event): PlanCatalogueState {
  switch (event.type) {
    case 'reset': return initialPlanCatalogueState;
    case 'started': return { ...state, phase: 'loading', staleReason: null };
    case 'succeeded': return { phase: 'ready', view: event.view, loadedAt: event.at, staleReason: null, offline: false };
    case 'failed': return { ...state, phase: state.view ? 'ready' : 'failed', staleReason: state.view ? event.offline ? 'offline' : 'refresh_failed' : null, offline: event.offline };
  }
}
export function planCatalogueNotice(state: PlanCatalogueState, copy: PlanCatalogueCopy, timeZone: string): { tone: 'warning' | 'error'; text: string } | null {
  if (state.phase === 'ready' && state.staleReason && state.loadedAt) return { tone: 'warning', text: (state.staleReason === 'offline' ? copy.staleOffline : copy.staleRefresh)(formatDateTime(state.loadedAt, timeZone)) };
  return state.phase === 'failed' ? { tone: 'error', text: state.offline ? copy.offline : copy.error } : null;
}
