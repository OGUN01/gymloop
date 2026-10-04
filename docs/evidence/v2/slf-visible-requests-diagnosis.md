# SLF visible requests suite — single-failure diagnosis (author round, 2026-10-04)

Runtime fact from the orchestrator's Cloud rollback-only diagnostic runs:
`supabase/tests/81_member_freeze_requests.sql` ran plan(141), ran=141,
failures=1, no abort — twice, at the same stable snapshot. All other SLF
visible suites and h10 are green. Failure identified by the orchestrator's
diagnostic TAP capture: assertion #59, `SLF-014: a source pause binds at most
one request` (the u(414) duplicate `source_pause_id u(603)` insert expecting
`23505`).

## Diagnosis (implementation-blind)

Derived from the frozen contract
(`openspec/changes/member-self-service/proposal.md`) and the frozen
every-writer boundary
(`openspec/changes/member-self-service/current-defense-declaration.md`):
"Request/member/membership/source tenant, member, **dates, reason and staff
provenance agree for every writer**."

The seed row u(413) was inserted through an unguarded probe and violated that
agreement boundary three ways against its linked source pause u(603):

1. dates: request span today+1..+2 vs pause 603's own +10..+12;
2. reason: `'Linked one'` vs the pause row's `'Closed-request evidence pause'`;
3. staff provenance: `adopted_by_staff_id u(23)` vs the pause's
   `requested_by_staff_id u(21)`.

A row-agreement trigger therefore refused u(413) (23514-class), so no request
row existed for source pause 603. u(414) — which carried the same disagreeing
shape — was then refused by the same agreement trigger BEFORE the
`(tenant_id, source_pause_id)` unique index could fire, so the probe returned
the agreement refusal's SQLSTATE instead of `23505` and assertion #59 failed.
The unguarded seed probe hid the true cause.

Runtime corroboration that cancelled+adopted is itself lawful: the suite's own
RPC flow produces exactly that shape (r109 is adopted at line ~271 and
withdrawn by the member at line ~295, assertions passing), and row 401
(decided_at == closed_at, same-statement stamps) inserts cleanly — so
same-statement timestamp equality is accepted and no timestamp-ordering rule
is implicated.

## Fixture correction applied (lawful, no assertion weakened)

- u(413) and u(414) now both satisfy the agreement boundary: span equals
  pause 603's own +10..+12 (which also sits outside every other fixture
  interval and effective request for member 102, and is excluded from
  overlap as each row's own source), reason `'Closed-request evidence pause'`
  matches the pause row, and `adopted_by_staff_id u(21)` matches the pause's
  `requested_by_staff_id`. All other shape facts unchanged (cancelled,
  `cancelled_by_user_id u(907)` = the requesting member subject, closed_at
  stamped, same-statement stamps).
- The u(413) seed is now asserted: `ok(probe(...) = 'OK', 'SLF-014: a lawful
  closed source-linked request row inserts cleanly')` — this class of silent
  fixture failure cannot recur.
- `plan(141)` → `plan(142)` for the added assertion. No assertion removed or
  weakened; #59's expectation (`23505`) is unchanged and now genuinely
  reachable: with both rows lawful and agreeing, the BEFORE-row agreement
  triggers pass and the unique index fires on u(414).

Downstream re-checks after the span change: member 102's later requests
(+3..+6 refused via approved pause 601; +6..+8 adjacent-OK) do not overlap
+10..+12, and a cancelled request does not consume the one-open-request
bound or reserve dates.

## Post-edit expectation

142/142 green against the current implementation at the same snapshot if the
diagnosis holds; any remaining failure is a genuine contract deviation to
round-trip. The orchestrator reruns the suite to confirm.

## History

- First-round hypothesis (approval-authorization masking the SLF-012 budget
  recheck at the former line 275) was applied as a fixture correction
  (approval caller changed to the configured `gym_manager` 22, different from
  the adopter; budget comment corrected to seven inclusive days). The rerun
  showed the failure was #59 all along; that edit remains lawful (the
  assertion's intent is now genuinely exercised) and is retained.

## Checks

- `check-pgtap-rollback.mjs`: 159 pgTAP files checked, all rollback-wrapped — green.
- File sha256 after edits:
  `a76c07751778ab804cc21860854d7795b437465f544503518486288333c287c6`
  (second fixture round: the seed assertion was first written as
  `ok(probe(...), 'OK', label)` — three arguments, text first — which pgTAP
  resolves as `ok(text, unknown, unknown)` and aborts 42883; corrected to the
  boolean comparison `ok(probe(...) = 'OK', label)`, plan stays 142).
- Nothing committed; no SQL executed against any database; implementation
  source never read.
