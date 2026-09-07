# Phase 0 NO-GO — triage and remediation

Blind critic verdict at `main = 75887d3`: **NO-GO**. Gate *mechanisms* are real and were
reproduced failing for their own reasons. What fails is the layer above: committed documents
that misdescribe reality, a hard rule that contradicts the drift gate, and three trivial
bypasses of the constitutional lint rules that `escape-hatches` does not see.

Ordered by what blocks what. Do not fix in report order — fix in this order.

---

## P0 — blocks Phase 1's first commit

### 1. OPEN-005: the migrations / drift circularity

`AGENTS.md` rule 7 says migrations are applied by CI only. `ADR-024`'s drift gate diffs
committed types against **live Cloud**. So a PR adding a migration can never go green: Cloud
does not have the migration, and nothing in CI applies it (gate 9 does not exist, though
`gates.md` claims "Wired"). Phase 1's first migration hits this on day one.

**Resolution — split the gate by trigger, keep it cloud-only, no Docker, no branching:**

- **On push to `main`:** `supabase db push` (this *is* gate 9 — it is what makes rule 7 true),
  then `supabase gen types`, then diff against the committed file. Red on drift.
- **On pull request:** run the drift diff **only when `supabase/migrations/**` is unchanged.**
  When a PR does add migrations, Cloud legitimately does not have them yet, so the check is
  skipped with an explicit "skipped: PR adds migrations, verified post-merge on main" status —
  never silently passed.
- `gates.md` row 9 changes from "Wired" to the truth, then to Wired once `db push` exists.

**Accepted limitation, record it in the ADR:** a migration that drifts is detected *after* it
has already been applied to Cloud, so `main` can go red with Cloud already mutated. That is
acceptable pre-launch and is exactly what Supabase preview branches solve. Add it to the Pro
upgrade rationale alongside gate 29's PITR requirement.

### 2. Immutability misclassifies pgTAP tests as implementation

`check-test-immutability.mjs` treats `supabase/tests/*.sql` as implementation, so a pgTAP test
and a migration committed together pass. Phase 1 is *entirely* pgTAP tests and migrations —
this means the tests-first rule is unenforced in the one phase where it matters most.

Fix: `supabase/tests/**` classifies as TEST, `supabase/migrations/**` as IMPLEMENTATION. Add
a unit test for both, and plant the violation in the next proof run.

### 3. The escape-hatch ban is itself escapable — three ways, all verified green

All three passed `lint` **and** `escape-hatches` with exit 0:

- an inline `/* eslint no-magic-numbers: "off", no-restricted-properties: "off" */` comment
- a nested `packages/shared/eslint.config.mjs` exporting `[]`, disabling every rule for that
  package — knip did not flag the file either
- renaming `knip.json` to `knip.jsonc` and adding an ignore key; the checker only knows four
  filenames

This is the meta-rule that protects every other rule. While it is bypassable, every gate is
advisory. Extend `escape-hatches` to cover inline ESLint config comments, nested ESLint
configs anywhere below root, and every knip config filename ESLint/knip actually accept.

### 4. Rotate `SUPABASE_ACCESS_TOKEN`

Account-wide, passed through a chat window, and `security.md` says it must be rotated. The
secret's timestamp shows it never was. Rotate, update the repo secret, then grep every doc
that describes its state — the stale-claim class has already bitten this project twice.

---

## P1 — before Phase 5, decide and record now

### 5. `supabase/functions/**` is invisible to four gates

Verified with planted files: `typecheck` passed a string-to-number error, `jscpd` passed a
36-line copy of `constants.ts`, `dependency-cruiser` passed an import of `apps/web`, knip
ignored the directory entirely. There is no tsconfig or workspace for it.

Per ADR-012 this is where Razorpay webhooks and cron jobs land — the highest-risk code in the
product, in the only directory nothing type-checks. `lint`, `registry-lint`, `escape-hatches`
and `immutability` do reach it, so this is partial, not total, blindness.

Decide the mechanism now (a tsconfig plus workspace entry, or explicit tool config), record it,
implement before Phase 5 opens.

### 6. Unused-export detection rests on one gate with five holes

Knip does not catch unused exports in `packages/shared` at all — the barrel `export *` makes
everything an entry export, which knip treats as public API. So §10's "unused exports" promise
is carried entirely by `registry-lint`, which misses `export const { a, b } = …`,
`export type { X }`, `export * as ns`, indented exports, and any helper exported from a
route-convention file. It also passes any export whose name appears in backticks *anywhere* in
the registry — trivially gamed.

Fix the five parsing holes. Then decide whether knip's entry-export blindness is accepted (and
say so in `gates.md`) or worked around.

---

## P2 — hygiene, before archiving

- `gates.md` row 9 currently claims "Wired". False until item 1 lands.
- Archived `tasks.md` says final state was "CI verified green". The push after archiving went red.
- `AGENTS.md` rule 4 omits two live magic-number exemptions: object-literal values, and any
  `const X = 42` outside `constants.ts`. Both pass lint today. ADR-026 omits them too.
- ADR-014 and ADR-015 record no rejected alternatives (§13 item 9).
- The in-flight uncommitted edits from the concurrent session must be committed and CI-green
  before any of this is re-verified. One of their comments is wrong: enabling `enforceConst`
  would *not* flag `constants.ts`, because the rule is already off in that file.

---

## Not defects — do not "fix" these

- Gates 4, 6, 8, 11–15, 17, 18, 20–33 unverifiable: nothing exists to gate yet. `gates.md` says
  so honestly. That is correct reporting, not a gap.
- `openspec/specs/` empty by declared `skip_specs` with a written reason.
- Gate 7 pgTAP unexercised: zero `.sql` tests exist. Phase 1 creates them.

---

## Re-verification standard

A fresh blind critic — not this one, and not the one that produced this report — re-runs after
the fixes. It must confirm the P0 items by doing, and must specifically re-attempt the three
escape-hatch bypasses. A critic that has seen this document is no longer blind to it.
