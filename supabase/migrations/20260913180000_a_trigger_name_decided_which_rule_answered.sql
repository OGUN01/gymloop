-- a_trigger_name_decided_which_rule_answered
--
-- **ADR-100 decided that `GL042` answers ahead of every other rule that can
-- refuse the same statement, and implemented it by reordering clauses inside
-- `app.enforce_membership_terms_frozen()`. That mechanism structurally cannot
-- reach `GL047`, which lives in a different trigger.** A fresh-context critic
-- measured it in one statement, from an ordinary front-desk session, against a
-- `cancelled` membership whose target member holds nothing:
--
--     update public.memberships set member_id = <other>, status = 'active'
--      where id = <cancelled>;                              -->  GL047
--
-- The contract says `GL042`. Reversing the SET list gives `GL047` too; from a
-- gym manager, `GL047` too. The controls say it is genuinely `GL047` winning:
-- the re-point alone answers `GL042`, and a LEGAL transition plus a re-point
-- answers `GL042`.
--
-- **Postgres fires same-timing row triggers in trigger-name order**, and
-- `memberships_status_transitions` sorts before `memberships_terms_frozen`
-- ('s' < 't'). So `GL047` preceded all five rules in that function — `GL042`,
-- `GL043`, `GL044`, `GL045` and `GL046` — and no amount of moving clauses
-- inside it could have changed that.
--
-- **This session created the gap and then wrote a rule that did not cover it.**
-- `GL047` and its trigger arrived one commit earlier; ADR-100 wrote down its own
-- general grep — *for every pair of rules that can fire on the same row, either
-- the contract decides which answers or an assertion pins that nobody may rely
-- on it* — and then OPEN-034 enumerated five undecided pairs and omitted the one
-- pair the same session had just introduced. The grep was right and I did not
-- run it on my own change.
--
-- **The fix is the name, not the placement.** `GL047` is in its own trigger
-- deliberately: both seed files disable `memberships_terms_frozen` around their
-- own statements, a window argued for dates and never for transitions, so
-- folding this rule in would leave it silently off for the whole seed (ADR-098,
-- which cost a round to learn). Renaming preserves that and fixes the order.
-- `memberships_transitions_after_terms` sorts after `memberships_terms_frozen`
-- ('tr' > 'te') and says why it is called that.
--
-- Dropped and recreated rather than `alter trigger … rename to`, so this
-- migration does not depend on what the trigger is currently called.
--
-- Measured, with this spliced: re-point + illegal revive --> GL042; re-point
-- alone --> GL042; illegal revive alone --> GL047, unchanged.
--
-- Nothing refers to the trigger by its old name: the seed disables
-- `memberships_terms_frozen`, never this one.

drop trigger if exists memberships_status_transitions on public.memberships;
drop trigger if exists memberships_transitions_after_terms on public.memberships;

create trigger memberships_transitions_after_terms
  after update on public.memberships
  for each row execute function app.enforce_membership_status_transition();
