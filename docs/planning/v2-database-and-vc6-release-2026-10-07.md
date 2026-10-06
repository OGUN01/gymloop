# Database follow-ups and next closed-test release

7 October 2026. Active continuation of the owner's 6 October instruction: "so do the database and db one then upload on the play console". The previous native navigation/Classes/Home/Shop implementation is closed and archived at `f91a745127b32154fa3265f62febac3e7cfc9d7b`; this document tracks new work rather than reopening that accepted evidence.

## Authorized scope and execution order

1. Complete the saved true Shop reservation database-pagination follow-up. Preserve legacy clients, active-hold access, caller isolation, exact money and the approved three/five display. Contract: `openspec/changes/shop-reservation-pagination/`.
2. Implement and measure the saved faster-full-database-validation plan while retaining the native Supabase CLI/pg_prove verdict, the complete visible/holdout manifest, rollback checks, migration serialization, schema drift and seed proofs. Regional paid hosting requires a concrete account/access/spending decision; none is configured yet. A faster duration cannot be claimed without a matching-input measured run.
3. After both units' required evidence is green, produce the signed production AAB from the final green source and upload/promote it to the existing FitCruxx closed Alpha track. The latest instruction supersedes the earlier vc6/no-Play-upload restriction; it does not authorize a production rollout.

Work directly on main, no branch/PR. Freeze each contract before independent test authors; commit red tests first and implementation separately. Land coherent units serially, wait for a preceding full DB run before the next migration, and archive completed OpenSpec changes. Preserve unrelated dirty/untracked work.

## Current truth

- Shop's old caller-scoped reservation RPC caps its read at fifty; current native Load more discloses already fetched rows. The new initial transport will read all active holds (at most five) plus three history rows and one hidden lookahead; continuations read five history rows and one hidden lookahead. Initially only three total rows are visible. This can preload at most eight public reservation rows and avoids fetching fifty historical rows.
- Accepted full DB baseline: run `37486763607`, source `23f5566900b6999e25bcac5e9f39f4e97b95871f`, 161 files / 16,156 tests PASS, native wall 7,788 seconds. Source execution inputs match closed main f91a7451. No new performance implementation or benchmark exists yet.
- Read-only infrastructure discovery found zero GitHub runners/repository variables and no configured compute credentials. The proposed single ephemeral Mumbai Lightsail Ubuntu x64 runner is $0.01612/hour for the 2GB/2vCPU/public-IPv4 bundle, before tax/extras; four-hour compute $0.06448. Account/billing/VM access is unverified. Do not provision until those concrete inputs and a spending ceiling are supplied. Keep the owner's daily desktop and phone out of permanent runner service.
- Authenticated Play Console was inspected through the in-app browser. Ductx account `7649203845150858113`, FitCruxx app `4975754557722576970`, package `in.fitcruxx.app`. Latest overview shows version 5 / 1.0.0 on closed Alpha, "Available to testers on Google Play" and full rollout; latest uploaded bundle is code 5. Candidate next code is 6, to recheck immediately before upload. Production is inactive; production qualification is outside this task.
- The existing production output AAB in C:/gc is stale vc5. The accepted v2check APK is source 90fdd8b6; current f91 execution sources match it, but new pagination will require a fresh build and screenshots.

## Native build and release safety

Preserve C:/gc's existing native/dependency workspace, `.p`, virtualStoreDirMaxLength 24, JDK17 and Android SDK. Protect native build-only settings before source updates; do not reset/reinstall/prebuild over them. Public Expo configuration comes privately from root .env.local plus canonical `https://fitcruxx.vercel.app`; strip literal surrounding quotes. Never print the demo password or signing secrets.

Device OnePlus DN2101 / `INPZT8DQPJROKFXC`: install only the isolated `in.fitcruxx.v2check` build. Never uninstall, overwrite, clear or install over the Play-signed `in.fitcruxx.app` pilot or any Play-signed build. Pushed temporary-file/device-side secret entry remains required. Record actual source and JS-bundle parity; test-package screenshots cannot be called an exact Play-installed production-artifact proof.

Production AAB requires applicationId `in.fitcruxx.app`, label FitCruxx, OAuth scheme fitcruxx, versionCode equal to the rechecked maximum plus one, and the established upload key read privately from `C:/Users/Harsh/.fitcruxx/upload.properties`. Expected upload-cert SHA256: `18:66:78:89:EC:16:6C:79:AD:FC:EE:CC:D4:62:07:D3:73:9C:6C:10:18:EC:ED:E7:B6:16:33:97:8B:21:05:C7`. Preserve namespace/Kotlin structure if the verified recipe uses it. Verify the actual merged manifest, certificate, package/version, permissions, embedded bundle and final source before upload; retain AAB hash and warnings.

Existing pilot exceptions (ADR-159/168), manual-only payments, unresolved HTTPS App Links proof and native Firebase/push setup are not silently turned into passed gates by this upload. Do not expand the release to unrelated feature implementation. Keep actual Console draft/review/published status distinct.

## Current execution checkpoint (7 October, 04:00 IST)

