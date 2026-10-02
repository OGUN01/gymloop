# FitCruxx v2 feature map — brainstorm record, 2026-10-02

This is the owner-approved brainstorm list for the post-closed-test build phase.
Nothing here is a commitment to build order until the closed test ends and the
real-user feedback is merged into it. Every feature listed will go through the
full Gauntlet Loop (bar → EARS spec → red tests → implementation → fresh
critic → gates → archive) before it ships.

Vertical positioning decided in brainstorm: the product serves **any
membership-based activity business** — gyms, dance academies, yoga studios,
martial arts — because the core engine (members, attendance, memberships,
churn detection, renewals) is vertical-free by design. Only copy varies.

## Build waves (suggested, not committed)

| Wave | Theme | Features |
|---|---|---|
| A | Identity foundations | INV, GRD, BIZ |
| B | The "front" of the app | CLS, SHP, PTF, ANC |
| C | Reach and member-visible money | NTF, WSP, PAY |
| D | Polish and retention | SLF, TRV, LDC, OCC |

Wave B is the centerpiece: what a business *does* (classes, training, selling)
becomes the visible front of the member app; what it *records* (membership,
receipts, activity) stays but moves behind.

---

## F1. Member invite and self-linking (INV)

**What.** The gym adds a member (as today) and the system sends that member an
invite — a link or QR — which they open, sign in with Google, and self-link to
their member row. No operator runs a binding script. Retires
`scripts/provision-identity.mjs` as the everyday path (kept for recovery).

**Surfaces.** Web console `members/new` (send invite, resend, revoke), member
app onboarding, `notifications` delivery, audit log.

**Edge cases.**
- Invite expiry (24–48 h) and single-use enforcement; resend creates a new token and invalidates the old.
- Revocation by staff before redemption.
- Redemption with a Google account whose email differs from the member record: refuse with generic copy (never leak whether a member exists), or require exact match — spec decides; edge cases for both.
- The Google account is already linked to a member row in ANY gym: today PROV-006 enforces exactly one binding per identity. A person joining two gyms is a real scenario; decide one-identity-many-gyms (contract change with holdout implications) or refuse with clear copy.
- Member status changes after invite sent (cancelled/refused members cannot link).
- Member email edited after invite sent (invite follows the row, not the stale address).
- Invite for an under-18 member: the **guardian's** Gmail is the one that links (see GRD).
- Rate limiting and abuse (invite spam), full audit of every link and unlink.
- DPDP: linking implies account-creation consent; the invite text must say what data is processed.
- Existing operator-bound members: a migration path so old-style linked members can re-invite nothing (they already work); no forced re-link.

## F2. Services and Classes (CLS) — the centerpiece

**What.** A per-tenant service catalogue the owner configures: which
activities this business runs (Zumba, yoga, HIIT, dance batches, martial
arts…), a weekly timetable with trainer and capacity, and member booking.
Each business's app shows only its own services. A dance academy uses the
same system with batches by age/level instead of drop-in classes.

**Surfaces.** New tables `services` (per tenant, owner-configurable types),
`class_sessions` (scheduled occurrences: recurring + one-off), `class_bookings`.
Owner console: catalogue manager + weekly schedule editor. Desk app: today's
sessions and bookings list. Member app: a **Classes** tab (today + week view +
book/cancel).

