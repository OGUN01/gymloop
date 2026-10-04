import { Fragment, useEffect, useState } from 'react';
import { getNetworkStateAsync } from 'expo-network';
import { formatMoney, purchaseRequestRefusalMessage, type PurchaseRequestRow } from '@gymloop/shared';
import { ActionButton, Body, EmptyState, Eyebrow, LoadingState, Row, RowAction, Screen, StateMessage, Title } from '../../components/ui';
import { useMobile } from '../../lib/mobile-context';
import { useMemberPurchases } from '../../lib/purchase';
import { nextCommandKey } from '../../lib/command-keys';
import { uploadProofImage } from '../../lib/proof-upload';

type PurchaseRow = Pick<PurchaseRequestRow, 'requestId' | 'status' | 'targetName' | 'quantity' | 'amountPaise' | 'currency'>;
/** The read model returns the accepted revision the confirm binds against. */
type UploadRow = PurchaseRow & { acceptedRevision?: string | null | undefined };

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
 * The member Buy tab: management root for purchase requests. Raising one
 * starts at what the member wants (shop, training, plan), this surface lists,
 * opens and cancels what they raised.
 */
export default function BuyScreen() {
  const { api } = useMobile();
  const { requests, loading, error, reload } = useMemberPurchases();
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  useEffect(() => { void reload(); }, [reload]);
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
      const network = await getNetworkStateAsync();
      if (!network.isConnected || !network.isInternetReachable) {
        setMessage('You are offline. Go back online and try again.');
        return;
      }
      const { launchImageLibraryAsync } = await import('expo-image-picker');
      const picked = await launchImageLibraryAsync({ mediaTypes: ['images'], allowsMultipleSelection: false, selectionLimit: 1 });
      if (picked.canceled || !picked.assets[0]) {
        setMessage('No screenshot selected.');
        return;
      }
      const asset = picked.assets[0];
      const answer = await uploadProofImage(api, request.requestId, { uri: asset.uri, mimeType: asset.mimeType ?? null, fileName: asset.fileName ?? null, fileSize: asset.fileSize ?? null }, request.acceptedRevision ?? null, nextCommandKey());
      setMessage(answer.message);
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
            const row: PurchaseRow = {
              requestId: request.requestId, status: request.status, targetName: request.targetName,
              quantity: request.quantity, amountPaise: request.amountPaise, currency: request.currency,
            };
            return <Fragment key={row.requestId}>
              <Row
                title={row.targetName}
                meta={`${row.quantity} × ${formatMoney(row.amountPaise, row.currency)}`}
                status={statusWord(row.status)}
                trailing={open ? <RowAction disabled={busy} onPress={() => void cancelRequest(row.requestId)}>Cancel request</RowAction> : null}
              />
              {request.status === 'owner_accepted' ? <>
                {request.reason ? <Body muted>{request.reason}</Body> : null}
                <ActionButton disabled={busy} onPress={() => proofUpload(request)}>{request.proofStatus === 'rejected' ? 'Re-upload payment screenshot' : 'Upload payment screenshot'}</ActionButton>
                <Body muted>{'JPG, PNG or WebP up to 2 MB. Uploading needs a network connection — nothing uploads offline.'}</Body>
              </> : null}
            </Fragment>;
          })
          : <EmptyState title="No purchase requests yet">{`Raise one from what you want — the shop, a training programme, or your plan renewal. Your gym accepts it, you pay outside the app, and the desk verifies the money.`}</EmptyState>}
    <ActionButton secondary quiet disabled={busy} onPress={() => void reload()}>Refresh</ActionButton>
  </Screen>;
}
