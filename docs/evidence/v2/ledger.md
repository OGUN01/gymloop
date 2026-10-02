# FitCruxx v2 acceptance ledger

## Batch 1 — INV + STI (2026-10-02, in progress)

Final acceptance remains pending. Batch 1 was pushed as `26ec832`; CI applied both
migrations successfully in [DB run 37009060386](https://github.com/OGUN01/gymloop/actions/runs/37009060386).
No migration has been applied manually. That run's schema drift failure is the
expected pre-regeneration state; its full pgTAP result remains pending.
The latest owner instruction uses GPT-6.1 Sol for parallel agents and minimizes
repeated work while preserving the independent authors, blind reviews and gates.

- Repaired missing STI holdout, visible STI/meta assertions, transaction-relative
  catalogue fixtures and independent legacy holdout expectations in `spec:` commits.
- Full linked-Cloud rollback sweep spliced both pending migrations into every suite:
  **107 files, 8,934 assertions, zero failures, each ran exactly its literal plan**.
  This includes both independent invite history suites. No database workflow was
  active during validation; the orchestrator serialized requests with the local lock.
- Core INV/STI SQL and the INV-028 reader received separate independent static GO
  reviews. These establish source review only, not deployed concurrency or UI evidence.
- Application unit gates passed all five packages/tasks after the approved recovery
  work: web 2,718, shared 545 and native 121. The later optional identity-cache
  repair passed all 127 native cases and 31 independent held recovery/cache cases.
  These are automated contract checks, not Android device or visual acceptance.
- Callback cache protection and Team creation/revoke/reader robustness were repaired
  after independent visible red checkpoints. Holdout fixture corrections preserved
  requirements, including truthful error text, delegated metadata and actual imports.
- Owner approved INV v1.4 to reconcile native consent/reopening with the published bar.
  Independent visible and holdout app suites were committed red before web/native
  implementers resumed. Web/API/Team received a fresh static GO. Native routing,
  consent, replay, direct chooser recovery and the official gradient mark passed
  static review; a cache failure and the provider font remained findings. The cache
  repair is independently verified. A subsequent integrated identity review found
  stale authentication work could overwrite a newer session and optional cache
  deletion could prevent sign-out. Five visible and six independent holdout checks
  were confirmed red and committed separately before the focused repair began.
  The repair passed all 132 native unit checks, all six new held ordering checks
  and the 31 held recovery/cache checks. Further blind reviews found device-wide
  cache ordering and durable Auth-write races across clients. The shared-cache
  repair passes all 41 affected held checks (one web cold-import timeout passed
  its focused retry during the Android build). The third identity rejection was
  escalated to the owner; the existing sign-out requirement is retained. Separate
  visible/held durable-Auth tests were confirmed red and committed as `450d2ec`
  before implementation. The durable-write repair passed 137 native unit checks
  and 46 affected held checks. A further blind review found late refresh/PKCE
  responses could restore Auth after logout. Actual installed-SDK regressions
  were independently authored and confirmed red (two failures, two passes), then
  committed as `9606490` before the focused operation-ordering repair. Final
  review verified the installed SDK's public `processLock` across clients; the
  four affected held suites passed all 26 checks. The fresh critic returned GO
  for completed logout, latest claims, offline ownership and provider teardown.
  Native implementation is committed as `b01f331`. An honestly failed Auth
  logout can retain tokens; the frozen guarantee applies when logout completes.
  Provider font acceptance is recorded below; deployed invite journeys and final
  Android runtime acceptance remain pending.
  The owner approved the Google-font amendment under the three-rejection rule;
  INV v1.5 is frozen in `8d843c2`, with platform readiness boundaries in `8c53737`.
  Independent font tests preceded implementation. The final provider implementation
  is committed as `b176b06`; a fresh source critic and a separate fresh visual
  critic returned GO against R10. Five actual-browser cases passed at 390/1440px
  in both themes, including 200% root text, exact emitted TTF bytes and real
  network-failure recovery with unchanged cookies/storage and zero Auth/API
  mutations. Screens are versioned in `provider-font/`. The initial real retry
  failure was committed red in `9223d1e` before repair. No font waiver is assumed.
- Final application checks: web **2,724/2,724**; shared **545/545**; native
  **141/141** in the broad sweep plus two new provider-stroke cases in the
  five-case focused pass. Script/held sweep: **60 suites / 2,526 checks**; later
  font/recovery follow-up: **31/31**. Full lint, registry, rollback, renewal-window,
  escape-hatch, dependency and unused-code checks passed; duplicate detection
  found zero clones. Commit immutability passed through the pre-font checkpoint
  and is checked again before pushing.
- Requirement-ID reporting is **127/153** globally (26 older IDs lack visible
  textual attribution); no INV/STI ID is reported missing. The reporter is not a
  strict CI gate and does not establish full historical requirement coverage.
- The complete script/held app sweep passed 55 suites and 2,492 checks before the
  subsequent cache supplement. Browser accessibility passed 93 of 94 checks on the
  first sweep; the sole appearance-control failure passed its focused retry. This
  pre-migration sweep does not prove deployed invitation journeys.
- Production invite origin was verified as `https://fitcruxx.vercel.app/` through the
  configured Vercel project. No unrelated environment values were printed.
- A separate Android debug package `in.fitcruxx.v2check` built successfully and
  was installed on the connected OnePlus DN2101 (Android 13), alongside Play v4.
  APK SHA-256: `5c16ad712fcdd8f512db67d42e2ca37538e593225bb757027e71206d112ad704`.
  The official Ninja 1.12.1 binary was used temporarily to repair the Windows
  Ninja 1.10.2 manifest loop; the SDK binary was restored after the build.
  Device runtime acceptance is pending; this debug build is not release evidence.
- Owner deferred phone testing until the end because another agent is using USB
  debugging. This orchestrator stopped its Metro process and will use web/mobile
  viewport checks meanwhile; those do not count as Android runtime proof.
- After CI migrate succeeded, CLI-generated types were committed/pushed as
  `8be0713` under ADR-177. All five typecheck tasks and all four build tasks passed
  locally. [Holdout](https://github.com/OGUN01/gymloop/actions/runs/37009955970) and
  [test immutability](https://github.com/OGUN01/gymloop/actions/runs/37009955864)
  passed. [Types-only DB 37009955982](https://github.com/OGUN01/gymloop/actions/runs/37009955982)
  passed every job, including schema drift and seed dry-run. The original
  [batch-1 DB 37009060386](https://github.com/OGUN01/gymloop/actions/runs/37009060386)
  passed the full pgTAP suite and seed dry-run; its historical pre-regeneration
  schema-drift failure is resolved by this successful generated-types follow-up.
- [Follow-up CI 37009955934](https://github.com/OGUN01/gymloop/actions/runs/37009955934)
  passed the non-browser gates but failed five provider font cases (66 other
  browser cases passed). Next generated a local Arial fallback despite an empty
  fallback list; Linux without Arial rejected the combined readiness query.
  A separate implementer reproduced the missing-local-font failure and disabled
  the automatic adjustment. Existing red browser tests stayed unchanged; six
  visible units, five actual-browser cases and eight independent held cases passed.
  A fresh source critic returned GO. The migration-free repair is pushed as
  `27d4191`. [Linux CI 37011785563](https://github.com/OGUN01/gymloop/actions/runs/37011785563)
  passed both gates and Deno checks, including the browser font cases. The deployed
  public provider also reached ready at 390px: canonical googleSans, 500 weight,
  14/20 typography, 44px target and no horizontal clipping. Deployed invalid member
  and staff invite pages showed their generic refusal with no identity disclosure.

## Batch 2 — contracts and vocabulary staging

Latest local checkpoint (2026-10-02, before any business migration push):

- PTF visible356 and held381 both pass after independent canonical-preview tests
  and the isolated helper correction. A fresh blind source critic returned GO;
  actual concurrent transactions, midnight waits and screen comparison remain open.
- Shop visible211/held276 pass. The negative-only order-default seam now models
  a prior transaction with `statement_timestamp() - interval '1 microsecond'`,
  executes the original deferred guard and restores the exact default before the
  genuine member reservation. Its default is never changed. This is synthetic
  chronology evidence; real separate-transaction reserve/fulfil/replay/prior-sale
  refusal remains mandatory. A fresh blind Shop/MEDIA DB critic returned static
  GO; trusted Edge publication, R2 bytes/cleanup/GET exposure and screens are open.
- Classes held221 passes live-membership parity through the real token-proof
  member check-in RPC and the unchanged attendance trigger. Core visible710
  reaches its complete plan; eight matrix calls were corrected by the independent
  author to the frozen six-argument signature without changing expected errors.
  That focused retry is in progress. Existing seed plus scenarios also passed
  the all-eight-migration rollback preview, without committing any data.
- Fresh Classes and ANC critics each found one source boundary issue. Concrete
  owner proposals are pending: `classes/wall-time-boundary-amendment.md` and
  `announcements/live-membership-boundary-amendment.md`. Affected amendments,
  independent tests and source fixes wait for approval. These are not accepted
  source wins; no business push or complete canonical sweep is claimed.
- Registry, rollback wrapping (123 files) and escape-hatch checks pass. Final
  whole-push immutability, canonical full SQL sweep, CI, generated types and all
  app/runtime Gauntlet work remain required. Future app tests are independent
  uncommitted drafts; missing-module red runs do not prove UI behavior.

Seven proposals and their fetchable bars are being aligned with authoritative
shared decisions before independent authors start. The owner explicitly approved
the scoped last-session PT waiver and the separate CI-only notification category
prelude on 2026-10-02. Their concrete amendment files are the acceptance contracts;
ordinary completed packs remain terminal. The prelude adds one DB verification
cycle so subsequent rollback-only feature tests can exercise committed enum labels.
The owner also approved the precise MEDIA verification architecture exception after
a fresh contract critic found confirmation/overwrite/projection/retention gaps.
The three consuming proposals were aligned and received a fresh contract GO,
including independently recomputed trainer pseudonym vectors; live Edge/R2
authorization, conditional-copy and runtime parity remain required. GRD,
BIZ, PLC and CLS contracts/bars received explicit GO and are frozen as `769eb13`;
independent GRD DB suites are drafted (visible 284, holdout 233 assertions), and
separate app authors are preparing tests. No batch-2 implementation, migration or
acceptance is claimed yet.

The two independent vocabulary assertions were run against the migrated Cloud
baseline after every DB workflow completed: visible 63/63 and holdout 123/123
each failed exactly one expected new-label assertion. Rollback wrappers and
exact plan counts were preserved. Red tests precede the separate implementer.

The separate builder added only the two enum statements. A fresh blind critic
returned GO, checking existing service-consent enforcement, category immutability
and WhatsApp revalidation. The complete committed baseline preview passed all
107 SQL files / 8,934 assertions, with zero failures and exact plans. A harness
filename filter stopped after 43 passing files on an existing dotted filename;
after correcting that disposable filter, only the remaining 64 files ran. The
combined manifest was independently checked for 107 unique files. Registry,
rollback, escape-hatch and test-immutability checks also passed. No new feature
drafts were included in this prelude preview. Prior Linux application gates
remain applicable to unchanged production source; the prelude push runs all CI
gates again before acceptance.

Deployed browser verification passed all five real demo-role landing/navigation
checks, including owner-only Team visibility and forbidden-route redirects.
This is not proof of a successful Google invitation redemption or Android use.

Vocabulary migration/tests/contracts were pushed as `9bcbd31`; CI migrate
succeeded in [DB 37021183243](https://github.com/OGUN01/gymloop/actions/runs/37021183243).
CLI-generated type bytes were pushed alone as `ccc62e4` under ADR-177 (four added
lines); [types DB 37022798758](https://github.com/OGUN01/gymloop/actions/runs/37022798758)
queues behind the complete prelude run. All five production typecheck tasks and
545 shared tests passed in the committed-source check. An isolated dependency
junction conflicted with the workspace installer; the exact locked dependencies
were restored offline without source/lockfile changes. Snapshot native checks had
timeouts; the original ordering check and the normal committed native baseline
subsequently passed, 143/143. The normal committed web baseline also passed:
92 suites, 2724/2724 tests. Untracked future red suites were excluded explicitly.

The owner separately approved the exact private-bucket upload policy in
`r2-cors-amendment.md`. Existing policy absence was rechecked before one bounded
PutBucketCors. Exact readback and production PUT / foreign-origin PUT / production
DELETE preflights passed; initial preflights returned 403 before later verification
matched the installed policy. No object was written. Evidence: `media/r2-cors.json`.
Live browser upload/Edge verification/current member exposure remain unproved.
The four existing registered media R2 values were supplied to repository secrets
through private stdin, without values in arguments, output or files. Independent
name/timestamp readback verified all four after the provisioning script failed to
retain its receipt. Evidence: `media/ci-secret-provisioning.json`. Edge secret
provisioning and verifier deployment remain pending the reviewed CI implementation.

GRD independent SQL suites and shared metadata were committed first as `3b4f7d2`.
Their schema-required red state has not been executed on Cloud during the active
prelude DB workflow; app red runs establish absent exported modules/behavior,
without claiming all drafted cases executed. Guardian marker-only writes were
found to permit false handover provenance. The owner approved the precise marker
amendment. Freeze is `0a09c3d`, insertion documentation is aligned in `38018d6`,
and unchanged-value clearing semantics are corrected in `258fd16`. A fresh critic
gave GO. Separate authors' amendments were committed as `91c4d52` before resuming
the paused SQL implementer: visible plan 311, holdout plan 292. Static checks pass;
runtime proof remains pending the complete prelude DB workflow. BIZ/PLC independent
SQL suites and their central metadata are committed first as `dce5b2e`.

Final local gates, browser/Playwright checks, Android runtime evidence, archive and
CI run links will be recorded after completion. The owner tests after all v2 is built.

### Batch-2 local checkpoint, 2026-10-02 (business push still blocked)

Prelude type-followup DB 37022798758 completed with every job green; all local
Cloud previews below ran only after DB workflows completed, under the atomic
rollback-run lock. Eight business migration drafts are snapshotted by SHA-256 per
run, never permanently applied locally. New/old SQL suites remain committed first;
production draft migrations are untracked and excluded from the existing push.

Independent authors repaired invalid ordinary membership dates, fixture identity
collisions, comparison shapes/collations, invoker temp-table grants and synthetic
command clocks. Historical null-date parity imports suspend only the exact named
CHECK, restore original state and its exact validated definition, and return to
origin before ordinary command proofs. Genuine money commands retain all guards.
Shop default seams drain the unchanged named deferred order constraint before
DDL and restore its deferred mode/default; these do not establish real races or
separate-transaction acceptance.

Focused pass receipts currently include GRD visible311/held293, BIZ61/71,
PLC32/30, ANC157/88, CLS notices42/46, and PTF held331. Remaining suites still
have fixture aborts/failures, so no whole-batch green claim is made. The disposable
diagnostic wrapper was corrected for parser character offsets and leaves any
data-modifying CTE at top level; final acceptance still requires the unmodified
canonical sweep with all 123 committed SQL files and exact plans.

Owner-approved expired-pack freeze a66c2cb added independent actual expired
10-total/3-used/2-scheduled cases: both readers were observed returning5 rather
than7. Tests were committed before a separate source fix. Ordinary complimentary
sale fixtures were corrected to NULL payment method, as the existing money guard
requires. A private-helper expression planning regression blocked normal staff
shop sales; the separate implementer restored lazy PLpgSQL control flow without
new grants or a wider command admission. Held331 subsequently passed all cases.

Fresh PT source review found canonical support preview blocked because its hook
token has no staff id. Existing PTF-022/PTF-028 read-only scope is preserved in
1feffcf, with exact live session/actor/tenant checks and any existing target gym
per NAV-006. Public review returned GO; independent red tests and separate source
repair are still pending. No source/visual Gauntlet win is claimed.

Owner explicitly retained PLC's minimal member-policy edit when its old mixed
claim sentence contradicted unchanged staff predicates. Freeze b6730b7 and fresh
public GO preserve the existing staff boundary; neither docs nor tests claim mixed
identity validation. PLC's source still changes only plans_member_select.

Registry and schema/privacy documentation now include PTF/ANC and the other
business drafts. Local registry, rollback (123 files) and escape-hatch checks
passed; complete source/application gates remain pending. Shop visible app drafts
and independent PTF visible/held app drafts are import-red, not evidence of
behavioral failures. Browser/native/R2 publication and console protocols remain
unexecuted. No USB/ADB/Metro interaction occurred; final Android remains deferred
while another owner-authorized agent uses the phone.

### Batch-2 canonical sweep and held reconciliation, 2026-10-03

Canonical rollback sweep `scratchpad/v2-vocabulary/batch2-all-canonical-preview-r18`
pinned test commit 2897658 and SHA-256 copies of all eight business migrations.
It completed all 123 files: 119 green, three one-assertion failures (h12/h21/h22),
and h69 aborted after its UTC-relative future DOB became today in India. The
literal plans totalled 12,224; 11,931 assertions ran. Classes visible710 and
held221, PTF356/381, Shop211/276, and all other feature files except h69 passed.
This run establishes neither a whole-batch green result nor runtime acceptance
for the two pending contract amendments.

Independent implementation-blind authors preserved h12's legacy role answers
while declaring the exact fifteen approved batch-2 table identities separately;
the inventory now rejects missing, additional and duplicate names. Its plan is 52.
h21/h22's closed app-definer inventories gained only the sixteen public-contract
names, preserving all money/refusal assertions. h69's future DOB now independently
uses the actual fixture gym timezone and retains its refusal and all 293 cases.
The public mechanical scope is `legacy-compatibility-clarification.md`; changes
were committed as spec: 08eb065, 2d5603b and a5b4225, without feature source edits.

Canonical focused retry `batch2-held-canonical-repairs-r20`, pinned a5b4225, passed
h12 52/52, h21 68/68, h22 1002/1002 and h69 293/293: 1,415 assertions, zero failures.
The eight migration hashes exactly match r18. Thus every canonical file now has
passing coverage across the full run and repair retry, totalling 12,226 assertions;
this is explicitly not one final all-green 123-file run. A complete canonical
sweep remains required after any approved class/announcement boundary changes.

Fresh independent static source reviews approve GRD/BIZ/PLC/PTF/SHP and the narrow
legacy policy/index reconciliation. CLS's 24:00/date conflict and ANC's status-only
versus current date-inclusive membership contract still need the owner choices
in their committed amendment proposals. Neither affected tests nor source fixes
were commissioned without those decisions. No business migration or application
source was pushed; screens, live media, real races, Waves C/D and final release
verification remain open. No Android/device interaction occurred.

### Approved date-boundary repairs, 2026-10-03

Owner chose rejection of `24:00` and active/frozen membership status with inclusive
gym-local dates. Public freeze a16ae30 preceded independent visible/holdout files
74/75/h74/h75 and the separate CLS/ANC source repairs. Canonical focused r23
passed 398 assertions. A fresh source critic found shared `app.gym_today` lacked
the approved defensive malformed-timezone fallback; GRD/ANC public dependency
clarifications were frozen before independent tests and a separate helper fix.

Legacy null-date fixtures retain every ordinary guard. Malformed timezone
fixtures suspend only the exact named commercial trigger inside a rollback-only
subtransaction, restore its original definition/enabled state immediately before
ordinary application reads/commands, and prove the sentinel restored original
rows/guards. Ordinary gym-owner direct writes remain refused actor-first with
42501; independent holdout correction bf9e3fc preserves that precedence.

Canonical `batch2-dates-guardian-canonical-r26`, pinned bf9e3fc, passed visible
74=42, 75=316, GRD69=311 and holdout h74=23, h75=72, h69=293: **1,057 assertions,
zero failures**, exact plans. Final fresh blind source critic reviewed only the
approved public boundaries and three source/predecessor pairs, returned GO, and
verified exact bytes outside six permitted routines. It saw no tests or runtime
evidence. Canonical all-file r27 is running against 127 committed SQL files and
snapshotted copies of all eight business migrations; its final result is still
pending. No business push, application/visual win or device test is claimed.

### Final canonical batch-2 SQL win, 2026-10-03

The complete unmodified canonical r27 finished **127/127 files green**, with
**12,679 planned and 12,679 executed assertions, zero failures**. It includes
all independent holdouts and the new owner-approved date-boundary suites.
Its eight executed migration hashes match focused r26 exactly. Separate source
commit 2ef398c contains those eight migrations, after all spec/test commits.
`batch2-seed-final-r2` also passed the unchanged seed plus scenarios in one
BEGIN/ROLLBACK transaction; its first eight hashes match the final sweep.
The durable per-suite and source-byte/Git-blob receipt is
`docs/evidence/v2/batch2-canonical-r27.json`. No permanent local migration,
fixture data, media publication or phone operation occurred. Business push and
CI/types verification are next; all app/visual/live acceptance remains open.

### Batch-2 CI landing and app test handoff, 2026-10-03

Source/doc push b2a331f applied all eight business migrations through CI only:
DB 37061065081's migrate job passed. Its full pgTAP/seed verification is still
in progress; the historical source-push drift failure awaits the normal generated
type follow-up. CLI-generated database declarations were committed separately
as 89c6cda and pushed after migrate success under ADR-177. Type-only DB
37061577506 is queued behind the source run; no drift win is yet claimed.

Types CI 37061577452 passed all code gates but failed two browser journeys
(timeout/missing heading); the permitted one-time failed-job retry is running.
Source CI's browser job separately reported a damaged trace. These are open
browser gate results, not accepted application evidence.

Independent BIZ/PLC app tests were committed red as 64b5820 before the isolated
BIZ application builder started. A scoped orchestrator audit found GRD and
SHP/MEDIA test harness defects and executable coverage gaps; independent visible
authors are repairing their uncommitted tests before any corresponding builder
is launched. Browser/media/race/native acceptance, Waves C/D and release remain
open. No local Cloud query, permanent mutation, or USB/ADB/Metro operation was
performed while CI's DB workflow is active.
