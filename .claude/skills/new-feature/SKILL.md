---
name: new-feature
description: Fires when the user asks to build, add, or implement any product feature or capability (a new screen, a new workflow, a new domain behavior) that isn't purely a migration, an API endpoint, an RLS policy, or a payment flow — those have their own more specific skills. Expects a feature description or an OpenSpec change name as input; if neither is given, ask what the user wants to build before proceeding.
---

# New feature

Pre-flight, in this order — do not start writing implementation code before step 4:

1. **Search first.** Grep `docs/registry.md` and the codebase for anything that already does this or close to it. Reuse, or record in `docs/decisions.md` why you couldn't.
2. **Check `docs/roadmap.md`** for which phase this feature belongs to and which model/effort it should run on — don't build Phase 4 logic inside a Phase 2 session.
3. **Write or open the EARS spec.** If `docs/domain-rules.md` already covers this behavior, cite the requirement ID(s). If not, open an OpenSpec change (`openspec new change "<name>"`) and get the proposal/spec approved before writing tests.
4. **Tests first, implementation-blind.** Write visible tests from the approved spec before touching implementation. Do not look at how you're about to build it while writing them.
5. **Build.** Make the tests green. Do not touch test files while doing this — CI blocks a commit spanning `tests/**` and `src/**` without a `spec:` prefix.
6. **Gauntlet.** Get a fresh-context critic (no knowledge of the build) to compare against the named quality bar (`docs/architecture.md`'s bar table, or the measurable backend bars in `docs/roadmap.md`/master-prompt §9 if this is backend work).
7. **Gates.** Run the relevant rows of `docs/gates.md`.
8. **Archive.** Fold the OpenSpec change into `openspec/specs/`, update `docs/registry.md` with every new exported symbol, `/clear`.

If this feature touches the database, an API route, RLS, or payments, also read the matching skill below — they cover invariants this one doesn't repeat.
