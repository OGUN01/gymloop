# Backup and restore

This runbook supports HARD-007 and production gate 29. Reading backup status is
safe; initiating a restore, replacing a database or redirecting an application
is destructive. No restore is authorized by this document alone.

**Free-plan controlled-pilot exception (ADR-159):** the owner excludes the
provider restore/PITR drill from the five-gym pilot GO decision because the
current Free project does not include that control. This does not pass gate 29
or prove recoverability. Before customer data, the protected logical backup
export described below still needs a current verified artifact, custody and cadence.
Any future drill uses a distinct Cloud Supabase target under ADR-158.

Backup owner: production owner. Cadence: daily at 00:43 UTC and after material
schema or Auth changes. The dedicated bucket-scoped writer reaches only the
private `gymloop-backups` archive.

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

## Cloud Supabase logical recovery track for the five-gym pilot

The owner has selected the existing shared project for a controlled five-gym
pilot and deferred a paid plan. [Supabase's backup guidance](https://supabase.com/docs/guides/platform/backups)
states that Free projects have no automatic database backup/PITR and recommends
regular off-site CLI exports. This is a possible **additional** recovery track,
not evidence that the cloud/PITR drill above passed and not permission to
restore over the live project.

Before the first customer record is accepted, the production owner must:

1. Verify the CLI database credential without printing it in a
   command, dry-run output, shell transcript or evidence file. Record a
   successful connection and the linked project reference before the export.
2. Use the private Cloudflare R2 `gymloop-backups` bucket approved in ADR-164.
   Public access is disabled. The production owner owns the daily export and
   daily receipt review; the owner also holds the encryption-key recovery copy.
   A dedicated writer credential can reach this bucket only. Keep the key in a
   separate GitHub Actions secret and outside R2. Neither a local file nor the
   source Supabase project is an off-site backup.
3. Use the [official CLI backup sequence](https://supabase.com/docs/guides/platform/migrating-within-supabase/backup-restore)
   to capture roles, schema and data, plus the migration history and any
   customized Auth/Storage schema objects. Record UTC time, source ref,
   artifact hashes and encrypted-upload receipt without storing raw data or
   credentials in Git. Inventory R2/Storage objects, Auth configuration,
   Edge secrets and external integrations separately: a SQL dump alone is not
   a complete application recovery point.
   Separate data-only CLI captures explicitly select `public` and `auth`: the
   default managed-schema exclusion would omit `auth.users`, leaving staff and
   member account references without recoverable identities. The runner
   refuses a combined data part lacking nonempty public COPY records or a
   nonempty Auth users COPY record. The six CLI captures are sequential, so
   this receipt is not a proven
   transactionally atomic recovery point. Only an isolated restore and
   validation can establish application recoverability.
4. Retrieve the exact R2 object after every upload, decrypt it in the ephemeral
   runner, verify the plaintext SHA-256 and capture a redacted receipt. Never
   upload or retain the SQL as an unencrypted artifact. The production owner
   checks the latest successful receipt before each onboarding day and treats
   one older than 36 hours as a backup failure.
5. Schedule an export daily at 00:43 UTC and run one after every material
   schema/Auth change. Alert on a failed export, missing receipt or failed
   read-back; halt new customer onboarding until repaired. Keep 30 days of
   encrypted archives while the controlled pilot runs, subject to owner review
   before any deletion.
6. A future restore rehearsal requires a **disposable, isolated Cloud Supabase
   project** with a different project reference, separate credentials and no
   customer traffic. Validate table counts, migration identity, one
   attendance/payment/audit reference, two-tenant read isolation and
   application startup. Record recovery-point age and elapsed restore time,
   then securely remove the target. No such restore is claimed for the Free
   pilot under ADR-159.

## Extract one encrypted object for an authorized recovery

Use an access-restricted ephemeral runner and an already approved distinct
Cloud recovery target. First download the redacted receipt artifact from the
successful `Phase 8 protected Cloud backup` workflow. Record its run ID, exact
R2 `objectKey`, `ciphertextSha256`, source ref and capture time. Retrieve that
exact key from the private `gymloop-backups` bucket with the dedicated backup
reader/writer credential, using `rclone cat backup:gymloop-backups/<objectKey>`
to write the **ciphertext** into a private temporary file. Do not use a public
bucket URL or the media credential.

Set `BACKUP_ENCRYPTION_KEY_B64` from the owner's protected recovery copy or the
separate GitHub Actions secret in the runner environment, not on a command
line or in a repository file. Run:

```text
node scripts/phase8-backup-extract.mjs <encrypted-object-file> <private-output-parent> <receipt-ciphertext-sha256>
```

The reader verifies the exact ciphertext hash, AES-GCM tag, source project,
header, every part length and SHA-256, then writes `roles.sql`, `schema.sql`,
`data.sql`, `history_schema.sql` and `history_data.sql` into a new private
subdirectory. Its output is only a source/time/hash receipt and the private
path. Keep the SQL inside that ephemeral environment, do not upload it as an
artifact, and remove the environment after the separately authorized Cloud
rehearsal. These files follow the official Supabase CLI logical restore
sequence; they are not evidence that an isolated restore has happened.

The owner recovery copy is DPAPI-protected in the local Codex profile at
`C:\Users\Harsh\.codex\gymloop-backup-key.dpapi`; only this Windows user
profile can decrypt it. The same key is stored separately from the bucket
writer as GitHub Actions secret `BACKUP_ENCRYPTION_KEY_B64`. Losing both copies
makes the encrypted archive unusable; the production owner checks custody and
rotation before onboarding and after access changes.

The earlier 2026-09-21 linked-password failure was corrected on 2026-09-22.
Manual workflow run `35846608557` succeeded on 2026-09-23: the linked Cloud
export was encrypted before upload to the private R2 bucket, then downloaded,
decrypted and checked against the plaintext and ciphertext hashes. The redacted
receipt is retained as a GitHub Actions artifact for 30 days and recorded in
`docs/evidence/phase8/ledger.md`. Its capture time was 10:13:41 UTC. Review
each new daily receipt and its age before onboarding; this one successful run
does not prove the daily schedule or an isolated restore. This track cannot be
described as Supabase PITR or make Gate 29 pass.

**2026-09-23 archive decision:** the owner approved private R2 as the encrypted
archive destination. Docker is used only by the official Supabase CLI for a
read-only dump from the existing Cloud project; no local Supabase database or
restore is used. Before decrypting or importing for a later rehearsal, record
the distinct Cloud recovery project's ref, access controls and approved
handling window. The existing media credential is not a backup principal.
Inventory R2 media object bytes and Auth/provider/SMTP/JWT configuration
separately; the SQL dump does not recover those. The cloud PITR gate remains
unpassed.

No distinct Cloud recovery project or restored validation artifact has been
evidenced. A logical export and Cloud import would prove only that logical
recovery path; it would not prove the frozen provider PITR drill unless the
provider operation and its validation actually occur. Gate 29 remains open.
