import { useEffect, useRef, useState } from 'react';
import { Image, StyleSheet, View, type ScrollView } from 'react-native';
import { Package } from 'lucide-react-native';
import { useRouter } from 'expo-router';
import * as Network from 'expo-network';
import { DEFAULT_TIMEZONE, MS_PER_HOUR, SHOP_LIMITS, SHOP_TERMS_CHANGED_NOTE, UI_TOKENS, formatMoney, groupShopItems, planCatalogueCopy, planDurationLabel, planGstLabel, shopGstLabel, shopMaxQuantity, shopOfflineNotice, shopReservationStateWord, shopReserveNotice, shopReserveRequestSchema, type ShopItem, type ShopReservation } from '@gymloop/shared';
import { ActionButton, Body, Display, EmptyState, Eyebrow, LoadingState, Row, RowAction, Screen, Sheet, SheetHeader, StateMessage, Status } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberSnapshot } from '../../lib/use-member-snapshot';
import { heldUntilLabel, reserveOutcomeMessage, shopCacheScope } from '../../lib/shop';
import { nativeShopCache, shopCacheCurrent } from '../../lib/shop-cache';
import { useMemberShopPages } from '../../lib/use-member-shop-pages';
import { useMemberPlans } from '../../lib/use-member-plans';
import { planCatalogueNotice } from '../../lib/plan-catalogue-state';

function ShopPhoto({ url, large = false }: { url: string | null; large?: boolean }) {
  const { palette } = useMobile();
  const [failed, setFailed] = useState<string | null>(null);
  let safe = false;
  try { const parsed = new URL(url ?? ''); safe = parsed.protocol === 'https:' && !parsed.username && !parsed.password; } catch { /* Invalid URLs use the same placeholder as a missing photo. */ }
  return <View accessibilityElementsHidden importantForAccessibility="no-hide-descendants" style={[styles.photo, large && styles.largePhoto, { backgroundColor: palette.elevatedSurface }]}>
    {url && safe && failed !== url ? <Image accessible={false} source={{ uri: url }} style={[styles.photo, large && styles.largePhoto]} resizeMode="cover" onError={() => setFailed(url)} /> : <Package size={UI_TOKENS.icons.navigationSize} color={palette.secondaryText} />}
  </View>;
}

