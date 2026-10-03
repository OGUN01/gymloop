import '../styles/announcements.css';
import { businessNouns } from '@gymloop/shared';
import { loadBusinessType } from '../../lib/business-type';
import '../styles/member.css';
import '../styles/addons.css';
import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { MemberNavigation } from './member-navigation';

export default async function MemberLayout({ children }: { children: ReactNode }) {
  const { supabase, identity } = await requireAudience('member');
  const type = await loadBusinessType(supabase, identity.tenantId);
  const nouns = businessNouns(type);
  return <div className="member-shell">
    <div className="member-shell-content">{children}</div>
    <MemberNavigation nouns={nouns} placeLabel={`My ${nouns.place}`} placeGlyph={type === 'gym' ? 'gym' : 'building'} />
  </div>;
}
