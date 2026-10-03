# NTF pre-configuration amendment — APPROVED (owner, 2026-10-03)

The owner approved the NTF transport amendment and directed this scoped
amendment: NTF tests and implementation proceed **before** Firebase
configuration is supplied. Missing configuration must fail closed; deployment
and live acceptance still require the approved Firebase project, Android
application registration and protected credentials.

## What is authorized now

- Independent visible and holdout authors, the separate implementer and fresh
  critics work against the frozen NTF contract (proposal + transport
  amendment + `v2-batch2-shared/wave-c-serial-freeze-declarations.md`).
- The CI-applied migration creates tables, amendments, RPCs, facades, grants
  and the SQL cron driver **in a disabled/inert state**: no `pg_cron` job is
  enabled, no Vault secret is read, no Edge function is deployed by the
  migration, no provider call is possible.
- The `supabase/functions/push-dispatch/` adapter source exists and passes
  Deno checks; it is not deployed or configured.

## Fail-closed behavior without configuration (pinned)

- `public.reserve_push_attempts` returns
  `{attempts:[],configuration:"provider_unconfigured"}` and creates no
  attempt/reservation, exactly as dec3278 pins for a missing configuration
  revision. No `pg_cron` job exists to wake the adapter, so no transport
  request occurs.
- Member device registration, preferences, settings and acknowledgement RPCs
  work fully — they never touch the provider. A member may register a device
  that cannot yet receive anything; this is honest inert state, not a
  delivery claim.
- `send_notification` keeps the existing `failed/provider_unconfigured`
  terminal behavior for push rows while the configuration revision is absent;
  an unconfigured-era notification is never revived when configuration later
  arrives (dec3278 rule preserved).
- In-app inbox/feed truth is unaffected (NTF-001).

## Still owner-gated (unchanged)

Protected CI provisioning of `PUSH_DISPATCH_SECRET` / `FCM_PROJECT_ID` /
`FCM_SERVICE_ACCOUNT_JSON`, the exact approved Firebase project identity,
Android application registration, enabling the cron job, deploying
`push-dispatch`, and every live-acceptance gate in the proposal's acceptance
section. Mock/static green tests close code gates only; the provider live
gate stays BLOCKED until real configuration and observed dispatch exist.

## Test-author consequence

Visible and holdout suites test the unconfigured path as the default
configuration state and pin the fail-closed outcomes above. Configured-path
behavior is tested as SQL state (configuration revision rows present), never
by touching a real provider; the provider adapter is outside SQL test scope.
