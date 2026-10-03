# PLC application test interfaces

Status: delegated interface clarification, 2026-10-03. This records the
existing frozen public signatures without changing behavior or authorization.
Blind authors may use these interfaces without reading implementation bodies.

- `apps/mobile/lib/mobile-context.tsx` exports `useMobile()`. PLC consumes
  `identity: GymloopIdentity`, `supabase: SupabaseClient<Database>` and
  `palette`, one theme palette from `UI_TOKENS.colors`. Full provider values
  additionally include api, appearance, businessType, nouns, ready, session,
  setAppearance, signOut and webOrigin; isolated PLC doubles need only consumed
  fields. This is already-classified identity, not a raw claim or audience.
- `apps/mobile/lib/use-member-plans.ts` exports
  `useMemberPlans(open: boolean): { state: PlanCatalogueState;
  reload(): Promise<void> }`. It consumes that provider and the registered
  shared `readPlanCatalogue(supabase, memberId)`. Tests may double the read's
  documented `PlanCatalogueRead` result to control independent caller requests.
- `apps/mobile/components/plan-catalogue.tsx` exports
  `PlanCatalogueBody({ state, copy, timeZone, onRetry })` with
  `state: PlanCatalogueState`, `copy: PlanCatalogueCopy`, `timeZone: string`
  and `onRetry(): void`. The component uses the existing native kit and palette.
- `PlanCatalogueState`, its event types and `PlanCatalogueView` are already
  fixed in the proposal. Visible and held authors retain separate harnesses;
  neither may read the other's suite or application source.

PLC-009's positive-discount condition and PLC-019/Q9's caller, lifetime and
last-good-copy boundaries remain unchanged. A retained callback is not an
authorization to read after its caller changes, the disclosure closes or the
hook unmounts. Fresh current-caller reads keep their normal behavior.

## Offered-row reader order

PLC-Q1/Q5 and the commissioned structural bar require the spoken order to
match the rendered order on both platforms: name, exact price, length,
offered-plan marker when present, then stored GST rate when present. The
proposal's native-label example placed GST before the marker and contradicted
that parity requirement. This clarification resolves the example in favour
of the frozen quality bar; it changes no field, money rule or audience.
Independent visible and held order regressions precede the source correction.
