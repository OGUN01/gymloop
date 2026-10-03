'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { shopRefusalMessage, SHOP_REFUSAL_COPY, mediaRefusalMessage } from '@gymloop/shared';
import { usePreviewReadOnly } from '../app/preview-context';

const DESK_COPY: Record<string, string> = { insufficient_stock: 'Not enough stock to sell this. Cancel the reservation and tell the member.', offer_unavailable: 'This offer is unavailable. Cancel the reservation and tell the member.', idempotency_conflict: 'This request key names another sale. Inspect the existing sale before continuing.', category_name_taken: 'A category with that name already exists. Choose another name.', category_not_found: 'That category is unavailable. Refresh and choose another.', invalid_request: 'Check the fields and try again.', retryable: 'The sale could not finish. Retry the same command.', invalid_payment: 'Choose a desk payment method, or give a reason for a complimentary item.' };
export function useShopCommand() {
  const preview = usePreviewReadOnly();
  const router = useRouter();
  const [online, setOnline] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const pending = useRef(false);
  const uncertain = useRef(false);
  useEffect(() => { const update = () => setOnline(navigator.onLine); update(); window.addEventListener('online', update); window.addEventListener('offline', update); return () => { window.removeEventListener('online', update); window.removeEventListener('offline', update); }; }, []);
  async function send(path: string, body: unknown, message: string, method = 'POST'): Promise<Record<string, unknown> | null> {
    if (preview || pending.current || !navigator.onLine) { if (!navigator.onLine) setError("You're offline. Connect before making this change."); return null; }
    pending.current = true; uncertain.current = false; setBusy(true); setError(null); setSuccess(null);
    try {
      const response = await fetch(path, { method, headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), cache: 'no-store' });
      const payload = await response.json() as { ok?: boolean; data?: Record<string, unknown>; error?: { code?: string } };
      if (!response.ok || payload.ok !== true || !payload.data) {
        const code = payload.error?.code ?? '';
        // Retryable database refusals retain the reviewed command just as a
        // transport failure does; only a definitive refusal permits replacement.
        uncertain.current = code === 'retryable' || (!Object.hasOwn(SHOP_REFUSAL_COPY, code) && !Object.hasOwn(DESK_COPY, code));
        setError(Object.hasOwn(SHOP_REFUSAL_COPY, code) ? shopRefusalMessage(code) : Object.hasOwn(DESK_COPY, code) ? DESK_COPY[code]! : code.startsWith('media_') || code.startsWith('asset_') ? mediaRefusalMessage(code) : shopRefusalMessage(code));
        router.refresh(); return null;
      }
      setSuccess(message); router.refresh(); return payload.data;
    } catch { uncertain.current = true; setError('The connection was interrupted. Check the latest reservation before trying again.'); return null; }
    finally { pending.current = false; setBusy(false); }
  }
  return { send, online, busy, error, success, preview, uncertain, disabled: preview || busy || !online };
}
export function ShopCommandStatus({ command }: { command: ReturnType<typeof useShopCommand> }) { return <>{!command.online ? <p className="cl-alert" role="status">You&apos;re offline. Connect before making changes.</p> : null}{command.error ? <p className="cl-alert" role="alert">{command.error}</p> : null}{command.success ? <p role="status">{command.success}</p> : null}{command.busy ? <p role="status">Saving…</p> : null}</>; }
export function ShopConnectionNotice() { const command = useShopCommand(); return <ShopCommandStatus command={command} />; }
