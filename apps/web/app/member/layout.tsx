import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { AccountFrame } from '../account-frame';

export default async function MemberLayout({ children }: { children: ReactNode }) {
  const { identity } = await requireAudience('member');
  return <AccountFrame home={identityHome(identity)} label="Member">
    <div className="member-shell">
      <div className="member-shell-content">{children}</div>
      <nav className="member-tab-bar" aria-label="Member navigation">
        <a href="/member/add-ons" aria-label="Home">Home</a>
        <a href="/member/messages" aria-label="Activity">Activity</a>
        <a href="/member/add-ons" aria-current="page">My gym</a>
        <a href="/member/messages" aria-label="You">You</a>
      </nav>
    </div>
  </AccountFrame>;
}
