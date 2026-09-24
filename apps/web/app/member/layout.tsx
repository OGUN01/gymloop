import '../styles/member.css';
import '../styles/addons.css';
import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { MemberNavigation } from './member-navigation';

export default async function MemberLayout({ children }: { children: ReactNode }) {
  await requireAudience('member');
  return <div className="member-shell">
    <div className="member-shell-content">{children}</div>
    <MemberNavigation />
  </div>;
}
