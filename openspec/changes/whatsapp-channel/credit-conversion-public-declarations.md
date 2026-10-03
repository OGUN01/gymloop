# Existing-credit conversion — frozen public declarations

2026-10-03. Frozen engineering declarations for the separately owner-approved
credit conversion only. The owner subsequently delegates the valuation decision
to root; root retains the explicit previously approved choice without reopening it.
The approved `existing-credit-conversion-amendment.md` (`efff581`) fixes
**1 old credit = INR 1 = 100 integer paise**. This question is settled.
Provider-wallet approval remains authoritative; this is its separately approved
nonzero/history conversion case, not permission to bypass the zero-value guard.
These declarations authorize independent visible and holdout authors for this
unit before a separate implementer. They do not freeze the full WSP or NTF
transport contracts, authorize delivery or attest to actual provider setup.

Fixed migration: `supabase/migrations/20261004085000_messaging_wallet_paise.sql`,
before the remaining Wave-C migrations. All schema/data changes apply through CI
only as part of the approved Wave-C order, after the preceding DB run is green.
This unit cannot be pushed without all existing wallet consumers and independently
amended wallet tests/gates passing. Tests remain rollback-only.

## EARS requirements for this isolated approved unit

- **WSP-101 (exact cutover).** WHEN CI converts the approved original inventory
  THE SYSTEM SHALL lock both existing tables, compare the complete canonical
  manifest and scale every original balance, signed delta and nonnull historical
  balance-after by exactly 100, preserving null, identity, chronology and all
  nonmoney facts. It SHALL create no movement or monetary receipt.
- **WSP-102 (atomic refusal).** IF any exact baseline fact, per-tenant net,
  nonnegative balance or converted bigint bound fails THE SYSTEM SHALL refuse
  with no partial schema, data, function, grant or audit change.
- **WSP-103 (evidence).** WHEN conversion commits THE SYSTEM SHALL retain
  immutable original-credit values, fixed rate, INR, approval reference and one
  cutover instant. Later writes SHALL neither change nor forge that evidence.
  New paise-native rows SHALL carry null conversion evidence.
- **WSP-104 (new adjustment).** WHEN an actual paise adjustment is requested
  THE SYSTEM SHALL retain the full active super-admin authority, target/replay
  rules, exact signed arithmetic, original replay result and one atomic audit
  from the existing command, using the explicit paise-and-INR facade below.
- **WSP-105 (legacy).** WHEN the old credit facade receives a historical retry
  THE SYSTEM SHALL return only exact converted original evidence for the same
  actor/key/facts. It SHALL reject new credit writes and never reinterpret their
  positional value as paise or derive original credits from a new movement.
- **WSP-106 (read projection).** WHEN the existing list is read THE SYSTEM SHALL
  preserve its caller/RLS/snapshot and notification facts, expose only the new
  wallet object to already-authorized roles and serialize amounts as canonical
  decimal strings. Unavailable money SHALL remain unavailable, not zero.
- **WSP-107 (HTTP/display).** WHEN an adjustment body or wallet display crosses
  the application boundary THE SYSTEM SHALL require explicit INR/paise fields,
  reject old or mixed credit fields and preserve exact large signed values with
  registered codecs/formatters; no floating point or guessed rounding applies.
- **WSP-108 (free channels).** WHILE paid provider transport remains inactive
  THE SYSTEM SHALL preserve existing free/manual/unconfigured notification
  behavior and the denied paid-acceptance stub, without wallet movement.
- **WSP-109 (history).** WHEN the unit cutover is recorded THE SYSTEM SHALL
  preserve all existing audit rows, ledger ids, actor/request/notification
  references, reasons and original timestamps, and emit no new historical
  adjustment/debit/top-up/payment event. Future actual adjustment audit failure
  SHALL still roll back the whole movement.

## Same tables, explicit units, immutable conversion evidence

Keep `public.messaging_wallets` (tenant PK) and
`public.messaging_wallet_ledger` (existing id PK); no duplicate wallet, ledger,
opening balance entry or monetary receipt. Rename operational columns in the
single transactional cutover, retaining bigint storage:

