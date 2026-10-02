# PTF quality bar — personal training front

Frozen contract bar, commissioned 2026-10-02; applies to PTF-001…034. Read with `openspec/changes/pt-front/proposal.md` and batch-2 `decisions.md`. Tests are authored after this bar. No implementation, tests or holdout suite was read for this commission.

## Fetchable references and evidence limits

**R1 — Square Appointments, Adjust your appointment settings** (official, fetched body 2026-10-02): https://squareup.com/help/us/en/article/5351-manage-your-square-appointments-account-settings . The public documentation exposes business-location timezone selection, duration-based slots, advance limits, and distinct history actions for cancelling and marking no-show with notification choice. This is the comparable operational-quality bar: explicit controls and legible consequences. Gymloop does not copy Square's pricing, notification delivery or artificial availability filter.

**R2 — ABC Glofox, Trainer Availability for Client-Side Appointment Bookings** (official, fetched body 2026-10-02): https://support.glofox.com/hc/en-us/articles/46455585200276-Trainer-Availability-for-Client-Side-Appointment-Bookings . Weekly availability, time-off exceptions, client-visible slots and removal of conflicting slots are observable functional precedents. This is a completeness comparator, not the visual-quality bar. The document has conflicting Pro App availability statements; no criterion relies on that ambiguity.

These are fetched public documentation bodies, not authenticated product inspections. No reference screenshots, tap counts, India-chain booking flow, or visual win is claimed. A critic must capture the actual Gymloop screens, accessible tree and comparable public visual evidence before declaring a visual win; documentation alone proves only the stated interaction qualities.

## Acceptance criteria (Gymloop requirements, not third-party measurements)

| ID | Observable quality / testable pass condition | Evidence |
|---|---|---|
| PTF-Q1 | At 390px, Training → booking takes at most four taps: pack, day, slot, Confirm; no typed field. Current pack has one clear booking action. | Recorded click path and screenshots; R2 supplies self-booking precedent. |
| PTF-Q2 | Confirm shows session duration and exact cancellation consequence with absolute gym-local cutoff. Cancel confirm re-evaluates current policy; at cutoff it is free, strictly after it uses one only when the flag is true. | Visible text plus independent boundary/parity tests; R1 supplies explicit scheduling controls, consumption is owner policy. |
| PTF-Q3 | Busy slots disappear. Open slots have weekday/date/time accessible names; empty states name a known reason and next action without inventing a cause. | Conflict fixture, screenshot, accessibility tree; R2. |
| PTF-Q4 | Pack displays purchased, used, booked, left-to-book and validity distinctly; waived late cancel changes effective used count and reactivates only the owner-approved unexpired/unreturned pack completed by that exact last-session forfeiture; ordinary completion remains terminal. No-show is recorded and uses zero. | Owner/manager and member fixture comparison; owner policy, not comparator behaviour. |
| PTF-Q5 | Only Booked, Attended, No-show, Cancelled by you, Cancelled by your {place}, Cancelled late - session used appear as status words, always with a dot. Past unmarked booked rows explain that the trainer must record them. | Exact-string and screenshot checks; R1's separate no-show action. |
| PTF-Q6 | All pinned refusal sentences match the proposal; interrupted/offline bookings have no fake success and retry reuses the same session id. | Request replay, offline/error states, visible and holdout app checks. |
| PTF-Q7 | Trainer with three weekly windows can be saved without leaving the page; overlap is named beside offending rows and rejected server-side. Time-off shows affected existing bookings. | Owner workflow recording; R2's multiple-window precedent. |
| PTF-Q8 | Member photo is placeholder or same-tenant currently exposed immutable MEDIA asset; member RPC returns only image_asset_id, Edge signer rechecks original-JWT trainer exposure before private-key resolution; reused staging PUT cannot replace published photo. Policy, waive and reassignment appear only for admitted roles; support preview is read-only. | Independent role/media fixtures and screenshot evidence. |
| PTF-Q9 | Both Chalkline themes at 390/1440px; 200% text, reduced motion, 44px web and 48dp Android targets, axe-clean; local zone stated when device differs. | Accessibility report, layouts and device evidence; R1 timezone precedent. |
| PTF-Q10 | Central Classes | Training mount consumes PTF's controls and CLS's panes; Home · Classes · Shop · Activity · You and Gym screen are coherent, superseded add-ons sections removed. | Final integration navigation checks; no unused-export push. |

Every applicable criterion must pass. Fresh-context critic records evidence per criterion and compares operational clarity against R1; missing captures mean unverified, never a fabricated win. Three rejections on one dimension escalate the requirement to the owner. Contract authoring grants no production/test changes or deployment approval.

PTF-Q8 consumes the owner-approved 2026-10-02 MEDIA seam: memberMediaUrl(supabase,assetId), shared Edge media verifier/signer, service-only verified publication, no public key/MIME/ETag projection, protected-CI deployment/configuration and metadata tombstones after object-only prune. No PTF-specific media route, web admin or Edge/native dependency. Booking/waiver quality criteria are unchanged.
