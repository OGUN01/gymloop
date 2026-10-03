# Classes cancellation final-send cutoff boundary

Status: **proposed owner clarification, 2026-10-03**. The third fresh Classes
cancellation review rejects the current client boundary. AGENTS.md requires
owner escalation after three rejections of one dimension; no bar is lowered.
No dependent source change is authorized by this proposal alone.

## Concrete failure

The native confirmation refreshes the exact own booking and checks the inclusive
cancellation deadline. Its existing helper then awaits a second connectivity
preflight. If the cutoff passes during that wait, the current lifetime guard
still permits the API call. The database refuses the closed cancellation, but
the frozen client promise says a closed window submits nothing.

## Proposed precise boundary

Retain that promise: immediately before the actual command invocation, after
every awaited preflight, the supplied presentation guard must require both the
permanent current caller lifetime and cancellation eligibility for the exact
freshly confirmed booking. Recheck the current instant against that booking's
authoritative cancelBy: at the deadline it may send; strictly after it must not.
The helper's synchronous final guard and api.post must have no intervening await.
A false or throwing guard sends nothing and cannot announce cancellation success.

This adds no read endpoint, parser, actor, grant, default window, queue, migration
or native dependency. It does not predict later policy changes or replace the
database's current command-time decision. Missing, wrong, cancelled and changed
confirmation facts keep their existing refusal/reconfirmation behavior.

## Verification after owner resolution

Independent visible and held authors exercise the actual pane and actual helper
with a paused final network preflight: resolve at the exact cutoff (one exact
allowed command), one millisecond after it (zero command and no success), and
after caller revocation (zero command). Their red tests precede the separate
implementer; a new blind critic reviews the complete closure. Full gates and
actual browser/Android acceptance remain required.