| Table | Operational cutover | Evidence columns added |
|---|---|---|
| messaging_wallets | balance_credits → balance_paise; add currency text NOT NULL CHECK currency='INR'; preserve tenant_id, created_at, updated_at | original_balance_credits bigint nullable; conversion_paise_per_credit bigint nullable; conversion_currency text nullable; conversion_approval_ref text nullable; converted_at timestamptz nullable |
| messaging_wallet_ledger | delta_credits → delta_paise; balance_after_credits → balance_after_paise; add currency text NOT NULL CHECK currency='INR'; preserve all other existing columns | original_delta_credits bigint nullable; original_balance_after_credits bigint nullable; conversion_paise_per_credit bigint nullable; conversion_currency text nullable; conversion_approval_ref text nullable; converted_at timestamptz nullable |

Converted existing rows carry original values, rate=100, conversion_currency=INR,
approval_ref=efff581 and one shared server cutover instant. Original nullable
historical balance-after stays null in both units. Wallet original_balance is
the cutover snapshot, never updated when later balance changes. New paise-native
wallets/movements have all conversion metadata/original-credit fields null.
Converted row metadata is all-or-nothing except the intentionally nullable
historical balance-after; original_delta is mandatory for converted ledger
rows. Guard evidence from UPDATE/DELETE even by normal owning commands; no
callable conversion command, session flag or user-controlled evidence input.
Existing ledger append-only protection covers both operational and evidence
columns after the one approved transactional historical conversion.

Preserve ids, signs, reasons verbatim, request keys, attribution, notification
references, every created_at and wallet updated_at; do not let a timestamp
touch trigger rewrite historical facts during conversion. Existing RLS,
tenant-leading indexes, composite notification FK and effective grants remain.
No new reader gets access to ledger/evidence merely because currency exists.

## Exact locked cutover conditions

CI alone runs one forward-only transaction. Acquire ACCESS EXCLUSIVE locks on
wallets then ledger before inventory, hold them through constraint/function
cutover and COMMIT. Exact approved row manifest is checked inside these locks;
an earlier aggregate inventory is insufficient authorization.

The manifest covers ALL wallet tenant ids, balances and timestamps,
and ALL ledger ids, tenant, signed delta, nullable balance-after, reason,
notification_id, request_key, recorded_by_user_id and created_at. Compare the
complete canonical field manifest fingerprint, with counts and null preservation,
not only totals. The approved
observation is three wallets, one nonzero wallet, aggregate 4500 credits,
two ledger rows and net movement 4500 credits. The +5000/-500 example does
not identify exact live rows. Root's authorized read-only complete observation
is recorded in `docs/evidence/v2/wsp-wallet-exact-manifest.json`. Its fingerprint
is `79a7a86950098a93b9a2d0f78e9e0416beea077ea0bdc9308ae1e805df12cacb`.
The original full private CLI result is retained; no identifiers are guessed from
seed or exposed in the public receipt. Reproduce its exact canonical grammar:
set session timezone UTC; build each wallet/ledger object with every field listed
above, money as canonical decimal text and original null as JSON null; aggregate
wallet objects ordered by tenant_id and ledger objects by tenant_id then id;
build `{wallets:[...],ledger:[...]}` as jsonb; compute lowercase hex SHA-256 of
UTF-8 `manifest::text` inside PostgreSQL. JavaScript JSON formatting is not
interchangeable. Refuse any complete-field fingerprint/count mismatch with
23514 before schema/data changes, including zero-wallet or timestamp changes.
Any unexpected/missing/changed row refuses the entire migration, preserving
credits untouched. Do not fabricate wallets for absent tenants.

Validate each tenant independently: wallet balance nonnegative; each existing
ledger delta nonzero; each ledger tenant has an existing wallet; sum of signed
deltas equals that tenant's balance (empty ledger sum is zero). Preserve exact
historical ordering/facts. Do not assert invented ordering between equal-time
rows or derive null historical balance-after. Every nonnull historical
balance-after must agree with its approved exact row fact; where command
history establishes a chronological chain, retain its existing consistency
contract. No aggregate cross-tenant netting or clamping can repair mismatch.

Compute each product as numeric(original bigint)*100, then prove within signed
bigint range before casting. Check balance, every signed delta AND every
nonnull historical balance-after independently; negative delta overflow is
also fatal. Compute sums in numeric to avoid intermediate bigint overflow.
After conversion assert per-row equality with originals*100, null preservation,
unchanged manifest nonmoney fields, exact row counts, and per-tenant
balance_paise=sum(delta_paise). Observed aggregate must become 450000 paise;
the example maps +5000/-500 to +500000/-50000 paise. No floating point,
rounding, reset, historical audit rewrite or new ledger movement occurs.
Failure anywhere rolls back schema/data/functions together.

