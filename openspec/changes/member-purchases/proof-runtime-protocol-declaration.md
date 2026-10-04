# PAY / MEDIA proof runtime protocol — REVIEW DRAFT

2026-10-04. This is a mechanical completion proposal, not owner approval,
implementation evidence, or permission to change frozen business policies.
Authority: committed member-purchases proposal and approved contract resolutions;
MEDIA verification amendment; Wave C public application declarations; canonical
currency declaration. Uncommitted proposal annotations are not authority.
No source, test, generated type, Cloud, device or money mutation accompanies it.

## Existing seams and exact reads

Reuse registered purchase schemas/types, safePurchasePage, purchaseRowProjection,
sqlRpcResponse, SQL refusal mapping, uploadPaymentProof/uploadProofImage,
MEDIA signer/verifier, matchesImageSignature, BUY_LIMITS and MEDIA_LIMITS.
No additional exported helper/type is proposed. Registry and signature inventory
name `read_member_purchase_requests` and `read_purchase_requests` (staff).
`read_staff_purchase_requests` is not an inventoried RPC: do not rename or call it.
Both existing readers take `(p_limit,p_after_created_at,p_after_id)` and return
one scalar JSON object `{requests: [], nextAfter: null, nextAfterId: null}`,
not a SETOF array. Rows order `(created_at DESC,id DESC)`; a continuation sends
the complete returned timestamp/UUID pair. Empty/final pages have null cursors.
Detail returns one safe JSON object; an unavailable target is a refusal.

Decode the declared camelCase request keys: requestId, requestKey, kind, status,
targetId, quantity, snapshot, quoteRevision, createdAt, expiresAt, acceptedAt,
acceptedRevision, rejectReason, activeProofAssetId, recordedPaymentId,
recordedOrderId, recordedMembershipId, recordedAmountPaise, recordedCurrency,
replayed. Absent recorded facts remain absent; do not fabricate zero payments,
receipts, dates or successful writes. Preserve the scalar list envelope before
decoding rows. Staff-only memberId is not a member-supplied authority field.

Nested snapshot keys are already camelCase; do not run a shallow snake-case
conversion and lose them. Shop/PT: productId, productName, kind, description,
cancellationTerms, validityDays, gstRateBp, unitPricePaise, pricePaise,
totalPaise, currency, quoteVersion; PT additionally trainerStaffId/sessionCount.
Renewal: membershipId, planId, planName, netPricePaise, grossPricePaise,
discountPaise, currency, durationDays, endsOn. Money remains canonical integer
decimal text. Nullable descriptive/GST facts remain null, never invented.
Historical end date is a date, not a fabricated timestamp or granted extension.
Only explicitly declared safe fields survive projection; no key, ETag,
staging URL, private storage metadata or arbitrary nested property does.

## Revision and exact viewed evidence

Shop/PT quoteVersion is the existing offer UUID; quoteRevision must not be
replaced with a generated client UUID. Renewal has no plan quote UUID.
The frozen renewal accepted representation is the held membership id plus
immutable sold net price/discount/currency/duration snapshot, compared against
the live held membership. Today's catalogue is display context. Null/omitted
quoteRevision means no quote UUID; it never means skip sold-term comparison.

An accepted command revision and an offer quote UUID have different purposes.
A request-scoped acceptedRevision UUID, if present in the canonical reader,
must be echoed exactly; never derive it from membershipId or quoteVersion.
Proof replacement invalidates any earlier verifier decision context even when
price is unchanged: recording must compare the exact current request revision
and active asset viewed. The runtime must not infer that “same request” means
“same proof”. A fresh view is required after replace/reject/cancel/expiry,
reacceptance, quote change, sign-out, rebinding or a late asynchronous result.

Verifier disclosure includes quoted terms, actual amount, currency, method,
exact current proof and resulting action. Enable proof-backed recording only
after successfully displaying that exact proof. Fetch/URL issuance alone is
not evidence the image rendered. Retain the requestId/proofId/assetId/revision
tuple in identity-scoped memory; failure clears it. Submit immutable viewed
facts and compare them under request/proof locks before ledger work. The
frozen six-argument recorder has no viewed-asset parameter; see decisions
below rather than pretending a UI variable binds the SQL transaction.
Cash without proof remains the already-approved explicit received-cash path.

## Upload, registration, confirmation and retries

Only the current owning eligible member may register for a live accepted owned
request with any required quote reconfirmation complete. Server resolves the
request, creator and tenant; no client storage key, actor or tenant is accepted.
Registration is bound durably to requestId, creator Auth/member, MIME and exact
registered bytes. An asset belongs to this request permanently; knowing an
unattached asset UUID is never permission to attach it elsewhere.

A logical upload needs a retained registration command UUID. Same actor/key
and same normalized requestId/MIME/bytes returns the same asset/staging PUT
facts without another registration/counter/deadline; changed facts conflict.
The inventoried `register_payment_proof(p_request_id,p_mime,p_bytes)` lacks
that key: its completion requires the serial decision below. Do not claim
that a new registration after a timeout is an idempotent retry.

Strict upload transport carries requestId from route, declared MIME/bytes,
registration key and returned assetId. Confirmation carries the same assetId,
expectedRevision and attachment commandKey; trusted Edge `proof-confirm`
receives the original verified caller token and exact request/asset evidence.
Recheck current actor/binding, live request, expiry/reconfirmation and exact
registration link before private metadata or R2 work and again after async
work immediately before finalization/attachment or returning success.

