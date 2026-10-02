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
  passed. The queued types-only DB run must still confirm schema drift.
- [Follow-up CI 37009955934](https://github.com/OGUN01/gymloop/actions/runs/37009955934)
  passed the non-browser gates but failed five provider font cases (66 other
  browser cases passed). Next generated a local Arial fallback despite an empty
  fallback list; Linux without Arial rejected the combined readiness query.
  A separate implementer reproduced the missing-local-font failure and disabled
  the automatic adjustment. Existing red browser tests stayed unchanged; six
  visible units, five actual-browser cases and eight independent held cases passed.
  A fresh source critic returned GO. The migration-free repair is pushed as
  `27d4191`; Linux CI confirmation remains required.

## Batch 2 — contracts and vocabulary staging

Seven proposals and their fetchable bars are being aligned with authoritative
shared decisions before independent authors start. The owner explicitly approved
the scoped last-session PT waiver and the separate CI-only notification category
prelude on 2026-10-02. Their concrete amendment files are the acceptance contracts;
ordinary completed packs remain terminal. The prelude adds one DB verification
cycle so subsequent rollback-only feature tests can exercise committed enum labels.
No batch-2 implementation, migration or acceptance is claimed yet.

Final local gates, browser/Playwright checks, Android runtime evidence, archive and
CI run links will be recorded after completion. The owner tests after all v2 is built.
