import { formatMoney, heldPlanNotice, memberAgreedPrice, planDurationLabel, planGstLabel, type PlanCatalogueCopy, type PlanCatalogueView } from '@gymloop/shared';
import { StatusWord } from '../../status-word';
import { memberShortDate } from '../member-ui';

export function HeldPlanBlock({ view, copy }: { view: PlanCatalogueView; copy: PlanCatalogueCopy }) {
  const held = view.held;
  const discounted = held && /^[1-9][0-9]*$/.test(held.recorded.discountPaise);
  const agreed = held && discounted && memberAgreedPrice(held.recorded.listPricePaise, held.recorded.discountPaise) !== null && held.recorded.agreedPricePaise !== null;
  return <section id="your-plan" className="member-section" aria-labelledby="your-plan-heading">
    <h2 id="your-plan-heading" className="cl-eyebrow member-eyebrow">{held?.past ? copy.heldHeadingPast : copy.heldHeading}</h2>
    {view.heldUnavailable ? <p className="member-quiet">{copy.heldUnavailable}</p> : !held ? <p className="member-quiet">{copy.noMembership}</p> : <>
      <dl className="member-facts">
        {held.planName ? <div><dt>Plan</dt><dd>{held.planName}</dd></div> : null}
        <div><dt>Status</dt><dd><StatusWord status={held.status} /></dd></div>
        {held.endsOn ? <div><dt>Ends</dt><dd>{memberShortDate(held.endsOn)}</dd></div> : null}
        <div><dt>Price when sold</dt><dd className="plan-price-amount">{formatMoney(held.recorded.listPricePaise, held.recorded.currency)}</dd></div>
        {discounted ? <div><dt>Discount</dt><dd className="plan-price-amount">{formatMoney(held.recorded.discountPaise, held.recorded.currency)}</dd></div> : null}
        {agreed && held.recorded.agreedPricePaise !== null ? <div><dt>Agreed price</dt><dd className="plan-price-amount">{formatMoney(held.recorded.agreedPricePaise, held.recorded.currency)}</dd></div> : null}
        <div><dt>Length</dt><dd>{planDurationLabel(held.recorded.durationDays)}</dd></div>
      </dl>
      {heldPlanNotice(held, copy).map((notice) => <p className="member-quiet" key={notice}>{notice}</p>)}
    </>}
  </section>;
}
export function PlanList({ view, copy }: { view: PlanCatalogueView; copy: PlanCatalogueCopy }) {
  return <section id="plans" className="member-section" aria-labelledby="plans-heading">
    <h2 id="plans-heading" className="cl-eyebrow member-eyebrow">{copy.listHeading}</h2>
    {!view.plans.length ? <div className="cl-empty"><strong>{copy.emptyTitle}</strong><p>{copy.emptyBody}</p></div> : <ul className="plan-list" aria-label="Plans on offer">{view.plans.map((plan) => <li key={plan.id} className="plan-entry" data-held={String(plan.held)}>
      <h3 className="cl-row-title">{plan.name}</h3>
      <p className="plan-price"><span className="plan-price-amount">{formatMoney(plan.pricePaise, plan.currency)}</span> <span className="plan-price-unit">for {planDurationLabel(plan.durationDays)}</span></p>
      {plan.held ? <span className="cl-status" data-tone="accent">{view.held?.past ? copy.badgePast : copy.badge}</span> : null}
      {planGstLabel(plan.gstRateBp) ? <p className="plan-gst">{planGstLabel(plan.gstRateBp)}</p> : null}
      {plan.description ? <p className="plan-description">{plan.description}</p> : null}
    </li>)}</ul>}
    {view.truncated ? <p className="member-quiet">{copy.truncated}</p> : null}
    {view.plans.some((plan) => plan.gstRateBp > 0) ? <p className="member-quiet">{copy.gstNote}</p> : null}
    <p className="member-quiet">{copy.deskNote}</p>
  </section>;
}
