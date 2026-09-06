# Gymloop

Multi-tenant SaaS for Indian gyms. See `AGENTS.md` for the product summary, hard rules, and a routing table to every doc — read that first, always.

## How a new session starts work

1. **Read `AGENTS.md`.** It's small on purpose and routes to everything else.
2. **Check `docs/roadmap.md`** for which phase is current and which model/effort to run it at.
3. **Check `openspec/changes/`** for an in-flight proposal. If one exists for the work you're picking up, continue it. If not, open one (`.claude/skills/openspec-propose/`) before writing any code — this project's methodology (`AGENTS.md`, "Methodology") requires an approved EARS spec before implementation.
4. **Search `docs/registry.md` and grep the codebase** before writing any helper, constant, type, hook, or component. If it already exists, reuse it. If it doesn't, you'll register what you add before you're done.
5. **Write tests from the spec before touching implementation**, in a fresh context that hasn't seen how you're about to build it. A holdout suite in `github.com/OGUN01/gymloop-holdout` exists for exactly this reason — never read it.
6. **Build, get a fresh-context critic's sign-off against the named quality bar, run the gates in `docs/gates.md`, then archive the change** (fold into `openspec/specs/`, update `docs/registry.md`, `/clear`).

One feature per session. If something in the docs is genuinely ambiguous or contradictory, that's a specification question — escalate it, don't invent an answer (`docs/decisions.md`'s Open Decisions section already tracks the ones we know about).

## Local setup

```
pnpm install
cp .env.example .env.local   # fill in real values — never commit .env.local
pnpm build && pnpm lint && pnpm typecheck && pnpm test && pnpm test:scripts
```

Also available, and run in CI: `pnpm knip`, `pnpm jscpd`, `pnpm depcruise`, `pnpm registry-lint`, `pnpm check-escape-hatches`, `pnpm check-pgtap-rollback`.

**OpenSpec** is invoked as `pnpm dlx @fission-ai/openspec@1.12.0 <command>` — pinned to that version, and deliberately not a repo dependency (nothing imports it, so `knip` would flag it, and silencing that needs an ignore entry `AGENTS.md` rule #4 bans). The generated `openspec-*` skills say plain `openspec …`; prefix them.

You will also need the `supabase` CLI on your PATH for schema work. Docker is not used anywhere: pgTAP runs against the Cloud project, every test file wrapped `BEGIN … ROLLBACK` (`docs/decisions.md` ADR-030).

## Seeding a demo gym

One command, and it runs in CI rather than from your shell — sessions hold no database credentials and CI owns every write to Cloud (`docs/decisions.md` ADR-030, ADR-034):

```
gh workflow run seed.yml -R OGUN01/gymloop
```

That applies `supabase/seed.sql` to the linked project. It is idempotent: run it again and you get the same demo gym, not a second one. The seed is deliberately not part of the migration stream — a demo gym must not be recreated every time an unrelated migration merges.

Supabase work goes through the `supabase` CLI, never the MCP server (`AGENTS.md` hard rule #2 — it's authenticated to the wrong account for this project).

## Repository layout

See `docs/architecture.md` for the full folder map and the reasoning behind what's built versus deliberately deferred (`apps/mobile`, `packages/api-client`).
