# PLC visible route state acceptance

Status: **unexecuted**. The focused Playwright route suite is listable without a
browser; listing proves no screen, RLS result, accessibility pass or device result.
The mocked PLC page tests independently exercise the frozen server-read branches.
Browser request interception cannot control the server's Supabase reads and is
not used to pretend it can. No fixtures are created or changed by these files.

After CI applies the approved policy and the app lands, the orchestrator uses
documented demo accounts and reconciles reversible states through ordinary
authorized application/API operations. Capture original facts for restoration.
Do not invent a second test endpoint, a demo account, plan ids or exact prices.
Record environment, member, actual stored facts, before/after state, screenshots,
accessible tree and requests. Missing setup remains unverified, never a skipped pass.

1. Baseline: documented Monthly, Quarterly, Half-Yearly, Annual order and 18%
   GST. Run the executable route suite at 390/1440, light/dark, reduced motion
   and 200% text. Verify name → price → duration reader order, held description
   list, tabular amounts, no offer actions, no tax arithmetic and no page writes.
2. Sold/current comparison: record the member's held plan's actual sold price,
   discount and duration. Through authorized plan editing, change its offered
   price and duration without changing membership facts. `/member/plans` must
   show the original `Price when sold` and `Length` and the exact `Today this
   plan is {price} for {length}.` sentence together, using the stored values.
   Verify the renewal pricing sentence, no strike-through and no GST in the held
   section. Restore the plan's original facts. Mocked page coverage is executable
   before this setup; no live comparison result is claimed by this protocol.
3. Rate-only variation: temporarily set the offered rate to zero and blank its
   description; there is no GST line/note or empty description label. With a
   nonzero stored rate, show only the rate and final-amount note, never an
   inclusive/exclusive claim, GST amount or invented total. Restore both facts.
4. Fallback: deactivate the held plan through the authorized API. Its offer row,
   name and badge disappear; sold terms remain and the live not-on-offer sentence
   is exact. Home, Gym and You show the accepted generic `Membership` label for
   the inactive embed. Reactivate and restore before running the baseline suite.
5. Unavailable/error/empty: in a controlled acceptance environment, have the
   server's existing plans read fail, then only its membership read fail, then
   provide zero active plans. Do not change RLS or claim a browser-side abort
   proves these server failures. Plans failure: alert `Plans could not be loaded.`
   and a plain full-navigation `/member/plans` retry. Membership failure: offers
   remain, `Your own plan details could not be loaded.`, no sold facts/badge/Today
   comparison. Empty: `No plans listed yet`, exact place-aware next-action copy,
   held block and desk note. All three remain axe-clean and wrap at 390/200% in
   both themes, without raw DB details. A controlled server-failure environment
   is a precondition; absent one, retain mocked results and mark live unavailable
   acceptance unverified.
6. Permission: execute signed-out and documented owner redirect cases. No in-page
   permission error or catalogue flash. Confirm actual navigation and a11y trees.

Native offline/stale and maximum Android text acceptance remain separate required
device checks. The repaired hook suite proves in-memory lifecycle through mocked
mount/effect cleanup/remount and racing responses, not physical device behavior.
