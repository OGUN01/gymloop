## Context

See `proposal.md` — Why. Starting state, verified this session: empty repo folder (`.env.local`, `.gitignore`, `supabase/.temp/` only); GitHub repos `gymloop` and `gymloop-holdout` exist, private, empty; Supabase CLI already linked to the correct `gymloop` project (ap-south-1, PG 17.6) but `supabase init` never run. Version corrections found this session: `openspec` on npm is a dead 2022 package (real tool is `@fission-ai/openspec`); TypeScript 7 breaks `typescript-eslint`'s peer range (`>=4.8.4 <6.1.0`) — pin TS 6.

## Goals / Non-Goals

**Goals:** a repo every future session can work from using only its files; CI gates that are *proven* to fail (not just configured); a doc framework layered against context rot.

**Non-Goals:** any application behavior, migration, or UI (per proposal's Capabilities section). No mobile app or generated API client — deferred with an ADR, not stubbed.

## Decisions

**Repo root moves to `C:\Users\Harsh\Desktop\gymloop`** (confirmed with user) — the original path contains a space, which breaks Metro/Expo bundling and some Docker volume mounts on Windows. Alternative considered: keep in place — rejected, defers a known class of bug to a session that has forgotten why.

**`apps/mobile` and `packages/api-client` deferred rather than stubbed** (confirmed with user) — an empty package trips the `knip` unused-export gate we are arming in this same change, and mobile UI is Phase 7 work per the master prompt's own build order. Alternative: scaffold all five packages now per §4's literal layout — rejected, contradicts §14's "no scaffolding for later."

**Expo/RN version left unpinned** (confirmed with user, reversed from initial plan) — §4's SDK 56/RN 0.85 pin is already one SDK behind current (57/0.87 as of this session); pinning "the current one" now only repeats the staleness problem by Phase 7. The ADR records that the version is chosen when Phase 7 starts, against whatever is current then.

**Status vocabularies (member, membership, no-show case, payment, add-on order, notification, follow-up outcome) are documented as the Phase 1 Postgres-enum spec in `docs/data-model.md`, not written as TypeScript constants now.** The master prompt's own truth chain is Postgres enum → `supabase gen types` → generated TS types → derived zod schemas. Hand-writing them as `packages/shared` constants today would create a second source that Phase 1 must then reconcile or delete — exactly the duplication `docs/registry.md` exists to prevent.

**`packages/shared` stays platform-free from day 0**: its `tsconfig.json` omits `DOM` from `lib`, and a `dependency-cruiser` rule forbids importing `next/*`, `react-dom`, or `node:*` from it. Alternative: enforce this by convention/review only — rejected, a convention with no CI teeth is the exact failure mode this whole change exists to close off, and the package is consumed by web, mobile, and Edge Functions, so a leak here is a Phase 7 blocker discovered at the worst time.

**`packages/shared/src/config/env.ts` validates lazily (on first property access, cached), not eagerly at module load.** An eager `zod.parse()` throws during `next build` in CI, where no env vars are set, turning the build gate red on missing secrets rather than on broken code. Alternative: seed CI with placeholder secret values — rejected, that either puts fake secrets in a checked-in workflow file or trains future sessions that a green build implies a valid environment.

**Schema-drift CI gate compares `supabase gen types --local` (after `supabase start`) against the committed `packages/db/types/database.ts`, not `--linked` against the remote.** This is hermetic (no network dependency, can't false-red on remote unavailability) and is the actual invariant CI should assert — that committed migrations and committed types agree. A `SUPABASE_ACCESS_TOKEN` repo secret is still required for Phase 1's `supabase db push`, so it is set now via `gh secret set` rather than discovered missing later; the user must create it from the account that owns the `gymloop` project (`pecxrpskmfeuyzngvewq`, org `gjjnocawiprbwdkktogn`), not one of their two other Supabase accounts.

**Holdout-repo access via a dedicated deploy key, not a personal access token.** An ed25519 keypair is generated locally; the public half becomes a read-only deploy key on `gymloop-holdout`; the private half becomes the `HOLDOUT_DEPLOY_KEY` secret on `gymloop`. Scoped to exactly one repo, read-only, and the private key never touches either repo's tracked files. `gymloop-holdout` gets a minimal package.json and one trivial passing test so the clone-and-run step is actually exercised, not silently skipped on an empty repo.

**`no-magic-numbers` is scoped (`ignoreArrayIndexes`, `ignoreDefaultValues`, `ignoreEnums`, off in test files), and no `eslint-disable` comment or `knip` ignore entry is permitted anywhere in this change.** An unscoped rule gets neutralized by disable comments, which is worse than a narrower rule that is always obeyed — and an escape hatch used even once in the founding commit sets the precedent that gates are negotiable.

**Every CI gate is its own parallel job, not a sequential step.** The exit condition (`proposal.md`, and master prompt §13.8) requires showing each gate fail independently; a sequential pipeline that stops at the first red job can't demonstrate the rest.

## Risks / Trade-offs

[Deferring `apps/mobile`/`packages/api-client` means Phase 7/2 sessions inherit no scaffolding] → mitigated by the ADR stating exactly what was deferred and why, so it reads as a decision, not an omission.

[Lazy env validation is a less obvious pattern than eager parsing, and a later session may "simplify" it back] → mitigated by an ADR entry naming the exact failure mode (CI build gate false-reds on missing secrets) that eager parsing reintroduces.

[Docker daemon not running locally] → blocks `supabase start`, so the schema-drift gate and pgTAP cannot run locally this session; the drift-gate proof in this change instead runs in GitHub Actions (which provides its own runner), and local Docker is a Phase 1 prerequisite, reported as a follow-up rather than fixed here.

[Two-key setup for holdout access is more moving parts than a single PAT] → mitigated by scoping: a leaked deploy key exposes read-only access to one already-private repo, versus a PAT which typically carries broader scope.

## Migration Plan

Not applicable — no prior implementation, no deployed users, no data. First commit to `main` establishes the baseline directly.

## Open Questions

None that would change the specs, approach, or task breakdown for this change. Two are explicitly deferred to later phases (SDK version at Phase 7, `packages/api-client` generator tool at Phase 2) and are recorded as such in `docs/decisions.md`, not left open here.
