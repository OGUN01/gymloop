# PTF native held tests — date-rollover re-homing (2026-10-05)

The six failing held tests (4 in ptf-native-current-held, 2 in
ptf-native-read-cancel) were authored on 2026-10-04 with session
cancelCutoff values on that date. The date rollover to 2026-10-05
pushed Date.now() past the cutoff, causing the component's own
time-guard (cancel() line 100: `if (!session.lateNow && Date.now() >
cutoff)`) to refuse every Confirm press before the api.post — the
frozen behaviors (exact caller client, pinned sentence, unmount
invalidation, A-B-A rejection, double-activation dedup,
uncertain-cancellation) were structurally intact but unreachable.

Fix: the six tests now pin `vi.useFakeTimers()` + `vi.setSystemTime()`
to instants BEFORE each session's cutoff (the same pattern the
cutoff-boundary it.each variants already use). The read-cancel file's
afterEach gains `vi.useRealTimers()` (the current-held file already
had it). No assertion, mock, expectation or press target changed —
the contract substance is identical.

sha256 (16-char prefixes):
- ptf-native-current-held.test.tsx: (see below)
- ptf-native-read-cancel-held.test.tsx: (see below)

Vitest: 66/66 green across all three PTF native held files
(including ptf-native-deferred-media-held, untouched).
- ptf-native-current-held.test.tsx: 921501c6dbd60b590375f2b45223c68da031cd3a73316a443492abe6663ce79c
- ptf-native-read-cancel-held.test.tsx: 06282d916dae6e86a325d8563410b895c145fa465f27050f6bbf945b51522306
