# Announcements on Home (ANC-001…ANC-025)

Feature F5 of `docs/planning/v2-feature-map.md`, phase V2-B5 of `docs/planning/v2-campaign-goal.md`,
batch 2. The cross-feature names are fixed in `openspec/changes/v2-batch2-shared/shared.md` (MEDIA,
the interim notifications primitive, member-app IA, `businessNouns`); where this file disagrees with it,
that file wins and this one is corrected. Rigor: **relaxed (ADR-059, shared.md)** — one implementer,
spec-first and tests-first, every CI gate unchanged, one visible pgTAP suite (`75_announcements.sql`), no
holdout pgTAP. Two defects here would be silent, and each is pinned by a dedicated visible assertion
group rather than left to review: a promotional announcement reaching a member without marketing
consent (ANC-005), and one member's read state becoming visible to anyone else (ANC-013). Whether
either deserves a holdout is Contract question 1.

## Quality bar

Method as in `docs/design/v2/inv-bar.md`: public pages only, never authenticate into a third party.
References and their limits (fetched or searched 2026-10-02; the orchestrator's bar step may extract
this section to `docs/design/v2/anc-bar.md` with screenshots):

| ID | Reference | URL | What was observed |
|---|---|---|---|
| R1 | Google Classroom Help, "Post announcements to your students" | https://support.google.com/edu/classroom/answer/6020270 | Fetched. Text plus attachments; drafts and scheduled posts live under "Saved announcements"; audience is all students or chosen students; the poster sees how many students received it (and can open their names); posts sort newest first and can be moved to the top; edit is More > Edit then Save. **Silent on** an "edited" label, on notifying about edits, and on read receipts for the post itself. |
| R2 | Wodify Help, "Understand Announcements" | https://help.wodify.com/hc/en-us/articles/208736808-Understand-Announcements | **Search snippet only; the page itself returned HTTP 403 to a direct fetch.** The snippet states: announcements go to clients and staff, appear in the mobile app and kiosk, a push may be sent when one is created, and the length cap is 1,000 characters. Treated as indicative, not authoritative. |
| R3 | Slack Help, "Edit or delete messages" | https://slack.com/help/articles/202395258-Edit-or-delete-messages | Official page documents who may edit and how; it does not document an "edited" marker (third-party guides say Slack shows one). |
| R4 | WhatsApp "Message info" per-member read list, described by Rasayel | https://learn.rasayel.io/en/blog/whatsapp-read-receipts/ | Third-party description only. A sender can see exactly who has and has not read a message. **Deliberately not copied** (see decision 5). |

Where the references are silent the criterion is FitCruxx's own and tagged **[own]**; nobody should
assume a best-in-class product does it. The critic scores each criterion pass or fail with evidence
(a screenshot, an accessibility-tree dump or the exact string); the bar is met when all ten pass, and a
third rejection of one criterion escalates to the owner as a spec problem.

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
  count) and R4; **[own]** (DPDP minimisation, `docs/security.md`).
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

## Why

Today a gym can say something to a member only through per-member `notifications` rows: renewal
reminders and templated messages, each written, consent-checked and acknowledged one member at a time
(`supabase/migrations/20260915100007_phase6_comms.sql`). There is no way to say "closed Sunday" or "new spin
bikes" to everyone at once; it has to be said member by member or outside the product. ANC adds the
broadcast: staff compose text (and one optional image), choose who it is for, and members see it as a
card on Home. Edits are versioned so a change is never silent; staff see how many members read it,
never which ones; push arrives later with NTF and attaches without a redesign.

## Scope

In: DB (4 enums, 3 tables, 2 invariant triggers, 4 helpers, 10 RPCs, one `message_category` label),
shared contracts, web (console list, composer, detail, 8 routes, member Home section, navigation entry),
mobile (Home section with an offline cache), audit, docs and ADR-184 text. Out (recorded, not built):
push, WhatsApp and email delivery (NTF, WSP — see "Interim notifications design"); scheduled publish and a
separate pin flag ("unpin" is unpublish, Contract question 5); a member dismissing or hiding a card;
named read lists; class-cohort and plan targeting (documented hooks only); rich text, links, several
images and alt text; showing announcements in the desk (staff) app; comments or reactions; analytics
beyond counts; a second-person approval step.

## Design decisions and deliberate deviations

1. **Pull, not fan-out.** The member feed is computed at read time from `announcements`; there is no
   per-member row written at publish. Rejected: one `notifications` row per target member (the feature map's
   "notifications reuse"). `app.enforce_notification` writes an audit row for the insert and for each
   status edge, so a 3,000-member gym would write ~6,000 audit rows per version; its payload is frozen
   after creation (a versioned edit needs a new row per member per version); its graph models delivery
   (`scheduled → sent → delivered`), not reading; members who join, renew or re-consent after publish would
   never get a row; and a withdrawal after fan-out would leave a card that the consent rule says must go.
   Push (NTF) will use `notifications` rows as the **delivery record** it was designed to be.
