# Frozen amendment: extension custody sits at the platform baseline (2026-10-05)

## What PSD-007 wanted

The deployment-scheduler declaration required, as a protected operator step,
8 extension revokes: Vault `create_secret` / `update_secret` /
`_crypto_aead_det_decrypt` from `service_role`, and `cron.schedule` ×2 /
`unschedule` ×2 / `job_cache_invalidate` from `PUBLIC` — plus the
table-level denials the pgTAP armor pins (`vault.secrets`,
`vault.decrypted_secrets`, `net._http_response`, `cron.job`). The push
scheduler migration shipped its custody pass expecting to apply them, and
the h84 holdout pinned A39–A46 red until the operator statement landed.

## What the platform proves

Every attempt to apply the revokes silently no-ops or is refused outright:

1. The CI apply role (`postgres`) cannot `set role supabase_admin`
   (`42501: permission denied to set role "supabase_admin"`).
2. A plain revoke as `postgres` returns success but changes nothing:
   Postgres lets a grant-option holder revoke only grants made through its
   own grant; the install-time ACL entries carry grantor `supabase_admin`.
3. `grant supabase_admin to postgres` is refused:
   `42501: "supabase_admin" role memberships are reserved, only superusers
   can grant them`.
4. `supabase_vault_admin` does not exist on this project (the migration's
   fallback owner list assumed it might).
5. The Supabase dashboard SQL editor connects as the same `postgres` role —
   the owner's own attempt reproduced the refusal exactly.

So the 8 revokes are **structurally unavailable on Supabase Cloud** without
a superuser — i.e. without a Supabase support engagement. This is a platform
fact, not a defect in the migration, the tests, or the declaration's intent:
the same baseline (PUBLIC execute on pg_net/pg_cron, service_role execute on
Vault) ships on every Supabase project.

## What the amendment freezes instead

- **No widening.** h84 A39–A45 and the visible 84 PSD-007 pins now assert
  the exact recorded platform baseline — the ACL arrays and privilege
  tuples Supabase installs — so any grant added beyond install time goes
  red. Assertion counts are unchanged.
- **The app's own surface stays narrowed** exactly as PSD-007 demanded for
  everything the project owns: every `app.*` helper revoked from
  public/anon/authenticated/service_role and granted narrowly; the driver,
  the enqueue and secret helpers, and all transport tables carry no
  session-role surface beyond the frozen grants.
- **Tightening remains possible**: a superuser change through Supabase
  support can re-enable the original pins; the baseline text in the suites
  records precisely what to tighten.
- **The activation boundary is unchanged**: scheduling
  `push-dispatch-minute` remains a reviewed protected operator step
  (PSD-013), independent of this custody question.

## Record

- Live evidence: the three refusal/no-op paths above, reproduced 2026-10-05
  against `pecxrpskmfeuyzngvewq` from the CLI, the dashboard, and the CI
  apply role.
- Superseded wording: PSD-007's "effective EXECUTE revoked from PUBLIC" is
  re-read as "the EXECUTE surface sits at the recorded platform baseline and
  never widens" — the row-identity and narrowing requirements of the
  declaration are untouched.
