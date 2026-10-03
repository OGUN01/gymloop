import { planCatalogueCopy, readPlanCatalogue, type PlanCatalogueDb } from '@gymloop/shared';
import Link from 'next/link';
import { requireAudience } from '../../../lib/identity-session';
import { loadBusinessNouns } from '../../../lib/business-type';
import { HeldPlanBlock, PlanList } from './plan-list';
import '../../styles/plans.css';

export default async function MemberPlansPage() {
  const { supabase, identity } = await requireAudience('member');
  const [result, nouns] = await Promise.all([readPlanCatalogue(supabase as unknown as PlanCatalogueDb, identity.memberId), loadBusinessNouns(supabase, identity.tenantId)]);
  const copy = planCatalogueCopy(nouns);
  return <main className="member-route member-portal member-plans">
    <header><Link href="/member/my-gym" className="cl-back">My {nouns.place}</Link><h1 className="member-title">{copy.title}</h1><p className="cl-lede member-lede">{copy.lede}</p></header>
    {result.ok ? <><HeldPlanBlock view={result.view} copy={copy} /><PlanList view={result.view} copy={copy} /></> : <div><p className="cl-alert" role="alert">{copy.error}</p><a href="/member/plans" className="cl-btn cl-btn--quiet">{copy.retry}</a></div>}
  </main>;
}
