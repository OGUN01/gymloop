# PTF rendered caption and first-page history clarification

Orchestrator-frozen integration metadata, 2026-10-03. No policy, actor, money,
status, eligibility or new-booking requirement changes. Read with PTF-029/031,
the authoritative batch-2 shared business-noun contract and
web-member-read-cancel-declarations.md.

- A Booked session displays the unrecorded-outcome caption only when its
  **endsAt** is strictly before the current instant, as PTF-029 states. It must
  not infer attendance, no-show or completion while the session is still running
  or at its exact end. The caption is separate from the six pinned status words.
- "Waiting for your trainer to record it." is PTF-029's default gym caption.
  Other accepted business types use the already registered `ptCopy(nouns).waiting`
  and BIZ's trainer noun: instructor for dance, teacher for yoga. This follows
  the binding shared noun requirement and PTF-031; it neither changes a status
  word nor rewrites the pinned refusal vocabulary. Web and native use the same
  canonical caption helper rather than introducing a second literal.
- `loadMemberTraining` already returns the first history section. On an initial
  page without a cursor that section supplies the displayed history; a validated
  subsequent cursor uses `loadMemberTrainingHistory`. Tests place first-page
  history rows in the declared MemberTraining.history section. No redundant
  history read or unbounded pagination is required.
- The owner-approved expired-pack display remains its returned unused count,
  independently of booked sessions. "Unused" and "unspent" describe that same
  number; neither may recalculate it as unreserved or imply it is bookable.

Independent authors amend only their own fixtures and add the end-time boundary
regressions before a separate source change. Actual rendered and device evidence
remain required; this metadata is not acceptance evidence.
