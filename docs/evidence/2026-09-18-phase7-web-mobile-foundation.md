# Phase 7 web and mobile foundation evidence — 2026-09-18

## Shipped scope

The remaining owner, member and platform web interiors use the approved v2
visual system in Light and Dark without replacing their existing loaders,
actions, identity, money or response contracts. The new Expo SDK 57 application
provides the frozen four member tabs and four front-desk tabs, shared tokens,
secure Supabase session storage, bearer API transport and an identity-owned
offline check-in queue.

The security repair retained no member table path to QR sessions or attendance
inserts. The atomic claim-validating command derives subject, tenant and member,
server-stamps live occurrences, validates complete offline pairs and enforces
exact event replay. Member money remains decimal text. Queue ownership is the
exact `(userId, tenantId, memberId)` triple. The final member-settings repair
adds `public.read_member_portal_settings()`, whose result is limited to city,
state, weekly goal, week start and streak rule; web and native loaders no longer
select the settings row containing GSTIN and financial configuration.

## Independent contracts and review

- Visible and holdout security contracts landed before implementation in
  `ee4202a`, `adc5ae2`, `e70132d`, `64bbd0d`, `2fd1d52` and `8d37421`.
- Implementation landed in `0d1a6b2`, `0bd360e`, `554eabe`, `0078bd6` and the
  verified-unlinked-session correction `027d052`.
- CI exposed stale direct-insert expectations plus one real regression in the
  shared attendance trigger. Independent visible and holdout authors repaired
  only their own contracts in `bc8609d` and `924cb69`; `88a2083` then scoped QR
  creation-time validation to member commands so staff historical check-ins
  remain valid without weakening member live/offline validation.
- A fresh security critic returned GO on member gate proof, canonical identity,
  time authority, wrapper/helper privileges, cookie/bearer equivalence, queue
  isolation and string money after `554eabe`.
- The first rendered Luna pass returned NO-GO because all four member routes
  truthfully displayed their shared load error. That finding caused the narrow
  presentation-settings RPC above rather than a permissive table policy.

## Web and native verification

- Full web suite: 45 files / 1,422 tests green with file parallelism disabled
  and one isolated worker; the serialization change preserves test isolation
  while preventing the prior resource-starvation timeouts.
- Shared suite: 9 files / 200 tests green.
- Repository lint, recursive typecheck, duplication, unused-code, registry,
  renewal-window, escape-hatch and pgTAP rollback checks: green.
- Focused identity navigation: 21/21 green, including verified unlinked users.
- Expo production export: iOS and Android bundles both completed from the same
  SDK 57 source (3,308 and 3,432 modules respectively); the temporary export
  directory was removed immediately after verification.
- Android ARM64 native debug build: Gradle `assembleDebug` completed all 647
  tasks against SDK/target 36 and JDK 17 from a disposable short-path worktree.
  The 98,919,320-byte APK had SHA-256
  `4B540A94D8B123CEC99F927BCD390F59DD88E46AB4BCF2C55563B8FD6B409E24`.
  The generated Android tree and build-only dependency layout are not product
  source and are removed after this evidence is recorded.

## Real member journey

After CI applied migration `20260918100000_phase7_member_mobile_check_in.sql`,
the real `aarav.member@ironbox.example.com` session was exercised against the
seeded Iron Box gym and signed out afterward. In both Light and Dark:

- Home rendered `IRNBX1`, Aarav's account, the scan-to-check-in entry, weekly
  goal and live membership instead of the shared error state.
- Activity rendered the real confirmed QR and desk-assisted history.
- My gym rendered the real branch address, gym code, membership and destinations
  for messages, add-ons and attendance.
- You rendered the real member identity and working System/Light/Dark control.

No demo row was written by this read-only journey.

## Remaining formal acceptance boundary

The Android ARM64 development/debug build is green, but it is not a signed Play
Store release artifact and no Android device is attached. This Windows host
cannot build iOS locally, and the repository has no EAS project/config or
available signing identity. Therefore the iOS development build, airplane-mode
device capture, reconnect behavior on real hardware, and text-scaling/reduced-
motion device crops remain unevidenced. The mobile change and Phase 7 stay open
until that external build/device capability is supplied. Gym join/switch also
remains intentionally absent because no owner-approved second-association
mechanism exists.