export default function ShopScreen() {
  const { identity, api, nouns, palette } = useMobile();
  const router = useRouter();
  const snapshot = useMemberSnapshot();
  const timeZone = snapshot.data?.gym.timezone ?? DEFAULT_TIMEZONE;
  const scope = shopCacheScope(identity);
  const plans = useMemberPlans(scope !== null);
  const plansCopy = planCatalogueCopy(nouns);
  const planNotice = planCatalogueNotice(plans.state, plansCopy, timeZone);
  const network = Network.useNetworkState();
  const online = network.isConnected === true && network.isInternetReachable !== false;
  const { view, loading, loadingMore, error, visibleCount, hasMore, reload, loadMore } = useMemberShopPages();
  const [message, setMessage] = useState<string | null>(null);
  const [selection, setSelection] = useState<{ owner: object; scope: string; item: ShopItem; quantity: number; confirm: boolean; heldUntil: string } | null>(null);
  const [cancellation, setCancellation] = useState<{ owner: object; scope: string; reservation: ShopReservation } | null>(null);
  const [busy, setBusy] = useState(false);
  const currentScope = useRef(scope);
  const command = useRef<object | null>(null);
  const scrollRef = useRef<ScrollView | null>(null);
  const sectionPositions = useRef<{ products?: number; plans?: number; services?: number }>({});
  const visible = view?.scope === scope ? view : null;
  const available = visible !== null;
  const interaction = useRef({ scope, api, available });
  const currentView = useRef(visible);
  currentView.current = visible;
  if (interaction.current.scope !== scope || interaction.current.api !== api || interaction.current.available !== available) {
    interaction.current = { scope, api, available }; currentScope.current = scope; command.current = null;
  }
  const owner = interaction.current;
  const selected = available && selection?.owner === owner && selection.scope === scope ? selection : null;
  const cancel = available && cancellation?.owner === owner && cancellation.scope === scope ? cancellation : null;
  const disabled = !available || !online || !!visible?.stale || busy || scope === null;

  useEffect(() => {
    setSelection(null); setCancellation(null); setMessage(null); setBusy(false);
    return () => { command.current = null; };
  }, [scope, api, available]);

  const close = () => { if (command.current === null) { setSelection(null); setCancellation(null); } };
  const openItem = (item: ShopItem) => {
    if (scope === null || interaction.current !== owner || !owner.available || currentScope.current !== scope || command.current !== null) return;
    setMessage(null);
    const heldUntil = new Date(Date.now() + SHOP_LIMITS.reservationTtlHours * MS_PER_HOUR).toISOString();
    setSelection({ owner, scope, item, quantity: 1, confirm: false, heldUntil });
  };
  const mutate = async () => {
    if (scope === null || interaction.current !== owner || !owner.available || !currentView.current || currentView.current.stale || currentScope.current !== scope || command.current !== null || (!selected && !cancel)) return;
    const request = {};
    command.current = request;
    setBusy(true);
    const cacheCurrent = shopCacheCurrent(nativeShopCache);
    const current = () => interaction.current === owner && owner.available && currentScope.current === scope && command.current === request && cacheCurrent();
    try {
      const state = await Network.getNetworkStateAsync();
      if (!current()) return;
      if (state.isConnected !== true || state.isInternetReachable === false || !currentView.current || currentView.current.stale) {
        setMessage('Reserving and cancelling need a connection. Check your connection and try again.');
        return;
      }
      const result = selected
        ? await api.post<{ reservationId: string; expiresAt: string }>('/api/shop/reservations', shopReserveRequestSchema.parse({ itemId: selected.item.itemId, quantity: selected.quantity, quoteVersion: selected.item.quoteVersion }))
        : await api.post<{ cancelled: true }>(`/api/shop/reservations/${cancel!.reservation.reservationId}/cancel`, {});
      if (!current()) return;
      if (result.ok) {
        const data: unknown = result.data;
        const valid = typeof data === 'object' && data !== null && (selected
          ? 'reservationId' in data && typeof data.reservationId === 'string' && 'expiresAt' in data && typeof data.expiresAt === 'string' && Number.isFinite(Date.parse(data.expiresAt))
          : 'cancelled' in data && data.cancelled === true);
        if (!valid) throw new Error('invalid response');
        setMessage(selected ? `Reserved until ${heldUntilLabel((data as { expiresAt: string }).expiresAt, timeZone)}. Pay and collect at the front desk.` : 'Reservation cancelled.');
        setSelection(null); setCancellation(null);
      } else {
        setMessage(reserveOutcomeMessage(result.error.code));
        setSelection(null); setCancellation(null);
      }
      await reload();
    } catch {
      if (current()) { setMessage(reserveOutcomeMessage('network_failed')); await reload(); }
    } finally { if (currentScope.current === scope && command.current === request) { command.current = null; setBusy(false); } }
  };

  const renderItem = (item: ShopItem) => item.section === 'services' ? <View key={item.itemId} style={[styles.itemCard, styles.supportingRow, { borderColor: palette.decorativeSeparator }]}>
    <View style={styles.serviceHeading}><ShopPhoto url={item.imageUrl} /><View style={styles.supportingCopy}><Body strong>{item.name}</Body></View></View>
    <Display size="section" accent>{formatMoney(item.pricePaise, item.currency)}</Display>
    <Status tone={item.availability === 'available' ? 'ok' : 'neutral'}>{item.availability === 'available' ? 'Available' : 'Out of stock'}</Status>
    <RowAction quiet accessibilityLabel={`View service ${item.name}`} disabled={busy || scope === null} onPress={() => openItem(item)}>View service</RowAction>
  </View> : <View key={item.itemId} style={[styles.itemCard, { borderColor: palette.decorativeSeparator }]}>
    <Row icon={<ShopPhoto url={item.imageUrl} large={item.section === 'products'} />} title={item.name} meta={item.description || undefined} status={<Status tone={item.availability === 'available' ? 'ok' : 'neutral'}>{item.availability === 'available' ? 'Available' : 'Out of stock'}</Status>} onPress={() => openItem(item)} accessibilityLabel={`${item.name}, ${formatMoney(item.pricePaise, item.currency)}, ${item.availability === 'available' ? 'Available' : 'Out of stock'}`} />
    <View style={styles.priceAction}><Display size="section" accent>{formatMoney(item.pricePaise, item.currency)}</Display><ActionButton secondary accessibilityLabel={`Reserve ${item.name}`} disabled={disabled || shopMaxQuantity(item) === 0} onPress={() => openItem(item)}>{item.section === 'products' ? 'Reserve' : 'View service'}</ActionButton></View>
  </View>;
  const groups = groupShopItems(visible?.response.items ?? []);
  const reservations = visible?.response.reservations ?? [];
  const orderedReservations = [...reservations.filter(row => row.state === 'reserved'), ...reservations.filter(row => row.state !== 'reserved')];
  const shownReservations = orderedReservations.slice(0, visibleCount);
  const hiddenActive = orderedReservations.slice(visibleCount).filter(row => row.state === 'reserved').length;
  return <Screen scrollRef={scrollRef}>
    <View style={styles.shopHeader}>
      <View style={styles.heading}>
        <Eyebrow>{snapshot.data?.gym.displayName ?? `Your ${nouns.place}`}</Eyebrow>
        <View style={styles.headingRow}><View accessible accessibilityRole="header" accessibilityLabel="Shop" style={styles.headingTitle}><Display size="heading">Shop</Display></View><RowAction quiet accessibilityLabel="Refresh shop" disabled={loading || busy} onPress={() => { setMessage(null); void reload(); }}>Refresh shop</RowAction></View>
        <Body muted>Reserve now. Pay at the front desk.</Body>
      </View>
      <View style={styles.sectionLinks}>
        <RowAction quiet onPress={() => { const y = sectionPositions.current.products; if (y !== undefined) scrollRef.current?.scrollTo({ y, animated: true }); }}>Products</RowAction>
        <RowAction quiet onPress={() => { const y = sectionPositions.current.plans; if (y !== undefined) scrollRef.current?.scrollTo({ y, animated: true }); }}>Plans</RowAction>
        <RowAction quiet onPress={() => { const y = sectionPositions.current.services; if (y !== undefined) scrollRef.current?.scrollTo({ y, animated: true }); }}>Services</RowAction>
      </View>
    </View>
    {visible && (!online || visible.stale) ? <StateMessage tone="warning">{online ? `Showing the shop saved ${heldUntilLabel(visible.savedAt, timeZone)}. Refresh before reserving or cancelling.` : shopOfflineNotice(heldUntilLabel(visible.savedAt, timeZone))}</StateMessage> : null}
    {message ? <StateMessage>{message}</StateMessage> : null}
    {error ? <StateMessage tone="warning">{error}</StateMessage> : null}
    {loading && !visible ? <LoadingState /> : null}
    <View style={styles.catalogueSection} onLayout={({ nativeEvent }) => { sectionPositions.current.products = nativeEvent.layout.y; }}><Eyebrow>Products</Eyebrow>{groups.products.map((group, index) => <View style={styles.productGroup} key={`${group.categoryId ?? 'uncategorised'}:${index}`}><Body strong>{group.categoryName ?? 'Other products'}</Body>{group.items.map(renderItem)}</View>)}{visible && !groups.products.length ? <Body muted>No products listed yet.</Body> : null}</View>
    <View style={styles.catalogueSection} onLayout={({ nativeEvent }) => { sectionPositions.current.plans = nativeEvent.layout.y; }}><Eyebrow>Plans</Eyebrow>
      {plans.state.phase === 'loading' && !plans.state.view ? <LoadingState /> : null}
      {planNotice ? <StateMessage tone={planNotice.tone}>{planNotice.text}</StateMessage> : null}
      {plans.state.view?.plans.map(plan => <View key={plan.id} style={[styles.itemCard, { borderColor: palette.decorativeSeparator }]}><View style={styles.supportingRow}><View style={styles.supportingCopy}><Body strong>{plan.name}</Body></View><Display size="section" accent>{formatMoney(plan.pricePaise, plan.currency)}</Display></View><View style={styles.supportingRow}><Body muted>{planDurationLabel(plan.durationDays)}</Body>{plan.held ? <Status tone="accent">{plansCopy.badge}</Status> : null}{planGstLabel(plan.gstRateBp) ? <Body muted>{planGstLabel(plan.gstRateBp)}</Body> : null}</View>{plan.description ? <Body>{plan.description}</Body> : null}</View>)}
      {plans.state.view && !plans.state.view.plans.length ? <Body muted>No plans listed yet.</Body> : null}
      <RowAction quiet onPress={() => router.push({ pathname: '/(member)/gym', params: { section: 'plans' } })}>View plans</RowAction>
      {planNotice ? <ActionButton secondary onPress={() => void plans.reload()}>Refresh plans</ActionButton> : null}
    </View>
    <View style={styles.catalogueSection} onLayout={({ nativeEvent }) => { sectionPositions.current.services = nativeEvent.layout.y; }}><Eyebrow>Services</Eyebrow>{groups.services.map(renderItem)}{visible && !groups.services.length ? <Body muted>No services listed yet.</Body> : null}</View>
    {visible && !visible.response.items.length ? <EmptyState title={`Your ${nouns.place} hasn't added anything to the shop yet.`}>Ask the front desk about available products and services.</EmptyState> : null}
    {visible?.response.truncated ? <StateMessage>Showing the first {SHOP_LIMITS.catalogueMax} items.</StateMessage> : null}
    <View><Row title="Purchase requests" meta="View your requests and payment confirmations" onPress={() => router.push('/(member)/buy')} accessibilityHint="Opens Buy" /><ActionButton secondary onPress={() => router.push('/(member)/buy')}>Buy</ActionButton></View>
    {orderedReservations.length ? <View style={styles.catalogueSection}><Eyebrow>Your reservations</Eyebrow>{hiddenActive > 0 ? <StateMessage>{hiddenActive} more active reservations. Load more to see their holds and cancellation actions.</StateMessage> : null}{shownReservations.map(reservation => <View key={reservation.reservationId}>
      <Row icon={<ShopPhoto url={reservation.imageUrl} />} title={reservation.itemName} meta={`${reservation.quantity} × ${formatMoney(reservation.unitPricePaise, reservation.currency)} = ${formatMoney(reservation.totalPaise, reservation.currency)}`} status={<Status tone={reservation.state === 'reserved' ? 'ok' : 'neutral'}>{shopReservationStateWord(reservation.state)}</Status>} />
      <Body muted>{reservation.state === 'reserved' ? 'Held until' : 'Hold ended'} {heldUntilLabel(reservation.expiresAt, timeZone)}</Body>
      {reservation.termsChanged ? <StateMessage tone="warning">{SHOP_TERMS_CHANGED_NOTE}</StateMessage> : null}
      {reservation.cancelReason ? <Body>Reason from your {nouns.place}: {reservation.cancelReason}</Body> : null}
      {reservation.state === 'reserved' ? <ActionButton secondary disabled={disabled} onPress={() => { if (interaction.current !== owner || !owner.available || currentScope.current !== scope || command.current) return; if (disabled) { setMessage('Cancelling needs a connection. Check your connection and try again.'); return; } if (scope) { setMessage(null); setCancellation({ owner, scope, reservation }); } }}>Cancel reservation</ActionButton> : null}
    </View>)}{hasMore ? <ActionButton secondary disabled={loadingMore || loading} onPress={() => { void loadMore(); }}>{loadingMore ? 'Loading…' : 'Load more'}</ActionButton> : null}</View> : null}
    <Sheet visible={selected !== null} onClose={close}>
      {selected ? <>
        <SheetHeader title={selected.confirm ? 'Confirm reservation' : selected.item.name} control="Cancel" onControl={close} controlDisabled={busy} />
        <ShopPhoto url={selected.item.imageUrl} /><Body strong>{selected.item.name}</Body><Body>{selected.item.description}</Body>
        <Display size="section" accent>{formatMoney(selected.item.pricePaise, selected.item.currency)}</Display>
        <Status tone={selected.item.availability === 'available' ? 'ok' : 'neutral'}>{selected.item.availability === 'available' ? 'Available' : 'Out of stock'}</Status>
        {shopGstLabel(selected.item.gstRateBp, nouns.place) ? <Body muted>{shopGstLabel(selected.item.gstRateBp, nouns.place)}</Body> : null}
        <Body muted>Validity: {selected.item.validityDays} days. {selected.item.cancellationTerms}</Body>
        <Body>Quantity: {selected.quantity}</Body>
        {!selected.confirm && selected.item.section === 'products' ? <View style={styles.quantity}>
          <ActionButton secondary accessibilityLabel="Decrease quantity" disabled={disabled || selected.quantity <= 1} onPress={() => setSelection({ ...selected, quantity: Math.max(1, selected.quantity - 1) })}>−</ActionButton>
          <ActionButton secondary accessibilityLabel="Increase quantity" disabled={disabled || selected.quantity >= shopMaxQuantity(selected.item)} onPress={() => setSelection({ ...selected, quantity: Math.min(shopMaxQuantity(selected.item), selected.quantity + 1) })}>+</ActionButton>
        </View> : null}
        <Body strong>Total: {formatMoney((BigInt(selected.item.pricePaise) * BigInt(selected.quantity)).toString(), selected.item.currency)}</Body>
        {selected.confirm ? <Body>{shopReserveNotice({ place: nouns.place, heldUntil: heldUntilLabel(selected.heldUntil, timeZone) })}</Body> : null}
        {message ? <StateMessage>{message}</StateMessage> : null}
        <ActionButton disabled={disabled || shopMaxQuantity(selected.item) === 0} onPress={() => { if (interaction.current !== owner || !owner.available || currentScope.current !== scope || command.current) return; if (disabled) { setMessage('Reserving needs a connection. Check your connection and try again.'); return; } if (selected.confirm) void mutate(); else setSelection({ ...selected, confirm: true }); }}>{busy ? 'Reserving…' : selected.confirm ? 'Confirm reservation' : 'Reserve'}</ActionButton>
      </> : null}
    </Sheet>
    <Sheet visible={cancel !== null} onClose={close}>{cancel ? <>
      <SheetHeader title="Cancel reservation?" control="Cancel" onControl={close} controlDisabled={busy} />
      <Body>{cancel.reservation.itemName}</Body><Body>This releases your reservation. Nothing has been charged in the app.</Body>
      {message ? <StateMessage>{message}</StateMessage> : null}
      <ActionButton disabled={disabled} onPress={() => { void mutate(); }}>{busy ? 'Cancelling…' : 'Cancel reservation'}</ActionButton>
    </> : null}</Sheet>
  </Screen>;
}

