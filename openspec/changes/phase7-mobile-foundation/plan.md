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

An offline command contains the original UUID event key, scanned gate token and
`offlineRecordedAt`. Server replay stamps `replayed_at` itself and accepts the
claimed occurrence only when it falls inside that QR session's own creation/
expiry interval and is not in the future. The membership check uses that
validated occurrence day for a complete offline pair and gym-local today for a
live request. Same event+member returns the existing success; event reuse by a
different member conflicts. Sign-out/account/gym change cannot replay another
identity's queued event. Only server confirmation is success; queued UI says
saved on this device and awaiting confirmation.

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

## Blind ownership and gates

Because identity/RLS/offline replay fail silently, independent visible and
holdout authors work from this contract without reading each other or future
implementation. Tests commit red first. Terra alone implements the bearer
boundary, migration/RPC/route, API client, secure session and replay queue;
Luna later owns route-complete screens against those frozen interfaces. Root
owns shared exports/constants/registry/spec/evidence. CI alone applies a
migration; wait before any later migration and regenerate types through the
Supabase CLI.

Acceptance requires Android and iOS development builds, member and desk auth,
airplane-mode capture, restart/reconnect/duplicate/conflict/revocation tests,
role isolation, Light/Dark device crops, reduced motion/text scaling, fresh Sol
security/visual GO, exact demo cleanup and archive. Windows bundling is not an
iOS build.

- [x] Contract frozen before dispatch.
- [ ] Independent visible and holdout tests committed red.
- [ ] Bearer/RLS/replay/API-client foundation green.
- [ ] Native member and desk routes green.
- [ ] Android/iOS/device/security evidence complete.
- [ ] Fresh critics GO; spec/evidence synchronized and archived.
