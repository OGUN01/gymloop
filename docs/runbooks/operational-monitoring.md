# Operational monitoring and escalation

This is the HARD-005 operating contract for redacted application errors and
security/availability events. GitHub Issues in `OGUN01/gymloop` is the selected
destination for `.github/workflows/phase8-production-monitor.yml` (ADR-161).
Controlled run `35764265002` delivered closed TEST-only issue `#4` at
2026-09-22T18:00:31Z. The replacement team-scoped Vercel CLI token then
completed manual workflow run `35828518944` and delivered closed TEST-only
issue `#5`. A second manual production evaluation, `35842057167`, passed on
2026-09-23 after the new check-in deployment. Earlier scheduled runs
`35798267364` and `35807766246` failed
before evaluation with the old token. The destination and credential work in
the controlled run, but the scheduled route has not yet shown five-minute
continuity; HARD-005 and gate 28 remain Partial/External.

The cron expression requests an evaluation every five minutes; GitHub does not
guarantee that delivery interval. The first observed scheduled starts were
2026-09-22T21:13:10Z, 23:37:00Z and 2026-09-23T01:47:49Z, leaving gaps far
longer than the five-minute log window. [GitHub's schedule-event guidance](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#schedule)
explicitly permits delayed or dropped jobs. Do not claim five-minute detection
coverage until a scheduler with measured continuity and missing-run alerting is
in place; a valid token alone does not close this gap.

The `gymloop-phase8-monitor-dispatch` Cloudflare Worker is prepared as the
second trigger. Its intended sole Cron is `*/5 * * * *`; it has no public HTTP
handler.
It dispatches `.github/workflows/phase8-production-monitor.yml` on `main` with
`force_test_alert=false` and accepts only GitHub HTTP 204. Its GitHub fine-grained
token must be restricted to the `OGUN01/gymloop` repository, Actions write, and
stored as the Worker secret `GITHUB_ACTIONS_DISPATCH_TOKEN`. The existing GitHub
schedule stays enabled. Set the secret with `wrangler secret put
GITHUB_ACTIONS_DISPATCH_TOKEN --config wrangler.phase8-monitor.jsonc`, then
deploy with `wrangler deploy --config wrangler.phase8-monitor.jsonc`; the
configuration requires that secret. Inspect real
Cloudflare Cron Past Events and matching GitHub workflow runs for consecutive
five-minute windows. Failed dispatches throw generic errors to Cloudflare logs.
No continuous cadence or missing-run alert is claimed before those observations
and an exercised escalation route are recorded.

On 2026-09-23 the dedicated Worker was created and the reviewed handler was
deployed as active version `55e0288a`. Its `workers.dev` production and preview
URLs were disabled. No Cron trigger or GitHub credential is installed yet, so
this deployment produces no scheduled monitor runs. GitHub's account
verification step must complete before a repository-only Actions-write token
can be created and stored as the Worker secret.

## Event boundary

- Emit only structured events through `createOperationalLogger`; pass a stable
  event name, the permitted tenant and correlation identifiers when available,
  and minimal contextual fields. Never log raw request bodies, tokens, cookies,
  provider signatures, email, phone or full member names. Do not put secrets or
  personal data in free-text `message`, event names, tenant or correlation IDs:
  the adapter redacts **context keys**, not those top-level strings.
- The structured sink and optional reporting adapter receive the same event.
  Adapter failures must not change the user-facing response. The scheduled
  monitor copies only whitelisted evidence into GitHub and never stores the raw
  Vercel log response or endpoint body as an artifact.
- Production responders should be able to join an error to its deployment and
  request without copying personal data into an alert or ticket.

## Alert policy implemented in code

| Signal | Intended trigger | Severity and initial owner |
|---|---|---|
| Credible cross-tenant disclosure, payment-integrity failure, exposed credential or destructive data loss | Any one confirmed or credible event | SEV-1; on-call Technical Lead immediately pages Incident Commander and Privacy Lead. |
| API 5xx failures | At least five production 5xx responses in the inclusive preceding five minutes | SEV-2; Technical Lead investigates within 30 minutes; escalate to Incident Commander if ongoing or customer-impacting. |
| Auth/check-in unavailable | The latest three production `/sign-in` endpoint probes fail consecutively | SEV-2; Technical Lead investigates within 30 minutes, and elevates to SEV-1 if broad or prolonged. |

The `docs/runbooks/incident-and-breach.md` severity and checkpoint rules govern
incident response after declaration. Do not treat an alert count alone as a
confirmed disclosure or legal notification trigger.

## Ownership, escalation and evidence

The `OGUN01` account is the proposed primary pilot recipient for GitHub Issues.
Assign the actual Technical Lead, Incident Commander and Privacy Lead in a
protected roster, then record a real acknowledgement and tested escalation
route. If a SEV-1 is not acknowledged within 15 minutes or a SEV-2 within 30
minutes, stop new onboarding and the core-loop write path until the owner has
reviewed the issue. Contact details belong in the protected roster, not this
public repository.

The delivery receipt is workflow run `35764265002`, deployment
`dpl_AU4cuvWZKZksR8xazboZsonmDN9F`, source commit `167c806`, log query
`vercel-35764265002-1`, endpoint probe `health-35764265002-1`, and closed
test-only issue `#4`. The test carried no production severity or
`production-alert` label.

The workflow persists no routine event body. Closed test receipts and real
alert/incident issue metadata are reviewed for deletion after 90 days; evidence
under a recorded legal hold follows the hold. Vercel's plan-controlled raw-log
retention is not extended or copied by this workflow.

## Provider preflight and current status

The following bounded inspection was performed on 2026-09-22 against the
configured Gymloop project. It made no Vercel, GitHub or Supabase mutation and
did not read or print secret values:

- Vercel lists the `gymloop` project and recent production deployments as
  ready. That proves deployment availability only; it is not evidence of an
  alert route or delivered notification.
- The production environment-variable name list contains the application URL
  and Supabase browser configuration only. No monitoring destination, alert
  webhook or pager configuration is present in Vercel's project environment.
- GitHub now has the scheduled production monitor and the real closed delivery
  receipt described above. A green CI run remains separate from an operational
  alert test.
- Supabase lists project `pecxrpskmfeuyzngvewq` as the linked, healthy
  `gymloop` project. The inspection did not query or mutate application data.
- At 2026-09-22T06:44:47Z, Vercel's read-only alert listing returned zero
  alert groups and one default rule (`ar_default`) with an empty
  `notifications` array. The rule's owner/project-admin autosubscribe flags do
  not reveal an email address or prove that a notification was delivered.
  The CLI exposes rule creation, but no rule was created in this inspection.

Vercel rejected custom alert-rule creation for the current account scope. That
rejection is not represented as a Vercel alert. The GitHub workflow is the
selected destination. One TEST receipt proves delivery in that run only; the
later scheduled failures prevent an operational claim.

[Vercel's current Alerts documentation](https://vercel.com/docs/alerts)
limits built-in anomaly alerts to Enterprise or Pro with Observability Plus.
The presence of the default rule in CLI output is therefore not proof that
this account has an entitled, delivering alert service. Before choosing it,
verify the actual project/team plan and feature entitlement without purchasing
an upgrade. If unavailable, select another approved destination and exercise
its real delivery path; do not create a decorative Vercel rule and call the
monitoring gate green.

For a repeatable preflight, an operator may list Vercel environment *names*
and deployments, list GitHub workflow runs, and list Supabase projects. Do not
run `vercel env pull`, print environment values, copy tokens into tickets, or
use a production endpoint to manufacture a failure. Record the date, target
project and the result category (configured / absent / inaccessible), never
the secret itself.

## Completion checklist

1. **Implemented:** GitHub Issues destination, five-minute evaluation windows
   and least-privilege workflow permissions; 90-day issue-metadata review is a
   proposed process, not an enforced retention setting.
2. **Observed once:** controlled run `35764265002` queried the real production
   deployment, made three endpoint probes and delivered closed TEST-only issue
   `#4`. It did not prove sustained scheduled collection.
3. **Done for manual monitoring:** the team-scoped Vercel token completed run
   `35828518944` and delivered closed TEST-only issue `#5`. Scheduled cadence
   still needs live proof; the unused project token awaits revocation.
4. **Open:** install the repository-restricted GitHub dispatch token as a
   Cloudflare Worker secret, deploy the Cron-only Worker, and record consecutive
   real Cron events paired with completed workflow runs. Exercise a missed-run
   or dispatch-failure escalation before claiming five-minute coverage.
5. **Open:** record an actual responder acknowledgement, protected role roster,
   escalation path and retention/access review. Keep tokens out of logs and
   command arguments.
