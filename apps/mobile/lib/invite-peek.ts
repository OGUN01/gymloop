import { useEffect, useState } from 'react';
import * as Crypto from 'expo-crypto';
import { INVITE_TOKEN_PATTERN } from '@gymloop/shared';
import { useMobile } from './mobile-context';

/** Native gym-only preview. The temporary RPC bridge awaits CI-generated database types. */
export function useNativeInvitePeek(token: string | null) {
  const { supabase } = useMobile();
  const [preview, setPreview] = useState<{ token: string | null; gymName: string | null; failed: boolean }>({ token: null, gymName: null, failed: false });
  const [attempt, setAttempt] = useState(0);
  useEffect(() => {
    let current = true;
    if (token === null || !INVITE_TOKEN_PATTERN.test(token)) return;
    void (async () => {
      try {
        const hash = await Crypto.digestStringAsync(Crypto.CryptoDigestAlgorithm.SHA256, token);
        const rpc = supabase.rpc as unknown as (name: 'peek_member_invite', args: { p_token_hash: string }) => Promise<{ data: unknown; error: unknown }>;
        const result = await rpc.call(supabase, 'peek_member_invite', { p_token_hash: hash });
        if (result.error) throw new Error('Invite preview failed');
        const rows = result.data;
        const row: unknown = Array.isArray(rows) && rows.length === 1 ? rows[0] : null;
        const gymName = row !== null && typeof row === 'object' && 'gym_name' in row && typeof row.gym_name === 'string' && row.gym_name.trim() !== '' ? row.gym_name : null;
        if (current) setPreview({ token, gymName, failed: false });
      } catch {
        if (current) setPreview({ token, gymName: null, failed: true });
      }
    })();
    return () => { current = false; };
  }, [attempt, supabase, token]);
  return {
    gymName: preview.token === token ? preview.gymName : null,
    failed: preview.token === token && preview.failed,
    loading: token !== null && preview.token !== token,
    retry: () => { setPreview({ token: null, gymName: null, failed: false }); setAttempt((previous) => previous + 1); },
  };
}