## Command, top-up, replay and audit candidate compatibility

Existing declared `public.adjust_messaging_wallet(uuid,bigint,text,uuid)` has
named p_delta_credits; changing that same argument name to p_delta_paise would
silently reinterpret positional callers. Candidate instead adds explicit:

`public.adjust_messaging_wallet_paise(p_tenant_id uuid,p_delta_paise bigint,
p_currency text,p_reason text,p_request_key uuid) returns jsonb`

VOLATILE DEFINER, postgres-owned, search_path='', authenticated EXECUTE only;
same complete active super_admin/platform_users/auth.uid() and no gym/member/
staff/impersonation authority as the existing adjustment. Existing wallet only.
Exact result is `{ledgerId,tenantId,deltaPaise,currency,reason,balanceAfterPaise,
createdAt}`, explicit nullable historical balance-after, canonical integer
strings, currency INR. Positive adjustment retains the existing authorized
manual top-up behavior; it is not a purchase, payment receipt or auto-top-up.

Retain `app.record_wallet_movement` as the sole locked arithmetic/audit path,
amended private declaration:

`app.record_wallet_movement(p_tenant_id uuid,p_delta_paise bigint,p_currency text,
p_reason text,p_request_key uuid,p_notification_id uuid,p_actor_user_id uuid)
returns jsonb`

Same private DEFINER ownership/search path and no EXECUTE to PUBLIC, anon,
authenticated or service_role. Owning adjustment invokes it with null
notification_id; transport remains inactive and acquires no privilege here.
Take wallet lock before replay lookup; key binds tenant, currency, signed paise,
trimmed reason and acting user. Compare converted original request to its exact
paise equivalent: replay returns original ledger id/timestamp/balance-after,
never the current wallet balance, and appends no row or audit. GL068 mismatch
never creates a second movement. No balance arithmetic in BEFORE INSERT or
ON CONFLICT side effect. Check negative balance, overflow and audit failure
before atomic commit; all roll back together. Future holds must serialize on
this same wallet and constrain available funds, but no hold/send is enabled
by conversion alone.

Keep old `public.adjust_messaging_wallet(p_tenant_id uuid,p_delta_credits bigint,
p_reason text,p_request_key uuid) returns jsonb` as a **legacy replay-only**
compatibility command with unchanged authority. It finds only converted
historical adjustment evidence: compare original delta credits/reason/actor/
key exactly and return original `{ledgerId,tenantId,deltaCredits,reason,
balanceAfterCredits,createdAt}`. Different facts GL068; a missing key or a
paise-native movement cannot authorize a new credit adjustment and fails
22023 invalid_request. This preserves historical retries without extending a
credit mutation interface. It must not infer original credits by dividing a
new paise movement. This legacy replay-only compatibility choice is frozen.

Preserve append-only historical audit rows and their credit-labelled JSON.
New movement audit uses `messaging_wallet.adjusted` with before
`{balance_paise:<string>,currency:"INR"}` and after
`{balance_paise, currency,ledger_id,delta_paise,notification_id,request_key,
recorded_by_user_id}`; integer fields strings, trimmed submitted reason,
one event per actual movement, zero on replay. Conversion emits no new
adjustment/debit/top-up/payment or historical audit event. Its immutable evidence
columns, approval reference, exact baseline receipt and CI result record the
unit cutover. Preserve every existing audit byte. Later actual paise adjustments
retain the original one-event/atomic rollback rule; audit failure aborts that
adjustment. No historical audit backfill.

Keep authorization→target visibility→validation→exact replay/conflict→funds
precedence. Preserve 42501/403 forbidden, P0002/404 not_found, GL068/409
idempotency_conflict, zero/blank 23514/422 invalid_adjustment, overflow
22003 with explicit new API code paise_out_of_range. New paise insufficiency
keeps GL067 but deliberately updates the paise command's response to
409 insufficient_funds; legacy command's old credits error vocabulary is not
silently changed. Currency other than INR is 22023 invalid_request. No
custom SQLSTATE allocation is needed for this isolated cutover.

## Named generated/API consumer cutover

Public generated metadata identifies only existing wallet/ledger fields,
`adjust_messaging_wallet` args, `list_notifications(p_channel?) returns Json`
and `onboard_gym` (no wallet-unit input). Private helper/body/trigger names
cannot be recovered from Database; the helper declaration above is grounded
in the registry and phase6 contract. No generated top-up RPC is declared.

