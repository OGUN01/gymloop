# Current owner-authorized campaign goal

Updated 2026-09-18 (owner continuation 2). This is the repository's current execution objective; older
prompt text is historical where it conflicts with this owner override.

## Objective

Phase 6 is closed: owner/fleet metrics and super-admin/support/preview browser
journeys passed, exact cleanup was verified, and the three final changes were
archived. The current objective is Phase 7's real web and member/front-desk
mobile experience without rebuilding the completed Phase 6 implementation.
Give members AND gym owners a polished, user-centric minimalist interface with
equal light/dark quality, visible gym identity/code, accessible typography,
comfortable curves and responsive, restrained motion. Preserve the attendance
→ follow-up → return → renewal → add-on → evidence loop and every security,
money, identity and constitutional gate.

The approved member/owner v2 boards are the conformance bar for every Phase 7
user, owner and front-desk route. Matching them means the same typography,
whitespace, continuous geometry, quiet chrome, hierarchy and equal-theme finish
with truthful route content—not merely applying their colours to a Phase 6 layout.

The owner approved the member v2 visual direction and requested its extension
to the gym-owner console. The new owner image is an adaptation proposal, not
yet separately approved. Platform super-admin uses the common fundamentals
with lower bespoke-polish priority. Iron Pulse is superseded.

## Governing artifacts

- [Experience PRD](phase7-experience-prd.md): scope, fonts, tokens, libraries,
  interactions, requirements and measurable acceptance.
- [Implementation prompt](phase7-implementation-prompt.md): bounded assignments,
  model hierarchy, sequence and verification rules.
- [Member direction](../design/phase7/member-minimal-light-dark-v2.md).
- [Owner direction](../design/phase7/owner-minimal-light-dark-v2.md).
- `docs/roadmap.md`, ADR-121/124/125, existing domain and OpenSpec contracts.

## Current evidence and remaining work

- Phase 6 backend/CI is green at `3e5120b`; latest recorded pgTAP evidence is
  81 files / 6812 assertions. All final browser journeys and exact cleanup are
  recorded in the communications, metrics and platform evidence files.
- Communications, metrics and platform are archived at
  `openspec/changes/archive/2026-09-18-phase6-{comms,metrics,platform}/`.
- Phase 7's shared web visual foundation is implemented: platform-neutral
  tokens, pinned local Latin/Devanagari fonts, persistent System/Light/Dark,
  accessible focus/targets, reduced-effect fallbacks, polished sign-in and the
  authenticated account shell. Final Sol visual review and repository gates
  passed; evidence is `docs/evidence/2026-09-18-phase7-visual-foundation.md`.
- The staff check-in route is the first board-conformant core-loop redesign. Its
  initial tokenized 768px pass was rejected; the corrected 1440px roster/gate
  composition and two-row mobile header passed fresh Sol review. Evidence is
  `docs/evidence/2026-09-18-phase7-check-in-surface.md`.
- The owner follow-up queue is the second board-conformant core-loop redesign.
  It preserves the real per-row mutation contract inside the owner-board list
  hierarchy. A first critic rejected clipped enum/note text and 24px member
  links; the tested repair measured full text, 44px links and zero overflow at
  1024px before a replacement fresh critic returned GO. Evidence is
  `docs/evidence/2026-09-18-phase7-follow-up-surface.md`.
- Core-loop route redesign and the native app/API-client, member self-check-in,
  join/switch and bearer seams still need their own frozen contracts,
  independent tests and implementation. The foundation changed no database,
  identity, navigation, money or domain contract.

## Budget and delegation

Latest measured usage at this continuation's start: 75% weekly consumed.
Owner-authorized Phase 6 checkpoint: **77% consumed**. If and only if Phase 6 is
fully closed below that checkpoint, continue Phase 7 under the approved PRD.
The absolute ceiling for this combined continuation is **79% consumed** (the
owner's total three-to-four-point allowance). Check after every micro-batch; do
not promise work fits a percentage. At the applicable cap, stop new work and
report the last green commit and preserved outstanding work. Phase 8 follows
Phase 7 as a separately verified stage; this allowance does not waive or skip
either phase's completion boundary.

Measured after the completed Phase 7 visual-foundation micro-batch: **77% used**.
Measured again after the completed check-in surface: **77% used**. These completed
slices are green and archived; the 79% absolute ceiling remains in force for any
next bounded Phase 7 slice.

Sol orchestrates/reviews; Terra owns bounded architecture/security/native work;
Luna is the default small-scope implementer. Maximum two simultaneous workers,
except independent visible/holdout authors. No Astra without explicit owner
authorization. Full blind arrangements, immutable tests and CI-only migration
application remain mandatory. No quota workaround or relaxed gate is authorized.

## Completion boundary

Phase 6 is archived with real owner/platform journeys. Phase 7 covers the PRD's
member, owner and desk surfaces; accessible English/Hindi light/dark states;
real Android and iOS development builds; role-isolated authentication; honest
offline capture and exactly-once replay; cropped visual criticism; current
registry/spec/evidence and archive. Missing device/signing/provider access is
a named blocker, never replaced by a simulated success. Phase 8 operational
hardening and credential-blocked Razorpay integration remain out of scope.

## Desktop goal-record limitation

The current desktop goal record still contains the older Iron Pulse direction
and 75% cutoff and was previously marked blocked. The available goal tools can
read/create a goal or mark its status complete/blocked; they cannot rewrite an
unfinished objective or resume its status. This file records the owner's update
without falsely completing/replacing the unfinished campaign. Synchronize the
desktop goal text through a supported UI/control when available; this note is
not a claim that its stored objective has changed.
