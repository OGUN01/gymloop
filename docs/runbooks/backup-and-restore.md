# Backup and restore

This runbook supports HARD-007 and production gate 29. Reading backup status is
safe; initiating a restore, replacing a database or redirecting an application
is destructive. No restore is authorized by this document alone.

## Safe read-only review

The production owner or platform operator may perform these checks without
changing data:

1. Confirm the selected Supabase project id/reference and environment label.
   The Gymloop production project reference is recorded in `AGENTS.md`; stop if
   the cloud control shows a different project.
2. In the Supabase cloud dashboard, inspect the backup/PITR page without
   starting a restore. Record whether backups and PITR are enabled, the latest
   successful recovery point displayed, retained recovery window and any failed
   job or warning.
3. Record UTC observation time, operator role, project reference, dashboard
   page/control, screenshot or exported control event, and the applicable plan.
   Do not put database passwords, access tokens or member data in the evidence.
4. Confirm the evidence is fetchable by the production owner and link it from
   `docs/evidence/phase8/ledger.md`.

This review proves only that a cloud control reports backup availability. It is
not a restore drill and does not satisfy gate 29.

## Destructive restore drill — approval boundary

A drill must use a disposable, access-restricted recovery project/environment,
never the live project. Before any restore:

- **Incident Commander or production owner** approves the recovery point,
  target project and data-handling period in writing.
- **Platform operator** records both source and target project references and
  positively verifies they differ. If the target is production or its identity
  is uncertain, stop.
- **Privacy Lead** approves use of production-derived personal data or requires
  a sanitized backup; access and deletion expectations are recorded.
- **Evidence Custodian** opens a drill id and records the operators, UTC start,
  source recovery point, target, expected RPO/RTO and rollback/cleanup plan.

## Restore and validation procedure

1. Start the Supabase cloud restore/PITR operation only through the approved
   cloud control and only into the recorded disposable target.
2. Record the provider operation/event id and every state transition. Do not
   report success from a local SQL import or mock provider response.
3. Keep application traffic away from the recovery target. Configure only
   dedicated test credentials and never copy a service-role key into a client.
4. After the provider reports completion, perform read-only validation:
   expected schema/migration identity; generated-type compatibility; bounded
   table counts; one known audit/payment/attendance reference; tenant-isolation
   checks from separate test sessions; and one non-mutating application smoke.
5. Record actual recovery-point loss and elapsed recovery time against the
   expected RPO/RTO. A provider-complete state without validation is a failure.
6. Revoke drill credentials, delete or securely quarantine the recovery target
   according to the approved data-handling plan, and record cleanup evidence.
7. The Incident Commander/production owner signs the outcome as Passed or
   Failed and assigns corrective actions. Never redirect production to the
   restored target as part of this drill.

## Evidence fields

Drill id; source and target project references; proof they differ; approvers;
operator roles; UTC start/end; selected recovery point; provider operation id;
plan/backup/PITR state; expected and actual RPO/RTO; exact validation procedure
and result; build/schema identity; artifact locations and SHA-256 hashes;
tenant-isolation outcome; cleanup/revocation proof; final disposition; and
follow-up owner.

## Current status

**External / unperformed.** No Supabase cloud PITR restore drill has been
performed or attached for Phase 8. Owner: production owner with a Supabase
project administrator. Required action: confirm the subscribed backup/PITR
capability and run the approved disposable-target drill. Required evidence:
cloud control/operation id, source and distinct target references, timestamps,
validation results, artifact hashes and cleanup. Until that exists, gate 29 is
not green.

The 2026-09-21 CLI control inspection found no available physical backups and
PITR disabled on the current free project; see the Phase 8 evidence ledger.
Before customer data relies on this project, establish a protected off-site
logical-export destination, recovery ownership and retention/access rules. Do
not place an unencrypted dump in the repository or treat an export as proof of
a successful restore drill.