Reuse immutable MEDIA staging -> conditional verification -> publication:
server staging key, staging-only PUT, HEAD exact MIME/length/source ETag,
conditional signature read, CopySourceIfMatch to fresh unpublished destination,
post-copy HEAD/signature/ETag verification, credential-only finalization.
JPEG/PNG/WebP only; 2 MiB bound, existing 300-second PUT TTL/signature head.
No ordinary authenticated confirm, published PUT, generic member-photo signer,
web administrator client, new credential or gateway is introduced.

Publication and attachment are distinct. A confirmed but unattached asset is
not payment proof success. Attach only the registered request's verified asset
under request/asset locks with revision and command replay guards; supersede
the previous active proof atomically and preserve immutable history. Confirm
retry after publication skips recopy and retries only this same attachment.
Unknown finalization/attachment outcome retains the same keys/facts and uses
authoritative caller rechecks/reread; never delete a possibly committed winner.
Concurrent losing publication may delete only its positively unreferenced own
candidate. Replayed commands do not add audits, quota uses, holds or deadlines.
Known rejection may clean staging safely; no failure may erase bound history.

## Commands and failure identity

Create retains requestKey and normalized kind/targetId/quantity/revision.
Accept/reconfirm retain commandKey/requestId/expectedRevision. Cancel retains
commandKey/requestId. Request rejection retains commandKey/requestId/revision
and trimmed reason. Proof rejection uses existing
`reject_payment_proof(p_request_id,p_asset_id,p_expected_revision,p_reason,p_command_key)`;
strict body supplies assetId, expectedRevision, reason, commandKey (route owns
requestId). Reason is 3–200 trimmed characters, shown to member. Reject only
the exact active proof and preserve original acceptance expiry.
Attach retains commandKey/requestId/assetId/revision. Record retains commandKey,
requestId/revision/actual integer-paise text/currency/manual method and exact
viewed evidence; initial PT slot retains exact normalized facts if approved.
Unknown outcome retries those facts/key, never generates a new key. Changed
actor/facts conflict. Late results cannot overwrite newer identity/view state.

Keep existing ledger/provider/receipt/refund/stock/renewal arithmetic unchanged.
GL123 is hard-hold conflict, GL124 binding conflict, GL125 mismatch-path guard.
No GL126 allocation is authorized by the committed proposal. Preserve 42501,
22023, P0002, GL068, GL066, GL067, 23514 and 22003 precedence and existing
ledger refusals. BUY caps still map to HTTP 429 rate_limited; choose a stable
existing SQLSTATE plus declared detail mechanically, rather than invent GL126.

## Exact bounded proof view

The reader's existing scalar result is
`{requestId,proofId,assetId,expiresAt,url}`; public POST exposes only
`{url,expiresAt}` in the standard no-store envelope. The URL is the same-origin
proof-asset route, not an invented database-produced R2 signature.
The route must carry an unforgeable issued capability bound to request/proof/
asset and issue/expiry instants, without exposing storage keys. Expiry is
mandatory and at most issuedAt + BUY_LIMITS.privateProofGetTtlSeconds (60s).
Unsigned caller timestamps, absent expiry, future issuedAt, changed tuple or
expired capability refuse before object access. Each successful GET independently
authenticates and reauthorizes the exact currently active proof and current
real actor; capability possession alone grants no authority.

After every asynchronous privileged lookup/sign/fetch, recheck current actor,
request exposure and exact active tuple before returning bytes or URL. Any
inner R2 signature expires no later than the original capability expiresAt;
GET cannot start a new 60-second window. No optional-expiry branch or fallback
URL re-mint bypass. A fresh explicit authorized POST may issue a fresh view;
an old GET cannot. Signed URL issuance is bounded revocation, not instant
revocation. Keys/ETags/URLs never enter reads, audit, notifications or analytics.
Responses/bytes are no-store and never persisted by the app.

This declaration authorizes only already-approved active proof viewing by its
owner member or real same-tenant front-office verifier. Trainers, preview,
impersonation, general catalogue exposure and recorded/mismatch/bound history
do not become proof viewers. Terminal receipt/history remains safe metadata.

## Serial decisions required before author fan-out

1. Public create/recorder schemas require UUID expectedRevision, but renewal
   explicitly has no quote UUID and compares sold snapshot. Specify creation
   null/omission semantics separately from accepted command revision. No
   public approval yet defines optional/null expectedRevision as skip-check.
   Review recommendation: renewal creation explicit null, never a fake UUID;
   all accepted commands echo a real request revision and sold-term comparison.
2. Pin request-revision renewal on proof replacement and a recorder binding
   to viewed asset/proof. Existing recorder signature cannot convey viewed
   asset; select one serial protocol change (explicit viewed evidence or a
   durable actor-scoped view binding), before blind authors start.
3. Pin registration retry UUID transport/storage and exact same-facts replay
   using the existing registration seam; its current signature lacks a key.
4. Pin authenticity for the same-origin expiring capability in the existing
   MEDIA boundary, using existing trusted runtime capability only. No new
   secret/admin route is implicitly approved by this draft.
5. Reconcile genuine currency declaration conflict: earlier app declarations
   require INR recorder input while frozen BUY-014/canonical-currency permit
   actual Shop/PT currency mismatch under existing payment guards. Preserve
   actual currency; do not silently reject or convert permitted facts.

Uncommitted proposal edits adding GL126, accepted-request rejection and a PT
slot argument need separately traceable authority; this draft does not label
assistant annotations human approval. GL126 is not a frozen conflict because
the committed allocation explicitly stops at GL125. No implementation/tests
may begin from unresolved clauses or treat this review draft as approval.
