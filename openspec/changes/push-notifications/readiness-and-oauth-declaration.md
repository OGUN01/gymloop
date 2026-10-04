# NTF readiness seam and OAuth refusal declaration — FROZEN

2026-10-04. Serial mechanical completion of
serial-tenancy-and-edge-mechanics.md. The visible author paused the unresolved
SQL behavior and OAuth credential-error assertion before this declaration.
No audience, consent, scheduling cutoff, permission or delivery rule changes.

## Exact private readiness seam

`app.push_configuration_ready(p_tenant_id uuid) returns boolean` is STABLE,
postgres-owned SECURITY DEFINER, with an empty search path. Revoke effective
EXECUTE from PUBLIC, anon, authenticated and service_role; trusted private
postgres-owned command/scheduler bodies can call it. It returns false for a
null or absent tenant configuration. A matching tenant row is ready only with
the approved `samuraiapi-51996` project and a non-null activation instant at or
before the server statement time. No table grant or public facade is added.

Retain `app.push_configuration_ready() returns boolean` solely for existing
authenticated invoker/guard composition. It is STABLE, postgres-owned SECURITY
DEFINER, empty search path, authenticated EXECUTE only. It derives the tenant
from existing JWT claim accessors and delegates to the private overload. A
complete ordinary member or staff claim is required; mixed, missing, platform
or impersonation claims return false. It accepts no tenant parameter and
grants no operation authority. Existing command actor/account/eligibility
checks remain the authority before writes or provider work.

Trusted event creation uses its SQL-selected `p_tenant_id`; transport
reservation filters each SQL-selected candidate tenant, and authorization
uses the durable attempt tenant. Readiness and source activation cutoff must
refer to that same tenant row. One configured gym cannot enable another gym
or its historical events. The frozen configuration table grants, global
empty-unconfigured result and terminal unconfigured-era notifications remain.

## OAuth failure classification

Before any work claim, missing/mismatched/invalid service-account configuration
or an unusable private key returns HTTP503 `configuration_invalid`. OAuth
HTTP401/403 or an explicit `invalid_grant`/`invalid_client` response returns
the same configuration failure and stops without any SQL claim. Network
failure, HTTP5xx, malformed success or unusable access-token result returns
HTTP502 `upstream_failed` and likewise creates no work claim. Other rejected
OAuth HTTP results fail as `upstream_failed`; never retry or disclose the
upstream body. Preserve the fixed no-store count-only envelope with zero
counts and null configuration before claim.

`private_key_id` is optional for the service-account OAuth assertion; no
requirement to disclose or require it is added. The configured approved
project/account, valid private key and fixed OAuth audience/scope remain
required. Private keys and access tokens never enter a response, audit,
receipt, artifact or log.
