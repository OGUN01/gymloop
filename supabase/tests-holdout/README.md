# Holdout pgTAP suite

These files run against the Supabase Cloud project `pecxrpskmfeuyzngvewq` from
the `pgtap` job of `gymloop`'s `.github/workflows/db.yml`, after CI applies a
migration on merge to `main`. They are checked out beside the visible suite and
both directories are passed to `supabase test db --linked` in the same run.

Nobody implementing `gymloop` reads this directory. That is the entire point:
these tests are the anti-gaming signal (`AGENTS.md` hard rule #10). They are
written blind from the EARS specs in
`openspec/changes/0001-data-model/specs/**/spec.md`, never from the DDL.

## Rules, enforced not assumed

- **Every file is wrapped `BEGIN … ROLLBACK`.** The suite runs against the one
  shared Cloud database — there is no disposable local instance — so a test that
  commits is a bug, not a style issue. `gymloop`'s
  `scripts/check-pgtap-rollback.mjs` is run over this directory in CI and fails
  the job on any file whose first statement is not `BEGIN`, whose last is not
  `ROLLBACK`, or which contains a `COMMIT`.
- **One file per cluster**, named `<NN>_<cluster>_holdout.sql` so the run order
  is stable and a failure names its area.
- A file may only reference schema objects that have already merged. A holdout
  file pushed ahead of the migration it tests turns `main` red for a reason that
  is not a defect.
