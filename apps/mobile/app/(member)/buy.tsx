import { Fragment, useEffect, useRef, useState } from 'react';
import { getNetworkStateAsync } from 'expo-network';
import { formatMoney, purchaseRequestRefusalMessage } from '@gymloop/shared';
import { ActionButton, Body, EmptyState, Eyebrow, LoadingState, Row, RowAction, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberPurchases } from '../../lib/purchase';
import { nextCommandKey } from '../../lib/command-keys';
import { uploadProofImage } from '../../lib/proof-upload';

import type { MemberPurchaseRow } from '../../lib/purchase';

/** The read model returns the accepted revision the confirm binds against. */
type UploadRow = MemberPurchaseRow;

function statusWord(status: string): string {
  switch (status) {
    case 'requested': return 'Requested';
    case 'owner_accepted': return 'Accepted';
    case 'payment_proof_uploaded': return 'Pending verification';
    case 'recorded': return 'Payment recorded';
    case 'mismatch_recorded': return 'Money recorded';
    case 'rejected': return 'Declined';
    case 'cancelled': return 'Cancelled';
    case 'expired': return 'Expired';
    default: return 'Update pending';
  }
}

const OPEN_STATUSES = ['requested', 'owner_accepted', 'payment_proof_uploaded'] as const;

/**
 * The image picker is warmed at mount and its launcher cached at module
 * scope, so opening the picker is synchronous from the press: no await may
 * run before the picker opens, or an identity change during the picker could
 * never be observed against the press-time identity.
 */
let pickerLauncher: (typeof import('expo-image-picker'))['launchImageLibraryAsync'] | null = null;

/**
 * The member Buy tab: management root for purchase requests. Raising one
 * starts at what the member wants (shop, training, plan), this surface lists,
 * opens and cancels what they raised.
 */
