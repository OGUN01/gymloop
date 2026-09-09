-- the_backfill_rounded_where_the_rule_truncates
--
-- **`sum()` over `bigint` returns `numeric`, and assigning a `numeric` to an
-- `integer` column ROUNDS.** `app.grant_periods()` declares both sides `bigint`
-- and therefore truncates. So the backfill in `20260910170000` and the rule it
-- was written to agree with disagreed by one, for every membership whose money
-- had reached at least half a period but not a whole one.
--
-- Measured against the demo gym: **one membership in 47.** Sneha Joshi's Annual,
-- priced 1,200,000 paise, with 1,080,000 arrived — a coupon discount, 90% of the
-- price. The rule computes `1080000 / 1200000 = 0` periods. The backfill
-- computed `0.9` and stored **1**.
--
-- Two consequences, and the second is worse than the first.
--
--   * She holds a period nobody paid for.
--   * Her next payment grants NOTHING. Total becomes 2,280,000, `owed` is
--     `2280000 / 1200000 = 1`, `periods_granted` is already 1, so
--     `v_periods = 0` and the function returns. **She pays ₹12,000 for zero
--     days**, in silence, and the only record that anything is wrong is a
--     column nobody looks at.
--
-- ADR-087 says a recorded count is right because it can be checked against the
-- rule. This is what that check is FOR — and it found a defect in the very
-- migration that introduced the column, one round after a critic named "does
-- the backfill agree exactly with its own rule" as the first thing to attack.
-- The answer was no, by one, on the one membership in the demo gym that carries
-- a discount.
--
-- **A discount is not an edge case in an Indian gym.** `memberships` has a
-- `discount_paise` column and the seed uses it; every part payment lands in this
-- window too. The rounding did not just mis-set one row, it mis-set exactly the
-- rows where the money and the price genuinely differ.
--
-- Recomputed here with the cast the rule uses, so the two cannot disagree.
-- Forward-only, and idempotent: it writes only rows that are wrong.

update public.memberships m
   set periods_granted = coalesce((
         select sum(pp.amount_paise)
           from public.payments pp
          where pp.tenant_id     = m.tenant_id
            and pp.membership_id = m.id
            and pp.currency      = m.currency
            and pp.status in ('paid'::public.payment_status,
                              'refunded'::public.payment_status,
                              'reversed'::public.payment_status)
       ), 0)::bigint / m.price_paise
 where m.price_paise > 0
   and m.periods_granted is distinct from coalesce((
         select sum(pp.amount_paise)
           from public.payments pp
          where pp.tenant_id     = m.tenant_id
            and pp.membership_id = m.id
            and pp.currency      = m.currency
            and pp.status in ('paid'::public.payment_status,
                              'refunded'::public.payment_status,
                              'reversed'::public.payment_status)
       ), 0)::bigint / m.price_paise;
