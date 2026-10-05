# v2 owner actions (2026-10-05)

Three actions only you can perform. Everything else is agent-side and in
flight. Run them in this order.

## 1. Approve the protected MEDIA deployment (waiting now)

The `media-deploy.yml` run (dispatched 2026-10-05 ~13:40Z) is **waiting on
the `production-media` environment approval**. Open
<https://github.com/OGUN01/gymloop/actions> → the waiting "Protected MEDIA
Edge deployment" run → **Review deployments** → tick `production-media` →
**Approve and deploy**. It provisions the R2 secrets and deploys the `media`
Edge function (`--use-api`, no Docker). Nothing else moves until this lands.

## 2. Run the operator custody statement set (dashboard SQL editor)

Open the Supabase dashboard for project `pecxrpskmfeuyzngvewq` → **SQL
Editor** (this runs as `supabase_admin`, which is the only role allowed to
change extension-owned ACLs — the CI apply role is `postgres`, which the
push-scheduler migration proved cannot). Paste and run the statement set in
`scratchpad/operator-push-custody.sql` in one go. It revokes:

- Vault secret/decrypt EXECUTE from `service_role` (A39)
- pg_net enqueue/inspection EXECUTE from PUBLIC (A40)
- pg_cron scheduling EXECUTE from PUBLIC (A41)
- SELECT on `vault.secrets`, `vault.decrypted_secrets`,
  `net._http_response`, `cron.job` from the ordinary roles (A42–A45)
- residual schema USAGE (`vault` from `service_role`, `net` from all three)

and re-grants `net.http_post` / `net.http_collect_response` to `postgres`
(the definer-owned push enqueue helper would otherwise break). Two of its
eight revokes (`vault` schema usage, `net` schema usage) failed as
"permission denied" only because the session role was not `supabase_admin` —
the dashboard session has it.

After this lands, the next pgTAP sweep flips h84 A39–A46 and the 84 PSD-007
pins green. **Do not schedule the `push-dispatch-minute` cron job yet** —
activation stays a separate owner decision after device testing.

## 3. The Play Console release (after device verification)

Per `docs/planning/v2-device-testing-handoff.md`: the release build uses the
same recipe with app id `in.fitcruxx.app` (Play app `4975754557722576970`,
Ductx account `7649203845150858113`). Closed-test track, ≥12 testers opted in
14 consecutive days before production. Still owed: support email, FCM
restricted server access key, Meta/DLT WhatsApp activation (deferred by
decision), legal sign-off.
