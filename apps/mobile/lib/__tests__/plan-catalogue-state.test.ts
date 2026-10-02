import { describe, expect, it } from 'vitest';
import { formatDateTime, planCatalogueCopy, type PlanCatalogueView } from '@gymloop/shared';
import { initialPlanCatalogueState, planCatalogueNotice, planCatalogueReducer } from '../plan-catalogue-state';
const view: PlanCatalogueView = { plans: [], truncated: false, held: null, heldUnavailable: false };
const at = '2026-10-02T06:30:00Z';
const copy = planCatalogueCopy({ place: 'academy' });
describe('PLC-018/019 in-memory catalogue states', () => {
  it('initial/cold start has no inherited copy or timestamp', () => {
    expect(initialPlanCatalogueState).toEqual({ phase: 'idle', view: null, loadedAt: null, staleReason: null, offline: false });
    expect(planCatalogueNotice(initialPlanCatalogueState, copy, 'Asia/Kolkata')).toBeNull();
  });
  it('start and success clear stale status and replace timestamp', () => {
    const loading = planCatalogueReducer(initialPlanCatalogueState, { type: 'started' });
    expect(loading.phase).toBe('loading'); expect(loading.view).toBeNull();
    const ready = planCatalogueReducer(loading, { type: 'succeeded', view, at });
    expect(ready).toEqual({ phase: 'ready', view, loadedAt: at, staleReason: null, offline: false });
    expect(planCatalogueNotice(ready, copy, 'Asia/Kolkata')).toBeNull();
  });
  it.each([false, true])('failure without a copy shows error offline=%s', (offline) => {
    const failed = planCatalogueReducer(initialPlanCatalogueState, { type: 'failed', offline });
    expect(failed.phase).toBe('failed'); expect(failed.view).toBeNull(); expect(failed.offline).toBe(offline);
    expect(planCatalogueNotice(failed, copy, 'Asia/Kolkata')).toEqual({ tone: 'error', text: offline ? copy.offline : copy.error });
  });
  it.each([false, true])('refresh failure retains exact prior copy offline=%s', (offline) => {
    const ready = planCatalogueReducer(initialPlanCatalogueState, { type: 'succeeded', view, at });
    const started = planCatalogueReducer(ready, { type: 'started' }); expect(started.view).toBe(view);
    const stale = planCatalogueReducer(started, { type: 'failed', offline });
    expect(stale.phase).toBe('ready'); expect(stale.view).toBe(view); expect(stale.loadedAt).toBe(at);
    expect(stale.staleReason).toBe(offline ? 'offline' : 'refresh_failed');
    expect(planCatalogueNotice(stale, copy, 'Asia/Kolkata')).toEqual({ tone: 'warning', text: (offline ? copy.staleOffline : copy.staleRefresh)(formatDateTime(at, 'Asia/Kolkata')) });
    const retry = planCatalogueReducer(stale, { type: 'started' }); expect(retry.staleReason).toBeNull(); expect(retry.view).toBe(view);
  });
  it('scope reset discards a stale view and does not mutate the old state', () => {
    const ready = planCatalogueReducer(initialPlanCatalogueState, { type: 'succeeded', view, at });
    expect(planCatalogueReducer(ready, { type: 'reset' })).toEqual(initialPlanCatalogueState);
    expect(ready.view).toBe(view); expect(ready.loadedAt).toBe(at);
  });
});
