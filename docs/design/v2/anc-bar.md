# ANC bar — Announcements on Home (V2-B5, F5)

Written 2026-10-02, before tests. Stable criteria ANC-Q1–ANC-Q10 are preserved from the contract. Authoritative batch-2 decisions fix the two silent-group holdout and the member-media exposure seam. No login, screenshots or deployed UI inspection was performed; fetchable primary docs provide behavioural references, not implementation acceptance evidence.

## References and limits

| ID | Fetched primary reference | Observable quality | Limit |
|---|---|---|---|
| R1 | [Google Classroom: Post announcements](https://support.google.com/edu/classroom/answer/6020270) | Composer, drafts, audience choice and editable announcements are explicit documented actions. | No evidence of honest per-version read state or privacy by aggregate; own requirements below. |
| R3 | [Slack: Edit or delete messages](https://slack.com/help/articles/202395258-Edit-or-delete-messages) | Editing/deleting are named actions with permissions. | Does not establish Gymloop's edited date, change note or immutable versions; these are own. |

Wodify's inaccessible page and third-party WhatsApp descriptions are excluded. No reference is treated as proof of current live UI. All criteria beyond the documented actions are labelled own.

## Criteria — all must pass

- **ANC-Q1 — Reach is stated before publish.** The publish confirmation shows the kind, the number of
  members who would see it now (`announcementReachSentence`), the absolute expiry in gym time or "until you
  take it down", and whether an image is attached; one confirmation, then publish. *From:* R1 (recipient
  count), INV-Q10 pattern. **[own]** for the consent wording.
- **ANC-Q2 — The kind choice explains itself and tells the truth about consent.** The composer's two
  kinds carry the pinned help sentences; a promotional announcement's count excludes members who have not
  agreed to news and offers and says so. *Probe:* seed three members (consented, withdrawn, never asked),
  compare the count with the member feeds. **[own]**
- **ANC-Q3 — Home stays Home.** At most three cards before "Show all"; a card is title, two-line preview,
  kind word, posted/edited date, state word; no carousel, no auto-advance, no badge counter on the tab;
  the scan action and week figure keep their positions; opening a card is one tap. *Probe:* count the
  taps and compare the Home with the announcement section removed. **[own]**
- **ANC-Q4 — Read state is honest per version.** Publish v1; member A opens it; the owner edits; A sees
  Updated, with the owner's note; member B (never opened v1) sees New and no Updated. *Probe:* the three
  member sessions in the state matrix. *From:* R3 (editing is a first-class, visible act). **[own]**
- **ANC-Q5 — An edit is never silent.** Every edited announcement shows "Edited {date}" to every member
  who can see it, and the console lists every version with its note and its read count. **[own]**
- **ANC-Q6 — No individual surveillance.** No screen, response, log line or export lists which member
  has or has not read an announcement; staff see counts only. *Probe:* grep every staff response and the
  rendered console for the seeded members' names and ids. *From:* contrast with R1 (names behind the
  count); **[own]** (DPDP minimisation, `docs/security.md`).
- **ANC-Q7 — Offline is a state, not a blank.** With the network off, Home on Android shows the cached
  cards under the word "Saved copy" with a time, opening a cached card works, and the read is delivered
  on the next successful load. **[own]**
- **ANC-Q8 — Gate 30.** Every screen reaches loading, empty, error, permission-denied and offline states
  (matrix below); a state that cannot be reached is a finding against the build.
- **ANC-Q9 — Accessible and calm.** Both Chalkline themes, 200 % text, reduced motion; the card control
  is a button exposing `aria-expanded` (`accessibilityState.expanded` on mobile); state is dot-plus-word,
  never colour alone; the image is decorative (`alt=""`) and the title is the accessible name, and the
  composer says so. No emoji. English only.
- **ANC-Q10 — Home never waits on announcements.** The announcement read starts independently of the
  rest of Home; its failure renders one inline row and leaves Home intact; no layout jump above the
  scan action once loaded.


## Evidence and silent groups

The critic records pass/fail with screenshot, accessibility tree or exact copy for every stable criterion; three rejects of one dimension escalate. Exercise live/draft/ended/taken-down, empty/loading/error/permission/offline and version-conflict states in both themes, 390 px mobile/1440 px web, large text and reduced motion. Keep Home's existing scan action usable during delayed or failed announcement fetch.

Independent `h75_announcements_holdout.sql` (75900000 prefix) covers exactly promotion-consent targeting and read-state privacy. Promotion withdrawal must remove both feed and generic member image exposure; staff never receive individual receipt state. Consent gates and media URLs are checked by tests, not inferred from screenshots. No implementation pass, screenshot or owner approval is claimed here.

Approved MEDIA seam (2026-10-02): asset-id-only public feed; current caller-JWT consent/visibility rechecked by SHP’s Edge signer before private immutable-published metadata resolution. ANC-Q2/Q6 image probes must refuse new GETs after withdrawal/take-down and expose no private RPC key fields. Historic version FK remains intact after object-only pruning and missing historic images render placeholders. The approved protected-CI architecture exception supplies infrastructure scope; this bar claims no deployed proof.
