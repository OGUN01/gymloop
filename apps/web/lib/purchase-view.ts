/**
 * Buy-tab presentational projection: the one whitelist deciding which row
 * fields may reach markup. Object keys, ETags, signed URLs and any unknown
 * column stay out, which keeps every page safe even if an upstream row
 * carries storage metadata.
 */
export type PurchaseRequestView = {
  requestId: string; kind: string; status: string;
  memberName: string | null; targetName: string; quantity: number;
  quotationPaise: string; amountPaise: string; currency: string; gstRateBp: number;
  createdAt: string; acceptedAt: string | null; expiresAt: string | null;
  acceptedRevision: string | null;
  reason: string | null; proofStatus: string; receiptId: string | null;
  receivedPaise: string | null; differencePaise: string | null; saleResolved: boolean;
  resultingEndDate: string | null;
};

export function presentPurchaseRequest(source: Record<string, unknown>): PurchaseRequestView {
  const resulting = source.resulting && typeof source.resulting === 'object' && !Array.isArray(source.resulting)
    ? (source.resulting as { endDate?: unknown })
    : null;
  const text = (value: unknown): string | null => typeof value === 'string' && value.length > 0 ? value : null;
  return {
    requestId: String(source.requestId ?? ''),
    kind: String(source.kind ?? ''),
    status: String(source.status ?? ''),
    memberName: text(source.memberName),
    targetName: String(source.targetName ?? ''),
    quantity: Number(source.quantity ?? 0),
    quotationPaise: String(source.quotationPaise ?? '0'),
    amountPaise: String(source.amountPaise ?? '0'),
    currency: String(source.currency ?? 'INR'),
    gstRateBp: Number(source.gstRateBp ?? 0),
    createdAt: String(source.createdAt ?? ''),
    acceptedAt: text(source.acceptedAt),
    expiresAt: text(source.expiresAt),
    acceptedRevision: text(source.acceptedRevision),
    reason: text(source.reason),
    proofStatus: String(source.proofStatus ?? ''),
    receiptId: text(source.receiptId),
    receivedPaise: text(source.receivedPaise),
    differencePaise: text(source.differencePaise),
    saleResolved: Boolean(source.saleResolved),
    resultingEndDate: resulting && typeof resulting.endDate === 'string' ? resulting.endDate : null,
  };
}