| Existing registered consumer | Explicit change required in same release |
|---|---|
| `walletAdjustRequestSchema` / `WalletAdjustRequest`, packages/shared/src/api/comms.ts | Body becomes `{tenantId,deltaPaise,currency,reason,requestKey}`. Strictly reject old deltaCredits or mixed-unit body, never multiply an unlabelled request. Reuse existing canonical integer codec; platform-free. |
| `POST /api/messaging-wallet/adjust` | Calls new adjust_messaging_wallet_paise through caller client; body/results explicitly paise+INR. Existing JSON 201 success/envelope conventions retained. Stale credit clients receive validation failure, not accidental charge. |
| `WalletAdjustmentResult` / `walletAdjustmentResult`, apps/web/lib/comms.ts | Validate exact new seven-key paise result and null/string historical balance-after. Update commsRpcFailure's explicit unit-aware error mapping. |
| `public.list_notifications`, `MessagesScreen` / `loadMessages`, apps/web/lib/messages.ts | Keep notification/status fields and one-statement/RLS behavior; wallet projection becomes an explicitly named `{balancePaise,currency}` object, null for existing unauthorized/absent wallet cases. No credit field returns paise. Front desk wallet denial remains. |
| `public.onboard_gym`, `POST /api/platform/gyms` | Initial wallet balance_paise=0,currency=INR; no conversion metadata and no opening movement/receipt. Preserve onboarding replay and authority. |
| `Database` messaging_wallets/messaging_wallet_ledger Row/Insert/Update and Functions | Regenerate only via correctly authenticated CLI after CI migration; never hand-edit. Generated bigint number typing does not authorize JS-number monetary serialization. All public JSON amounts remain decimal strings. |

`app.accept_paid_notification(...p_cost_credits...)` remains denied/unconfigured;
do not rename its cost argument into an active paise debit. In-app, manual
WhatsApp opening and unconfigured push still create no ledger movements.
Provider acceptance will not debit under the approved WSP rule; verified
billable-delivery writer belongs to separately frozen transport declarations.

## Fixed consumer and evidence declarations

The complete baseline is now captured and per-tenant net/overflow checks pass
read-only. CI repeats the complete fingerprint and arithmetic checks while both
tables are locked; changed facts refuse rather than changing the chosen inventory.
`public.list_notifications` replaces only its old `walletBalanceCredits` field
with `wallet: {balancePaise:string,currency:'INR'} | null`. Keep its existing rows,
statusCounts, asOf, caller/RLS/single-statement rules and wallet-role denial.
`MessagesScreen` and its internal reply type use the same `wallet` field. Invalid
or unavailable money remains unavailable, never zero. Console display reuses
registered `formatMoney`, preserving exact strings. Any existing or future
adjustment input keeps an explicit currency/unit label; it cannot submit old
credit-labelled fields to the paise API.

Reuse `PAISE_PER_RUPEE` for TypeScript conversion scale if needed; the approved
old-credit policy is one rupee, so no duplicate number/helper is introduced.
All new public amounts are canonical decimal strings with INR. The request codec
keeps its existing zero-delta validation order; SQL zero/blank still uses 23514.
Old/mixed credit field bodies fail strict new-shape validation.

One new INVOKER VOLATILE trigger function `app.enforce_wallet_conversion_evidence()`
has search_path='', is postgres-owned and grants no direct EXECUTE to PUBLIC,
anon, authenticated or service_role. Existing converted evidence cannot change
or be removed by any later UPDATE. New paise-native wallet/ledger INSERTs require
all original-credit/conversion metadata null; they cannot forge converted history.
The migration stamps original rows before installing that protection. Existing
ledger append-only, wallet arithmetic, timestamp and authorization protections
remain. No callable conversion RPC or user-controlled flag grants an exception.

Independent authors amend only earlier wallet-unit/signature/mock expectations
in their own visible or held suites, retaining every authority, RLS, replay,
overflow, audit rollback, free-channel/no-ledger and unrelated scenario. Add new
regressions for original-value/null/history retention, exact scaling, evidence
immutability, strict HTTP units, legacy replay-only, role denials and explicit
unavailable versus zero. Root coordinates visible meta-suite ownership once;
the implementer cannot alter tests or read holdouts/private result files.
No transport author builds against this isolated conversion as if delivery were
approved or configured. Provider/rate/tax/compliance facts remain activation
prerequisites and this unit creates no hold, charge or external provider request.

## Published application signatures for independent authors

