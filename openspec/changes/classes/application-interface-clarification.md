# CLS rendered application interfaces

Status: delegated presentation clarification, 2026-10-03. No booking,
capacity, membership, identity, cancellation or attendance rule changes.

- Named `MemberClassesView({ sessions, today, nouns, cancelWindowHours })`
  consumes the frozen camelCase `MemberClassSession[]` schedule (null on a
  failed read), gym-local `today: string`, `nouns: BusinessNouns` and optional
  settings presentation context. That optional context is not permission to
  invent a member deadline; prebooking confirmation remains fail-closed while
  the separately proposed cutoff repair is pending.
- Named `ClassesPane({ desk })` accepts optional boolean `desk` (default false)
  and consumes the existing `useMobile` provider's verified `identity`, caller
  `supabase`, `api`, palette/nouns and web origin. It introduces no second
  identity source. Member schedule, desk timetable/roster and command seams
  remain the proposal's public helpers.

## Desk member search

CLS-Q6 promises adding the member found by search. The existing registered
`loadDeskMembers(client, query)` signature and `DeskMember` projection are
reused. A non-empty name/phone search must be evaluated by the caller-bound
database **before** the existing result-page cap, so a matching member outside
the initial unfiltered page can be found. An empty query retains the existing
bounded name-ordered roster. This corrects the inherited first-page local
filtering defect; a web-link workaround does not complete the native bar.

Preserve RLS, the supplied client, public fields, case-insensitive name/phone
matching, bounded results and normal failures. Query text cannot become filter
grammar, choose a tenant or widen an audience. No new RPC, grants, member
policy, duplicated reader or unbounded dataset is introduced. Independent
visible and held query/projection regressions precede the isolated helper
repair and removal of the temporary first-page warning.
