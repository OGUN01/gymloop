import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { gymTimeLabel } from '../../lib/time';
import { AccountFrame } from '../account-frame';
import { PreviewProvider } from '../preview-context';

export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const { supabase, identity } = await requireAudience('console');
  const preview = identity.kind === 'impersonation';
  let banner: ReactNode = null;
  if (preview) {
    const [gym, session] = await Promise.all([
      supabase.from('organizations').select('name,timezone').eq('id', identity.tenantId).maybeSingle(),
      supabase.from('impersonation_sessions').select('expires_at')
        .eq('id', identity.impersonationSessionId).eq('actor_user_id', identity.userId).maybeSingle(),
    ]);
    banner = <aside className="sticky top-0 z-50 flex flex-wrap items-center justify-between gap-3 bg-red-700 px-6 py-4 text-white" aria-label="Read-only support preview">
      <div><p className="font-semibold">Read-only preview · {gym.data?.name ?? 'Gym details unavailable'}</p>
        <p className="mt-1 text-sm">{session.data && gym.data ? `Expires ${gymTimeLabel(session.data.expires_at, gym.data.timezone)}` : 'Preview expiry could not be loaded.'}</p></div>
      <form method="post" action="/api/impersonation/end"><button type="submit" className="rounded-md border border-white px-4 py-2 font-medium">End preview</button></form>
    </aside>;
  }
  return <AccountFrame home={identityHome(identity)} label={preview ? 'Support preview' : identity.role.replaceAll('_', ' ')}>
    {banner}
    <PreviewProvider readOnly={preview}>{children}</PreviewProvider>
  </AccountFrame>;
}
