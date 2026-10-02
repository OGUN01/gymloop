# NTF quality bar — DRAFT, 2026-10-03

Public contract draft: `openspec/changes/push-notifications/proposal.md`. This is a fetchable comparison and acceptance rubric, not a frozen specification or delivery evidence.

## Comparable and technical references

Fetched primary public pages on 2026-10-03, no third-party login:

| Reference | Apply to NTF |
|---|---|
| [Linear Notifications](https://linear.app/docs/notifications) | Durable inbox plus optional real-time channels, category controls and honest channel availability. Use its public settings illustration/content as the comparison; preserve FitCruxx Chalkline styling and smaller member scope. |
| [Expo direct FCM/APNs](https://docs.expo.dev/push-notifications/sending-notifications-custom/) | Native device token with direct provider delivery, rather than Expo Push Service. |
| [Expo Notifications SDK](https://docs.expo.dev/versions/latest/sdk/notifications/) | Permission/channel, token rotation and received/response listeners. Resolve compatibility with the repo's pinned SDK at implementation; latest documentation alone proves no local build compatibility. |
| [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api) | Trusted server OAuth send credentials; a successful request is provider acceptance only. |
| [FCM token management](https://firebase.google.com/docs/cloud-messaging/manage-tokens) | Timestamped registration, freshness and careful invalid-token removal. |
| [FCM errors](https://firebase.google.com/docs/cloud-messaging/error-codes) | Separate token-specific permanent failures from malformed requests, credential failure and quota/outage. |
| [FCM delivery reporting](https://firebase.google.com/docs/cloud-messaging/understand-delivery) | Aggregate provider telemetry is insufficient evidence for one member's delivered/clicked timestamps. |

## Clickable outcome

Member opens You→Notifications, sees Android permission state and meaningful category switches, and still finds updates in Activity/inbox or Home announcements. A guardian-linked account sees only its linked child's notifications. On web the same member can set categories and read inbox, with clear Android-only push availability. Owner/manager previews an announcement version and reach, confirms kind and sends it to the delivery queue; front desk sees the preview and an “Ask an owner or manager to approve” explanation. Console facts distinguish accepted, received in app, opened, failed and delivery unknown. No success confetti for queueing, no invented reach percentage.

Chalkline visual comparison: light and dark at 390px/native and 1440px web; labels lead, a small permission/status line gives context, one row per category, one clear action. Use existing Sheet/StateMessage/ledger rows/UI_TOKENS/businessNouns and accessible touch target/font rules. No new tab, badge-count gimmick or decorative delivery chart.

## Must-win dimensions

| Dimension | Acceptance | Automatic rejection |
|---|---|---|
| Truth | “Accepted by push service”, “Received in app”, “Opened”, “Delivery unknown” each backed by distinct real evidence; inbox survives failure | Provider HTTP 200 called delivered; accepted send fabricates click/read/conversion |
| Member control | Per-category controls persist, consent remains independent, permission request follows action, denied/offline states actionable | Toggle grants consent, withdrawal ignored, automatic OS prompt on launch |
| Dispatch policy | Current source/account/device/consent checked, promo dispatch quiet 21–08 IST, transactional exemption explicit | Audience snapshot sends after withdrawal; claims late OS display is impossible |
| Identity/privacy | Tokens private; exact revision invalidation; guardian linked user only; generic lock-screen content | Phone/email matching, sibling device fan-out, replacement token killed by old error |
| Operational safety | Idempotent event keys, concurrent tenant budget, reviewed ANC version, no blind retry after uncertain response | Duplicate buzz on backfill/timeout, front-desk bulk send, cross-tenant token exposure |
| Navigation | Closed allowlist, authenticated current RLS target, useful unavailable state | Arbitrary URI/intent, stale signed-out payload exposes content, tap records ANC read before opening card |
| Resilience | Real inbox/feed independent of token/network/permission; no fake acknowledgement on list load | Push-only event lost forever; OEM background kill described as guaranteed receipt |
| Accessible polish | Light/dark, 390/1440, large text, screen-reader switch labels/value, keyboard review, reduced motion, no clipped copy | Unlabelled toggles, hidden failure, horizontal overflow, unreachable action |

## State evidence matrix

| Surface | Loading / empty | Failure / denied | Offline / deferred |
|---|---|---|---|
| Native settings | current settings skeleton; no device: “Enable Android notifications” | denied: explain OS settings action; registration failure: Retry; missing provider: honest configuration copy | saved preferences labelled saved copy, changes need connection; no fake enabled device |
| Web settings/inbox | existing list skeleton/empty copy | category save error preserves prior value; own unavailable target generic | existing inbox read behavior; push advertised only for Android |
| Review | current version/title/kind/count before confirmation | stale version reload, no eligible audience, rate limit, wrong role all distinct actionable state | review disabled offline; promo due tomorrow 08:00 IST clear; estimate not promised delivery |
| Campaign facts | no campaigns: useful create-via-announcement path | failure reason/uncertainty without token or recipient PII | queued/quiet defer label; cancellation warns already accepted pushes cannot be recalled |
| Push open | authenticated target loading | expired, foreign, unlinked or unavailable target generic | callback acknowledgement retries idempotently; content uses existing source offline contract, no stale authorization |

Fresh critic evaluates independent current artifacts against the public comparable and these dimensions. Full blind backend criticism covers every silent dimension. Three same-dimension rejections escalate contract ambiguity, never lower the bar.

## Evidence that cannot be substituted

Provider keys/configuration/signup and adapter architecture are owner-gated. A stub, unit mock, rollback SQL result or Expo Go screen cannot prove live Android FCM delivery. Record exact deployed/build identity, redacted FCM acceptance, real device receipt/open, current inbox source and denied/withdrawn/foreign cases before declaring the live gate won. OEM/battery-kill failure retains an explicit best-effort limitation. No phone, USB, ADB or Metro action is part of bar drafting.
