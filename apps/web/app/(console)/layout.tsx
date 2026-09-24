import '../styles/desk.css';
import '../styles/money.css';
import '../styles/leads.css';
import '../styles/addons.css';
import '../styles/comms.css';
import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { gymTimeLabel } from '../../lib/time';
import { FRONT_OFFICE_ROLES } from '../../lib/leads';
import { canImportMembers } from '../../lib/member-imports';
import { canViewMessages } from '../../lib/messages';
import { AccountFrame } from '../account-frame';
import { ConsoleNavigation } from '../console-navigation';
import { PreviewProvider } from '../preview-context';

export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const { supabase, identity } = await requireAudience('console');
  const preview = identity.kind === 'impersonation';
  const [gym, session] = await Promise.all([
    supabase.from('organizations').select('name,gym_code,timezone').eq('id', identity.tenantId).maybeSingle(),
    preview
      ? supabase.from('impersonation_sessions').select('expires_at')
        .eq('id', identity.impersonationSessionId).eq('actor_user_id', identity.userId).maybeSingle()
      : Promise.resolve(null),
  ]);
  const frontOffice = identity.kind === 'staff' && (FRONT_OFFICE_ROLES as readonly string[]).includes(identity.role);
  const items = preview
    ? [
      { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
      { href: '/console', label: 'Members' }, { href: '/payments', label: 'Payments' },
      { href: '/messages', label: 'Messages' }, { href: '/add-ons', label: 'Add-ons' },
    ]
    : identity.kind === 'staff' && identity.role === 'trainer'
      ? [
        { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
        { href: '/console', label: 'Members' }, { href: '/add-ons', label: 'Add-ons' },
      ]
      : [
        ...(identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager')
          ? [{ href: '/dashboard', label: 'Overview' }] : []),
        { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
        { href: '/console', label: 'Members' },
        ...(frontOffice ? [{ href: '/memberships', label: 'Memberships' }] : []),
        ...(identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager')
          ? [{ href: '/payments', label: 'Payments' }] : []),
        ...(canViewMessages(identity) ? [{ href: '/messages', label: 'Messages' }] : []),
        { href: '/add-ons', label: 'Add-ons' },
        ...(frontOffice ? [{ href: '/leads', label: 'Leads' }] : []),
        ...(canImportMembers(identity) ? [{ href: '/imports', label: 'Imports' }] : []),
      ];
  const banner: ReactNode = preview ? (
    <aside className="preview-banner" aria-label="Read-only support preview">
      <div><p><strong>Read-only preview</strong> · {gym.data?.name ?? 'Gym details unavailable'}</p>
        <p>{session?.data && gym.data ? `Expires ${gymTimeLabel(session.data.expires_at, gym.data.timezone)}` : 'Preview expiry could not be loaded.'}</p></div>
      <form method="post" action="/api/impersonation/end"><button type="submit" className="cl-btn cl-btn--small">End preview</button></form>
    </aside>
  ) : null;

  return <AccountFrame home={identityHome(identity)} label={preview ? 'Support preview' : identity.role.replaceAll('_', ' ')}
    navigation={<ConsoleNavigation items={items} />}
    context={{ primary: gym.data?.name ?? 'Gym details unavailable', secondary: gym.data?.gym_code === null || gym.data?.gym_code === undefined ? 'Gym code unavailable' : `Gym code · ${gym.data.gym_code}` }}>
    {banner}
    <PreviewProvider readOnly={preview}>{children}</PreviewProvider>
  </AccountFrame>;
}