Ordinary app CI37528725170 attempt2 is now SUCCESS on unchanged c77 source; the single retry receipt is retained in docs/evidence/v2/accessibility-retry-2026-10-07.json. The GitHub transport regression is independently authored and frozen:35 visible/22 held checks,57/57 focused PASS and full scripts/held JavaScript569 suites/6115 tests PASS. Visible SHA25669c0e2b75601e1732b29f914fde49ac8cd1bd6154a81782c11ccc457783efc10; held SHA256e77456a36d100eea9bbdf44a75e916ddfb2eec1ab31abde91077d1dffdb7ac0e. Independent test-only red commits a5648faa/3ce8a4f0/3a0943e0 preserve author repairs without history rewrite. The final current-run fallback contract is90568b9e: exhausted history can omit the current row, but exact independently fetched current metadata must bind earlier-attempt scanning. Static source critic gives GO; workflow correction is uncommitted pending the following concrete Windows boundary fix.

Before a new native run, root reproduced a protected-directory PowerShell5 invocation refusal without any Cloud effect: the original -Command argument did not bind its param path. A second readonly probe exposed inherited PowerShell7 module-path incompatibility. Frozen65f51c10 clarifies existing DBV-004/007 native custody behavior. New independent visible and held authors are writing meaningful native/process-boundary regression tests red; root will then make the minimal inert encoded-path/encoded-command/module import correction with terminating ACL errors and complete-process checks. Curly apostrophes are literal path data too; no raw path interpolation into executable PowerShell is permitted. Root has not read held bodies or changed these tests. Native Cloud trial has NOT started, all previous runners are retired, readiness variable absent. Fresh unregistered owner-protected C:/fr6-20261007 and C:/fr6w-20261007 are prepared; new exact-source/run binding remains mandatory.

Runner25 watchdog final proof confirms all three physical cleanup facts true after retirement, SHA25669756a4ed45ae91db5e766f1b1d2ead2b338c7c55fc5729031a50352d5d61ea6. Current review/protected probe logs and full JavaScript metadata are outside the checkout under C:/fr-sealed-20261007. App/schema/test-SQL inputs and vc6 artifact are unchanged; actual full regional run/restoration/guardian/serial seed/performance comparison and Play upload remain OPEN. No new full hosted baseline or overlapping Cloud workload is authorized.

### Previous checkpoint (7 October, 03:20 IST)

The required hosted baseline37519113387 is COMPLETE:163 files/16,329 native assertions PASS, native8242s, native step8254s, full job8277s. Serial seed succeeds with rollback verdict and independent visible34/34 plus held26/26 verifier PASS. Overall run remains failure solely on the expected old generated-type snapshot. Matching SQL/migration hashes and exact pins are retained in docs/evidence/v2/database-native-baseline-2026-10-07.json; protected logs/manifest are outside the repository. Generated Cloud types are already committed in c77.

Final DB37528725159 atc77 was refused in hosted recovery preflight before selector or any Cloud work: official Octokit iterator normalizes listWorkflowRuns to page.data array, while the integration incorrectly used the REST envelope. Native/guardian/migrate/drift/seed all skipped, no runner assignment. Source correction is pending independent visible and held integration fixtures from the frozen DBV transport paragraph. Root has not changed implementation or seen held test bodies; no previous failures are waived. Exactly one ordinary CI failed-job retry37528725170/attempt2 was invoked after actual baseline+seed completion at21:48:48UTC; it is in progress, exact c77 source. All successful prior gates remain recorded separately.

One-job runner25 was genuinely Windows online idle with official default system labels, owner-bound suspended/resume proof, reviewed four-hour external watchdog and source/run-bound short-lived readiness. After the hosted preflight refusal, root removed readiness, verified exact ID/name/label/original process creation/executable, deleted25 and stopped the same retained process handle21:48:48UTC. Watchdog independent final cleanup must be retained. Earlier23/24 setup/refusal records remain;24 all physical cleanup facts are true and no readiness was published for its custom-label/unknown-OS state. Reviewed watchdog68a535c52d7846ca133b1161ce52b6287e46bc30e651d947182943e2ab271eeb; launchera31bb9d68001e4df1162b2f390e5a2694c99a1e11b5a68ffefea8949b3570b71. Actual guard-probe22 and five physical fixtures plus reviewed six-case pending-page parsing metadata are retained in docs/evidence/v2/database-runner-preflight-2026-10-07.json. No tracked app/schema source changed in these operator steps.

Signed vc6 AAB from c77 is verified:93,727,171bytes SHA25689F3ACEBE9197502FCEBECFD7DF2C9DCBED6C276CDAF193D7B05DAA5E59C5D61. Fresh isolated OnePlus pagination/context checks and nine screenshots are committed7f1ffee1; separate bounded deployed reads succeed. Play pilot identity/APK/certificate remain unchanged. Latest actual Console overview still showsvc5 available closedAlpha; no vc6 upload has occurred. Execution-only GitHub transport correction cannot alter app payload, but final source/app byte equivalence still requires evidence.

