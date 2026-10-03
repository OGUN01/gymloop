import { purchaseRoute } from '../../../../lib/purchase-http';
import { noStore, apiOk, apiFail } from '../../../../lib/api';
import { readRequestIdentity } from '../../../../lib/identity-session';
import { loadMemberPurchaseRequests } from '../../../../lib/purchase';

/** Member raises a purchase request; the ledger decision stays in the RPC. */
export async function POST(request: Request) {
  return purchaseRoute(request, 'create');
}

/** Keyset list of the member's own requests. */
export async function GET(request: Request) {
  const resolved = await readRequestIdentity(request);
  if (!resolved || resolved.identity.kind !== 'member') return noStore(apiFail('unauthorized', 'not_permitted', 'Sign in to continue.'));
  try {
    return noStore(apiOk(await loadMemberPurchaseRequests(resolved.supabase as never, null)));
  } catch {
    return noStore(apiFail('server_error', 'operation_failed', "That didn't work. Try again."));
  }
}
