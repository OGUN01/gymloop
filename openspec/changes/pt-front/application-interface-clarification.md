# PTF application interface clarification

Status: orchestrator-frozen delegated interface clarification, 2026-10-03.
No eligibility, money, policy, identity or booking requirement changes. The
separate member-policy read proposal remains pending owner approval.

## Presentation helper

`ptBookingConsequence(input: PtConsequenceInput): string` returns the pinned
booking sentence. `ptCancellationConsequence(input)` retains the explicitly
specified `{ late, consumes, cutoff, sentence }` object. The booking helper's
earlier omitted return annotation must not invent a second outcome object.
All cutoff boundaries and both consumption flags remain unchanged and tested.

## Native surface seams

- `TrainingSection()` in `components/training-section.tsx` takes no props and
  loads the current member's training through registered `useMobile` context
  and `loadTraining(client)`. It does not obtain another caller from supplied
  identifiers. Wrong/unlinked audience produces no member fetch or mutation.
- `app/training/book/[orderId].tsx` exports its screen as the default, following
  the existing Expo route convention. Route parameters select only the order;
  server identity and current pack eligibility still decide authority.
- Both surfaces use the existing API client's `post` for commands and Expo
  Network's `getNetworkStateAsync`/network-state listener for connectivity.
  A positively disconnected/unreachable state prevents writes. A thrown live
  command remains a retryable failure, never success or a queued command.
- Both loaders return independent named sections `trainers`, `programmes`,
  `packs`, `upcoming`, `history`, each `{ data: publicRows[] | null,
  error: string | null }`. Their public row fields are the frozen member RPC
  projection mapped mechanically to camelCase; images become `imageUrl` only.
  A failed section is null with a sanitized error and does not erase other
  successful sections. Each invocation uses only its supplied caller.
- `loadSlots(client, orderId, from, to)` returns the analogous `{ data, error }`
  over frozen slot facts (`startsAt`, `endsAt`, `timezone`). Empty is an empty
  list; failure is null and never a fabricated open slot.
- Async results after a caller/scope change or unmount are discarded. No
  private queue, persisted training cache, module-global caller state or new
  native dependency is introduced.

Rendered independent tests may mock those existing caller/API/network seams
and raw public RPC rows. This specifies interfaces rather than source details.
Before booking-confirmation test fanout or UI build, the separately proposed
member-policy seam must be owner-resolved and frozen. Existing-session
cancellation previews use the authoritative current session read facts.

## Shared Classes / Training controls

The frozen PTF-owned controls are presentation seams, independent of the
proposed member-policy read. They introduce no reads, commands or identity.

- Web `ClassesSegments({ current })` takes `current: 'classes' | 'training'`.
  It renders the exact labels Classes and Training as links to `/member/classes`
  and `/member/classes/training` in a navigation landmark labelled
  "Classes and training"; only the current link has `aria-current="page"`.
  These are navigation links, with ordinary keyboard focus and kit targets.
- Native `SegmentedControl({ value, onChange })` takes
  `value: 'classes' | 'training'` and
  `onChange(value: 'classes' | 'training'): void`. The same two labels are
  controlled tabs, each with the correct selected accessibility state; an
  activated different tab calls the supplied callback once with its literal
  value. The control contains no member data, network requests, storage,
  provider lifecycle changes or default selection outside its supplied value.
- Both reuse registered kit/theme/spacing/target tokens, support enlarged text
  without fixed-height clipping, and introduce no motion. The native control
  obtains only palette through the existing `useMobile` presentation context.
  The central integrator owns mounting the feature panes and selection state.

Independent visible control tests are committed before their implementation.
Rendered/native runtime acceptance and final navigation remain separate gates.
