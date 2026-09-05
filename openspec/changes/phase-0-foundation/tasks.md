## 1. Repo bootstrap and change tracking

- [x] 1.1 Move project to `C:\Users\Harsh\Desktop\gymloop` (no space in path) and verify `.env.local`, `.gitignore`, `supabase/` copied intact
- [x] 1.2 Install pnpm 12.3.4 globally and verify `pnpm -v` reports it
- [x] 1.3 `git init -b main`, add `origin` remote, verify `git remote -v`
- [x] 1.4 `openspec init --tools claude`, verify `openspec/{specs,changes}` and `.claude/skills/openspec-*` exist
- [x] 1.5 Open this change (`phase-0-foundation`) with proposal, design, tasks written and `specs` correctly `skipped`

## 2. Workspace config

- [x] 2.1 `pnpm-workspace.yaml`, root `package.json` (packageManager pinned), `turbo.json` (build/lint/typecheck/test pipelines), `.node-version`, `.npmrc` (save-exact=true) — verify `pnpm install` runs clean
- [x] 2.2 `tsconfig.base.json` with strict + noUncheckedIndexedAccess + exactOptionalPropertyTypes + noImplicitOverride
- [x] 2.3 Root ESLint 10 flat config with scoped `no-magic-numbers` (ignoreArrayIndexes, ignoreDefaultValues, ignoreEnums, off in tests) and `no-restricted-properties` banning `process.env` outside `env.ts` — verify it lints the empty repo clean
- [x] 2.4 `.env.example` (variable names only, the 10 from the master prompt) and extend `.gitignore` if needed

## 3. Packages

