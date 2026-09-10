import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { AccountFrame } from '../account-frame';

export default async function MemberLayout({ children }: { children: ReactNode }) {
  const { identity } = await requireAudience('member');
  return <AccountFrame home={identityHome(identity)} label="Member">{children}</AccountFrame>;
}
