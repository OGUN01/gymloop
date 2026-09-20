# Phase 7 mobile identity, replay and application foundation

## Frozen interfaces

This security-critical slice applies UX7-001/003–014, ATT-001–008 and
NAV-001–008. It creates `packages/api-client` and `apps/mobile` on Expo SDK 57,
React Native 0.86 and React 19.2.3, using the shared schemas, tokens and existing
success/error envelope. The device receives the public Supabase URL/anon key
only, stores the refreshable user session in Expo SecureStore and never receives
a service-role credential.

The Next request boundary accepts exactly one credential transport: existing
Supabase cookies or `Authorization: Bearer <user access token>`. Missing,
malformed, unverifiable, service-role/unclassified and mixed cookie+bearer
requests fail closed before body parsing. Bearer verification produces the same
`classifyIdentity` result and RLS-scoped Supabase client as cookie verification;
it never trusts decoded claims without signature verification.

Member QR check-in reuses the existing envelope and gate-token lookup. A member
may check in only the `member_id` and `tenant_id` in the verified token; the
body cannot choose either, and a member request requires a gate token. Staff
assisted behavior stays exact. Member insertion receives a dedicated
member-self RLS policy; it does not widen staff/platform policies.

Gate-token proof is atomic at the database boundary. Members cannot select QR
session rows or insert attendance directly through PostgREST; a narrowly
granted claim-validating command accepts the scanned token proof, derives
tenant/member from canonical member claims and records the attendance in one
transaction. Both policy and command require `app_role = member` and reject
mixed/non-member claim sets. Live check-in server-stamps its occurrence time;
only a complete validated offline command may carry an earlier occurrence.

An offline command contains the original UUID event key, scanned gate token and
`offlineRecordedAt`. Server replay stamps `replayed_at` itself and accepts the
claimed occurrence only when it falls inside that QR session's own creation/
expiry interval and is not in the future. The membership check uses that
validated occurrence day for a complete offline pair and gym-local today for a
live request. Same event+member returns the existing success; event reuse by a
different member conflicts. Sign-out/account/gym change cannot replay another
identity's queued event. Only server confirmation is success; queued UI says
saved on this device and awaiting confirmation.

Queue ownership is the exact `(userId, tenantId, memberId)` identity triple,
and any change clears/refuses the prior association's commands. Cookie and
bearer transports enforce the same signature, authenticated-user role, subject
and claim-classification checks before body parsing. Mobile money facts cross
the application boundary as canonical decimal strings, never JavaScript
numbers; their database read surface casts bigint paise to text.

The shared member snapshot reads organization presentation settings only
through a claim-scoped `public.read_member_portal_settings()` command. The
command returns exactly `city`, `state`, `weekly_goal_default`,
`week_start_day` and `streak_rule_type` for the canonical member tenant after
the same complete member-identity validation; it exposes no settings row,
GSTIN, financial configuration or cross-tenant data. Web and native callers
must use that command instead of selecting `organization_settings` directly.

The first native application exposes the approved four labelled member tabs
(Home, Activity, My gym, You) and four desk tabs (Check-in, Members, Follow-ups,
More), complete Light/Dark/System tokens, verified gym identity/code, member QR
scan/queue/status, attendance/streak, membership/receipts, messages/consent,
add-on history, desk search/assisted check-in/follow-up/lead entry, appearance
and sign-out. All product copy is English and no language mode is exposed. It
consumes real authorized reads; no mock production data, UI-only tenant switch
or decorative disabled delivery claim is allowed.

Gym joining/switching is not inferred from a public code. If the existing data
model cannot prove a second association without a new owner-approved linking
mechanism, the app shows no switch/join control and Phase 7 remains formally
incomplete with that precise blocker recorded; code alone never grants access.

ADR-134 supplies the later owner decision: v1 supports one verified gym
association, exposes no public-code join/switch control and defers secure
invitation-based multi-gym linking. The absence of that post-v1 mechanism is
therefore no longer a Phase 7 blocker.

## Blind ownership and gates

Because identity/RLS/offline replay fail silently, independent visible and
holdout authors work from this contract without reading each other or future
implementation. Tests commit red first. Terra alone implements the bearer
boundary, migration/RPC/route, API client, secure session and replay queue;
Luna later owns route-complete screens against those frozen interfaces. Root
owns shared exports/constants/registry/spec/evidence. CI alone applies a
migration; wait before any later migration and regenerate types through the
Supabase CLI.

The original acceptance required Android and iOS development builds, member and
desk auth, airplane-mode capture, restart/reconnect/duplicate/conflict/revocation
tests, role isolation, Light/Dark device crops, reduced motion/text scaling,
fresh Sol security/visual GO, exact demo cleanup and archive. ADR-134 supersedes
only that platform boundary: physical iOS runtime is deferred and not claimed;
the complete Android evidence remains mandatory. Windows bundling is not an iOS
build.

- [x] Contract frozen before dispatch.
- [x] Independent visible and holdout tests committed red.
- [x] Bearer/RLS/replay/API-client foundation green.
- [x] Native member and desk routes green.
- [x] Android ARM64 development/debug build and security evidence complete.
- [x] Physical Android member/desk authentication, all eight tabs, Light/Dark and sign-out transitions complete.
- [x] Fresh Sol visual critic GO and synchronized English-only design/evidence.
- [x] Physical Android device-max text and Remove animations evidence complete, with settings restored.
- [x] Minimal EAS internal-distribution profile configured for a real iPhone build without a local Mac.
- [x] Credential-free EAS iOS Simulator profile and SDK 57 cloud build complete (`22ede637-bdad-428b-b091-ceda282e7fa5`).
- [x] Physical Android real-QR airplane capture, cold restart, reconnect replay and duplicate restart evidence complete.
- [x] Physical iOS runtime and airplane/reconnect acceptance explicitly deferred outside the Android-first v1 boundary by ADR-134; no runtime claim is made.
- [x] Owner-approved association decision complete: v1 supports one verified gym, exposes no public-code join/switch control and defers secure invitation linking.
- [x] Mobile foundation folded into `openspec/specs/mobile/spec.md` and archived under the ADR-134 Android-first boundary.
