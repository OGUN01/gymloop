# Phase 7 follow-up surface

This third Phase 7 slice applies UX7-006/007/013/014 and ADR-128 directly to the
existing `/red-list` work queue. The approved owner v2 board's “People to follow
up” list is the visual bar. The slice changes presentation and user-facing label
clarity only; it does not change RET-001–008, the `red_list_cases` read, ordering,
cursor, roles, preview read-only behavior, form action/fields or follow-up write.

## Frozen interface

- The route and link remain `/red-list`, but the page title becomes “People to
  follow up” and the supporting sentence keeps the exact meaning that these are
  members who stopped coming, longest away first. “Red list” remains an internal
  route/domain term rather than the primary user-facing heading.
- The shared 1440px canvas, 32px desktop inset, 20px mobile inset, 32/38/600
  title, porcelain/ink surfaces and emerald/mint action system are reused. The
  Members route is a finished 44px control, not a raw underlined link.
- Each case is one spacious operational row/group: quiet first-initial mark;
  linked member name and phone; prominent `days_absent`; the existing truthful
  last-attendance wording; and the existing latest-contact sentence, including
  the explicit “Nobody has contacted them yet.” state. No illustrated name,
  last-visit value or recovery fact is synthesized.
- The existing `MutationForm` stays attached to its case. Channel/outcome remain
  generated-enum selects, note stays optional, hidden case id stays exact and the
  POST target remains `/api/follow-ups`. The submit label becomes the channel-
  neutral “Log follow-up”. Fields and button are 48px, opaque and keyboard clear.
- Problem/load errors, empty truth and Next page remain present with their same
  semantics. The empty state is a calm intentional surface; errors use semantic
  risk styling and never resemble an empty queue.
- At desktop width identity, absence evidence and action form have a deliberate
  productive hierarchy derived from the owner board. At or below 40rem each case
  and form becomes one column with no clipped label/action or page overflow.
- Only `apps/web/app/(console)/red-list/page.tsx` and private `follow-up-*` CSS in
  `apps/web/app/globals.css` change. No export, dependency, query, helper, client
  component, mutation behavior or domain calculation is added.

## Acceptance scenarios

### Requirement: The queue says who needs the next action

#### Scenario: Open cases exist
- **WHEN** staff opens `/red-list`
- **THEN** “People to follow up” leads a longest-away-first operational queue
- **AND** every row preserves member identity, current days away, attendance evidence and latest-contact truth

### Requirement: Follow-up logging remains exact

#### Scenario: Staff records an outcome
- **WHEN** an eligible non-preview user submits a row's form
- **THEN** the existing case id, generated channel/outcome, optional note and `/api/follow-ups` action are submitted
- **AND** the redesign performs no optimistic dispatch or additional mutation

### Requirement: Empty and error are not confused

#### Scenario: No case is due or the read fails
- **WHEN** the loader returns an empty queue or an error
- **THEN** the existing honest empty message or explicit load error is displayed respectively
- **AND** neither state fabricates a person, count or recovery outcome

### Requirement: The owner-board list system survives narrow screens

#### Scenario: A case renders at desktop and 390px
- **WHEN** identity, evidence and the follow-up form reflow
- **THEN** their hierarchy remains legible with 44/48px targets and semantic focus
- **AND** no control clips or creates page-level horizontal scrolling

## Ownership and verification

An independent Luna author owns only
`apps/web/app/__tests__/phase7-follow-up-surface.test.tsx` and commits the focused
tests red before implementation. Terra owns only the red-list page and
`globals.css`; it never edits the test. Root owns contract/evidence/spec/archive.
Run only the focused test and web typecheck/lint during implementation, then one
repository gate run. Real owner light/dark desktop and 390px journeys inspect the
queue and open no external action; no form is submitted. A fresh Sol critic uses
the approved owner v2 list crop as the strict visual bar.

- [x] Contract and path ownership frozen.
- [x] Independent focused tests committed red.
- [x] Follow-up surface implemented without behavior changes.
- [x] Focused checks and one full repository gate pass.
- [x] Real light/dark desktop/390px journey recorded without mutation.
- [x] Fresh Sol visual critic returns GO after the cited clarity repair.
- [x] Registry/spec/evidence synchronized and change archived.