- [x] 3.1 `packages/shared/src/config/constants.ts` — non-enum values only (PRODUCT_NAME, DEFAULT_TIMEZONE, DEFAULT_CURRENCY, SUPPORTED_LOCALES, RENEWAL_REMINDER_DAYS, TRIAL_DAYS, GYM_CODE_LENGTH, PLAN_TIER_PRICES_PAISE, SUPABASE_REGION, ROLES) — verify it typechecks and has no DOM lib usage
- [x] 3.2 `packages/shared/src/config/env.ts` — zod schema, lazy validation on first access, server/client split, `assertEnv()` export — verify importing it does not throw with zero env vars set (4 vitest tests, all passing)
- [x] 3.3 `packages/shared/tsconfig.json` excludes `DOM` from `lib` — proven by a throwaway `document.title` reference failing to typecheck, then removed
- [x] 3.4 Register both config files in `docs/registry.md` (also seeded the file's full table structure)
- [x] 3.5 `packages/db/types/database.ts` generated via `supabase gen types typescript --linked` against the live (empty) schema — 190 lines, generated/do-not-edit header, typechecks clean

## 4. `apps/web`

- [x] 4.1 Minimal Next.js 16.3.4 + React 19.2.8 + Tailwind 4.3.3 + TS app with one root page — `turbo run lint typecheck build test` green across all 3 packages (12/12 tasks); both constitutional ESLint rules proven firing on real code, then reverted (see 8.x for the permanent proof branch)

## 5. Supabase

- [x] 5.1 `supabase init` (writes `config.toml`), verify `supabase projects list` still shows `gymloop` linked — confirmed `project_id = "gymloop"`, `major_version = 17`, link re-verified via `supabase link`
- [x] 5.2 Confirm no migrations are created — schema is Phase 1 (`supabase/migrations/` does not exist)

## 6. Documents

- [x] 6.1 `CLAUDE.md` (`@AGENTS.md` first line, plain file not symlink) and `AGENTS.md` (47 lines, hard rules + routing table, Supabase-MCP warning, registry rule, no restart-at-70%-context line)
- [x] 6.2 `docs/architecture.md` — full 5-package target layout with mobile/api-client marked deferred, API split, dependency-cruiser boundaries
- [x] 6.3 `docs/data-model.md` — canonical status vocabularies as the Phase-1 enum spec, org→branch→member tenancy, Phase 2 schema accommodations
- [x] 6.4 `docs/domain-rules.md` — every §8 rule as an EARS requirement with a stable ID (55 requirements across 9 categories: ATT, STK, NSH, PAY, MNY, ADD, INT, DQA, DPD)
- [x] 6.5 `docs/security.md` — RLS/JWT-claim tenancy, DPDP, payment integrity, audit scope
- [x] 6.6 `docs/registry.md` — Constants/Enums/Types/Utilities/Hooks/Components/Env-vars tables (done in Task 3.4)
- [x] 6.7 `docs/decisions.md` — 29 ADRs (ADR-001…028 plus ADR-022a) covering §4/§5 and this session's own, a separate Open Decisions section (4 entries: first super_admin bootstrap/Phase 2, api-client generator/Phase 2, GST PDF approach/Phase 5, transactional email/Phase 6), and a Market context section transcribing the competitor/pricing research that several ADRs depend on and that otherwise lived only outside the repo
- [x] 6.8 `docs/gates.md` — all 33 gates as a table (automated? / enforced by / status), honestly scored (most N/A until their phase; 2 proven, 2 process-applied, 2 partial)
- [x] 6.9 Five `.claude/skills/{new-feature,db-migration,new-api-endpoint,rls-policy,payment-flow}/SKILL.md` with routing-rule descriptions
- [x] 6.10 `docs/roadmap.md` — §12's 8 phases with exit criteria and a model/effort column (confirmed policy, supersedes the master-prompt header), routed to from `AGENTS.md`

## 7. CI gates and credentials

- [x] 7.1 `scripts/registry-lint.mjs` + vitest tests (`scripts/__tests__/`, not `tests/visible/` — these test build tooling, not a product requirement, so they live next to the script per repo convention) — 4 tests passing, CLI proven clean against the real repo, and a real Windows bug found+fixed (the `import.meta.url === file://${argv[1]}` CLI-detection guard silently no-op'd on Windows backslash paths; fixed with `pathToFileURL`)
- [x] 7.2 `scripts/check-test-immutability.mjs` + vitest tests — 5 tests passing; CLI proven against the real repo, including a real edge case found+fixed (`HEAD^` doesn't resolve on a repo's first commit / CI's first-push `before`-is-all-zeros case — added a fallback to checking `HEAD` alone with a warning)
- [x] 7.3 `.github/workflows/ci.yml` — one parallel job per gate (typecheck, lint, knip, jscpd, depcruise, registry-lint, build, test)
- [x] 7.4 `.github/workflows/test-immutability.yml` — found+fixed a real self-referential bug: the rule flagged its own authoring commit (scripts/** exempted, ADR-027)
- [x] 7.5 `.github/workflows/db.yml` — schema-drift check (comment- and blank-line-stripped diff, since the committed file's header would otherwise always mismatch) + pgTAP runner stub (checks for `.sql` files first, so it never starts Docker while there are none). **Went through three designs before landing**: `--local` via Docker → abandoned after two real bugs and ~5-6 min/run of image pulls → `--linked` → failed on a fresh checkout with no link state → `--project-id`, which needs no link step (ADR-024)
- [x] 7.6 `.github/workflows/holdout.yml` — clone `gymloop-holdout` via deploy key (`actions/checkout` `repository:`+`ssh-key:`), run its suite
- [x] 7.7 **Done.** `SUPABASE_ACCESS_TOKEN` set as a repo secret and verified before use: the token resolves the correct account (sees `gymloop`), and the exact command CI runs (`supabase gen types typescript --project-id pecxrpskmfeuyzngvewq`) succeeds and matches the committed file under CI's own comparison. **Follow-up, tracked in `docs/security.md`: this token must be rotated** — it was transmitted in plaintext through a chat transcript, and it is account-scoped rather than project-scoped. Original task text below for the record.
  - ~~Not done — needs the user, and it IS a Phase 0 blocker.~~ Create a Supabase access token (while logged into the account owning `pecxrpskmfeuyzngvewq`/org `gjjnocawiprbwdkktogn`) at supabase.com/dashboard/account/tokens; it then gets set via `gh secret set SUPABASE_ACCESS_TOKEN -R OGUN01/gymloop`. This entry previously claimed "not a Phase 0 blocker, `db.yml` uses `--local`, needing no remote auth" — that stopped being true when the drift gate moved to Cloud (ADR-024), and leaving the stale line in place is precisely why the missing secret went unnoticed until a fresh-context critic caught `main` sitting red. Without it, `schema-drift` fails identically on good and bad commits: gate 10 is jammed, not wired.
- [x] 7.8 Generated ed25519 keypair; public half registered as a read-only deploy key on `gymloop-holdout` (`gh api` confirms `read_only: true`); private half set as `HOLDOUT_DEPLOY_KEY` on `gymloop`; local copies deleted; `gymloop-holdout` bootstrapped with package.json + one trivial `node:test` (zero deps), verified passing locally before push
- [x] 7.9 `dependency-cruiser` config with the `packages ↛ apps` layer rule and the `packages/shared` portability rule (no `next/*`/`react-dom`/node core) — both proven firing (exit 1) on real violations, then reverted. Also wired `.jscpd.json` (found the CLI's real flag is `--exit-code`, kebab-case, not `--exitCode`) and `knip.json` (found+removed a genuinely unused `prettier` dependency I'd added speculatively; found+fixed my own exit-code-masking bug from piping through `tail` in earlier checks)
- [~] 7.10 Pushed `main`; first real run showed `CI` and `Test immutability` green but `DB` and `Holdout` genuinely red — both fixed with real causes, not assumptions: (1) `db.yml` was pinned to Supabase CLI 2.116.0 while the locally-committed `database.ts` was generated with 2.110.0 — different versions emit different type-gen templates (extra `__InternalSupabase` block, different conditional-type parens) even against an identical empty schema; re-pinned CI to 2.110.0 to match (docs/decisions.md ADR-024 addendum). (2) `holdout.yml`'s `pnpm/action-setup@v6` had no version to auto-detect (`gymloop-holdout` has no `packageManager` field) and no lockfile existed for `--frozen-lockfile`; pinned the version explicitly and generated+committed a real `pnpm-lock.yaml` in `gymloop-holdout`. Re-pushing to confirm green for real.

## 8. Prove every gate fails

Proven via PR #1 (`chore/gate-proof` → `main`), which carries 3 commits of deliberate violations. Workflows only trigger on push-to-`main` or `pull_request`, so a real PR — not just a branch push — is what makes these checks run.

- [x] 8.1 Duplicated helper (`__gateproof_jscpd__.ts` copies `constants.ts`) — **`jscpd` job red**
- [x] 8.2 Unregistered exported symbol — **`registry-lint` job red**
- [x] 8.3 Hardcoded `149900` used inline — **`lint` job red** (`✖ 5 problems`, incl. `2:27 error No magic number: 149900`). Two things had to be fixed before this proof was real: (a) the rule ignores a bare `const X = <n>` declaration by default (`enforceConst: false`), so the proof uses the number inline in an expression — the realistic bad-code shape anyway; (b) **the first run's `lint` failure was fake** — `turbo.json` had `lint` depending on `^build`, so a broken `build` aborted the graph before ESLint ever executed (ADR-028). Caught by the fresh-context critic, not by me
- [x] 8.4 Type error (string assigned to number) — **`typecheck` job red** (and `build` red downstream of it)
- [x] 8.5 Unused export — **`knip` job red**
- [x] 8.6 Cross-layer import (`packages/db` → `apps/web`) — **`depcruise` job red**
- [x] 8.7 `packages/shared` importing `next/headers` — **`depcruise` job red** (same job, second distinct rule)
- [x] 8.8 Hand-edit to `packages/db/types/database.ts` — **`schema-drift` job red on the real diff**: authenticated against Cloud, generated fresh types, and reported exactly `-export type GateProofBogusHandEdit = true;`. Took three attempts to become a real proof rather than a false one: it first failed on a CLI version mismatch, then on "Cannot find project ref" (fixed with `--project-id`), then on the missing token. The same job passes on `main`, so it discriminates rather than always failing
- [x] 8.9 A real test file + its implementation touched together, no `spec:` prefix — **`check` (test-immutability) job red**
- [ ] 8.10 Delete `chore/gate-proof` branch + close PR #1 once 8.8 and 8.11 are captured
- [x] 8.11 Failing test committed to `gymloop-holdout` — **`holdout` job red** on `AssertionError: 2 !== 3` from `gate-proof-failing.test.mjs` (run 33990875244), proving the read-only deploy key, the cross-repo clone, and the suite execution all work end to end. Reverted immediately after; holdout suite verified green again (1 pass, 0 fail). Note: the first PR run's `holdout` check *passed* because it cloned the holdout repo before that push landed — a real race, re-triggered by force-pushing the rebased branch
- [x] 8.12 Grepped for `eslint-disable` and `knip` ignore entries — zero real matches (only Next.js's own generated `.next/` output, which is gitignored, and one comment in `eslint.config.mjs` that merely mentions the term while explaining the rule)

**Final state of the proof run** (PR #1): `lint`, `typecheck`, `build`, `knip`, `jscpd`, `depcruise` (both rules), `registry-lint`, `check`, `holdout`, and `schema-drift` all **red for their own intended reason**; `test` **green** (4/4 — correctly unaffected, which is itself the evidence ADR-028's fix worked); `pgtap` **green** (correctly skips, no `.sql` tests yet).

**Every one of these was also verified green on `main` in the same round.** That matters more than the red: a gate that fails on everything is jammed, not wired — the pairing is what proves each one actually discriminates a good commit from a bad one. Two gates in this session were caught in exactly that jammed state (`lint`, which ran zero rules behind a turbo cascade, and `schema-drift`, which died on auth before diffing anything), and neither was distinguishable from working by looking at the red X alone.

## 9. Close out

- [x] 9.1 `README.md` — how a new session starts work
- [ ] 9.2 Fresh-context critic sub-agent audits deliverables against the master prompt's §13 items and §11's 33 gates — capture its report
- [ ] 9.3 Archive this change into `openspec/specs/`, recording which gate proved what (Task 8's captured output) in the archived record
- [ ] 9.4 Final commit to `main`, verify CI green
