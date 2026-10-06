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

## Current execution checkpoint (7 October, 00:55 IST)

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

The active persistent goal tracks these three outcomes. Neither a running suite, an unmeasured regional proposal nor a prepared/uploaded draft is completion. Next action: finish frozen Shop wire/EARS contract, then independent test authors. No new code, database, build or upload has run at this checkpoint.
