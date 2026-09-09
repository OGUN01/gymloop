-- a_writer_does_not_name_a_term_it_does_not_choose
--
-- `memberships.duration_days` arrived `not null` with no default, and
-- `supabase gen types` reads that as **required on insert** — so every writer
-- of a membership had to name a length, when the whole point of ADR-090 is that
-- the length comes from the plan and a caller-supplied one is ignored.
-- `POST /api/memberships` stopped typechecking on exactly that.
--
-- The fix is not to make the route send a value the trigger throws away. It is
-- to say in the schema what is already true in the trigger: a writer does not
-- choose this.
--
-- **The default is never observed.** `app.stamp_membership()` runs `before
-- insert` and replaces it with the plan's length whenever the plan is readable;
-- when it is not, the composite foreign key refuses the row and nothing lands.
-- Any positive value would do, and `1` is the smallest that satisfies
-- `memberships_duration_days_chk`.
--
-- It also fixes an ordering wrinkle that was there from the start. Without a
-- default, a membership naming a plan in another gym reached `not null` before
-- it reached the foreign key, so the row was refused with a complaint about a
-- column the caller never named instead of about the plan it did (ADR-066 — a
-- refusal should come from the rule that actually has the answer). With the
-- default, `duration_days` is filled, the CHECK passes, and the foreign key
-- gets to speak.

alter table public.memberships
  alter column duration_days set default 1;

comment on column public.memberships.duration_days is
  'How long one period of this membership is, in days, as sold. Recorded rather '
  'than read from plans.duration_days when money arrives: a plan may be '
  're-lengthened for future sales, and doing so must not re-measure months '
  'already paid for (ADR-090). The default is never observed — '
  'app.stamp_membership() replaces it with the plan''s length before insert, and '
  'a plan that cannot be read is refused by the foreign key. It exists so that a '
  'writer need not name a term it does not choose.';
