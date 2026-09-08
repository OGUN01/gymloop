# The Razorpay half: what exists, what is blocked, and exactly what unblocks it

The owner's instruction for Phase 5 was two first-class payment paths — Razorpay
**and** manual recording at the desk, with manual explicitly *not* a fallback —
and, where test credentials do not exist, to build everything up to the point
they are required and **leave a clearly-named gap rather than faking them**.

This is that gap, named.

## What is built, and provably works without any credential

The database half of the online path is complete and was exercised as
`service_role` — the role a Razorpay webhook will run as — through every rule
Phase 5 added, inside `begin … rollback` against Cloud:

| | Result |
|---|---|
| An online payment recorded with `provider`, `provider_order_id`, `provider_payment_id` and the provider's own `paid_at` | accepted — the claim rules carve out trusted callers precisely so this works |
| A receipt number allocated to that online payment | `2026-27/000001` |
| The membership extended by it | `ends_on` moved a full period |
| A provider-initiated reversal (`paid → refunded`) | accepted |
| The same provider event id delivered twice | exactly **one** `webhook_events` row; the second refused `23505` |
| Rewriting the recorded amount, as `service_role` | refused `GL038` |
| Reviving a refunded payment, as `service_role` | refused `GL039` |

The last two matter most: the rules that stop a front desk rewriting money stop
the webhook too. A webhook bug cannot silently restate what a gym was paid.

**This is the roadmap's stated Phase 5 exit criterion** — *"Payment state machine
complete; duplicate webhook delivery changes nothing"* — met, with no Razorpay
account in existence.

Also already in place, and not blocked:

- `webhook_events` carries `UNIQUE (tenant_id, provider, event_id)` and **no
  write policy at all**, so only the service key can write it. Idempotency of
  delivery is structural, not a code path somebody must remember.
- `payments_tenant_id_provider_provider_payment_id_key` makes a provider payment
  id unique per gym.
- `razorpay_accounts` and `razorpay_mandates` exist from Phase 1 with their
  policies.
- `supabase/functions/**` is typechecked by `deno check` in **two** places —
  `ci.yml`'s `deno-check` job and `functions.yml`'s deploy job — so webhook code
  cannot land untypechecked. That gap was closed deliberately *before* any money
  code, and this is the reason.
- `.github/workflows/functions.yml` deploys Edge Functions on push and is
  verified working. The webhook arrives into a pipeline that already runs
  rather than bringing its own deployment story.

## What is blocked, and why it is not faked

Three things need a real Razorpay account and are **not** written:

1. **Signature verification** (`gate 20`: *webhook signature verified per gym
   before any state change*). The algorithm is not the hard part —
   `HMAC-SHA256(raw_body, webhook_secret)` compared against
   `X-Razorpay-Signature`. What cannot be built honestly without credentials is
   the evidence that it is right: a known-good payload and signature pair
   produced by Razorpay itself. **A signature check verified only against
   signatures I generated with the same code I am testing proves nothing** — it
   is a checker tested in one direction, which is the exact failure ADR-078 is
   named for and which cost this project six red commits believing itself green.
2. **Order creation**, which needs `key_id`/`key_secret` to call Razorpay's API.
3. **Per-gym key storage in Supabase Vault** (`gate 19`), which needs keys to
   store.

A stub for any of these would be worse than their absence. A stubbed signature
verifier that returns `true` is a security control that exists in the file tree
and nowhere else — and this project's single most repeated defect, recorded four
separate times (ADR-070, ADR-071, ADR-074, ADR-081), is **documentation
asserting a capability the system does not have**. A fake would be that defect
committed deliberately.

## What unblocks it

One thing: a Razorpay **test-mode** account, which is free and needs no company
verification. From it:

- `key_id` and `key_secret` (test mode) → `.env.local`, then Vault per gym.
- A webhook secret, set on the endpoint in the Razorpay dashboard → the Edge
  Function's secrets, alongside `CRON_SECRET`.
- **At least one captured webhook payload with its signature header**, taken
  from the dashboard's webhook log. This is the piece that matters and the one
  easiest to forget: it is what lets the signature check be verified in the
  direction that counts — a payload Razorpay signed, which our code must accept,
  and the same payload with one byte changed, which it must refuse.

With those, the remaining work is small and its shape is already fixed by what
exists: an Edge Function that verifies the signature, writes `webhook_events`
(where the unique index makes redelivery a no-op), and then moves the payment's
status along the edges `app.payment_transition_allowed` already permits. Every
rule it must obey is already enforced by the database and already tested.

## The one rule the online path will meet on its first day

`OPEN-020`. `app.enforce_payment()` refuses any row where `method = 'razorpay'`
or a provider column is non-null, on INSERT and UPDATE, for every session row
security applies to (`GL035`). That is correct — online state is the provider's
to report (PAY-006) — and it also means the console cannot let a manager add a
note to an online payment, ever. Harmless today because no online payment
exists. It should be decided when the webhook lands, not discovered: either the
writable columns are exempted from the provider rule, or the console never
offers them for online rows.