Declaration-only metadata from registered existing seams; no function body is
part of this packet. Root `vitest.config.mts` supplies installed web/native
module identities. Holdout authors own their held files and may mock external
caller/read hosts while keeping the real command/schema/result boundary.

```ts
// apps/web/lib/api.ts
type PlatformSession = { supabase: CallerSupabase; userId: string; role: PlatformRole };
function platformSession(options?: { requireAdmin?: boolean }):
  Promise<{ session: PlatformSession } | { failure: Response }>;
function jsonBody(request: Request): Promise<{ payload: unknown } | { failure: Response }>;
function apiFail(status: ApiFailStatus, code: string, message: string,
  details?: Readonly<Record<string, unknown>>): Response;
// apps/web/lib/comms.ts
function walletAdjustmentResult(data: unknown): WalletAdjustmentResult | null;
function commsRpcFailure(error: { code: string; message: string }, unit?: 'paise' | 'credits'): Response;
function commsOk(status: 'ok' | 'created', data: unknown): Response;
// apps/web/lib/messages.ts
function loadMessages(searchParams: Promise<{ channel?: string; q?: string; memberCursor?: string }>):
  Promise<MessagesScreen>;
```

`CallerSupabase` denotes the existing verified caller's installed client, not a
new exported replacement type. The POST uses `platformSession({requireAdmin:true})`
before JSON parsing; mock the registered `apps/web/lib/api.ts` host if needed,
never the actual wallet POST or result/schema under test. `commsOk('created',data)`
is HTTP 201 `{ok:true,data}`; `'ok'` is 200. Failure is the existing
`{ok:false,error:{code,message}}` envelope. A malformed RPC result refuses with
HTTP 500 rather than success. Public result fields and paise SQLSTATE responses
above govern the new unit. This corrects the consumer table's former accidental
303 wording; no form redirect is introduced.

The retained native22023 response is HTTP400 `invalid_request`; it is not
changed into422 by the currency cutover. New paise22003 remains explicitly
HTTP422 `paise_out_of_range`. Optional mapper context preserves the other
existing comms callers' legacy credit vocabulary; wallet calls default to paise.
The original phase6§1 signed PostgreSQL bigint input bounds remain mandatory:
canonical delta strings must fit -9223372036854775808 through9223372036854775807.
Zero remains parseable and is refused by SQL23514 in the existing validation
order. Registered named bigint bounds implement that existing range rule.

The registered messages loader uses `requireAudience('console')` from
`apps/web/lib/identity-session.ts` and `loadMemberSearch` from
`apps/web/lib/members.ts` as external caller/roster hosts. Its own list RPC,
wallet validation and real formatter remain the unit under test. The fields
other than wallet remain the existing MessagesScreen declarations.

The console audience host returns `Promise<{supabase:CallerSupabase,
identity:Extract<GymloopIdentity,{kind:'staff'|'impersonation'}>}>`, with the
existing classified `GymloopIdentity` exported from `@gymloop/shared`. A complete
staff identity has kind, userId, tenantId, staffId and role; preview uses its
existing full classified shape. Member-search declaration is
`loadMemberSearch(Promise<{q?:string,cursor?:string,limit?:string,access?:string,
status?:string}>)` returning `{phone:string,filters:object,members:Array<{
id:string,full_name:string,phone:string,status:MemberStatus,user_id:string|null,
erased_at:string|null}>,pageSize:number,nextCursor:string|null,errorMessage:string|null}`.
MemberStatus and identity roles remain the generated/registered vocabularies.
The returned messages screen retains rows, statusCounts, asOf, isAdmin, isPreview,
tenantId, members `{id,name}`, memberNextCursor, memberSearchError, templates
`{id,key,channel,locale,category,body,isActive}`, errorMessage and the new wallet.
List rows retain id, memberId, memberName, channel, category, status, scheduledFor,
sentAt, deliveredAt, failedAt, failedReason, optedOutAt, optedOutReason and
sourceNotificationId (nullable event fields). `statusCounts` has scheduled,
sent, delivered, failed and opted_out canonical integer-string counts.

The exact live fingerprint is a locked migration acceptance condition. Ordinary
recurring suites must not recompute it from a wallet's later mutable updated_at
or require all future wallets/movements to remain at the original inventory.
Immutable evidence checks scope converted rows; new rows have null evidence.
Original timestamp and complete-fingerprint checks belong at the cutover,
including a rollback preview of changed baseline facts. No extra historical
timestamp column is authorized merely to repeat a one-time baseline assertion.
