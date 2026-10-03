'use client';
import { useEffect, useRef, useState } from 'react';
import { useRouter } from 'next/navigation';
import { usePreviewReadOnly } from '../app/preview-context';

const REFUSALS: Record<string, string> = {
  member_not_found: 'This member could not be found. Reload the page and try again.',
  date_of_birth_in_future: 'The date of birth cannot be in the future.',
  guardian_name_invalid: 'Enter a valid guardian name.',
  guardian_phone_invalid: 'Enter the guardian phone with its country code.',
  guardian_email_invalid: 'Enter a valid guardian email address.',
  guardian_details_incomplete: 'Add both the guardian name and relation before contact details.',
  guardian_required: "Add the guardian's name, relation and phone, then try again.",
  member_not_minor: 'This member is no longer under 18. Reload the page to see their current status.',
  member_not_adult: 'This member has not turned 18 yet. The guardian keeps their sign-in.',
  member_not_guardian_linked: 'This membership is not linked through a guardian account. Reload the page to see its current status.',
  not_permitted: 'Your role cannot make this change.',
  not_signed_in: 'Your session has ended. Sign in again, then try again.',
  invalid_request: 'Check the fields and try again.',
};
/** Never queues an offline mutation or announces eligibility before a server read. */
export function useGuardianCommand(readOnly = false) {
  const router = useRouter();
  const preview = usePreviewReadOnly() || readOnly;
  const [online, setOnline] = useState(true);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const pending = useRef(false);
  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update(); window.addEventListener('online', update); window.addEventListener('offline', update);
    return () => { window.removeEventListener('online', update); window.removeEventListener('offline', update); };
  }, []);
  async function send(path: string, body: unknown, successMessage: string): Promise<boolean> {
    if (preview || pending.current) return false;
    if (!navigator.onLine) { setError('You are offline. Connect to the internet, then try again.'); return false; }
    pending.current = true; setBusy(true); setError(null); setSuccess(null);
    try {
      const response = await fetch(path, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body), cache: 'no-store' });
      const envelope = await response.json() as { ok?: unknown; error?: { code?: unknown } };
      if (!response.ok || envelope.ok !== true) {
        const code = envelope.error?.code;
        setError(typeof code === 'string' && Object.hasOwn(REFUSALS, code) ? REFUSALS[code]! : 'The change could not be saved. Try again.'); return false;
      }
      setSuccess(successMessage); router.refresh(); return true;
    } catch { setError('The change could not be saved. Check your connection and try again.'); return false; }
    finally { pending.current = false; setBusy(false); }
  }
  return { send, online, preview, busy, error, success, disabled: preview || busy || !online };
}