const styles = StyleSheet.create({
  shopHeader: { gap: UI_TOKENS.geometry.spacing[3] },
  heading: { gap: UI_TOKENS.geometry.spacing[1] },
  headingRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[2] },
  headingTitle: { flexGrow: 1 },
  sectionLinks: { flexDirection: 'row', flexWrap: 'wrap', gap: UI_TOKENS.geometry.spacing[1] },
  photo: { width: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[3], height: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[3], borderRadius: UI_TOKENS.geometry.radii.control, alignItems: 'center', justifyContent: 'center', overflow: 'hidden' },
  quantity: { flexDirection: 'row', gap: UI_TOKENS.geometry.spacing[3] },
  largePhoto: { width: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[6], height: UI_TOKENS.geometry.targets.touch + UI_TOKENS.geometry.spacing[6] },
  itemCard: { borderWidth: StyleSheet.hairlineWidth, borderRadius: UI_TOKENS.geometry.radii.section, padding: UI_TOKENS.geometry.spacing[2], gap: UI_TOKENS.geometry.spacing[1] },
  catalogueSection: { gap: UI_TOKENS.geometry.spacing[2] },
  productGroup: { gap: UI_TOKENS.geometry.spacing[2] },
  priceAction: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', justifyContent: 'space-between', gap: UI_TOKENS.geometry.spacing[2] },
  supportingRow: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[2] },
  supportingCopy: { flex: 1, minWidth: 0 },
  serviceHeading: { width: '100%', flexDirection: 'row', alignItems: 'center', gap: UI_TOKENS.geometry.spacing[2] },
});
