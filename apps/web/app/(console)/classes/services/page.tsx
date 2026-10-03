import Link from 'next/link';
import { notFound } from 'next/navigation';
import { humanize } from '@gymloop/shared';
import { requireAudience } from '../../../../lib/identity-session';
import { loadBusinessNouns } from '../../../../lib/business-type';
import { loadServices } from '../../../../lib/classes';
import { ServiceEditor } from '../class-forms';
import '../../../styles/classes.css';
export default async function ServicesPage() { const { supabase, identity } = await requireAudience('console'); if (identity.kind !== 'staff' || !['gym_owner', 'gym_manager'].includes(identity.role)) notFound(); const [services, nouns] = await Promise.all([loadServices(supabase), loadBusinessNouns(supabase, identity.tenantId)]); if (services === null) throw new Error('Services could not be loaded.'); return <main className="cl-page classes-workspace"><Link className="cl-back" href="/classes">Back to {nouns.classes}</Link><h1 className="cl-title">{humanize(nouns.classes)} catalogue</h1>{services.length === 0 ? <p className="cl-empty">No {nouns.classes} yet. Add the first activity your {nouns.place} runs.</p> : null}<ServiceEditor nouns={nouns} />{services.map((service) => <ServiceEditor key={service.id} service={service} nouns={nouns} />)}</main>; }
