# Parallel MEDIA / PAY repair handoff — 2026-10-04

You coordinate only the remaining MEDIA/PAY integration repairs in
`C:/Users/Harsh/Desktop/gymloop`. The primary continues SLF, WSP, RPE, OCC,
push infrastructure, Cloud verification, Git, CI, deployment and release.
Preserve all other agents' work. No duplicate campaign coordinator.

Read in order:

1. `AGENTS.md` and the current owner instructions in `docs/planning/v2-handoff.md`.
2. The committed `openspec/changes/member-purchases/proposal.md` and approved
   public PAY/MEDIA amendments. Compare dirty proposal annotations to the
   committed contract; an assistant annotation is not an owner decision.
3. `docs/evidence/v2/media-pay-current-fresh-critic.md` — fresh source-only
   NO-GO, independent of tests and prior implementers. Reproduce or resolve
   every finding; do not dismiss it because mocked tests passed.
4. `openspec/changes/member-purchases/proof-runtime-protocol-declaration.md`
   — REVIEW DRAFT, not a frozen contract. Resolve its mechanical choices
   serially before commissioning new authors or changing protocols.
5. `docs/evidence/v2/parallel-media-pay-primary-checkpoint.md`, architecture,
   security, registry and the relevant frozen bars.

## Concrete repairs

- Use real scalar SQL pages `{requests,nextAfter,nextAfterId}`, camelCase
  details and nested snapshots on web/native. Preserve server cursors.
- Repair proof GET `[id]` parameters, actual scalar response, SQL evidence
  return type and an authentic immutable issued expiry, maximum 60 seconds.
  A GET must never reset that deadline or treat expiry as optional.
- Bind exact registration to request before privileged metadata/R2 access;
  enforce the same immutable link independently at attachment. Add only the
  narrowly needed caller-scoped exposure seam, never an admin web client.
- Honor expected revisions and complete retry facts. A replacement must
  invalidate an older verifier context, so old review cannot record new proof.
- Preserve registration, asset and attachment identities across unknown
  outcomes. Retry the same logical upload; no fresh quota/deadline reset.
- Revalidate identity, live request and exact proof after asynchronous work.
  Native picker/hook/upload state needs sign-out/rebinding and stale-result cleanup.
- Build the real desk screenshot viewer, exact-asset rejection, member proof
  replacement and native refresh/detail path. Recording requires the exact
  reviewed evidence; upload alone never creates money or entitlement.
- Make held-plan renewal representable without inventing a plan quote UUID;
  compare immutable sold terms and an actual request command revision.
- Retain the committed active-proof viewing boundary unless the human approves
  a concrete amendment. Recorded/bound history is not silently newly viewable.
- Retain canonical generated status enums, central constants, factual currency
  rules and GL123–125 allocation. Dirty GL126 annotation is not approved.

## Independence, ownership and evidence

Use owner-approved `gpt-6.1-sol` subagents with narrow briefs. Independent
visible and holdout authors start with NO inherited implementation/test context;
each reads only public frozen requirements and own fixtures. A separate builder
never reads holdouts or private diagnostics. Fresh critics likewise start
without inherited coordinator/test/implementation discussions. The previous
inherited-context critic supplies no fresh acceptance.

Draft/freeze public mechanical decisions before authors fan out. Preserve
existing approved identity, stock, consent, privacy and money behavior. Escalate
only a genuine changed business requirement with a concrete reviewed amendment.
Do not silently make tests conform to implementation. Do not claim the previous
SQL79 supplement was captured runtime RED before its already-written source.

Primary owns Git/index: do not stage, commit, reset, rewrite history or push.
Notify primary with exact DOCS/test paths and independent authorship evidence;
primary captures needed SQL RED and makes test-only `spec:` commits. Source work
starts only after that checkpoint. Never mutate a shared migration concurrently.
Keep source/test edits confined to your agreed PAY/MEDIA paths; new shared
constants/env/registry edits need exact narrow integration notes for primary.

No Supabase MCP, Cloud queries/migrations, provider work, secrets, device,
ADB/Metro, deploy, live money or release. Migrations remain CI-only.
Root alone serializes rollback Cloud previews and full pgTAP. Local provider-free
affected tests/typechecks/static gates are yours; no broad repeated runs or ignores.

Update `docs/evidence/v2/parallel-media-pay-progress.md` with exact hashes,
commands, true results, remaining blockers and a source-only fresh critic result.
Do not expose held cases to builders. Final handback must distinguish mocked
local verification, real SQL proof, deployed R2/browser proof and Android proof.
No end-to-end acceptance is claimed until primary has verified the latter.
