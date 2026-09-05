---
name: new-api-endpoint
description: Fires when the user asks to add a new mutation endpoint (create/update/delete something) reachable from web or mobile. Expects the resource and operation (e.g. "cancel a membership", "record an offline payment") as input. Do not use this for read-only data access — reads go direct through supabase-js + RLS per docs/architecture.md, not through a Route Handler.
---

# New API endpoint

Every mutation in this project is a Next.js Route Handler in `apps/web`, never a client-side direct write, never a GraphQL resolver, never logic embedded in an Edge Function (those are reserved for Razorpay webhooks and cron — `docs/architecture.md`).

A conforming endpoint has all of:

1. **Zod validation** on the request body, derived from `packages/db/types/database.ts`-sourced schemas where the endpoint touches a table — not a hand-rolled shape that can drift from the DB.
2. **A typed error envelope** on every failure path — no bare 500s, no inconsistent shapes between endpoints. The envelope should say how to fix the error, not just that one occurred (master prompt §9's "Stripe-grade API ergonomics" bar).
3. **An auth guard** appropriate to the role matrix (`docs/security.md`) — checked before any DB write, not relied upon via RLS alone for mutation-shaped requests (RLS is the reads' safety net; a mutation endpoint should reject a wrong-role request explicitly, with a clear error, not rely on a policy silently no-op'ing the write).
4. **Idempotency** if the endpoint is retryable from the client (payment-adjacent or offline-queue-replayed endpoints especially — see the `payment-flow` skill).
5. **Cursor pagination**, never offset, if the endpoint returns a list (gate 26).

Register the route and any new zod schema in `docs/registry.md`. Once `packages/api-client` exists (Phase 2, `docs/decisions.md` OPEN-002), the endpoint's contract is generated into it — don't hand-write a duplicate client-side fetch wrapper for it.
