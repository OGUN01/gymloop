import { businessNouns, isBusinessType } from '@gymloop/shared';
import { requireAudience } from '../../../lib/identity-session';
import { Alert } from '../alert';
import { BusinessTypeForm } from './business-type-form';
import { loadBusinessOrganization } from '../../../lib/business-type';

export default async function SettingsPage() {
  const { supabase, identity } = await requireAudience('console');
  const preview = identity.kind === 'impersonation';
  const { data, error } = await loadBusinessOrganization(supabase, identity.tenantId);
  const nouns = businessNouns(error ? null : data?.business_type);
  return <main className="cl-page">
    <div className="cl-page-header"><div><p className="cl-eyebrow">Your {nouns.place}</p><h1 className="cl-title">Settings</h1></div></div>
    {!preview && (identity.kind !== 'staff' || identity.role !== 'gym_owner') ? <p>Only the {nouns.place} owner can change settings.</p>
      : error || !data || !isBusinessType(data.business_type) ? <><Alert>Settings could not be loaded. Try again.</Alert><a href="/settings" className="cl-btn">Reload settings</a></>
        : <section className="cl-section"><h2 className="cl-section-title">Business</h2><BusinessTypeForm currentType={data.business_type} businessName={data.name} readOnly={preview} /></section>}
  </main>;
}
