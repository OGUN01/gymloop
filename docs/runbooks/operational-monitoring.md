# Operational monitoring and escalation

This is the HARD-005 operating contract for redacted application errors and
security/availability events. It names intended alert rules, owners, escalation
and retention. It is **not** evidence that a monitoring provider or pager is
configured: the 2026-09-21 production inspection found no live destination,
alert route, delivered event or receipt. Gate 28 remains Partial/External.

## Event boundary

- Emit only structured events through `createOperationalLogger`; pass a stable
  event name, the permitted tenant and correlation identifiers when available,
  and minimal contextual fields. Never log raw request bodies, tokens, cookies,
  provider signatures, email, phone or full member names. Do not put secrets or
  personal data in free-text `message`, event names, tenant or correlation IDs:
  the adapter redacts **context keys**, not those top-level strings.
- The structured sink and optional reporting adapter receive the same event.
  Adapter failures must not change the user-facing response. The provider
  destination is external until an actual delivery ID is captured.
- Production responders should be able to join an error to its deployment and
  request without copying personal data into an alert or ticket.

## Alert policy to configure and verify

These are engineering thresholds, not a claim that an alert currently fires.
The production owner must record the provider's actual rule IDs, evaluation
windows and test receipts before marking them operational.

| Signal | Intended trigger | Severity and initial owner |
|---|---|---|
| Credible cross-tenant disclosure, payment-integrity failure, exposed credential or destructive data loss | Any one confirmed or credible event | SEV-1; on-call Technical Lead immediately pages Incident Commander and Privacy Lead. |
| API 5xx failures | At least five in five minutes, or above 1% of at least 100 requests in five minutes | SEV-2; on-call Technical Lead investigates within 30 minutes; escalate to Incident Commander if ongoing or customer-impacting. |
| Auth/check-in unavailable | Three consecutive synthetic checks fail, or a real customer report confirms the core loop is unavailable | SEV-2; on-call Technical Lead investigates within 30 minutes, and elevates to SEV-1 if broad or prolonged. |
| Repeated policy denial or suspicious provider callback | Five related denials in five minutes for one route/tenant, after excluding expected user errors | Security triage by Technical Lead; Incident Commander decides whether SEV-2/SEV-1 applies. |

The `docs/runbooks/incident-and-breach.md` severity and checkpoint rules govern
incident response after declaration. Do not treat an alert count alone as a
confirmed disclosure or legal notification trigger.

## Ownership, escalation and evidence

The production owner must assign **named people and tested out-of-band contact
routes** for on-call Technical Lead, Incident Commander, Privacy Lead and
backup responders before launch. Until then, the role names above are procedure
owners, not a working pager. If the first responder cannot acknowledge a SEV-1
within 15 minutes or SEV-2 within 30 minutes, the backup Technical Lead and
Incident Commander are contacted using the tested route. Keep actual contact
details in the protected on-call roster, not this public repository.

Record one controlled, redacted test event's provider event ID, received time,
alert rule ID, notification receipt, acknowledging person/time, escalation
route, and deployment commit in the Phase 8 ledger. A local mock or a Vercel
console line is not proof that the alert was delivered.

The intended operational retention is 30 days for redacted routine events and
90 days for alert/incident metadata; incident evidence under a recorded legal
hold follows the hold, not this deletion target. The production owner and
Privacy Lead must approve and verify actual provider retention/access settings
against the final privacy contract. No claim is made that these durations are
currently enforced, legally sufficient, or applicable to unredacted backups.

## Read-only preflight and current status

The following bounded inspection was performed on 2026-09-22 against the
configured Gymloop project. It made no Vercel, GitHub or Supabase mutation and
did not read or print secret values:

- Vercel lists the `gymloop` project and recent production deployments as
  ready. That proves deployment availability only; it is not evidence of an
  alert route or delivered notification.
- The production environment-variable name list contains the application URL
  and Supabase browser configuration only. No monitoring destination, alert
  webhook or pager configuration is present in Vercel's project environment.
- GitHub has the normal build/database/function workflows, but no monitoring
  workflow or notification receipt. A green CI run is not an operational
  alert test.
- Supabase lists project `pecxrpskmfeuyzngvewq` as the linked, healthy
  `gymloop` project. The inspection did not query or mutate application data.
- At 2026-09-22T06:44:47Z, Vercel's read-only alert listing returned zero
  alert groups and one default rule (`ar_default`) with an empty
  `notifications` array. The rule's owner/project-admin autosubscribe flags do
  not reveal an email address or prove that a notification was delivered.
  The CLI exposes rule creation, but no rule was created in this inspection.

This leaves HARD-005 **Partial/External**. Do not change that status based on
deployment readiness, a local logger test, a console log, or a synthetic event
that has no provider receipt.

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

## Completion checklist for the production owner

HARD-005 can move beyond Partial/External only after all of the following are
attached to the Phase 8 ledger:

1. The selected provider and destination are named, with the provider rule IDs,
   evaluation windows and retention/access settings captured without secrets.
2. A controlled, redacted test event is emitted through the production logger
   on an owner-approved target (or an explicitly designated non-production
   target), and its provider event ID and received time are recorded.
3. The notification receipt identifies the destination, alert rule, recipient
   and acknowledgement time. A provider event visible only in a dashboard is
   not a receipt.
4. A named on-call Technical Lead, Incident Commander, Privacy Lead and backup
   responder have each tested the out-of-band route. Keep their contact details
   in the protected roster, not this repository.
5. The deployment commit, redacted event identifier, acknowledgement,
   escalation result and cleanup/retention outcome are cross-checked by the
   production owner and Privacy Lead.

Until every item exists, leave the route unconfigured or partially evidenced
and keep the launch stop line in `docs/gates.md` and the Phase 8 ledger.

The exact next action is an owner-authorized configuration change: in Vercel
Observability → Alerts (or the equivalent `vercel alerts rules add` workflow),
choose the approved destination and create the rule for the Gymloop project.
Before doing so, the owner must confirm the team billing/role permits alert
rule creation and identify the protected owner email or out-of-band route.
After creation, record the rule ID and destination category, then perform the
controlled redacted test and collect the provider receipt described above.
