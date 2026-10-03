# Existing booking-read adapter signatures

Declaration-only addendum to member-booking-public-declarations.md, 2026-10-03.
It records existing registered adapter signatures; no interface or requirement
is changed and no implementation body is disclosed.

```ts
// apps/web/lib/training.ts
declare function loadMemberSlots(
  supabase: StaffSession['supabase'], orderId: string, from: string, to: string
): Promise<PtReadSection<{ startsAt: string; endsAt: string; timezone: string }>>;
// apps/mobile/lib/training.ts
declare function loadSlots(
  client: SupabaseClient<Database>, orderId: string, from: string, to: string
): Promise<PtReadSection<{ startsAt: string; endsAt: string; timezone: string }>>;
```

Both use only the supplied current authenticated caller; from/to are inclusive
ISO calendar dates. Web page props are only the ordinary promised orderId
params already declared in the main packet. The page's closed-over refreshFacts
server action has no parameters and revalidates the original complete caller.
