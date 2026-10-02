# WSP quality bar — DRAFT / NOTFROZEN, 2026-10-03

Contract: `openspec/changes/whatsapp-channel/proposal.md`. This draft is a comparison rubric, not approval, test instruction, implementation or live-provider evidence. Uses existing Chalkline web/native kit and registered `UI_TOKENS` only; no new design system.

## Fetchable references

Fetched primary sources on 2026-10-03:

- [Meta official Cloud API collection](https://www.postman.com/meta/whatsapp-business-platform/documentation/wlk6lh4/whatsapp-cloud-api): comparable for template payload, sender/message identifiers and webhook correlation.
- [Meta official examples](https://github.com/fbsamples/whatsapp-api-examples): template and raw webhook signature verification reference.
- [WhatsApp Business policy](https://www.whatsapp.com/legal/business-policy/): template/recipient expectation and opt-out bar.
- [Meta pricing](https://whatsappbusiness.com/products/platform-pricing/): transparent category/market billing explanation; precise effective India tariff remains unresolved because linked rate cards were not fetchable. No invented per-message price.
- [Twilio WhatsApp pricing](https://www.twilio.com/en-us/whatsapp/pricing) and [Twilio messaging webhooks](https://www.twilio.com/docs/usage/webhooks/messaging-webhooks): comparable fee separation and truthful delivered/read outcome reporting, not approval to select Twilio.
- [TRAI sender guidance](https://www.trai.gov.in/advice-to-senders) and [TCCCPR](https://www.trai.gov.in/tcccpr): required India compliance evidence. These do not by themselves settle WhatsApp-only DLT applicability; retain F9 until owner-approved recorded resolution.

## Clickable product bar

| Surface | Observable win / refusal of a false win |
|---|---|
| Member settings (web/native) | WhatsApp service/marketing controls show the current recipient kind and safe masked number, named business/purpose notice and actual saved opt-in time. Current generic-purpose consent is independent. Off takes effect on queued work; unknown phone/guardian/age states give a clear desk action. No preselected grant, permission implied by phone entry or inferred Google binding. Save has pending/error/retry and no premature success. |
| Desk member/contact workflow | One clear Send approved reminder action with current template/readiness; refusal states explain wallet funds, recipient opt-in, guardian, current renewal settlement or provider/template configuration. Existing manual WhatsApp action is labelled manual; no claim that opening WhatsApp sent anything. In-app/desk fallback is actionable and remains available when provider unavailable. Phone and child details never leak through cross-tenant lookup errors. |
| Owner template/settings | List real approved/paused/unavailable provider revision/category, last checked evidence and safe exact preview. No false local “Approved” button. No arbitrary message composer or balances/arrears in a preview. Configuration is an owner-approved activation workflow, never credentials pasted into a browser field. Exact missing prerequisites are readable without creating accounts. |
| Owner wallet | Ledger uses exact INR amounts after the unit amendment; posted balance, reserved amount and available amount are distinct. Rows show tariff version, cause and truthful charged/refunded/adjusted facts; no decorative charts or arbitrary desk top-up. Empty state states no WhatsApp send, with existing funded-adjustment process and desk fallback. Existing credits remain labelled credits until approved conversion; never format an unvalued credit as rupees. |
| Staff report | Accepted, delivered, provider-read, clicked, failed and outcome-unknown are separate counts with the actual evidence time. Read unknown is not unread; no provider read→app click substitution. Charge totals reconcile exactly to the canonical ledger; no “100% delivery” from HTTP 200. Bounded member drilldown shows safe refusal/actions rather than raw receipt payload/provider identifiers. Trainer/member reports reveal no other-member or wallet data. |

Use ledger rows, `Sheet` confirmations and `StateMessage` outcomes with precise English, light/dark, large text, readable contrast, reduced motion and labelled thumb-friendly targets. Keyboard/screen-reader focus must remain sensible during pending/refusal/retry; no color-only financial or delivery states. Safe member authenticated deep links open the current permitted record, never bearer secrets. An unlinked recipient gets generic sign-in/desk guidance rather than an identity relaxation.

## Evidence and race bar

Full blind visible/holdout authors and fresh critic are mandatory for money, RLS, identities and causal evidence, after a serial frozen contract. Holdouts remain unread by implementers. Required cases include two sends fighting for the final funds; send vs adjustment; consent/guardian phone withdrawal before final authorization; opt-in grants without actual recipient basis; erased/blocked/unknown-age recipient; cross-tenant forged notification/provider id; reused request key with changed amount/template; forged/duplicate/out-of-order webhook; invalid HMAC/raw-byte changes; accepted id followed by transport crash; unknown outcome with no safe provider query; zero/free tariff; INR/currency overflow; stale/recategorized template; exact fractional-paise tariff rounding boundaries; empty wallet/provider outage; retained financial proof after erasure. No retry/debit/release based solely on elapsed time.

Actual browser E2E must exercise member opt-in/out, desk action/refusal, owner wallet/report and authenticated receipt links using genuine roles/RLS. Actual authorized provider E2E on an owner-nominated consented recipient must correlate POST acceptance id, verified webhook, delivered and read evidence when available, duplicate handling and exactly one causal ledger debit under the selected billing event. Capture provider account/template/rate revision plus sanitized evidence ids/timestamps. No fabricated screenshot, fixture receipt or manual WhatsApp open counts as live transport success. Device testing is separately authorized; this draft performs none.

Critic compares the named references and runnable product blindly, failing silent overspend, duplicate paid I/O, stale consent, identity broadening, false delivery/read, unregistered symbols or inaccessible action states. Three failures on one dimension return to owner wording; never lower the bar. Registry/gates/CI-only migrations/generated types/serial landing/archive remain required. WSP cannot freeze while the exact NTF shared-function edits or wallet unit/charge-event amendment remain unresolved.
