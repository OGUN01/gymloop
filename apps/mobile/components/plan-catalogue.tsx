import { formatMoney, heldPlanNotice, memberAgreedPrice, planDurationLabel, planGstLabel, UI_TOKENS, type PlanCatalogueCopy } from '@gymloop/shared';
import { ActivityIndicator, StyleSheet, Text, View } from 'react-native';
import { useMobile } from '../lib/mobile-context';
import { planCatalogueNotice, type PlanCatalogueState } from '../lib/plan-catalogue-state';
import { ActionButton, Body, EmptyState, ErrorRetry, Eyebrow, FONT, StateMessage, Status, dayLabel, statusTone, statusWord } from './ui';

export function PlanCatalogueBody({ state, copy, timeZone, onRetry }: { state: PlanCatalogueState; copy: PlanCatalogueCopy; timeZone: string; onRetry(): void }) {
  const { palette } = useMobile();
  const notice = planCatalogueNotice(state, copy, timeZone);
  const view = state.view;
  const held = view?.held;
  const discounted = held && /^[1-9][0-9]*$/.test(held.recorded.discountPaise);
  const agreed = held && discounted && memberAgreedPrice(held.recorded.listPricePaise, held.recorded.discountPaise) !== null && held.recorded.agreedPricePaise !== null;
  const fact = (label: string, value: string, money = false) => <View key={label} style={[styles.fact, { borderColor: palette.decorativeSeparator }]}><Body muted>{label}</Body><Text style={[money ? styles.amount : styles.value, { color: palette.primaryText }]}>{value}</Text></View>;
  return <View nativeID="plans" style={styles.body}>
    <Body muted>{copy.lede}</Body>
    {state.phase === 'loading' ? <View accessibilityLiveRegion="polite" style={styles.loading}><ActivityIndicator color={palette.secondaryText} /><Body muted>{copy.loading}</Body></View> : null}
    {notice ? notice.tone === 'error' ? <ErrorRetry message={notice.text} onRetry={onRetry} /> : <><StateMessage tone="warning">{notice.text}</StateMessage><ActionButton secondary onPress={onRetry}>{copy.retry}</ActionButton></> : null}
    {view ? <>
      <Eyebrow>{held?.past ? copy.heldHeadingPast : copy.heldHeading}</Eyebrow>
      {view.heldUnavailable ? <Body muted>{copy.heldUnavailable}</Body> : !held ? <Body muted>{copy.noMembership}</Body> : <View>
        {held.planName ? fact('Plan', held.planName) : null}
        <View style={[styles.fact, { borderColor: palette.decorativeSeparator }]}><Body muted>Status</Body><Status tone={statusTone(held.status)}>{statusWord(held.status)}</Status></View>
        {held.endsOn ? fact('Ends', dayLabel(held.endsOn, timeZone)) : null}
        {fact('Price when sold', formatMoney(held.recorded.listPricePaise, held.recorded.currency), true)}
        {discounted ? fact('Discount', formatMoney(held.recorded.discountPaise, held.recorded.currency), true) : null}
        {agreed && held.recorded.agreedPricePaise !== null ? fact('Agreed price', formatMoney(held.recorded.agreedPricePaise, held.recorded.currency), true) : null}
        {fact('Length', planDurationLabel(held.recorded.durationDays))}
        {heldPlanNotice(held, copy).map((text) => <Body muted key={text}>{text}</Body>)}
      </View>}
      <Eyebrow>{copy.listHeading}</Eyebrow>
      {!view.plans.length ? <EmptyState title={copy.emptyTitle}>{copy.emptyBody}</EmptyState> : view.plans.map((plan) => {
        const price = formatMoney(plan.pricePaise, plan.currency);
        const length = planDurationLabel(plan.durationDays);
        const gst = planGstLabel(plan.gstRateBp);
        const badge = plan.held ? held?.past ? copy.badgePast : copy.badge : null;
        return <View key={plan.id} accessible accessibilityLabel={`${plan.name}, ${price} for ${length}${badge ? `, ${badge}` : ''}${gst ? `, ${gst}` : ''}${plan.description ? `, ${plan.description}` : ''}`} style={[styles.entry, { borderColor: palette.decorativeSeparator }]}>
          <Body strong>{plan.name}</Body>
          <Text style={[styles.amount, { color: palette.primaryText }]}>{price}<Text style={styles.unit}> for {length}</Text></Text>
          {badge ? <Status tone="accent">{badge}</Status> : null}
          {gst ? <Body muted>{gst}</Body> : null}
          {plan.description ? <Body>{plan.description}</Body> : null}
        </View>;
      })}
      {view.truncated ? <Body muted>{copy.truncated}</Body> : null}
      {view.plans.some((plan) => plan.gstRateBp > 0) ? <Body muted>{copy.gstNote}</Body> : null}
      <Body muted>{copy.deskNote}</Body>
    </> : null}
  </View>;
}
const space = UI_TOKENS.geometry.spacing;
const styles = StyleSheet.create({
  body: { gap: space[2] }, loading: { flexDirection: 'row', gap: space[1], alignItems: 'center' },
  fact: { paddingVertical: space[2], gap: space[1], borderBottomWidth: StyleSheet.hairlineWidth },
  entry: { paddingVertical: space[3], gap: space[1], borderTopWidth: StyleSheet.hairlineWidth },
  amount: { fontFamily: FONT.displayBold, fontSize: UI_TOKENS.typography.mobileSection.size, lineHeight: UI_TOKENS.typography.mobileSection.lineHeight, fontVariant: ['tabular-nums'] },
  value: { fontFamily: FONT.medium, fontSize: UI_TOKENS.typography.mobileBody.size, lineHeight: UI_TOKENS.typography.mobileBody.lineHeight },
  unit: { fontFamily: FONT.regular, fontSize: UI_TOKENS.typography.mobileBody.size },
});
