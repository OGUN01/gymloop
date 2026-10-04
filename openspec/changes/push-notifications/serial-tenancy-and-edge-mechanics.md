# NTF serial tenancy clarification and Edge mechanics — FROZEN

Date: 2026-10-04. Coordinator mechanical freeze under the existing approved
NTF transport and pre-configuration amendments; no business rule, permission,
audience, consent or delivery-truth change. No source or test changes in this
declaration. Independent authors may now derive tests from this exact packet.

## Tenant representation clarification

This section clarifies existing frozen wording; it adds no owner decision or
third exception to ADR-033. The serial freeze's source-event cutoff already
names the tenant's Firebase configuration row. AGENTS rule 9 and the closed
tenant-path exceptions in docs/data-model.md remain authoritative.

`public.push_provider_configurations` represents one configuration/activation
row per gym: non-null `tenant_id` references `public.organizations(id)` and is
the primary key (therefore indexed and unique per tenant). Remove the global
boolean singleton key. Preserve `firebase_project_id`, `activated_at` and
timestamps. Enable RLS and retain all direct privileges revoked from PUBLIC,
anon, authenticated and service_role. Do not add ordinary SELECT or DML policy,
synthetic platform organization, global configuration row, or table exception.

The one approved Firebase project and protected Edge credential remain the
provider boundary. Tenant rows describe activation/configuration revisions;
they do not authorize separate projects, credentials or provider endpoints.
Provider-project binding must agree with the protected approved configuration.

Readiness and activation cutoff use the same tenant row. Member/staff commands
derive tenant from complete verified JWT claims. Trusted event creation binds
`p_tenant_id` selected by the SQL scheduler. Reservation selects eligible
tenants itself and filters each candidate against that tenant's configuration;
authorization derives tenant from the durable attempt/reservation pair. No
request accepts a tenant selector. Never make one tenant's activation enable
another tenant or admit its historical events.

A private tenant-parameter readiness helper may serve trusted SQL contexts;
it must have no ordinary EXECUTE. If the existing authenticated zero-argument
readiness seam is retained, it derives its tenant from verified claims and
delegates privately; it must never answer global readiness. Service transport
continues through the three frozen service-only facades, with no configuration
table grant and no new public configuration/readiness facade.

Missing tenant configuration remains provider_unconfigured. Reservations create
no work for an unconfigured tenant; when no configured tenant exists the frozen
empty provider_unconfigured result applies. Mixed tenants may return ready
with work only from configured tenants. Existing terminal unconfigured-era
notifications remain terminal. Source creation retains the tenant activation
cutoff; absent activation cannot enable transport. Replay, start/expiry,
token revision, evidence and notification transition rules do not change.

## Edge mechanical declaration — FROZEN

This section fixes the missing serial mechanics. It grants no deployment,
provider configuration, protected credential access or live acceptance authority.

### Exact testable module boundary

`supabase/functions/push-dispatch/handler.ts` exports only:

```ts
export interface PushDispatchDependencies {
  readEnvironment(name: string): string | undefined;
  fetch: typeof globalThis.fetch;
  now(): number; // epoch milliseconds, only expiry/OAuth timing, never eligibility
  crypto: Crypto;
}
export function createPushDispatchHandler(
  dependencies: PushDispatchDependencies,
): (request: Request) => Promise<Response>;
```

`index.ts` is composition only: bind Deno.env.get, global fetch, Date.now and
global crypto, then Deno.serve the returned handler. No import-time environment
validation or I/O. Handler construction performs no I/O. Injected dependencies
allow independent adapter tests without live provider calls. No domain rule or
audience decision is exported or delegated to Edge.

Central `packages/shared/src/config/env.ts` export:

```ts
export function pushDispatchEnv(
  readEnvironment: (name: string) => string | undefined,
): {
  SUPABASE_URL: string;
  SUPABASE_SERVICE_ROLE_KEY: string;
  PUSH_DISPATCH_SECRET: string;
  FCM_PROJECT_ID: string;
  FCM_SERVICE_ACCOUNT_JSON: string;
};
```

