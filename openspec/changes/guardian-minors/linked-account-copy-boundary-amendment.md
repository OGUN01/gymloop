# Guardian linked-account copy boundary

Status: proposed for owner decision, 2026-10-03. No authorization, SQL,
claim, consent, handover eligibility or recipient rule changes.

Three fresh application reviews have rejected the guardian-account copy
dimension. AGENTS.md requires escalation after three rejections of a dimension.
This clarification makes the existing GRD-013 provenance rule explicit in the
linked-account explanation before independent regression tests and a source fix.

## Exact boundary

- For an already linked account, describe guardian provenance only when the
  authoritative `guardian_linked_at` marker is present. A minor's current age
  alone does not prove who owns the linked account: operator-bound minors have
  no guardian marker under GRD-013.
- A retained marker continues to describe the guardian account if DOB becomes
  unknown. A known eighteenth birthday does not transfer the account; only the
  existing handover/unlink operation changes the binding.
- Without the marker, describe only that the member app is connected; do not
  claim that either the guardian or member owns its Google account.
- Prospective invite routing still uses the current authoritative minor state:
  known minors use the guardian email; others use the member email. An older
  pending invite is compared with today's eligible email under GRD-011.
- Guardian email recovery, sharing, consent and handover controls retain their
  existing conditions. Read failure still fails closed without child contact
  fallback or invented account provenance.

Independent visible and holdout authors will pin operator-bound minors,
marker-bound minors/adults/unknown DOB, absent marker and prospective routing
before the separate implementer changes source. A fresh critic must approve the
result; approval of this clarification does not waive any acceptance gate.
