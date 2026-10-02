# Proposed INV v1.4 — resolve the invite recovery bar conflict

Status: owner-approved 2026-10-02 and frozen as v1.4 in `proposal.md`.

The published INV-Q1/Q3/Q8 bar requires a named gym and full notice before Google,
one-tap account recovery, and safe same-account reopening. The frozen Mobile fixed
names currently prescribe immediate sign-in and refuse every linked identity; the
web INV-020/v1.1 linked branch likewise skips idempotent replay. This proposal meets
the existing bar without widening database capabilities or revealing member facts.

- **INV-029 (native landing and consent).** A valid native invite SHALL first load
  only the gym name through existing `peek_member_invite`, hashing the raw token
  locally with the already-installed `expo-crypto` dependency. No raw token reaches
  Postgres. Before its Google button the screen SHALL display that gym's name,
  shared `inviteNotice(gymName)`, and a link to the configured web origin's `/privacy`.
  Unavailable links and connection failures SHALL have distinct honest recovery
  states and SHALL expose no member record. The Google action SHALL save the token
  securely and open native Google sign-in directly, preserving the two-tap join
  budget. Native Google sign-in SHALL request `prompt: 'select_account'`. A saved
  invite offered after sign-in SHALL show the named gym and the full-notice link;
  no redemption SHALL be queued offline.
- **INV-030 (reopening and linked-account recovery).** A signed-in member opening
  an invite SHALL use the existing POST redemption path to check INV-009's replay.
  Only `already_linked_here` SHALL open that member's home with fresh claims;
  failures/refusals SHALL show the viewer's own signed-in email and a one-tap account
  switch while preserving the token. Other linked identities SHALL remain refused
  under D1 and receive the same account-switch recovery. Web SHALL use a client POST,
  never a mutating GET/render-time database call. Native SHALL use its live API client.
  No picker, other gym/member fact, new binding capability or new SQL function is added.

This replaces only the conflicting linked-entry/immediate-native-sign-in presentation
clauses of INV-020, INV-022 and their fixed-name descriptions. INV-007/009/011, refusal
privacy, hashing, throttles, secure storage and cookie transport remain unchanged.

If approved: freeze this amendment in the main proposal, commission independent
visible and holdout app tests before a separate implementer, then repeat affected
blind reviews and required gates. Android runtime evidence still requires a device.
