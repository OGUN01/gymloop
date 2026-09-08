# Demo accounts

Five sign-ins against the seeded demo gym (**Iron Box Fitness — Vijay Nagar**, `IRNBX1`, tenant `00000001-…-000000000001`), one per role, so any behaviour can be simulated end to end rather than argued about. Created 2026-09-08 while building Phase 3's first screens.

**Password for all five: `IronBox!Demo2026`.**

| Email | Role | What it is for |
|---|---|---|
| `owner@ironbox.example.com` | `gym_owner` | The full gym-side matrix — the only role that may write `staff` and `organizations` |
| `divya@ironbox.example.com` | `front_desk` | The Square-POS surface: assisted check-in, payments, the member list |
| `rohit@ironbox.example.com` | `trainer` | The narrowest gym-side role — reads the retention loop, no transaction tables |
| `aarav.member@ironbox.example.com` | `member` | Reads its own rows and the gym's catalogue; writes nothing directly |
| `admin@gymloop.example.com` | `super_admin` | Platform: reads every gym, writes through the platform policy, may impersonate |

**These are not fixtures.** They are real `auth.users` rows linked to real `staff`, `members` and `platform_users` rows, so a sign-in exercises the access-token hook and every RLS policy exactly as a real user would. That is the point: Phase 2's identity layer was proven entirely by pgTAP setting `request.jwt.claims` by hand, and these are the first accounts to prove it through an actual token.

## What each one gets from the hook

Verified by calling `app.custom_access_token_hook` directly:

- **gym_owner** → `app_role`, `tenant_id`, `staff_id`
- **front_desk** → same shape, different role
- **trainer** → same shape, different role
- **member** → `app_role`, `tenant_id`, **`member_id`** and no `staff_id`
- **super_admin** → `app_role` only; no gym claims at all

The console gates on `staff_id`, so the member and the super admin both land on `/not-linked` — correctly. A platform session especially must not fall into the member list, where RLS would let it read *every* gym.

## Housekeeping

**The password is in a conversation transcript, so treat it as disclosed.** That is acceptable while the application is not live and is the same standing as `SUPABASE_DB_PASSWORD` (ADR-051): rotate it before launch, along with everything in `docs/security.md`'s "Credential rotation" section.

Two of these sit on seeded rows rather than rows of their own — `divya@` and `rohit@` set `staff.user_id` on seed staff, and `aarav.member@` sets `members.user_id`. Unlinking is one `update … set user_id = null`. `owner@` and `admin@` created their own rows and can be deleted outright.

Re-creating them after a database reset needs the Supabase Auth Admin API (for the password hash) plus the link statements above; `supabase/seed.sql` cannot do it, because it has no way to write a bcrypt hash GoTrue will accept.
