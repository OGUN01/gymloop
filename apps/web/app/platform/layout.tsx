import type { ReactNode } from 'react';
import { requireAudience } from '../../lib/identity-session';
import { identityHome } from '../../lib/identity';
import { AccountFrame } from '../account-frame';

export default async function PlatformLayout({ children }: { children: ReactNode }) {
  const { identity } = await requireAudience('platform');
  return <AccountFrame home={identityHome(identity)} label={identity.role === 'platform_support' ? 'Support · read only' : 'Platform admin'}>{children}</AccountFrame>;
}