2. **Targeting is evaluated at read time through one predicate**, `app.announcement_audience`, used by the
   feed, the read marker, the staff counts and (later) NTF. Rejected: a snapshot audience at publish
   (stale the moment a member's status or consent changes) and an RLS policy carrying the targeting
   (duplicates the predicate, cannot carry per-member read state, runs per row).
3. **Consent.** `transactional` announcements reach every addressed member in good standing;
   `promotional` ones only members whose latest `marketing` consent row is `granted` (absent means
   not granted). Showing a notice inside the app the member opened is not a send, so the `service`
   purpose is not consulted. The kind is fixed at publish and cannot be edited (editing it would be a
   silent consent bypass). Residual risk, stated: staff can mislabel a promotion as a notice; the
   mitigations are that only owner/manager publish, the confirmation names the kind, and the kind is audited.
4. **Roles.** Owner and manager publish, edit and unpublish; front desk composes drafts and discards
   them. Justification: an announcement is one voice to every member and, if promotional, a marketing
   communication with legal weight; `send_notification` is already gym-admin-only and the feature map's NTF edge cases ask for
   "campaign review before a bulk send"; front desk is the first to know about a closure, so drafting is
   kept (Contract question 13 asks the owner to confirm the split). Rejected: front desk publishes (one typo reaches everyone); owner-only (a manager
   runs the floor); no drafts (the composer would have to publish to save).
5. **Read means opened, and staff see counts only.** A receipt is written when the member opens a card.
   Staff get aggregate counts through definer RPCs that return no member identifier. Rejected: names behind
   the count (R1, R4) — behavioural data about a member the gym does not need to run an announcement;
   viewport tracking (cannot be defined or tested).
6. **Versioned, with a required note.** Each edit of title, body or image inserts an immutable version and
   requires a 3–200 character note shown to members as "what changed"; a stale editor is refused
   (`version_conflict`). Receipts are per version, so an edit makes the announcement unread-for-this-version
   again while remembering that a member read an earlier one (state `updated`). Expiry-only changes are
   not versions.
7. **One SQLSTATE.** shared.md reserves only `GL088` for ANC. Precedent: `GL055` carries many `detail` reason
   codes across the add-on sale commands, and `apps/web/app/api/add-on-orders/route.ts` maps `error.details`
   through a known-set lookup. Routes here do the same through an `Object.hasOwn` table.
8. **Deviation from MEDIA ("a placeholder renders when absent").** An announcement without an image is a
   text card with no placeholder; a grey box on a closure notice adds noise.
9. **Plain text only.** No markup, no auto-linking (nothing a member can tap that leaves the app; no
   phishing surface). A link in an announcement is shown as text.
10. **Kind words.** `transactional` is shown as "Notice", `promotional` as "News and offers".

## Fixed names (the contract — nothing here changes while agents work against it)

### Database (migration `20261003150000_announcements.sql`, sorted after SHP `…120000` and CLS `…140000`)

| Object | Name / signature |
|---|---|
| enums | `public.announcement_kind` = `transactional`, `promotional` · `public.announcement_status` = `draft`, `published`, `unpublished`, `discarded` · `public.announcement_audience` = `all_members`, `segment` · `public.announcement_membership_filter` = `any`, `live`, `not_live` |
| enum value | `alter type public.message_category add value if not exists 'announcement'`, first statement of the migration. PostgreSQL refuses to use a value added in the same transaction, so **no statement executed by this migration may reference the label** (function bodies are late-bound and may). Resulting order after CLS: `renewal, payment, fulfilment, promotion, motivation, class_update, announcement`. |
| table | `public.announcements` (tenant-scoped, direct `tenant_id`, RLS on): `id uuid pk default gen_random_uuid()`, `tenant_id uuid not null → organizations(id)`, `kind announcement_kind not null`, `status announcement_status not null default 'draft'`, `audience announcement_audience not null default 'all_members'`, `segment_member_statuses public.member_status[]`, `segment_membership announcement_membership_filter`, `current_version integer not null default 1`, `expires_at timestamptz`, `published_at timestamptz`, `closed_at timestamptz`, `created_by_staff_id uuid not null`, `created_at`, `updated_at` |
| table | `public.announcement_versions`: `id uuid pk`, `tenant_id`, `announcement_id uuid not null`, `version_no integer not null`, `title text not null`, `body text not null`, `image_asset_id uuid`, `change_note text`, `created_by_staff_id uuid not null`, `created_at` (no `updated_at`) |
| table | `public.announcement_receipts`: `id uuid pk`, `tenant_id`, `version_id uuid not null`, `member_id uuid not null`, `read_at timestamptz not null default now()`, `created_at` (append-only; no `updated_at`) |
| keys | Foreign-key names follow `<table>_tenant_id_<column>_fkey`. `announcements_tenant_id_id_key unique (tenant_id, id)`; `announcement_versions_tenant_id_id_key unique (tenant_id, id)`; `announcement_versions_announcement_version_key unique (tenant_id, announcement_id, version_no)`; `announcement_receipts_version_member_key unique (tenant_id, version_id, member_id)`. Composite FKs only, each exactly `(tenant_id, x) → parent (tenant_id, id)` (the ADR-052 meta-test admits no 3-column key): `announcements (tenant_id, created_by_staff_id) → staff`; `announcement_versions (tenant_id, announcement_id) → announcements`, `(tenant_id, created_by_staff_id) → staff`, `(tenant_id, image_asset_id) → media_assets` (SHP); `announcement_receipts (tenant_id, version_id) → announcement_versions`, `(tenant_id, member_id) → members`. Receipts carry no `announcement_id` (it is reached through the version, so version and announcement cannot disagree). |
| checks (ADR-040 names) | `announcements_segment_shape_chk` (`all_members` ⇒ both segment columns null; `segment` ⇒ statuses non-null with 1–3 elements, all contained in `active, paused, expired`, membership filter non-null; distinctness is enforced by the RPCs and the zod schema because a CHECK cannot contain a subquery) · `announcements_state_chk` (`draft`: `published_at` and `closed_at` null; `published`: `published_at` set, `closed_at` null; `unpublished`: both set; `discarded`: `published_at` null, `closed_at` set) · `announcements_version_chk` (`current_version >= 1`) · `announcements_expiry_chk` (`expires_at is null or published_at is null or expires_at > published_at`) · `announcement_versions_version_no_chk` (`>= 1`) · `announcement_versions_title_chk` (`char_length(btrim(title)) between 1 and 80`) · `announcement_versions_body_chk` (`char_length(btrim(body)) between 1 and 1500`) · `announcement_versions_change_note_chk` (`version_no = 1` ⇒ note null; `> 1` ⇒ `char_length(btrim(change_note)) between 3 and 200`) |
| indexes | `announcements (tenant_id, created_at desc, id desc)` · `announcements (tenant_id, published_at desc) where status = 'published'` · `announcements (tenant_id, created_by_staff_id)` · `announcement_versions (tenant_id, image_asset_id) where image_asset_id is not null` · `announcement_versions (tenant_id, created_by_staff_id)` · `announcement_receipts (tenant_id, member_id)` (plus the unique keys above, which cover `announcement_id` and `version_id`) |
| RLS / grants | Per `docs/data-model.md`, `revoke all … from anon, authenticated` then `grant select to authenticated` on each table; no insert, update or delete grant. Policies in the matrix template (`04_contract_meta`): `announcements_tenant_select` and `announcement_versions_tenant_select` (tenant term first, `app.is_front_office()`); `announcement_receipts_member_select` (`tenant_id = (select app.current_tenant_id())` and `(select app.current_app_role()) = 'member'` and `member_id = (select app.current_member_id())`); **no** tenant policy on receipts, **no** member policy on announcements or versions, **no** `_tenant_write` anywhere. Members read announcements only through `read_member_announcements`. |
| triggers (fused slot, as `consents` and `notifications` did) | `announcements_touch_updated_at` (ROW, BEFORE INSERT OR UPDATE) → invoker `app.enforce_announcement()`; `announcement_versions_touch_updated_at` (ROW, BEFORE UPDATE OR DELETE) → invoker `app.enforce_announcement_version()`. Both functions `revoke all … from public, anon, authenticated`. Their rules are ANC-025. No `preview_read_only` trigger is added (the tables hold no DML grant; the rule's third layer applies to DML-granted tables, and every writer here refuses impersonation in `app.announcement_actor`) — this avoids touching the shared carve-out CTE in `04_contract_meta` that INV, STI and others edit. |
| helper: staff actor | `app.announcement_actor(p_roles text[], p_allow_preview boolean default false) returns uuid` — invoker, stable. Returns the acting staff id. `42501` unless `auth.uid()` and a tenant claim exist, `app.current_app_role()` is in `p_roles`, no member id claim, and either (no impersonation, staff id claim present, and an active `staff` row matches tenant, id, `user_id` and role) or (`p_allow_preview` and an impersonation claim — returns null). Front office = `{gym_owner, gym_manager, front_desk}`; gym admin = `{gym_owner, gym_manager}`. |
| helper: member actor | `app.announcement_member_actor() returns uuid` — invoker, stable. Returns the member id. `42501` unless `auth.uid()`, role `member`, member id and tenant claims exist, no staff id, no impersonation, and a `members` row matches tenant, id and `user_id = auth.uid()` with status not `cancelled`/`blocked` and `erased_at` null (the `acknowledge_notification` rule). |
| helper: audience | `app.announcement_audience(p_announcement_id uuid, p_member_id uuid default null) returns setof uuid` — invoker, stable; the **single targeting predicate** (ANC-006). With `p_member_id` it returns that member's id or nothing; without it, every member in the audience. Execute: `service_role` only (NTF), plus use from the definer RPCs. |
| helper: audit | `app.announcement_audit(p_tenant_id uuid, p_actor uuid, p_role public.app_role, p_action text, p_record_id uuid, p_before jsonb, p_after jsonb, p_reason text) returns void` — definer, owner `postgres`, `search_path = ''`, executable by nobody else; record type is always `announcement`; action allowlist exactly the five below, anything else raises `22023`. |
| RPC: create draft | `public.create_announcement_draft(p_kind public.announcement_kind, p_title text, p_body text, p_audience public.announcement_audience, p_segment_member_statuses public.member_status[], p_segment_membership public.announcement_membership_filter, p_expires_at timestamptz, p_image_asset_id uuid) returns uuid` — definer, **VOLATILE**, `set search_path = ''`, executable by `authenticated` only; front office |
| RPC: update draft | `public.update_announcement_draft(p_announcement_id uuid, p_kind public.announcement_kind, p_title text, p_body text, p_audience public.announcement_audience, p_segment_member_statuses public.member_status[], p_segment_membership public.announcement_membership_filter, p_expires_at timestamptz, p_image_asset_id uuid) returns void` — same posture, VOLATILE; full replacement of the draft's fields; front office |
| RPC: discard | `public.discard_announcement_draft(p_announcement_id uuid) returns void` — same posture, VOLATILE; front office |
| RPC: publish | `public.publish_announcement(p_announcement_id uuid) returns table (published_at timestamptz, expires_at timestamptz, audience_count integer)` — same posture, VOLATILE; gym admin |
| RPC: edit | `public.edit_announcement(p_announcement_id uuid, p_expected_version integer, p_title text, p_body text, p_image_asset_id uuid, p_expires_at timestamptz, p_change_note text) returns table (version_no integer, new_version boolean)` — same posture, VOLATILE; gym admin. `p_expires_at` is the full replacement (null = no expiry); kind and audience are not parameters. |
| RPC: unpublish | `public.unpublish_announcement(p_announcement_id uuid) returns void` — same posture, VOLATILE; gym admin |
| RPC: list | `public.list_announcements(p_before_created_at timestamptz default null, p_before_id uuid default null) returns table (announcement_id uuid, kind public.announcement_kind, status public.announcement_status, display_status text, audience public.announcement_audience, segment_member_statuses public.member_status[], segment_membership public.announcement_membership_filter, title text, current_version integer, created_at timestamptz, published_at timestamptz, expires_at timestamptz, closed_at timestamptz, audience_count integer, read_current integer, read_any integer)` — definer, **STABLE**, same posture; front office, support preview allowed (read-only). Newest first by `(created_at, id)`, `discarded` rows omitted, at most **51** rows (the 51st only signals another page; the loader drops it and builds the next cursor with `lib/keyset.ts`). `display_status` ∈ `draft`, `live`, `ended` (published and past `expires_at`), `taken_down`. `audience_count` is non-null only for `draft` and `live`. |
| RPC: read one | `public.read_announcement(p_announcement_id uuid) returns jsonb` — definer, **STABLE**, same posture; front office, preview allowed. Keys exactly: `announcement` `{id, kind, status, displayStatus, audience, segmentMemberStatuses, segmentMembership, currentVersion, createdAt, publishedAt, expiresAt, closedAt, audienceCount, readCurrent, readAny}` and `versions` (newest first) `[{versionNo, title, body, imageAssetId, changeNote, createdAt, createdByStaffId, readCount}]`. Unknown, foreign and discarded ids are `42501`. |
| RPC: member feed | `public.read_member_announcements() returns table (announcement_id uuid, kind public.announcement_kind, title text, body text, image_asset_id uuid, version_no integer, published_at timestamptz, edited_at timestamptz, expires_at timestamptz, change_note text, read_state text, read_at timestamptz)` — definer, **STABLE**, same posture; real member only (`app.announcement_member_actor`). Live announcements targeted at the caller, transactional first then `published_at desc, id desc`. `read_state` ∈ `unread`, `updated`, `read`. `edited_at` and `change_note` are non-null only when `version_no > 1`. `read_at` = the caller's latest receipt time for that announcement (any version), else null. |
| RPC: mark read | `public.mark_announcement_read(p_announcement_id uuid, p_version_no integer) returns boolean` — definer, **VOLATILE**, same posture; real member only. Idempotent; `true` when a receipt for (caller, that version) exists afterwards, `false` when the announcement is not currently visible to the caller or the version does not exist. A new receipt is stamped `read_at = statement_timestamp()` (never a caller-supplied time). |
| advisory lock | tenant-wide, taken by `publish_announcement` before it counts: `pg_advisory_xact_lock(hashtextextended('announcements:' \|\| tenant_id::text, 0))`; then the announcement row lock (`for update`). Lock order everywhere: tenant lock, announcement row, version rows. |
| SQLSTATEs | `GL088` (with `detail`, below) · `42501` · `22023` — see "SQLSTATE table" |
| limits (mirrored in `ANNOUNCEMENT_LIMITS`) | title 1–80 characters, body 1–1500, change note 3–200 (all after trim, counted as characters); at most 10 live announcements per gym; 20 publishes per gym per rolling 24 hours (counted from `published_at`); 10 versions per announcement; expiry at most 365 days after now; list page 50 |
| audit actions | `announcement.drafted`, `announcement.discarded`, `announcement.published`, `announcement.edited`, `announcement.unpublished` |

"Good standing" = member status `active`, `paused` or `expired` and `erased_at is null` (a `paused` or
`expired` member signs in normally because renewing is what they sign in to do — `docs/security.md`).
"Live membership" = the check-in gate's predicate, a `memberships` row with status `active` or `frozen`
(`20260908071401_check_in_exactly_once.sql`).

### Shared (`packages/shared`, platform-free)

`src/api/announcements.ts`, re-exported from `src/index.ts`. Enum-backed schemas are built from
`Constants.public.Enums` of `@gymloop/db` (the `platform.ts` precedent), never hand-written lists.

- `announcementDraftRequestSchema` = `z.strictObject({ kind: z.enum(<announcement_kind>), title: trimmed 1..80, body: trimmed 1..1500, audience: z.enum(<announcement_audience>), segmentMemberStatuses: optional unique array 1..3 of ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES, segmentMembership: optional z.enum(<announcement_membership_filter>), expiresAt: optional ISO instant with offset, imageAssetId: optional uuid })` with a refinement that `all_members` carries neither segment field and `segment` carries both. Used for create and for update.
- `announcementEditRequestSchema` = `z.strictObject({ expectedVersion: z.int().min(1), title, body, imageAssetId: optional uuid, expiresAt: optional ISO instant, changeNote: optional trimmed 3..200 })`.
- `announcementReadRequestSchema` = `z.strictObject({ versionNo: z.int().min(1) })`; `memberFeedRequestSchema` = `z.strictObject({})`.
- `ANNOUNCEMENT_SEGMENT_MEMBER_STATUSES` = the generated `member_status` list without `cancelled` and `blocked`; `ANNOUNCEMENT_READ_STATES = ['unread','updated','read'] as const`; `ANNOUNCEMENT_DISPLAY_STATUSES = ['draft','live','ended','taken_down'] as const`; `ANNOUNCEMENT_REFUSAL_REASONS = ['not_draft','not_live','not_published','expiry_invalid','image_unavailable','live_limit','publish_rate_limited','version_limit','version_conflict','no_change','invalid_transition','field_frozen','version_immutable'] as const` (the last three are raised by the invariant triggers only).
- Wire types: `AnnouncementCard` `{ announcementId, kind, title, body, imageUrl: string | null, versionNo, publishedAt, editedAt: string | null, expiresAt: string | null, changeNote: string | null, readState, readAt: string | null }`; `memberAnnouncementFeedSchema` = `z.strictObject({ asOf: ISO instant, announcements: AnnouncementCard[] })`; `announcementListRowSchema`, `announcementDetailSchema` (the exact keys of `read_announcement`).
- Pinned copy (tests assert these strings; everything else is implementation-owned but must not invent numbers):
  - `ANNOUNCEMENT_KIND_LABELS = { transactional: 'Notice', promotional: 'News and offers' }`.
  - `announcementKindHelp(kind, nouns)`: transactional — "Reaches every {nouns.member} this is addressed to. Use it for closures, safety and schedule changes."; promotional — "Reaches only {nouns.members} who agreed to hear about news and offers from your {nouns.place}. Others will not see it."
  - `announcementReachSentence({ kind, count, nouns })`: 0 — "No {members} would see this right now."; 1 — "1 {member} will see this on their Home screen."; n — "{n} {members} will see this on their Home screen."; promotional appends " Only {members} who agreed to news and offers are counted."
  - `announcementSectionHeading(place)` → "From your {place}". `ANNOUNCEMENT_STATE_WORDS = { unread: 'New', updated: 'Updated', read: null }`. `ANNOUNCEMENT_STALE_WORD = 'Saved copy'`. `ANNOUNCEMENT_UPDATED_HINT = 'You read an earlier version. This one changed.'`. `ANNOUNCEMENT_EDIT_WARNING = 'Anyone who already opened the earlier version will see this marked Updated, with your note.'`. `ANNOUNCEMENT_READ_FOOTNOTE = 'A member counts as having read an announcement when they open it in the app.'`. `ANNOUNCEMENT_PRIVACY_SENTENCE = 'When you open an announcement in the app, FitCruxx records that you opened that version. Your gym sees how many members opened it, not who.'`
  - `ANNOUNCEMENT_REFUSAL_COPY` (verbatim) and `announcementRefusalMessage(reason: string)` (unknown reason → the generic last line):
    - `not_draft`: "This announcement is no longer a draft. Reload to see where it stands."
    - `not_live`: "This announcement has ended, so it can't be edited. Write a new one instead."
    - `not_published`: "This announcement isn't showing to members, so there is nothing to take down."
    - `expiry_invalid`: "Choose an end time that is in the future and within a year."
    - `image_unavailable`: "That image isn't ready. Upload it again, or publish without an image."
    - `live_limit`: "Too many announcements are showing right now. Take one down before publishing another."
    - `publish_rate_limited`: "Too many announcements were published today. Try again tomorrow."
    - `version_limit`: "This announcement has been edited as many times as allowed. Take it down and publish a new one."
    - `version_conflict`: "Someone else changed this announcement while you were editing. Reload to see the latest version, then try again."
    - `no_change`: "Nothing was changed, so no new version was published."
    - generic: "The announcement could not be saved. Nothing was changed."
- `announcementPreview(body: string): string` — whitespace collapsed; at most `previewChars` characters, cut at the last space at or before the limit, then "…" when cut.
- `SYSTEM_OWNED_MESSAGE_CATEGORIES = ['announcement', 'class_update'] as const` — categories written only by their owning feature's commands, never by gym template CRUD (ANC-022).
- `config/constants.ts`: `ANNOUNCEMENT_LIMITS = { titleMaxChars: 80, bodyMaxChars: 1500, changeNoteMinChars: 3, changeNoteMaxChars: 200, maxLivePerTenant: 10, publishesPerDay: 20, maxVersions: 10, maxExpiryDays: 365, homeCards: 3, listPageSize: 50, previewChars: 140 }`.
- Nouns come from `businessNouns(type)` (BIZ); until it lands the code imports it by that name.

### Web (`apps/web`)

- `lib/announcements.ts`: `canPublishAnnouncements(identity)` (real `gym_owner`/`gym_manager`; `FRONT_OFFICE_ROLES` from `lib/leads` is reused for the rest), `loadAnnouncementList(supabase, cursor?)`, `loadAnnouncementDetail(supabase, announcementId)` (validated by `announcementDetailSchema`; null when the RPC says `42501`), `announcementRpcFailure(error: { code: string; message: string; details?: string | null }): Response` (the SQLSTATE and `GL088` reason table below, by `Object.hasOwn`).
- `lib/member-announcements.ts`: `loadMemberAnnouncementFeed(supabase): Promise<{ asOf: string; announcements: AnnouncementCard[] }>` — calls `read_member_announcements`, then `mediaDisplayUrl(assetId)` for exactly the rows returned that have an image, validates with `memberAnnouncementFeedSchema`. A card whose image URL cannot be minted renders as a text card; the feed does not fail.
- Routes (all `Cache-Control: no-store`; session before body; envelope per `lib/api.ts`; the `[announcementId]` segment must be a uuid or the answer is 400 `invalid_request`):
  - `POST /api/announcements` (front office; `announcementDraftRequestSchema`) → `data: { announcementId }`.
  - `POST /api/announcements/[announcementId]/draft` (front office; same schema) → `data: { updated: true }`.
  - `POST /api/announcements/[announcementId]/discard` (front office; `{}`) → `data: { discarded: true }`.
  - `POST /api/announcements/[announcementId]/publish` (gym admin; `{}`) → `data: { publishedAt, expiresAt, audienceCount }`.
  - `POST /api/announcements/[announcementId]/edit` (gym admin; `announcementEditRequestSchema`) → `data: { versionNo, newVersion }`.
  - `POST /api/announcements/[announcementId]/unpublish` (gym admin; `{}`) → `data: { unpublished: true }`.
  - `POST /api/member/announcements/feed` (real member, cookie or bearer; `{}`) → `data: { asOf, announcements }`. A POST because `packages/api-client` is POST-only; it is idempotent and side-effect-free. Web server components call `loadMemberAnnouncementFeed` directly without HTTP.
  - `POST /api/member/announcements/[announcementId]/read` (real member; `announcementReadRequestSchema`) → `data: { recorded: boolean }`.
- Pages and components (console, `FRONT_OFFICE_ROLES` and support preview read-only): `app/(console)/announcements/page.tsx` (list with filters All · Live · Drafts · Ended), `announcements/new/page.tsx`, `announcements/[announcementId]/page.tsx` (detail: member-view preview, reach, versions with read counts, actions), `announcements/[announcementId]/edit/page.tsx`; client components `announcement-composer.tsx` (one component for new, edit-draft and edit-published) and `announcement-actions.tsx` (Publish, Take down, Discard confirm panels). Navigation: one exact-match line in `app/(console)/layout.tsx` adding `{ href: '/announcements', label: 'Announcements' }` for front office and to the preview list; the e2e role allow-list is amended in a `spec:` commit.
- Member Home: `app/member/announcements-section.tsx` (server, renders `announcementSectionHeading`, up to `homeCards` cards, "Show all N" beyond) and `app/member/announcement-card.tsx` (client; a `<button aria-expanded>` that expands the card inline, posts the read once per (announcement, version) on the first open and shows `ANNOUNCEMENT_STATE_WORDS`); inserted into `app/member/page.tsx` by one exact-match edit after the `member-hero` section. Styles in `app/styles/announcements.css` (Chalkline `cl-*` tokens; one import line each in the console and member layouts).
- `app/privacy/page.tsx` gains `ANNOUNCEMENT_PRIVACY_SENTENCE`. `app/(console)/messages/message-forms.tsx` and `app/api/message-templates/route.ts` exclude `SYSTEM_OWNED_MESSAGE_CATEGORIES` from gym template categories (route answers 422 for them).

### Mobile (`apps/mobile`)

- `lib/announcements.ts` — pure logic and storage. `ANNOUNCEMENT_CACHE_KEY = 'gymloop.announcements-cache'`; one SecureStore value `{ scope: { tenantId, userId, memberId }, fetchedAt, announcements, pendingReads: [{ announcementId, versionNo }] }` (a cache write that the platform rejects is skipped silently — the screen then simply has no cache). `resolveAnnouncementFeed(input: { fetched: AnnouncementCard[] | null; cached: CachedFeed | null; scope }): { cards: AnnouncementCard[]; stale: boolean; fetchedAt: string | null }` (fresh fetch wins; else a cache with the **same scope** is returned as stale; else empty); `applyLocalRead(cards, announcementId, versionNo)` (optimistic `read`); `loadAnnouncementCache(scope)`, `saveAnnouncementCache(...)`, `queueRead(...)`, `flushPendingReads(api, scope)` (posts each pending read, idempotent, drops entries the server answers `recorded: false` or 404).
- `lib/use-announcements.ts`: `useAnnouncements()` → `{ cards, stale, fetchedAt, loading, error, reload, markRead }`; the fetch is `api.post('/api/member/announcements/feed', {})` and does not share a promise with `useMemberSnapshot`.
- `components/announcements.tsx`: `AnnouncementsSection` built from the existing `Row` (`expanded`), `Status`, `StateMessage` and `Eyebrow`; inserted into `app/(member)/index.tsx` by one exact-match edit after the first `<Rule />`.

## Interim notifications design (shared primitive 3)

ANC owns this primitive. It is a **convention plus one enum label**, not a helper function, so no migration
depends on a later one (CLS `…140000` sorts before ANC `…150000`).

1. `notifications` is the **delivery record**, written only for events that need delivery or an inbox
   presence (CLS cancellation notices now, push later). Content that has its own table (announcements)
   keeps it there.
2. A feature that writes an in-app notice before NTF does so in its own definer RPC, in the same
   transaction as the business event: insert `channel = 'in_app'`, `status = 'scheduled'`, its own
   `category`, `template_key = null`, `dedupe_key = '<feature>:<event>:<subject_uuid>:<member_uuid>'`
   (lowercase hyphenated uuids; unique per tenant by the existing index), `related_type`/`related_id` = the
   subject, `payload = {"body": "<member-facing sentence, <= 500 chars>", …}` (the Home "latest from your
   gym" row and `/member/messages` read `payload.body`); then update to `sent` in the same transaction. The
   RPC must itself have checked what `send_notification` checks: member in good standing, gym eligible, and
   — for a promotional category (`promotion`) — the latest `marketing` consent granted. A transactional
   category (`class_update`, `announcement`) needs no consent row (Contract question 3). The definer context
   (`current_user = postgres`) is what lets this skip the direct-write availability check; the
   `scheduled → sent` audit rows are written by `app.enforce_notification` as for any edge.
3. ANC itself writes **no** `notifications` rows. Its proof obligation is ANC-022: the new label is
   accepted by the unchanged lifecycle and the member can acknowledge such a row.
4. **How NTF attaches.** On `announcement.published` (and, if NTF decides, a new version) NTF takes its
   recipients from `app.announcement_audience(<announcement_id>)` **at send time**, never from a stored
   snapshot, so consent withdrawal or a status change between publish and send removes the member without a
   send. Per recipient it writes one `notifications` row: `channel = 'push'`; `category = 'promotion'` for a
   promotional announcement (so the existing `app.notification_consent_purpose` maps it to `marketing`
   unchanged) and `'announcement'` for a transactional one (maps to `service`; whether a closure notice may
   go to a member with no `service` consent row is NTF's decision, Contract question 3);
   `dedupe_key = 'announcement:' || <announcement_id> || ':v' || <version_no> || ':' || <member_id>`;
   `related_type = 'announcement'`; `related_id = <announcement_id>`; `payload = {"body": <title>,
   "announcementId": …, "versionNo": …}`. Quiet hours, rate limits and campaign review are NTF's. A push
   click sets `clicked_at` on the notification only; the read receipt is written only when the member opens
   the card in the app. Minors route to the guardian's device (GRD).
5. **Hooks, documented and not built.** CLS class cohorts: a later migration adds an `announcement_audience`
   value and a join table and amends only `app.announcement_audience`. PLC plan targeting: same. GRD: may
   amend the same function to require the guardian's consent record for a minor's promotional reach.

## EARS requirements

- **ANC-001 (draft).** WHEN real front-office staff (owner, manager, front desk; never an impersonation or preview identity) save a draft with a kind, a trimmed title of 1–80 characters, a trimmed body of 1–1500 characters, an audience, an optional expiry and an optional image of their own gym THE SYSTEM SHALL create one `draft` announcement and its version 1, stamp the creator, and write `announcement.drafted`. A draft is readable only by front-office staff of the same gym. Segment audiences carry 1–3 distinct statuses from `active`, `paused`, `expired` and a membership filter; `all_members` carries neither (else `22023`). An expiry is not validated at draft time.
- **ANC-002 (draft edit and discard).** Any front-office staff of the gym SHALL be able to update (full replacement, including the kind) or discard a draft. Update or discard of a non-draft SHALL fail `GL088 not_draft`. Discard sets `discarded` and `closed_at` and writes `announcement.discarded`; discarded rows vanish from every list and read. Draft updates are not audited (a draft is not member-visible; the first visible state is publish).
- **ANC-003 (who publishes).** Only a real owner or manager SHALL publish, edit a published announcement, or take it down. Front desk, trainer, member, platform and impersonator callers SHALL be refused `42501`; the console shows front desk the composer with Save draft and the sentence "Ask an owner or manager to publish.", not a hidden control. A trainer sees no Announcements entry.
- **ANC-004 (publish).** WHEN a gym admin publishes a draft THE SYSTEM SHALL, in one transaction holding the tenant lock, re-validate and then set `status = 'published'` and `published_at = statement_timestamp()`: an expiry must be null or in the future and at most 365 days away (`expiry_invalid`); an image must be a confirmed, undeleted `announcement` asset of the gym (`image_unavailable`); fewer than 10 announcements may be live (`live_limit`) and fewer than 20 published in the rolling 24 hours (`publish_rate_limited`). It writes `announcement.published` carrying the audience count and returns it. Two concurrent publishes SHALL never exceed either cap.
- **ANC-005 (kind and consent).** A `transactional` announcement SHALL be visible to every member its audience addresses who is in good standing. A `promotional` one SHALL be visible only to members whose latest `marketing` consent row (`recorded_at desc, id desc`) has `granted = true`; no row means not granted. This SHALL be evaluated on every read, so a withdrawal removes the card with no send and a later grant restores it while the announcement is live. The `service` purpose is not consulted for in-app display. The kind SHALL NOT change after the draft leaves `draft` (ANC-025).
- **ANC-006 (audience predicate).** `app.announcement_audience(announcement, member?)` SHALL be the only place targeting is decided. A member is in the audience when they are in good standing, the announcement's kind rule (ANC-005) holds, and: `all_members`, or `segment` with the member's status in `segment_member_statuses` and the membership filter satisfied (`any`; `live` = holds a live membership; `not_live` = holds none). Cancelled, blocked and erased members are never in an audience. The feed, the read marker, the publish count, the staff counts and NTF SHALL all use this function.
- **ANC-007 (live window and order).** An announcement SHALL be live while `status = 'published'` and (`expires_at` is null or later than `statement_timestamp()`); expiry is derived, no sweeper runs. The member feed SHALL return only live announcements whose audience contains the caller, transactional first, then `published_at` descending, then `id`.
- **ANC-008 (edit is versioned).** WHEN a gym admin edits the title, body or image of a live announcement THE SYSTEM SHALL require `p_expected_version` to equal `current_version` (`version_conflict`), a change note of 3–200 trimmed characters (`22023` otherwise), fewer than 10 versions (`version_limit`), insert version n+1 with the note and the editor, bump `current_version`, and write `announcement.edited` carrying the note as the reason. Kind and audience cannot be edited. An edit changing neither content nor expiry SHALL fail `no_change`. An announcement that is not live SHALL fail `not_live`.
- **ANC-009 (expiry-only change).** An edit that changes only the expiry SHALL write no version, need no note, obey the ANC-004 expiry rule, and write `announcement.edited` with `content_changed = false`. An ended announcement cannot be extended (`not_live`).
- **ANC-010 (take down).** WHEN a gym admin takes down a published announcement (expired or not) THE SYSTEM SHALL set `unpublished` and `closed_at` and write `announcement.unpublished`; the announcement SHALL leave every member feed at once, its receipts and counts SHALL remain, and it SHALL NOT be republishable. A non-published announcement fails `not_published`.
- **ANC-011 (receipts).** A member SHALL have read version v when a receipt exists for (member, v). `mark_announcement_read` SHALL, for a real member session, record a server-stamped receipt for that version idempotently (at most one per member and version) when the announcement is live and the caller is in its audience, and return `true` whenever that receipt exists afterwards. Any other case — unknown id, another gym's id, not targeted, ended, taken down, no such version — SHALL return `false` with no distinction between them (no oracle). Older versions may be marked after a newer one exists. The apps SHALL call it only when the member opens the announcement, never when it is merely listed.
- **ANC-012 (member read state).** For each feed card, `read_state` SHALL be `read` when a receipt exists for the current version, `updated` when receipts exist only for earlier versions, and `unread` otherwise. Version 1 cards carry no `edited_at` or `change_note`; later versions carry the version's creation time and its note. The apps SHALL show `New` for `unread`, `Updated` for `updated` (with `ANNOUNCEMENT_UPDATED_HINT` and the note when opened), nothing for `read`, and "Edited {date}" for every card with `version_no > 1`.
- **ANC-013 (privacy and counts).** Receipts SHALL be readable only by the member they belong to: staff, trainers, platform users and other members SHALL read zero receipt rows directly, and no RPC SHALL return a member identifier derived from a receipt to staff. Counts SHALL be: for `draft` and `live` announcements, only receipts of members **currently in the audience** (so a count never exceeds `audience_count`); for `ended` and `taken_down`, all receipts and no audience count. `read_current` counts distinct members with a receipt for the current version, `read_any` distinct members with a receipt for any version, a version's `readCount` distinct members for that version.
- **ANC-014 (staff read model).** `list_announcements` and `read_announcement` SHALL be front-office only (support preview allowed, read-only) and answer `42501` for another gym's or an unknown id, indistinguishable. The list SHALL be newest first by `(created_at, id)`, omit discarded rows, return at most 51 rows, and carry `display_status`, the current title and the ANC-013 counts. The detail SHALL return the header, the audience count for `draft`/`live`, and every version, newest first, with its note, creator id and read count.
- **ANC-015 (audit).** Draft creation, discard, publish, edit and take-down SHALL write `audit_log` through `app.announcement_audit`, attributed to `auth.uid()` and role, record type `announcement`, with no title, body or image in `before`/`after`. Shapes: `drafted` after `{status:'draft', kind, audience}`; `discarded` before `{status:'draft'}` after `{status:'discarded'}`; `published` before `{status:'draft'}` after `{status:'published', kind, audience, version_no:1, expires_at, audience_count}`; `edited` before `{version_no, expires_at}` after `{version_no, expires_at, content_changed}` with the note as `reason` (null for expiry-only); `unpublished` before `{status:'published', version_no}` after `{status:'unpublished'}`. Reads and receipts are not audited.
- **ANC-016 (tenancy and grants).** The three tables SHALL be RLS-enabled with the policies and grants in "Fixed names"; `authenticated` SHALL hold no insert, update or delete on any of them; every public RPC SHALL be executable by `authenticated` only (revoked from `public`, `anon`, `service_role`); tenant is read from the claim, never from a parameter; a foreign gym's or unknown id SHALL be `42501` or, for the member read marker, `false`. Existing schema meta-tests are amended (see "Test and deployment order").
- **ANC-017 (image).** An announcement MAY carry one image: a `media_assets` row of kind `announcement`, same gym, confirmed, not deleted, attached by id; the database stores no URL. Members SHALL receive a short-lived presigned display URL (TTL `MEDIA_LIMITS.displayUrlTtlSeconds`) only through the feed route and only for cards the caller can see. Removing or replacing the image is a content edit (a new version). A card without an image is a text card.
- **ANC-018 (API).** The eight routes SHALL behave as in "Web", validate through the shared schemas, return the typed envelope, set `Cache-Control: no-store`, identify the caller before reading the body, map SQLSTATEs and `GL088` reasons through the table below by `Object.hasOwn`, and never place an announcement body, a token or a member id in a log, an error message or a URL query.
- **ANC-019 (console).** The console SHALL provide: a list with dot-plus-word status (`Live`, `Draft`, `Ended`, `Taken down`), kind word, audience summary, dates in gym time (`gymTimeLabel`) and "Read by X of Y" for live rows (only "Read by X" for ended rows) with `ANNOUNCEMENT_READ_FOOTNOTE`; a composer (kind with `announcementKindHelp`, title and body with character counters, optional image through SHP's upload flow, audience controls, optional end date and time in gym time, Save draft, and for gym admins Review and publish); a publish confirmation with `announcementReachSentence` and the expiry; an edit form that requires the note and shows `ANNOUNCEMENT_EDIT_WARNING`; a take-down confirmation; a detail page with the preview exactly as a member sees it, the audience count and the version list. In support preview every control is absent and the pages are read-only. States per the matrix.
- **ANC-020 (member web Home).** `/member` SHALL render `AnnouncementsSection` after the greeting: up to three cards then "Show all N"; a card is kind word, title, `announcementPreview`, posted or edited date and state word; opening it expands the full body and image inline and, once per (announcement, version) per page load, posts the read; the section is absent when there are none; a failure renders one inline row and never blocks the rest of Home.
- **ANC-021 (mobile Home and offline).** The mobile Home SHALL show the same section. Fetching is independent of the member snapshot. WHEN the fetch fails and a cache for the same (tenant, user, member) exists THE SYSTEM SHALL show the cached cards flagged `ANNOUNCEMENT_STALE_WORD` with the fetch time; with no cache, one inline row. Opening a cached card SHALL work; its read is kept in `pendingReads` and flushed after the next successful fetch (idempotent, never double-counted). A cache from another account or gym is ignored and overwritten. Composing, publishing, editing and taking down need a connection and are not offered on mobile.
- **ANC-022 (interim notifications).** The `message_category` label `announcement` SHALL exist, and a `notifications` row written as the convention above with that category SHALL pass `app.enforce_notification` unchanged and be acknowledgeable by its member through `acknowledge_notification` (proof of the unchanged lifecycle). Gym template CRUD SHALL NOT offer or accept `announcement` or `class_update`. ANC SHALL write no `notifications` row.
- **ANC-023 (copy and consent).** Every user-visible string SHALL follow the product voice: specific, honest, no invented numbers; the pinned strings in "Shared" are asserted verbatim; nouns come from `businessNouns`; `/privacy` states what the receipt records and that staff see counts only.
- **ANC-024 (data lifecycle).** `announcements` and `announcement_versions` hold gym content, no member personal data (retained with the gym, 8 years, not erasable). `announcement_receipts` holds (member, version, time): retained 1 year after the announcement's `closed_at` or `expires_at`, erasable by `delete` on a DPD-006 request. Both are rows in `docs/security.md`; no job is built, like the other rows.
- **ANC-025 (structural integrity).** `app.enforce_announcement` SHALL set `updated_at`, freeze `id`, `tenant_id`, `created_by_staff_id`, `created_at` always and `kind`, `audience`, `segment_*` once the status is not `draft`, allow only the transitions `draft → published | discarded` and `published → unpublished`, allow `current_version` to change only by exactly +1 while `published`, and freeze `published_at` and `closed_at` once set; a refused transition or version bump raises `GL088 invalid_transition`, a refused change to a frozen column `GL088 field_frozen`. `app.enforce_announcement_version` SHALL refuse every delete and every update unless the row is version 1 of an announcement whose status is `draft` (identity columns and the null note unchanged), raising `GL088 version_immutable`. These rules bind every writer including `postgres`-owned code.

## State matrix (gate 30)

| Surface | Loading | Empty | Error | Permission denied | Offline | Other |
|---|---|---|---|---|---|---|
| Console list | skeleton rows, `aria-busy` | "No announcements yet. Post a closure, a new class or an offer and it appears on members' Home." and per-filter "Nothing live right now." | alert with Try again | trainer or non-front-office: not-found page; support preview: read-only, no controls | banner "You're offline. Announcements can't be loaded or saved until you reconnect." with retry | pagination "Load older" |
| Composer | draft load skeleton | n/a | field errors; refusal copy from `ANNOUNCEMENT_REFUSAL_COPY` | front desk: Save draft only plus "Ask an owner or manager to publish." | Save and Publish disabled with the offline banner | image: uploading, too large, unsupported type, failed (publish without it); `version_conflict` panel with Reload; saving busy |
| Detail | skeleton | no versions never occurs | alert with Try again; not found for foreign/discarded ids | as list | as list | states `Draft`, `Live`, `Ended`, `Taken down` each with only the actions that apply |
| Member web Home section | Home renders without it | section absent | inline row "Announcements couldn't be loaded. Try again." | n/a (members only) | browser offline = the error row (no web cache) | New, Updated, Read; expired mid-view removed on next load; opened card shows hint and note |
| Mobile Home section | Home renders without it | section absent | no cache: inline row; cache: stale cards | n/a | cache: cards under "Saved copy" with time; no cache: row "Announcements will appear when you're back online." | pending reads flushed on next success; account change ignores the cache |

## SQLSTATE table

Refusal order, identical in every RPC: actor (`42501`) → id resolution and row lock (`42501`) → malformed input
(`22023`) → state (`not_draft`, `not_live`, `not_published`) → `version_conflict` → resource (`image_unavailable`)
→ rule (`expiry_invalid`, `no_change`) → limits (`version_limit`, `live_limit`, `publish_rate_limited`).

| Code / `detail` | Raised by | Web answer |
|---|---|---|
| `42501` | any role/session/tenant failure; unknown, foreign or discarded id | 403 `not_permitted` (create); 404 `announcement_not_found` (id routes) |
| `22023` | blank/over-long title, body or note; bad segment shape; bad audience/kind combination; a change note missing or short on a content edit; bad allowlist action | 400 `invalid_request` |
| `GL088` `not_draft` | update, discard, publish | 409 `announcement_not_draft` |
| `GL088` `not_live` | edit | 409 `announcement_not_live` |
| `GL088` `not_published` | unpublish | 409 `announcement_not_published` |
| `GL088` `expiry_invalid` | publish, edit | 422 `announcement_expiry_invalid` |
| `GL088` `image_unavailable` | create, update, publish, edit | 422 `announcement_image_unavailable` |
| `GL088` `live_limit` | publish | 409 `announcement_live_limit` |
| `GL088` `publish_rate_limited` | publish | 429 `announcement_rate_limited` (`apiFail('too_many_requests', …)`, the key INV added to `lib/api.ts`) |
| `GL088` `version_limit` | edit | 409 `announcement_version_limit` |
| `GL088` `version_conflict` | edit | 409 `announcement_version_conflict` |
| `GL088` `no_change` | edit | 422 `announcement_no_change` |
| `GL088` `invalid_transition`, `field_frozen`, `version_immutable` | invariant triggers only (never from an RPC) | 500 `announcement_failed` |
| anything else | | 500 `announcement_failed` |

The message of every 4xx is the matching `ANNOUNCEMENT_REFUSAL_COPY` sentence (404: "That announcement isn't available.").

## Operational preconditions (owner-gated; not performed by this change)

1. **Marketing consent must exist for promotional reach to be non-zero.** Members with no `marketing` row
   are, by rule, not reached by a promotion. The composer's count says so; recording consent is the existing
   front-desk flow (`record_consent`). Notices are unaffected.
2. SHP's media infrastructure (R2 bucket, upload routes, `mediaDisplayUrl`) must be live for images; text
   announcements work without it. Campaign order puts SHP (V2-B2) before ANC (V2-B5).
3. No Auth, signup or release-channel change. The Android build is part of V2-R (versionCode 5).

## Test and deployment order

1. `spec:` commits (one author, relaxed rigor; the implementer touches no test): this proposal; visible
   pgTAP `supabase/tests/75_announcements.sql` (fixture prefix `75000000-0000-4000-8000-…`, `begin;` …
   `rollback;`); amended meta-suites: `04_contract_meta.sql` (matrix rows `('announcements','is_front_office',null,null)`,
   `('announcement_versions','is_front_office',null,null)`, `('announcement_receipts',null,null,'own')`; the
   definer allowlist gains exactly ten public signatures with the volatilities above plus
   `app.announcement_audit`; the trigger assertion needs no carve-out), `31_comms_schema_consent.sql` lines
   84–86 **and** the holdout `supabase/tests-holdout/h29_comms_holdout.sql` lines 215–217, which pin
   `message_category` to its five original labels — the orchestrator amends both to the final list
   (`…, motivation, class_update, announcement`), the holdout by someone who may read it (ADR-060 bars the
   implementer, not the orchestrator); TypeScript suites named `announcements-*` beside their siblings
   (shared schemas and copy; `lib/announcements`; the eight routes; console components; member section;
   mobile `lib/announcements`).
2. 75_announcements.sql covers at least: structure (enums, columns, keys, checks, indexes, policies, grants,
   triggers, function posture and volatility, `announcement` label present); every RPC by role and by gym
   (owner/manager/front desk/trainer/member/platform/impersonator/other gym); the refusal order; the
   lifecycle and graph; consent matrix (consented, withdrawn, never asked, re-granted) against the feed;
   segment matrix (status × membership filter); version semantics across three members (ANC-Q4);
   receipt privacy (staff and other member read nothing directly; counts never exceed the audience);
   caps and the rolling window; the tenant lock key present in `publish_announcement`'s definition;
   immutability triggers as `postgres`; ANC-022 conformance. An integration test races two publishes at the
   live cap.
3. Migration `20261003150000_announcements.sql` only, in the single batch-2 push after batch 1 has settled
   (ADR-177: `migrate` succeeded, types regenerated). Prove locally with `scripts/pgtap/sweep.py` splicing
   all batch-2 migrations together; wait for the DB run.
4. Regenerate `packages/db/types/database.ts` with `supabase gen types typescript --linked`; push types,
   then TypeScript tests (`spec:`), then implementation in separate commits; wait for the schema-drift
   and `ci.yml` runs.
5. Web verification first; Android hot-reload after, with the owner.

## Requires / Provides

**Requires.** SHP: `media_assets` with `unique (tenant_id, id)` (otherwise the image FK cannot exist),
columns `kind`, `confirmed_at`, `deleted_at`, kind `announcement`, `register_media_asset`, the upload and
confirm routes, `mediaDisplayUrl`, and migration `…120000` applied first. CLS: its `class_update` label in
`…140000` (ANC's label sorts after it). BIZ: `businessNouns` and a way to read the gym's business type
from a server component and the mobile snapshot (Contract question 7). INV: the `too_many_requests: 429` key
in `apps/web/lib/api.ts` `STATUS` (already present in the working tree from INV's implementation; ANC adds
nothing to that file). Existing: `app.current_*` accessors,
`app.is_front_office`, `app.is_gym_admin`, `consents`, `members`, `memberships`, `staff`, `audit_log`,
`lib/keyset.ts`, `lib/time.ts gymTimeLabel`, `FRONT_OFFICE_ROLES`, the Chalkline kit.

**Provides.** The `announcement` label and the interim-notification convention (CLS follows it);
`app.announcement_audience` (NTF recipients; GRD and cohort hooks); the NTF attach contract above;
`SYSTEM_OWNED_MESSAGE_CATEGORIES`; Home insertion points on web and mobile; the console navigation
entry; ADR-184. Nothing else is changed in another feature's tables or functions.

## ADR-184 text

**ADR-184 — Announcements on Home: a pull-based, versioned broadcast with per-version read receipts, consent evaluated at read time (owner-approved feature map F5, 2026-10-02).** Decisions, each with the alternative rejected. (1) *The member feed is computed at read time from `announcements`, not fanned out as `notifications` rows.* `app.enforce_notification` audits the insert and every status edge and freezes the payload, so a broadcast would cost two audit rows per member per version, need a new row per member per edit, give members who join after publish nothing, and leave a card standing after consent is withdrawn; the table's graph models delivery, not reading. `notifications` stays the delivery record for NTF. Rejected: fan-out ("notifications reuse" in the feature map). (2) *One targeting predicate, `app.announcement_audience`, used by the feed, the read marker, the staff counts and NTF.* Rejected: a snapshot audience at publish, and an RLS policy carrying the targeting. (3) *Kind decides consent.* Promotional requires the latest `marketing` consent granted; transactional needs none; in-app display is not a send, so the `service` purpose is not consulted; the kind cannot change after the draft stage because that would be a silent consent bypass. Residual risk: mislabelling by staff, mitigated by admin-only publish, a kind-naming confirmation and audit. (4) *Owner and manager publish; front desk drafts.* An announcement is one voice to every member and may be marketing; `send_notification` is already admin-only; the feature map's NTF edge cases ask for review before a bulk send. Rejected: front-desk publish, owner-only, no drafts. (5) *Versioned edits.* Immutable version rows, a current pointer, a required 3–200 character note shown to members, an optimistic `expected_version`, receipts per version, so an edit is visible (`Updated`) to anyone who read an earlier version and a stale editor is refused. Rejected: silent in-place edit; carrying receipts across versions. (6) *Read means the member opened the card; staff see counts only, restricted to the current audience so a count never exceeds the reach.* Rejected: names behind the count (data the gym does not need to run an announcement; DPDP minimisation) and viewport tracking. (7) *One SQLSTATE, `GL088`, with `detail` reason codes* (the `GL055` precedent), because shared.md reserves one. (8) *The interim notification primitive is a convention plus the `announcement` label, not a helper*, so no migration depends on a later one; the label is not referenced in the migration that adds it (a PostgreSQL restriction), and the two tests that pin the original five `message_category` labels are amended. (9) *Reads for mobile use POST* because `packages/api-client` is POST-only. (10) *Plain text, optional decorative image, no scheduled publish, no pin flag, no dismiss, no names* — each recorded as out of scope, not forgotten.

## Contract questions for the orchestrator

1. **Rigor.** shared.md calls ANC relaxed. The two silent defects (a promotion reaching a non-consenting member; read state visible to others) are covered by dedicated visible assertion groups. Do you want a holdout pgTAP (`h75`) for those two groups only?
2. **One SQLSTATE.** `GL088` with ten RPC `detail` reasons (thirteen with the trigger-only ones) follows `GL055`. If you would rather reserve `GL088`–`GL089`, say so before tests are written.
3. **Consent for transactional notices.** In-app display needs no consent row (decision 3). For the interim convention and for NTF: may a closure or class-cancellation notice reach a member with no `service` consent row? The existing `app.notification_consent_purpose` would require it for category `announcement`/`class_update`; this contract assumes transactional rows skip consent, and NTF decides for push.
4. **Message-category pins.** `31_comms_schema_consent.sql` and holdout `h29_comms_holdout.sql` pin five labels. CLS and ANC both extend the list; one amendment to the final order is needed. Confirm who owns the holdout edit.
5. **Unpin.** "Expiry and unpin" is realized as optional expiry plus take-down (irreversible). A separate pin flag, a "pinned above everything" order, or a republish are not built; confirm or add.
6. **api-client is POST-only.** The member feed is a POST route. Alternatively hoist a `get` into `packages/api-client` once, for ANC, SHP and CLS together.
7. **Business type for nouns.** ANC needs the gym's `business_type` in server components and in the mobile snapshot. BIZ must name the loader; until then ANC defaults to `gym` nouns.
8. **Actor helper duplication.** INV's `app.member_invite_actor(p_roles text[])` now exists (returns `(tenant_id, staff_id, user_id, role)` and refuses any impersonation). ANC needs a variant that admits a support preview for its read RPCs and returns just the staff id, so `app.announcement_actor` is its own function. Collapse the two into one shared helper at integration, or keep them per-feature?
9. **Aggregate-only read counts.** Staff cannot see who has not read a safety or closure notice. Confirm aggregate-only for v2, or name a transactional-only exception.
10. **Template category hygiene.** ANC edits `message-forms.tsx` and `message-templates/route.ts` to hide system-owned categories (also covers CLS's `class_update`). Confirm this cross-feature touch, or move it to the integrator.
11. **Plan and cohort targeting** are hooks only (decision 2, "Interim notifications design" item 5); confirm that status + live-membership is enough for v2.
12. **Bar evidence.** The Wodify page returned 403; the bar step should either fetch R2 another way or drop it. Screenshots and `docs/design/v2/anc-bar.md` are the orchestrator's if wanted.
13. **Who publishes.** Recommended and drafted: owner and manager publish, edit and take down; front desk drafts and discards. The feature map says "owner/staff" and its NTF note says "campaign review before a bulk send (front-office role boundary)", which could also be read as front desk being the sender. If the owner wants front desk to publish, the change is the role array passed to `app.announcement_actor` in `publish_announcement`, `edit_announcement` and `unpublish_announcement` plus ANC-003 and the composer's front-desk state; nothing else moves.