Next: commit independent regression tests red, make the minimal transport correction separately, run relevant gates/critic, push source, register a fresh exact-run guard-bound default-system-label ephemeral runner, prove full regional native/guardian/restoration/seed/drift/performance and ordinary CI, then archive and upload the validated AAB to closedAlpha. Do not dispatch a duplicate hosted baseline or overlap Cloud workloads. Final source/run binding must be regenerated; never reusec77/run375287/attempt1 readiness for a new job.
### Previous checkpoint (7 October, 02:16 IST)

Shop is pushed at6802d201, migration applied by CI37519113387. Native163 files/16,329 assertions remains LIVE, no overlapping Cloud query/sweep/seed. Earlier drift failure is truthful; generated Cloud types and narrow generated-Args nullable bridge now reconcile it in the next source commit. Exact Shop app/held/immutability CI runs are green.

Native tooling f3453f74 was pushed; GitHub refused its dynamic step.shell before any job/SQL. Correction d172573a uses literal OS-specific shells and is accepted/queued as37528085849 behind the live baseline. Official checksum-verified Actionlint1.7.12 now passes both workflows. Fresh critic also approves checkout-local LF custody and the frozen minimal production dependency closure/short .p store. No global Git/WSL/Docker setting changed.

New validation tooling is locally green:565 suites /6,058 tests (metadata only for held tests), latest crypto bounds148 visible/132 held, workspace type/lint5/5, root lint, registry, escape-hatch, knip, zero clones, dependency checks, strict OpenSpec and3YAML parses pass. Independent source and adapter critics return static GO after tests-first malformed/function/owned-byte and bounded-hook corrections. No test body was changed by implementers; root has not read held bodies. Local evidence: docs/evidence/v2/database-validation-local-2026-10-07.json.

Official Windows client-only smoke remains9 cases with exact native pins and unchanged bytes. Root sealed approved source into owner-protected C:/fr-sealed-20261007; runner C:/fr-runner-20261007 is extracted but unregistered. Actual pre-checkout guard rejection, registration-time external watchdog/narrow physical teardown, hosted loss recovery, and matching-input faster complete run remain OPEN. A conservative pre-arm failure can block the gate; no invented recovery or physical proof may bypass it. Before retirement/expiry of protocol artifacts, preserve original/restoration/custody proof and explicitly revise the adopted cutover only from a completed matching success;7-day expiry is fail-closed and is not an automatic green checkpoint.

Independent build agent owns protected C:/gc native build and OnePlus isolated v2check verification, with187 non-test execution-source hashes and13 critical source-map entries. Never touch any Play-signed installation; root owns Console. Signed candidate6 will be rechecked in Console before upload; no Play write has occurred.

### Earlier local checkpoint (7 October, 00:55 IST)

Shop paging is implemented with an additive bounded read-only RPC, strict initial/more endpoint and native three/five coordinator. Independent SQL proofs pass 59/59 visible, 114/114 held and 31/31 metadata with rollback. Shared/web full suites pass 1,103/4,525 checks; native passes 1,055 before the final awaited freshness guard, whose focused hook/sheet suite passes36/36. Held JS passes92/92, body unread by implementation. A blind critic now gives GO after tests-first corrections for retained sheets and current-view freshness after network preflight. [Local evidence](../evidence/v2/shop-reservation-pagination-local-2026-10-07.json) distinguishes this from still-pending CI/device/release acceptance.

The preferred validation trial is now the free existing Windows client environment, not paid provisioning. Official client-only smoke proves native Windows short-path readonly mounts/cwd/host networking/config consumption: successful fixtures have per-file timers; eight deliberately broken fixtures exit red, all bytes unchanged. The DBV contract is frozen at3aa8518b plus0321784c operational interfaces. Visible288 synthetic cases are red because the two implementation modules do not exist; independent holdout author is active. No runner has been registered, no machine setting changed, no timeout altered and no complete performance trial run. Paid fallback still requires concrete account/access/spending if needed.

Next: push the coherent green Shop unit to let CI apply its migration and run the required full hosted baseline; generate types only after migration success. Build the independently tested validation harness while that suite runs, then conduct the regional run serially after baseline completion. No competing Cloud suite or second migration is authorized during the full run. Play remains untouched; candidate6 must be rechecked before upload.

## Progress and resume boundary

- [x] Read saved follow-ups and prior closed handoff.
- [x] Parallel read-only Shop, runner and release discovery.
- [x] Confirm authenticated correct Play app, published vc5 and candidate vc6.
- [x] Freeze and commit Shop pagination contract.
- [x] Commit independent tests red; implement without altering tests.
- [ ] Green focused/local gates, CI-applied migration, generated types and complete CI.
- [ ] Prepared safe regional harness, hosting/access decision, independent failure-equivalence checks and measured complete run.
- [ ] Fresh isolated-device pagination/navigation smoke and screenshots.
- [ ] Verified signed AAB from final green source.
- [ ] Closed Alpha upload/promote and actual Console evidence.
- [ ] Archive completed units, final evidence and goal completion.

The active persistent goal tracks these three outcomes. Neither a running suite, an unmeasured regional proposal nor a prepared/uploaded draft is completion. Resume from the latest checkpoint above; the initial discovery boundary is historical.