This follows the existing lazy, narrowly scoped accessors and keeps shared
platform-free: no Deno imports/global access, no DOM type or Crypto dependency
in shared. Deno.env is read only through the injected reader passed to this
accessor. Validate only these required names, uncached per invocation. Keep
secret values out of parse/error output. Existing no-show-scan's direct reads,
local numeric constants and upstream-detail responses are historical patterns,
not permission to copy their acknowledged gaps. Register eventual exports and
put every numeric bound/status in shared constants before source implementation.

### Request validation and exact response envelope

Validation precedence: method; required configured wakeup secret; supplied
credential; body/media type/size/shape; remaining provider configuration; OAuth;
claim; individual authorize/send/finish. Missing secret returns configuration
failure before DB/provider I/O. Bad method or credential never reads body or
contacts DB/provider. Authenticate before body parsing.

POST only, `Content-Type: application/json` (optional charset parameter),
streamed body at most 1024 UTF-8 bytes, parsed value exactly an empty object;
arrays, null, scalars, extra keys and malformed JSON fail. Check actual streamed
bytes even when Content-Length is absent or false. No URL/query inputs are
accepted: a nonempty query string fails bad_request. No OPTIONS/CORS exception.

All responses use application/json and Cache-Control: no-store, with no CORS
headers. Envelope exactly:

```text
{ok:boolean,error:null|"method_not_allowed"|"unauthorized"|"bad_request"|
 "payload_too_large"|"configuration_invalid"|"upstream_failed",
 configuration:"ready"|"provider_unconfigured"|null,
 counts:{reserved:number,authorized:number,accepted:number,failed:number,
 uncertain:number,deferred:number}}
```

HTTP mapping: 200 successful bounded invocation (including unconfigured SQL
empty claim); 405 method_not_allowed with Allow: POST; 401 unauthorized;
400 bad_request (including unsupported media type); 413 payload_too_large;
503 configuration_invalid; 502 upstream_failed. Errors before claim have
zero counts and null configuration. Errors after claim retain bounded factual
counts and the known claim configuration. No upstream text/body/status,
identifiers, tokens, reservations, credential values or exception detail.
Unhandled exceptions produce the same upstream_failed envelope.

Counts are nonnegative JSON integers no greater than the claimed batch bound.
reserved counts returned reservations; authorized counts affirmative SQL
authorizations; accepted/failed/uncertain count successfully finalized factual
result classes; deferred counts negative SQL authorizations (including safe
refusals). No successful finish means no finalized count. They are operational
facts, not delivery/receipt/unique-member claims. Stop on configuration/auth
failure; no drain loop, retries or self-scheduling.

### Wakeup comparison and outbound confinement

Dedicated secret must be nonblank; no alternate credential or Auth JWT fallback.
Compare SHA-256 digests of complete supplied/expected UTF-8 values with a fixed
32-byte XOR accumulation and one final equality result; never prefix comparison,
trim, normalize or log either value. Missing header fails unauthorized. This
fixed-length digest comparison avoids content-dependent early exit; it is not
a claim that JavaScript is a formally constant-time execution environment.

The protected configuration must match the approved identities in
firebase-provisioning-packet.md: Supabase origin exactly
`https://pecxrpskmfeuyzngvewq.supabase.co`, Firebase project
`samuraiapi-51996`, and service account
`fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com`.
Reject other origins, embedded credentials, paths, queries or fragments before
transmitting any server credential. The OAuth token endpoint is fixed to
`https://oauth2.googleapis.com/token`; ignore any alternate endpoint supplied
by service-account JSON. No refresh token, topic, condition or device-group
send is introduced. Validate service-account JSON/project/account match
before claiming, obtain short-lived OAuth credentials, and send only to the
FCM HTTP v1 endpoint for that configured project. Fetch redirects use error
mode for OAuth, SQL and FCM; no request-derived URL/host. SQL work remains the
exact three frozen facades with their frozen JSON results. Never guess an
unknown authorization or expired expiry into a provider send. A lost provider
response is uncertain, never an automatic resend.

## Review notes

Tenancy correction requires no owner amendment. Edge export names, 1024-byte
bound, error/count envelope, endpoint identity and digest comparison are frozen
mechanical choices before independent authors start. Exact
Firebase/app identity, protected provisioning/deployment and live gates remain
the existing owner prerequisites. If a global configuration table is insisted
upon instead, it requires a separate owner-approved third-exception ADR before
migration; this document does not approve that alternative.