**Edge cases.**
- Capacity race: two members booking the last spot concurrently — the same per-resource serialization pattern as the check-in day lock; exactly one wins, the other gets a specific refusal.
- Cancellation window per gym (member cancels ≥ N hours before → spot freed; inside the window → kept).
- Owner cancels a session: everyone booked must be notified (depends on ANC/NTF); booking status becomes `session_cancelled`, not member no-show.
- Booking requires a live membership (lapsed member refused with the membership error, matching check-in semantics).
- Recurring sessions and the existing `organization_holidays` calendar: sessions on holidays are auto-skipped, not just shown.
- Timezone per branch (falling back to gym timezone) — arrival/day logic must follow the existing check-in timezone rules.
- Past sessions are not bookable; late-cancel of a past session is impossible.
- Capacity reduced below existing bookings: existing bookings stand, new ones refused.
- Service disabled/deleted with future sessions and bookings: decide freeze-and-finish vs cancel-with-notice.
- Cross-branch booking (member of branch A booking branch B's class): decide per business; default refuse, matching check-in's cross-branch refusal.
- Booked-but-absent: does a no-show for a booked class feed the existing absence-risk scan? Default yes via normal attendance; the booking is not itself attendance.
- Booking is online-only (no offline queue) — the member gets a clear error offline.
- Trainer reassignment on a session with existing bookings.
- RLS: every new table tenant-scoped; a gym's services never leak to another gym's members.
- Audit: bookings, cancellations and catalogue changes are audited like gate actions.

## F3. Shop — proper storefront for products (SHP)

**What.** Protein, supplements, merchandise, and remaining ancillary services
get a real Shop section with **images** (the provisioned R2 bucket
`gymloop-media`), categories, stock and prices. Members browse; the desk
sells at the counter and records payment (existing order flow); a member can
place an order to pick up and pay at the desk (no online charging — ADR-146
until PAY).

**Surfaces.** `addon_products` gains `image_url` and `category`; owner console
product manager with image upload (signed R2 URLs); member app **Shop** tab;
desk sell flow unchanged.

**Edge cases.**
- Image upload validation: size cap, MIME allowlist, one image per product at first (gallery later), placeholder when absent.
- Product deleted or deactivated with order history: orders keep the snapshot (price-at-sale already enforced by the money rules).
- Stock reaching zero mid-sale: the last item race follows the existing order-lock pattern; overselling is refused, not rounded.
- Category renames with live products; category ordering.
- GST rate per product already exists — display correctness on the member side.
- Member "order" without payment is a reservation with an expiry; desk confirms collection.
- Tenant isolation of images (R2 path prefixes per tenant).

## F4. Personal Training — a front section, not an add-on (PTF)

**What.** Trainers get profiles (photo, specialities, bio). Their session
packs are displayed as training programmes. Members pick a trainer and book
sessions on a calendar. Trainers get a "my clients today" view (TRV overlaps).

**Surfaces.** `staff` profile fields; member app PT section; trainer desk
view; booking calendar shared with CLS infrastructure.

**Edge cases.**
- Trainer leaves the gym with unspent packs: reassignment flow (the add-on logic already locks products per order; surfacing it).
- Pack expiry with sessions remaining; per-session consumption conflicts.
- Double-booking a trainer (same slot two members) — the CLS capacity lock generalizes to trainer calendars.
- Cancellation policy per gym (late cancel consumes a session or not — business rule, per-tenant setting).
- A member's trainer-facing data must not be visible to other members; trainer sees only their own clients (RLS).

## F5. Announcements on Home (ANC)

**What.** Owner/staff post announcements (text, optional image): "closed
Sunday", "new spin bikes". They appear as cards on member Home with read
receipts, and later as push (NTF).

**Surfaces.** Console composer; member Home feed; `notifications` reuse for
read/click tracking; consent system distinguishes promo from transactional.

**Edge cases.**
- Marketing consent gates promotional announcements (the consents system already exists); transactional (safety/closure) goes to everyone.
- Expiry and unpin; edit-after-publish is versioned, not silent (members may have read v1).
- Targeting: all / segment (status, membership, class cohort once CLS exists).
- Read receipt is per member (notifications table shape fits).

## F6. Push notifications (NTF)

**What.** Android push via FCM. Segments: away-7+-days, renewal-due, class
reminders (with CLS), announcements (with ANC). Member settings toggle per
category. The `notifications`, `member_devices`, `consents` tables already
exist — this is delivery wiring plus policy.

**Edge cases.**
- Consent withdrawal mid-campaign removes the member from the segment without a send.
- Token rotation and uninstall handling; stale tokens pruned on delivery failure.
- Dedupe per member per event (`dedupe_key` exists) so a backfill cannot double-buzz.
- Quiet hours (no promo pushes 21:00–08:00 IST); transactional exempt.
- Clicked/delivered tracking (`clicked_at`, `delivered_at` exist) and failure reasons.
- Tenant isolation: a gym can never push another gym's member.
- Minors: push routes to the guardian's device (GRD).
- OEM battery-kill realities: delivery is best-effort; the in-app inbox remains the source of truth.
- Per-tenant rate limits and campaign review before a bulk send (front-office role boundary).

## F7. Optional guardian and minor protection (GRD)

**What.** Optional guardian fields on `members` (name, phone, email,
relation). If `date_of_birth` < 18, guardian + a consent record are required.
For minors, the guardian's Gmail is the linked app user, notifications route
to the guardian, and absence-risk scoring is OFF unless a guardian consent
record exists. Closes the open DPDP follow-up from ADR-172.

**Edge cases.**
- No DOB given: no behavioral scoring for that member (fail-safe), guardian optional.
- Member turns 18: scoring eligibility turns on by date; guardian fields become optional but retained for history; account transition (guardian-linked → own account) is an explicit flow, not automatic.
- Same guardian, multiple children: each child is a separate member row with the same guardian Gmail — **collides with the current one-binding-per-identity rule (PROV-006)**; must be decided together with INV.
- Consent withdrawal: scoring stops, attendance recording continues (attendance is the gym's operational record; scoring is the inference).
- Guardian contact changes; guardian vs member shown on receipts (payer note).

## F8. business_type — multi-vertical copy (BIZ)

**What.** A per-tenant setting `business_type` (gym | dance | yoga |
martial_arts | studio) with a display noun that drives app copy ("Ask your
academy"). The schema is already vertical-free; this is copy, settings and
listing correctness.

**Edge cases.**
- Copy audit: every user-visible "gym" string across mobile, web, emails and legal pages — the public pages must stay truthful for every vertical.
- Changing business_type on a live tenant flips copy mid-membership; version the copy change with an announcement (ANC).
- `/platform` classification and analytics labels per vertical.
- Play listing and privacy policy wording stay vertical-neutral ("fitness and activity businesses").

## F9. WhatsApp channel (WSP)

**What.** Provider wiring for WhatsApp (the `messaging_wallets` ledger is
already scaffolded): renewal reminders, absence follow-ups, receipts.
Pay-per-message wallet per gym.

**Edge cases.**
- Meta template approval before any send; DLT registration for India.
- Opt-in/out per member via the consents system; withdrawal stops sends immediately.
- Wallet empty: fail-safe (no send, desk fallback), never a silent drop.
- Per-message cost recorded in the wallet ledger (money rules apply — integer paise).
- Delivery and read receipts; fallback to in-app/push on failure.
- PII minimization in templates (no balances/arrears in plain template text where avoidable).

## F10. Member-visible orders and payment requests - manual collection (PAY)

**Owner direction, 2026-10-02:** **no payment gateway.** Money is collected at
the counter, exactly as ADR-146 decided. What is built instead is the perfect
*offline payment track*: the member sees every rupee the gym asks of them and
everything they buy, in the app, before and after the desk records it.

**What.**
- A **payment request** the owner/desk raises against a member: what it is for
  (renewal of plan X, PT pack, shop order, locker rent), the amount, GST, due
  date. The member sees it in the app, can **accept** (acknowledge) or
  **query/reject** (tell the desk something is wrong) - accepting is not
  paying; the text says "pay at the counter."
- **Shop orders** name the product, quantity, price-per-unit and total; a
  member-placed order is a **reservation with an expiry**; the member picks it
  up at the counter, the desk records the money, the receipt appears in the
  member app.
- Full member-side history: paid receipts (exists today), open requests, open
  orders - one money screen.
- The money recording itself stays the existing desk flow: integer paise,
  paid rows frozen, refunds with ceilings, receipts, GST. Nothing about the
  ledger changes; the member just finally sees it.

**Edge cases.**
- Request states: `requested -> accepted | queried/rejected -> paid at desk | cancelled by desk | expired`. State transitions audited; a rejected request is never silently re-raised (desk must act visibly).
- Acceptance is an acknowledgment with a timestamp and an audit row - it is legally "the member saw and agreed to owe this," not payment. The copy must never imply the member paid.
- Amount or product changed after the member accepted (price correction, pack swap): the request is versioned - the member sees what changed, old acceptance does not silently carry over.
- Duplicate request raised by the desk for the same thing: visible as duplicates; merge or refuse, never collect twice (the existing dedupe/refusal rules extend to requests).
- Member-placed order: stock reserved then expiry releases it (the last-item race follows the existing order-lock pattern); unclaimed reservations never block stock forever.
- Member rejects/queries a request: desk sees it in the console as a to-do, resolves in person; nothing auto-cancels.
- Member leaves the gym with open requests/orders: status hygiene on membership end - open requests are closed as `expired`, unclaimed orders released.
- A pending-status member cannot accept orders (consistent with every other self-service boundary).
- The member app shows requests read-only offline (cache), but accepting/rejecting requires a connection - clear error, no fake success.
- Notifications (NTF) later: "you have a payment request" is transactional - no marketing consent needed.
- Money-path blind rigor (ADR-059) applies: requests, acceptances, order expiry and their state machine are money-adjacent and get the full blind arrangement.
- **Explicitly deferred:** UPI/gateway (provider webhooks, auto-extend on verified payment, gates 20/21 evidence). If the owner later elects online charging, that is a separate change reopening all of it.
## F11. Member self-service (SLF)

**What.** In the app: see plan, request a freeze (existing desk action,
member-initiated as an approval request), request a renewal (PAY raises the
member-visible payment request; the desk collects and records it), view
receipts (already there).

**Edge cases.** Overlapping freeze requests; pending-status members blocked
from self-service; self-purchase reuses PAY edge cases; approval workflow
notifications.

## F12. Trainer view (TRV)

**What.** "My clients today": a trainer-role screen listing sessions and
remaining pack balances per client.

**Edge cases.** RLS to their own clients only; days with no clients; pack
balances shown must match the money/order records exactly.

## F13. Lead → member one-tap convert (LDC)

**What.** Convert a walk-in lead into a member without retyping, keeping
source attribution for metrics.

**Edge cases.** Duplicate detection by phone; converting a lost lead;
attribution preserved for the acquisition metrics gate.

## F14. Occupancy and revenue analytics (OCC)

**What.** Peak-hours and day-of-week attendance heatmaps per branch for
staffing decisions, plus two owner-facing additions pinned 2026-10-02:
**revenue trend over time** (monthly collection split by renewals vs
new-member money, refunds netted) and — once CLS exists — **class attendance
percent** (fill rate per class, which classes fill and which die; the number a
dance/yoga owner checks daily).

**Edge cases.** Holiday exclusion (existing calendar), timezone correctness
per branch, low-data smoothing on new gyms, cross-branch comparison view,
revenue trend must derive from the same money rules (integer paise, refunds
netted, no floats anywhere in the aggregation), class fill rate counts
bookings against capacity only for sessions that actually ran (cancelled
sessions excluded).

---

## What stays in add-ons

The add-ons **section** as the member sees it goes away; its contents split:

- PT session packs → **Personal Training** (F4).
- Protein, supplements, merchandise → **Shop** (F3).
- What genuinely remains — ancillary services: **locker rent, towel service,
  day passes, guest passes** — becomes an "Other services" category inside
  Shop, or sits on the gym profile. The `addon_orders` money machinery stays
  unchanged behind all of it: orders, receipts, refunds, GST and the
  blind-tested money rules are reused, not rebuilt.

## Standing rules for all of v2

- Every feature gets the full Gauntlet Loop; money, RLS and identity features get the full blind arrangement (ADR-059).
- `spec:` commits before implementation; holdout authors never read implementation.
- Migrations via CI only; no Supabase MCP; no eslint-disable.
- The closed-test feedback merges into this map before build order is locked.
