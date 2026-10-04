# WSP consent ordering builder report

Frozen canonical order: `recorded_at DESC, id DESC` per tenant/member/purpose
(`consent-ordering-declaration.md`). All consent-currency decision sites in
`supabase/migrations/20261004110000_whatsapp_channel.sql` previously broke
equal-instant ties by physical `ctid` (insertion order). Ten decision sites
changed to the canonical predicate; one comment block rewritten; no other
behavior touched.

## Decision sites changed (10)

| Line (before edit) | Site | Predicate before | Predicate after |
|---|---|---|---|
| 704 | Member consent summary — service purpose (`whatsapp_channel_consents`) | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 709 | Member consent summary — marketing purpose | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 714 | Latest `notice_version` per member | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 831 | `record_whatsapp_consent` idempotency "latest existing row" lookup | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1188 | `request_whatsapp_dispatch` generic purpose-consent (`public.consents`) eligibility | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1334 | `app.wsp_channel_consent_ok` strict opt-in body (used at claim and immediately before I/O) | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1465 | Claim loop generic purpose-consent recheck (`public.consents`) | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1480 | Claim loop channel-consent current-row resolution | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1682 | `authorize_whatsapp_dispatch` final revalidation — generic purpose consent | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |
| 1685 | `authorize_whatsapp_dispatch` final revalidation — channel consent current row | `recorded_at desc, ctid desc` | `recorded_at desc, id desc` |

The obsolete append-only/ctid-stability rationale comment above site 1334 was
replaced with the declaration's canonical statement (UUID tie order, no
physical-order dependence). Both consent tables have `id uuid primary key`,
so `id DESC` is well-defined and matches the idiom already used at three
pre-existing canonical sites (attempt-insert `consent_id` lookup, the
notification-status trigger, and the guardian communication guard).

## Sites enumerated and unchanged (not consent currency)

- `1005`, `1032`, `1080` — attempts listing/keyset pagination ordering
  (`created_at DESC, id DESC`): already keyset-canonical, not consent currency.
- `1276` — `wsp_current_template_revision` (`checked_at DESC`): template
  revision recency, not consent currency; declaration silent, behavior
  unchanged.
- `1294` — `wsp_current_rate_version` (`effective_from DESC`): rate version
  selection, unchanged.
- `1411` — dispatch claim queue (`scheduled_for, id` ordering): request queue
  ordering, unchanged.
- `1424` — sender-account pick (`order by a.id limit 1`): deterministic unique
  id ordering, not consent currency; unchanged.
- `1520`, `2891`, `3210` — already canonical `recorded_at DESC, id DESC`.

## Static checks

- `ctid` remaining references: 1 (inside the rewritten explanatory comment only).
- `$fn$` tokens: 72 (even, balanced); `$$` dollar-quote bodies: 0 unbalanced.
- `commit` statements: 0. Parens: 1028/1028 balanced.
- `node scripts/check-pgtap-rollback.mjs`: 159 pgTAP file(s) checked, all
  rollback-wrapped.
- Full-statement count and all non-ordering bytes unchanged outside the ten
  predicates and the one comment block.

No test files read or touched. No commits. No Cloud SQL.
