import { freezeRequestRefusalMessage } from '@gymloop/shared';

/**
 * One shared POST runner for the member and desk freeze client components.
 * Every logical command carries ONE key (SLF-013): the slot mints it on the
 * first attempt and keeps it across uncertain outcomes, so a retry carries
 * the same key and reconciles the same request; a definitive known failure —
 * nothing was written — nulls the slot so the next deliberate attempt mints
 * fresh. An unknown code or an interrupted transport leaves the outcome
 * uncertain and the key in place.
 */

export type FreezeCommandControls = {
  busy: boolean;
  setBusy: (busy: boolean) => void;
  setMessage: (message: string | null) => void;
  onOk: () => void;
};

/** A known code is a definitive answer — the write either happened or it did not. */
const DEFINITIVE_CODES = new Set(['invalid_request', 'not_permitted', 'request_unavailable', 'idempotency_conflict', 'state_conflicted', 'limit_reached', 'validation_refused', 'rate_limited']);

export type KeySlot = { current: string | null };

export async function runFrozenCommand(
  path: string,
  keyField: string,
  baseBody: Record<string, unknown>,
  controls: FreezeCommandControls,
  slot: KeySlot,
  uncertainCopy: string,
): Promise<void> {
  return (async () => {
    if (controls.busy) return;
    controls.setBusy(true);
    controls.setMessage(null);
    const key = slot.current ?? crypto.randomUUID();
    slot.current = key;
    try {
      const answer = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ ...baseBody, [keyField]: key }), cache: 'no-store' });
      const payload = await answer.json() as { ok: boolean; data?: unknown; error?: { code: string } };
      if (!payload.ok) {
        const code = typeof payload.error?.code === 'string' ? payload.error.code : '';
        if (DEFINITIVE_CODES.has(code)) {
          slot.current = null;
          controls.setMessage(freezeRequestRefusalMessage(code));
        } else {
          // Unknown commit outcome: the key stays; retrying checks the same request.
          controls.setMessage(uncertainCopy);
        }
      } else {
        slot.current = null;
        controls.onOk();
      }
    } catch {
      controls.setMessage(uncertainCopy);
    } finally {
      controls.setBusy(false);
    }
  })();
}
