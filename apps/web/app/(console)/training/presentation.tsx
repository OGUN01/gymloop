import { createHash } from 'node:crypto';
import Link from 'next/link';
import { notFound } from 'next/navigation';
import type { GymloopIdentity } from '@gymloop/shared';
import type { VerifiedConsoleViewer, ConsoleViewer } from '../../../lib/training-console';
import '../../styles/classes.css';

export function consoleCaller(identity: GymloopIdentity): VerifiedConsoleViewer {
  if (identity.kind !== 'impersonation' && (identity.kind !== 'staff' || !['gym_owner', 'gym_manager', 'front_desk', 'trainer'].includes(identity.role))) notFound();
  const viewer: ConsoleViewer = identity.kind === 'impersonation'
    ? { role: null, staffId: null, readOnly: true, scopeKey: createHash('sha256').update(JSON.stringify(identity)).digest('hex') }
    : { role: identity.role, staffId: identity.staffId, readOnly: false, scopeKey: createHash('sha256').update(JSON.stringify(identity)).digest('hex') };
  return { identity, viewer };
}
export function TrainingNavigation({ viewer }: { viewer: ConsoleViewer }) {
  return <nav className="cl-actions" aria-label="Training"><Link className="cl-btn" href="/training">Bookings</Link><Link className="cl-btn" href="/training/packs">Packs</Link><Link className="cl-btn" href="/training/trainers">Trainers</Link>{viewer.readOnly || viewer.role === 'gym_owner' || viewer.role === 'gym_manager' ? <Link className="cl-btn" href="/training/policy">Policy</Link> : null}</nav>;
}
export function ReadFailure({ href }: { href: string }) {
  return <div className="cl-alert" role="alert"><p>Please try again.</p><Link className="cl-btn" href={href}>Retry</Link></div>;
}
