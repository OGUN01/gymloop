# v2 owner actions (2026-10-05, revised)

~~Three actions~~ **One action.** The custody statement set turned out to be
impossible from every role the platform exposes (see
`openspec/changes/push-notifications/platform-baseline-custody-amendment.md`
for the evidence) — the pins now freeze the platform baseline instead, so
there is nothing left for you to run. Everything else is agent-side.

## 1. Approve the protected MEDIA deployment (waiting now)

The `media-deploy.yml` run (dispatched 2026-10-05 ~13:40Z) is **waiting on
the `production-media` environment approval**. Open
<https://github.com/OGUN01/gymloop/actions> → the waiting "Protected MEDIA
Edge deployment" run → **Review deployments** → tick `production-media` →
**Approve and deploy**. It provisions the R2 secrets and deploys the `media`
Edge function (`--use-api`, no Docker). Until it lands, media/photo uploads
fail on device; everything else is testable.

## 2. ~~Operator custody statement~~ — cancelled, nothing to run

The revokes need a superuser; Supabase Cloud reserves `supabase_admin`
membership and the dashboard SQL editor connects as `postgres` like the CLI.
The pgTAP pins were re-scoped to freeze the platform baseline (no widening),
which is achievable and already verified. If hardening beyond the platform
baseline is ever wanted, it goes through Supabase support as a superuser
change — the suites record the exact baseline to tighten.

Both Edge functions verified live 2026-10-05: `media` refuses unauthenticated
calls (403, JWT-verified), `no-show-scan` refuses with
`{"ok":false,"error":"CRON_SECRET is not configured"}` — the designed guard.
That last one has a small owner step when the nightly scan should go live:
set `CRON_SECRET` in the project's function secrets (Dashboard → Edge
Functions → no-show-scan → Secrets) with a strong random value — the
function refuses to serve until it is set, by design, because a scheduled
job with a public URL is a public URL.

## 3. The Play Console release (after device verification)

Per `docs/planning/v2-device-testing-handoff.md`: the release build uses the
same recipe with app id `in.fitcruxx.app` (Play app `4975754557722576970`,
Ductx account `7649203845150858113`). Closed-test track, ≥12 testers opted in
14 consecutive days before production. Still owed: support email, FCM
restricted server access key, Meta/DLT WhatsApp activation (deferred by
decision), legal sign-off.
