import '../styles/announcements.css';
import { businessNouns, businessRoleLabel, humanize } from '@gymloop/shared';
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
import { loadBusinessOrganization } from '../../lib/business-type';

export default async function ConsoleLayout({ children }: { children: ReactNode }) {
  const { supabase, identity } = await requireAudience('console');
  const preview = identity.kind === 'impersonation';
  const [gym, session] = await Promise.all([
    loadBusinessOrganization(supabase, identity.tenantId),
    preview
      ? supabase.from('impersonation_sessions').select('expires_at')
        .eq('id', identity.impersonationSessionId).eq('actor_user_id', identity.userId).maybeSingle()
      : Promise.resolve(null),
  ]);
  const nouns = businessNouns(gym.error ? null : gym.data?.business_type);
  const frontOffice = identity.kind === 'staff' && (FRONT_OFFICE_ROLES as readonly string[]).includes(identity.role);
  const items = preview
    ? [
      { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
      { href: '/console', label: humanize(nouns.members) }, { href: '/payments', label: 'Payments' },
      { href: '/messages', label: 'Messages' }, { href: '/add-ons', label: 'Add-ons' },
    ]
    : identity.kind === 'staff' && identity.role === 'trainer'
      ? [
        { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
        { href: '/console', label: humanize(nouns.members) }, { href: '/add-ons', label: 'Add-ons' },
      ]
      : [
        ...(identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager')
          ? [{ href: '/dashboard', label: 'Overview' }] : []),
        { href: '/console/check-in', label: 'Check-in' }, { href: '/red-list', label: 'Follow-ups' },
        { href: '/console', label: humanize(nouns.members) },
        ...(frontOffice ? [{ href: '/memberships', label: 'Memberships' }] : []),
        ...(identity.kind === 'staff' && (identity.role === 'gym_owner' || identity.role === 'gym_manager')
          ? [{ href: '/payments', label: 'Payments' }] : []),
        ...(canViewMessages(identity) ? [{ href: '/messages', label: 'Messages' }] : []),
        { href: '/add-ons', label: 'Add-ons' },
        ...(frontOffice ? [{ href: '/leads', label: 'Leads' }] : []),
        ...(identity.kind === 'staff' && identity.role === 'gym_owner' ? [{ href: '/team', label: 'Team' }] : []),
        ...(canImportMembers(identity) ? [{ href: '/imports', label: 'Imports' }] : []),
        ...(identity.kind === 'staff' && identity.role === 'gym_owner' ? [{ href: '/settings', label: 'Settings' }] : []),
      ];
  const banner: ReactNode = preview ? (
    <aside className="preview-banner" aria-label="Read-only support preview">
      <div><p><strong>Read-only preview</strong> · {gym.data?.name ?? `${humanize(nouns.place)} details unavailable`}</p>
        <p>{session?.data && gym.data ? `Expires ${gymTimeLabel(session.data.expires_at, gym.data.timezone)}` : 'Preview expiry could not be loaded.'}</p></div>
      <form method="post" action="/api/impersonation/end"><button type="submit" className="cl-btn cl-btn--small">End preview</button></form>
    </aside>
  ) : null;

  return <AccountFrame home={identityHome(identity)} label={preview ? 'Support preview' : businessRoleLabel(identity.role, nouns)}
    navigation={<ConsoleNavigation items={[...items, { href: '/training', label: 'Training' }]} />}
    context={{ primary: gym.data?.name ?? `${humanize(nouns.place)} details unavailable`, secondary: gym.data?.gym_code === null || gym.data?.gym_code === undefined ? `${humanize(nouns.place)} code unavailable` : `${humanize(nouns.place)} code · ${gym.data.gym_code}` }}>
    {banner}
    <PreviewProvider readOnly={preview}>{children}</PreviewProvider>
  </AccountFrame>;
}
