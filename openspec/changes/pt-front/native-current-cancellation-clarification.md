# Native Training current cancellation and caller lifetime

Orchestrator-frozen integration clarification, 2026-10-03. This applies the
existing PTF-029/030/034 and PTF-Q2/Q6 requirements to TrainingSection, with the
same public interfaces in native-read-cancel-declarations.md. No policy, actor,
grant, money, booking implementation or native dependency is added.

1. Refresh the exact current caller-owned session through loadTraining before
   preparing, reopening **and confirming** an existing cancellation. A missing,
   mismatched, failed, no-longer-booked or uncancellable result submits nothing.
   Compare the fresh cancellation consequence and displayed facts with the
   confirmation already shown. If they changed, display them and require renewed
   explicit confirmation; the action confirming old facts sends nothing.
   Null cutoff or failed reads cannot use a policy default or old confirmation.
2. Display both the pinned current consequence and its absolute local cutoff,
   including late consuming and late non-consuming states, before Confirm.
   Preserve the exact inclusive boundary and authoritative lateNow/consumesNow
   facts. If the known clock crosses the presented cutoff during an awaited
   preflight/read, stale free-cancellation facts cannot authorize an immediate
   send; review the refreshed consequence before another explicit confirmation.
   The database still decides command-time facts; no client predicts policy.
3. The permanent presentation lease includes the verified identity tuple,
   readiness and supplied API/read-client capabilities. Replacing api or supabase
   with the same identity, becoming unready, changing caller or unmounting revokes
   preceding callbacks, reads, results, feedback and navigation permanently.
   A → B → A cannot revive an earlier lease. Use only the existing useMobile
   provider and supplied clients; no second identity source or token parser.
4. A live canBook pack has its frozen Book action to the existing proposed route
   /training/book/[orderId]; unavailable packs have no enabled booking action.
   This is read-surface navigation, not permission to implement the owner-pending
   booking policy or booking destination. Retained obsolete handlers cannot
   navigate a replacement caller. Offline actions remain disabled, no queue.
5. Offline last-loaded reads include the frozen offline sentence and an explicit
   stale marker. Reconnect sends nothing automatically. No persisted Training
   cache, optimistic final status or new command transport is introduced.

Independent authors exercise the actual TrainingSection using the existing
useMobile, loadTraining, Expo Network and router public seams. Their red tests
precede a separate source-only repair; a new blind source critic and actual
browser/Android evidence remain required. This clarification is not a full PTF
feature acceptance or an owner-approved new-booking policy reader.
