import { purchaseRequestRefusalMessage } from '@gymloop/shared';

/** One shared POST runner for the member and desk purchase client components. */
export async function postPurchaseCommand(path: string, body: Record<string, unknown>): Promise<{ ok: boolean; refusal: string | null; payload: unknown }> {
  try {
    const answer = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), cache: 'no-store' });
    const payload = await answer.json() as { ok: boolean; data?: unknown; error?: { code: string } };
    if (!payload.ok) return { ok: false, refusal: purchaseRequestRefusalMessage(payload.error?.code ?? 'operation_failed'), payload };
    return { ok: true, refusal: null, payload: payload.data };
  } catch {
    return { ok: false, refusal: purchaseRequestRefusalMessage('operation_failed'), payload: null };
  }
}

/** Shared busy/message guard for the member and desk action components. */
export function runPurchaseAction(
  path: string,
  body: Record<string, unknown>,
  controls: {
    busy: boolean;
    setBusy: (busy: boolean) => void;
    setMessage: (message: string | null) => void;
    onOk: () => void;
  },
): Promise<void> {
  return (async () => {
    if (controls.busy) return;
    controls.setBusy(true);
    controls.setMessage(null);
    const answer = await postPurchaseCommand(path, body);
    if (answer.ok) controls.onOk();
    else controls.setMessage(answer.refusal);
    controls.setBusy(false);
  })();
}
