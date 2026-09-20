# Incident and breach response

This runbook is the operational procedure for HARD-007. It is not legal advice.
Any regulator, law-enforcement, affected-person or contractual notification
deadline and message must be confirmed against current law and the applicable
Data Processing Agreement by qualified legal/privacy review at incident time.

## Roles

- **Incident Commander:** declares severity, owns the timeline and authorizes
  containment and recovery.
- **Technical Lead:** preserves evidence, identifies affected systems/tenants,
  contains the event and validates recovery.
- **Privacy Lead:** classifies exposed data, coordinates Data Fiduciary gym(s),
  obtains current legal advice and records notification decisions.
- **Communications Lead:** prepares consistent internal, gym and public updates;
  sends nothing externally without Incident Commander and Privacy Lead approval.
- **Evidence Custodian:** maintains the append-only incident record, access list,
  artifact hashes and decision log.

Record the person assigned to each role in the incident record; this repository
does not invent names, phone numbers or addresses. The production owner must
maintain tested out-of-band contact routes for these roles before launch.

## Internal severity and checkpoints

| Severity | Trigger | Initial internal target |
|---|---|---|
| SEV-1 | Confirmed or credible cross-tenant disclosure, credential compromise, destructive loss, payment-integrity failure or broad outage | Declare immediately; first checkpoint within 15 minutes |
| SEV-2 | Material single-tenant exposure/outage or repeated security refusal with contained scope | First checkpoint within 30 minutes |
| SEV-3 | Degraded service or suspicious event with no confirmed disclosure/integrity loss | Triage during the active support window |

These are internal response targets, not statutory notification periods.

1. **T+0:** open an incident identifier, assign roles, record who declared it,
   current UTC time, suspected start time and why the severity was chosen.
2. **T+15 (SEV-1) / T+30 (SEV-2):** preserve volatile evidence, bound known
   tenants/data/systems, choose reversible containment and record the decision.
3. **T+30 / T+60:** Privacy Lead records whether personal data may be involved,
   which gym Data Fiduciaries are affected and whether current legal advice is
   required before any external notice.
4. **Every 60 minutes while active:** record scope changes, containment state,
   customer impact, next decision owner and next checkpoint. Silence is not a
   status update.
5. **Recovery checkpoint:** Technical Lead supplies validation evidence;
   Incident Commander explicitly authorizes restoration of normal operation.
6. **Within two business days of closure:** hold a no-blame review, assign every
   corrective action an owner/evidence target, and link it from the incident.

## Response procedure

### Detect and preserve

- Record the original alert/report exactly, without copying secrets or full
  personal records into chat or tickets.
- Preserve relevant structured logs, deployment/build identifiers, database
  audit references, request correlation ids and cloud-control events. Restrict
  raw evidence to responders who need it.
- Hash exported artifacts with SHA-256 and record collection time, collector,
  source, storage location and access list. Never alter an original artifact;
  investigate a copy.
- Do not clear logs, rotate data destructively or restore a database merely to
  inspect it. Credential rotation is containment, but record what was rotated,
  by which control and when.

### Contain and investigate

- Revoke the narrowest affected sessions/credentials, disable the affected
  path or isolate the affected tenant/service. Prefer reversible controls.
- Never weaken RLS, money verification or audit rules to restore availability.
- Establish: first known event, discovery time, affected tenant ids, data
  categories, approximate record count, actors, systems, geographic scope,
  whether access/exfiltration/modification is confirmed, and confidence level.
- Treat logs and member data as evidence; minimize further copies and redact
  unnecessary email, phone, full name, credentials and tokens.

### Decide notifications

- The Privacy Lead coordinates each affected gym as Data Fiduciary and Gymloop
  as Data Processor, following the current DPA and legal advice.
- Before sending any notification, record the legal reviewer or authoritative
  current source, required audience, required timing, approved channel, message
  owner and approval time. If those are unavailable, mark the decision
  **External — legal confirmation required**, not complete.
- Candidate channels are the contractually registered gym contact route,
  authenticated in-product notice, verified email/SMS provider, status page and
  the channel required by an authority. Availability is not authorization.
- Include only verified scope, protective action and contact path. Do not guess
  cause, record count, deadline or impact.

### Recover and close

- Remove the cause, rotate exposed credentials, deploy only reviewed changes,
  and validate identity, tenant isolation, money integrity and audit evidence.
- Use `docs/runbooks/backup-and-restore.md` if recovery requires restore. A
  production restore needs its own approval and evidence.
- Monitor for recurrence for a duration chosen and recorded by the Incident
  Commander. Close only when containment, recovery, notification decisions and
  follow-up owners are recorded.

## Required evidence record

Every incident record contains: incident id; severity; UTC timestamps; assigned
roles; reporter/source; affected environment, commit/build and tenant ids;
data categories and estimated records; timeline; correlation/audit ids;
containment/recovery actions and approvals; artifact paths plus SHA-256 hashes;
notification decision, current legal authority/reviewer and approved channels;
residual risk; closure approval; and follow-up owner/due evidence. Secrets and
unnecessary personal data are referenced through restricted evidence, never
copied into the ledger.

## Current external readiness gap

Owner: production owner. Action: assign tested role contacts and obtain current
legal/privacy confirmation of DPA, notification audiences, channels and timing.
Evidence required: approved contact roster location, dated legal/DPA decision
and one tabletop exercise record. Until attached, legal notification readiness
is **External**, not passed.