export default function BuyScreen() {
  const context = useMobile();
  const { api } = context;
  const { requests, loading, error, reload } = useMemberPurchases();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  // The signed-in identity at decision time: the context reader is the live
  // source where the runtime exposes it as a plain reader; React's dispatcher
  // refuses that call outside render, and the last committed render's
  // identity (fresh after any identity change re-renders consumers) is the
  // fallback. Either way a picker await never submits under a changed identity.
  const identityRef = useRef(context.identity);
  identityRef.current = context.identity;
  // One retained registration + attachment command identity per logical
  // upload (frozen decision 5): the caller holds the keys across unknown
  // outcomes, so a retry replays the same facts instead of minting fresh ones.
  const uploadKeysRef = useRef<Map<string, { commandKey: string; registrationKey: string }>>(new Map());
  const readLiveIdentity = (): unknown => {
    try {
      const reader = useMobile as unknown as () => { identity: unknown };
      return reader().identity;
    } catch { return identityRef.current; }
  };
  /** The identity scope that must not change across an await: equal facts are
   * the same identity even when the runtime hands back a fresh object. */
  const identityScope = (identity: unknown): string | null => {
    if (!identity || typeof identity !== 'object') return null;
    const facts = identity as { kind?: string; userId?: string; tenantId?: string; memberId?: string; staffId?: string };
    if (facts.kind === 'member') return `member:${String(facts.userId)}:${String(facts.tenantId)}:${String(facts.memberId)}`;
    if (facts.kind === 'staff') return `staff:${String(facts.userId)}:${String(facts.tenantId)}:${String(facts.staffId)}`;
    return typeof facts.kind === 'string' ? facts.kind : null;
  };
  useEffect(() => { void reload(); }, [reload]);
  // Warm the picker so opening it from the press is synchronous: no await may
  // run before the picker opens, or an identity change during the picker could
  // never be observed against the press-time identity.
  useEffect(() => {
    void import('expo-image-picker').then(module => { pickerLauncher = module.launchImageLibraryAsync; }).catch(() => { /* The picker stays lazy; the press falls back to the dynamic import. */ });
  }, []);
  const cancelRequest = async (requestId: string) => {
    if (busy) return;
    setBusy(true);
    setMessage(null);
    try {
      const key = nextCommandKey();
      const answer = await api.post<{ ok: boolean; error?: { code: string } }>(
        `/api/member/purchase-requests/${requestId}/cancel`,
        { commandKey: key },
      );
      if (answer.ok) {
        setMessage('Request cancelled.');
        await reload();
      } else {
        setMessage(purchaseRequestRefusalMessage(answer.error?.code ?? 'operation_failed'));
      }
    } catch {
      setMessage('You are offline. Go back online and try again.');
    } finally {
      setBusy(false);
    }
  };
  const proofUpload = async (request: UploadRow) => {
    if (busy) return;
    setBusy(true);
    setMessage(null);
    try {
      // The picker opens synchronously from the press; every await (network,
      // identity revalidation, upload) happens after it, so a changed identity
      // during the picker is observable against the press-time identity.
      const startedIdentity = identityScope(identityRef.current);
      const launch = pickerLauncher ?? (await import('expo-image-picker')).launchImageLibraryAsync;
      const picked = await launch({ mediaTypes: ['images'], allowsMultipleSelection: false, selectionLimit: 1 });
      const asset = picked.assets?.[0];
      if (picked.canceled || !asset) {
        setMessage('No screenshot selected.');
        return;
      }
      const network = await getNetworkStateAsync();
      // Only a DEFINITIVE offline state refuses before the network calls; an
      // unknown state proceeds and the command itself answers honestly.
      if (network.isConnected === false || network.isInternetReachable === false) {
        setMessage('You are offline. Go back online and try again.');
        return;
      }
      // Identity revalidation after the asynchronous picker await: a member
      // change or sign-out while the picker was open refuses before any
      // network command (BUY-001/021).
      if (identityScope(readLiveIdentity()) !== startedIdentity) {
        setMessage('Your sign-in changed. Pick the screenshot again.');
        return;
      }
      let keys = uploadKeysRef.current.get(request.requestId);
      if (!keys) {
        keys = { commandKey: nextCommandKey(), registrationKey: nextCommandKey() };
        uploadKeysRef.current.set(request.requestId, keys);
      }
      const answer = await uploadProofImage({ uri: asset.uri, mimeType: asset.mimeType ?? null, fileName: asset.fileName ?? null, fileSize: asset.fileSize ?? null }, request.requestId, request.acceptedRevision ?? null, keys.commandKey, keys.registrationKey);
      setMessage(answer.message);
      if (answer.ok) {
        uploadKeysRef.current.delete(request.requestId);
        await reload();
        setMessage('Screenshot uploaded. Pending verification — view your request for the verification check.');
      }
    } catch {
      setMessage('You are offline. Go back online and try again.');
    } finally {
      setBusy(false);
    }
  };
  return <Screen footer={<Body muted>{'Requests are checked by your gym before payment counts. A screenshot is your claim of payment, pending verification — the desk records the money.'}</Body>}>
    <Eyebrow>Buy / payments</Eyebrow>
    <Title>Your purchase requests</Title>
    {message ? <StateMessage>{message}</StateMessage> : null}
    {loading ? <LoadingState /> :
      error ? <StateMessage tone="error">{error}</StateMessage> :
        requests.length ?
          requests.map(request => {
            const open = OPEN_STATUSES.includes(request.status as typeof OPEN_STATUSES[number]);
            const row = request;
            return <Fragment key={row.requestId}>
              <Row
                title={row.targetName}
                meta={`${row.quantity} × ${formatMoney(row.amountPaise, row.currency)}`}
                status={statusWord(row.status)}
                trailing={open ? <RowAction disabled={busy} onPress={() => void cancelRequest(row.requestId)}>Cancel request</RowAction> : null}
              />
              {request.status === 'owner_accepted' || request.status === 'payment_proof_uploaded' ? <>
                {request.reason ? <Body muted>{request.reason}</Body> : null}
                <ActionButton disabled={busy} onPress={() => proofUpload(request)}>{request.proofStatus === 'rejected' ? 'Re-upload payment proof screenshot' : request.status === 'payment_proof_uploaded' ? 'Replace payment proof screenshot' : 'Upload payment proof screenshot'}</ActionButton>
                <Body muted>{'JPG, PNG or WebP up to 2 MB. Uploading needs a network connection — nothing uploads offline.'}</Body>
              </> : null}
            </Fragment>;
          })
          : <EmptyState title="No purchase requests yet">{`Raise one from what you want — the shop, a training programme, or your plan renewal. Your gym accepts it, you pay outside the app, and the desk verifies the money.`}</EmptyState>}
    <ActionButton secondary quiet disabled={busy} onPress={() => void reload()}>Refresh</ActionButton>
  </Screen>;
}
