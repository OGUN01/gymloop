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

## Free-project logical recovery track for the five-gym pilot

The owner has selected the existing shared project for a controlled five-gym
pilot and deferred a paid plan. [Supabase's backup guidance](https://supabase.com/docs/guides/platform/backups)
states that Free projects have no automatic database backup/PITR and recommends
regular off-site CLI exports. This is a possible **additional** recovery track,
not evidence that the cloud/PITR drill above passed and not permission to
restore over the live project.

Before the first customer record is accepted, the production owner must:

1. Repair and verify the CLI database credential without printing it in a
   command, dry-run output, shell transcript or evidence file. Record a
   successful connection and the linked project reference; the currently
   failing CI migration job makes this a release stop line.
2. Select an encrypted, access-controlled, off-device/off-project destination
   with an identified recovery operator, key custodian, retention period and
   scheduled export cadence. A local file or the same Supabase project is not
   an off-site backup. Protect the encryption key separately from the export.
3. Use the [official CLI backup sequence](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
   to capture roles, schema and data, plus the migration history and any
   customized Auth/Storage schema objects. Record UTC time, source ref,
   artifact hashes and encrypted-upload receipt without storing raw data or
   credentials in Git. Inventory R2/Storage objects, Auth configuration,
   Edge secrets and external integrations separately: a SQL dump alone is not
   a complete application recovery point.
4. Restore a selected encrypted export into a **disposable, isolated local
   Postgres environment** or other independently identified recovery target;
   positively verify that the target is not the shared project. Validate
   expected table counts, migration identity, one attendance/payment/audit
   reference, two-tenant read isolation and application startup. Record the
   actual recovery-point age and elapsed restore time, then securely remove
   the disposable copy. A dump that has never been restored is unproven.
5. Rehearse the export and restore once after every material schema/auth change
   and on the scheduled cadence. Failed exports, missing objects or a failed
   validation halt new customer onboarding until repaired.

At the earlier 2026-09-21 check, the linked database password did not work
for the dump path. No isolated restore has run, so this track remains
**planned, not operational**. It can reduce the Free-plan pilot's
recoverability risk after execution, but it cannot be described as Supabase
PITR or make the frozen cloud-restore Gate 29 pass.

**2026-09-22 preflight correction:** the linked password now authenticates,
but that alone does not create a recovery point. The existing Docker daemon
and Supabase CLI can host a disposable **local Supabase stack** for the drill;
a bare Postgres container may not reproduce Auth, Storage, extensions or
project roles. Before export, verify the CLI dump scope for roles, schema and
data, and record the source project ref. Decrypt/import only after checking
the local target's host, port and identity are distinct from the shared Cloud
project. The encrypted archive may use a dedicated recovery-only prefix in
R2 only after recovery-specific access, separate encryption-key custody,
retention and a Privacy Lead-approved handling window are established. The
existing media credential is not by itself a least-privilege backup principal.
Inventory R2 media object bytes and Auth/provider/SMTP/JWT configuration
separately; the SQL dump does not recover those. No dump, upload, restore or
cleanup has yet been executed, and the cloud PITR gate remains unpassed.
