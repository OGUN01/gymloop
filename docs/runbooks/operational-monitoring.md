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
