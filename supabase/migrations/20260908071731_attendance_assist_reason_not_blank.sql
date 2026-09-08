-- Phase 3 — ATT-006: a reason of three spaces is not a reason.
--
-- Implements openspec/changes/phase-3-core-domain/specs/check-in/spec.md,
--   "An assisted check-in names the staff member and the reason"
--   → Scenario: Assisted check-in with a reason of whitespace.
-- Conventions: docs/data-model.md § Conventions → Migration file layout (this file
--   has only section 4, "constraints not expressible inline"), § Naming (the
--   constraint keeps its Phase 1 name — the rule it states is unchanged, only its
--   definition of "stated").
-- Decisions: ADR-030 (CI applies migrations, forward-only).
--
-- Phase 1 wrote `assist_reason <> ''`, which rejects the empty string and accepts
-- `'   '`. `attendance` is the audit trail for one staff member marking another
-- person present; a whitespace reason satisfies the letter of ATT-006 and none of
-- its purpose, and it is the shape a form submits when somebody tabs past the field.
--
-- **The rule is "contains a non-whitespace character", and it is written as a regex
-- because a trim cannot state it.** The first draft of this migration said
-- `btrim(assist_reason) <> ''` and had the same hole one turn further in: bare
-- `btrim` strips **spaces only**, so a reason of a tab and a newline still passed.
-- Measured against Cloud rather than reasoned about, writing the escapes rather
-- than the characters -- the first version of this very comment carried a literal
-- tab and newline, which ended the `--` line mid-sentence and made the rest of the
-- paragraph parse as SQL: btrim of three spaces is empty, btrim of tab-newline is
-- NOT empty, and tab-newline matches the regex. A regex is
-- total over whitespace and takes no second argument that can be forgotten, which is
-- exactly why the trim version was wrong in a way that looked right.
--
-- **A dropped-and-re-added check constraint validates every existing row**, so this
-- was measured against the live project under *this* definition before it was
-- written: `public.attendance` holds 585 rows, 68 of them `front_desk` and carrying
-- a reason, and `count(*) filter (where assist_reason is not null and assist_reason
-- ~ '^\s*$')` is **0**. Nothing in the seeded gym fails the tighter rule.
--
-- Drop-then-add rather than `add … not valid` + `validate constraint`: the table is
-- small, the validation scan is the point, and a constraint that is only ever
-- `NOT VALID` is a rule the catalogue reports as unenforced for old rows.
--
-- Scope, stated so the next reader does not mistake it for an oversight: this fixes
-- the constraint the spec names and no other. `attendance_corrections_reason_chk`
-- carries the same `<> ''` shape and the same weakness; it belongs to DQA-003 and to
-- whichever phase builds attendance corrections, and widening this migration to
-- reach it would be changing a rule nobody has specified yet.


-- ---------------------------------------------------------------------------
-- 4. Constraints not expressible inline
-- ---------------------------------------------------------------------------

alter table public.attendance
  drop constraint attendance_front_desk_has_assist_chk;

alter table public.attendance
  add constraint attendance_front_desk_has_assist_chk
  check (
    source <> 'front_desk'
    or (
      assisted_by_staff_id is not null
      and assist_reason is not null
      and assist_reason !~ '^\s*$'
    )
  );
