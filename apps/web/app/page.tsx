import { redirect } from 'next/navigation';
import { identityHome } from '../lib/identity';
import { readIdentity } from '../lib/identity-session';

export default async function Page() {
  const session = await readIdentity();
  redirect(session.signedIn ? identityHome(session.identity) : '/sign-in');
}
