import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { AccountFrame } from '../account-frame';
import { MemberNavigation } from './member-navigation';

export default async function MemberLayout({ children }: { children: ReactNode }) {
  const { identity } = await requireAudience('member');
  return <AccountFrame home={identityHome(identity)} label="Member">
    <div className="member-shell">
      <div className="member-shell-content">{children}</div>
      <MemberNavigation />
    </div>
  </AccountFrame>;
}
