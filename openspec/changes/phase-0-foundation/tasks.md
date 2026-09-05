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
- [x] 6.7 `docs/decisions.md` — 26 ADRs (§4/§5 + this session's) plus a separate Open Decisions section (4 entries: first super_admin bootstrap/Phase 2, api-client generator/Phase 2, GST PDF approach/Phase 5, transactional email/Phase 6)
- [x] 6.8 `docs/gates.md` — all 33 gates as a table (automated? / enforced by / status), honestly scored (most N/A until their phase; 2 proven, 2 process-applied, 2 partial)
- [x] 6.9 Five `.claude/skills/{new-feature,db-migration,new-api-endpoint,rls-policy,payment-flow}/SKILL.md` with routing-rule descriptions
- [x] 6.10 `docs/roadmap.md` — §12's 8 phases with exit criteria and a model/effort column (confirmed policy, supersedes the master-prompt header), routed to from `AGENTS.md`

## 7. CI gates and credentials

- [x] 7.1 `scripts/registry-lint.mjs` + vitest tests (`scripts/__tests__/`, not `tests/visible/` — these test build tooling, not a product requirement, so they live next to the script per repo convention) — 4 tests passing, CLI proven clean against the real repo, and a real Windows bug found+fixed (the `import.meta.url === file://${argv[1]}` CLI-detection guard silently no-op'd on Windows backslash paths; fixed with `pathToFileURL`)
- [x] 7.2 `scripts/check-test-immutability.mjs` + vitest tests — 5 tests passing; CLI proven against the real repo, including a real edge case found+fixed (`HEAD^` doesn't resolve on a repo's first commit / CI's first-push `before`-is-all-zeros case — added a fallback to checking `HEAD` alone with a warning)
- [ ] 7.3 `.github/workflows/ci.yml` — one parallel job per gate (typecheck, lint, knip, jscpd, depcruise, registry-lint, build, test)
- [ ] 7.4 `.github/workflows/test-immutability.yml`
- [ ] 7.5 `.github/workflows/db.yml` — `supabase gen types --local` drift check + pgTAP runner stub
- [ ] 7.6 `.github/workflows/holdout.yml` — clone `gymloop-holdout` via deploy key, run its suite
- [ ] 7.7 User creates a Supabase access token (correct account) and provides it; set as `SUPABASE_ACCESS_TOKEN` + `SUPABASE_PROJECT_REF` repo secrets via `gh secret set`
- [ ] 7.8 Generate ed25519 keypair, register public half as read-only deploy key on `gymloop-holdout`, set private half as `HOLDOUT_DEPLOY_KEY` secret on `gymloop`; bootstrap `gymloop-holdout` with package.json + one trivial passing test
- [x] 7.9 `dependency-cruiser` config with the `packages ↛ apps` layer rule and the `packages/shared` portability rule (no `next/*`/`react-dom`/node core) — both proven firing (exit 1) on real violations, then reverted. Also wired `.jscpd.json` (found the CLI's real flag is `--exit-code`, kebab-case, not `--exitCode`) and `knip.json` (found+removed a genuinely unused `prettier` dependency I'd added speculatively; found+fixed my own exit-code-masking bug from piping through `tail` in earlier checks)
- [ ] 7.10 Push `main`, verify CI green via `gh run view` — including `db.yml` and `holdout.yml` genuinely green (not skipped) on real credentials

## 8. Prove every gate fails

- [ ] 8.1 Branch `chore/gate-proof`; commit a duplicated helper — verify `jscpd` job goes red, capture output
- [ ] 8.2 Commit an unregistered exported symbol — verify `registry-lint` job goes red, capture output
- [ ] 8.3 Commit a hardcoded number replacing a constants.ts value — verify `lint` (no-magic-numbers) job goes red, capture output
- [ ] 8.4 Commit a type error — verify `typecheck` job goes red, capture output
- [ ] 8.5 Commit an unused export — verify `knip` job goes red, capture output
- [ ] 8.6 Commit a cross-layer import (db → ui) — verify `depcruise` job goes red, capture output
- [ ] 8.7 Commit `packages/shared` importing `next/headers` — verify `depcruise` portability rule goes red, capture output
- [ ] 8.8 Hand-edit `packages/db/types/database.ts` — verify the `db.yml` drift job goes red, capture output
- [ ] 8.9 Commit touching `tests/**` and `src/**` together without a `spec:` prefix — verify `test-immutability` job goes red, capture output
- [ ] 8.10 Delete `chore/gate-proof` branch after all 7 proofs above are captured
- [ ] 8.11 Separately: commit a deliberately failing test to `gymloop-holdout`, verify `holdout.yml` on `gymloop` goes red, capture output, then revert the holdout commit
- [ ] 8.12 Grep the repo for `eslint-disable` and `knip` ignore entries — verify zero matches

## 9. Close out

- [ ] 9.1 `README.md` — how a new session starts work
- [ ] 9.2 Fresh-context critic sub-agent audits deliverables against the master prompt's §13 items and §11's 33 gates — capture its report
- [ ] 9.3 Archive this change into `openspec/specs/`, recording which gate proved what (Task 8's captured output) in the archived record
- [ ] 9.4 Final commit to `main`, verify CI green
