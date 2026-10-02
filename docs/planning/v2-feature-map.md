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
| A | Identity foundations | INV, STI, GRD, BIZ |
| B | The "front" of the app | CLS, SHP, PTF, ANC, PLC |
| C | Reach and member-visible money | NTF, WSP, PAY |
| D | Polish and retention | SLF, TRV, LDC, OCC, RPE |

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
- The Google account is already linked to a member row in ANY gym: **DECIDED (owner, 2026-10-02): one account, one member, ever.** Refuse with clear copy - this account is already joined as a member and cannot be linked again; ask your gym to use a different email. Never a picker, never a silent second binding.
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
- Same guardian, multiple children: **DECIDED (owner, 2026-10-02): one Google account, one member.** Both children's rows may carry the guardian's contact fields (notifications, DPDP consent), but only one child's row binds the guardian's Gmail as its app identity; a second child needing app access links a different Google account, chosen by the gym at invite time.
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

## F10. Buy tab, member-initiated requests and payment screenshots - manual collection (PAY)

**Owner direction, 2026-10-02 (amended same day):** **no payment gateway.**
Money is collected outside the app (cash, or UPI to the gym's own QR). What
the app adds is the **member-initiated purchase flow with payment proof** -
the direction is the member's, not the desk's.

**What.**
- A **Buy / Payments tab** in the member app. The member raises a request for
  what they want: a **shop product**, a **PT pack**, or a **gym fee**
  (renewal of their current plan; plan changes stay desk-assisted).
- The request lands with the owner/desk for **acceptance** (stock, price
  confirmation, eligibility - e.g. live membership for a PT pack).
- The member pays outside the app and **uploads a payment screenshot** (UPI
  transaction confirmation) against their request.
- The owner/desk **verifies the screenshot** and records the payment in the
  existing money flow - that record (not the screenshot) is what activates the
  product, extends the membership or credits the pack. Receipt appears in the
  member app.
- The desk can still record plain counter sales as today (walk-in, no app
  involvement); both paths feed the same ledger.

**State machine.**
`requested -> owner_accepted -> payment_proof_uploaded -> recorded (paid)`,
with `rejected by owner`, `rejected proof` (member re-uploads), `cancelled by
member` (before owner acceptance) and `expired` as exits. Every transition is
audited.

**Edge cases.**
- **The screenshot is evidence, never money.** No state advances on upload
  alone; only the desk's recorded payment does. All existing money rules
  (integer paise, frozen paid rows, receipts, GST) apply unchanged to that
  record.
- **A screenshot is not proof of receipt of money by the gym** - it is proof
  the member *says* they paid. The desk's manual verification is the control;
  the copy must say "pending verification," never "paid."
- One active proof per request; a member can replace it before verification. A
  rejected proof requires a reason (typed by desk, shown to member).
- Screenshot hygiene: size cap, MIME allowlist (image/*), one per state,
  tenant-scoped private storage in the R2 bucket. **DPDP retention rule
  required** - screenshots carry UPI transaction ids and partial account
  details; delete N days after the verification decision (default 90), and
  never show one member's proof to another member or staff outside the
  verifying path.
- A proof file may verify exactly one request: recording a payment binds the
  stored image to that payment row so the same screenshot cannot verify two
  purchases.
- Stock race: two members request the last item; the owner accepts one, the
  other is declined with the out-of-stock reason. Acceptance reserves stock
  with the existing order-lock pattern; request expiry releases it.
- Amount mismatch: the member's request and the verified money may differ
  (they paid the old price). The desk records the truth; the request shows the
  difference rather than silently matching.
- Member cancels after owner accepted: allowed until payment is recorded;
  stock released, state auditable.
- Member leaves the gym with an open request: closed as expired.
- Offline: the Buy tab is read-only; raising a request or uploading proof
  needs a connection - clear error, no fake success.
- Notifications (NTF) later: "order accepted", "payment verified", "new order
  awaiting approval" for the desk - all transactional, no marketing consent.
- Money-path blind rigor (ADR-059) applies to the state machine, screenshot
  binding and request expiry.
- **Explicitly deferred:** UPI/gateway (provider webhooks, auto-verification,
  gates 20/21 evidence). If the owner later elects online charging, that is a
  separate change reopening all of it.

**What.** In the app: see plan, request a freeze (existing desk action,
member-initiated as an approval request), request a renewal (PAY's Buy tab:
member raises the request, pays outside the app, uploads proof, the desk
verifies and records it), view receipts (already there).

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

## F16. Plans catalogue in the member app (PLC)

**What.** A read-only view of the gym's active plans - name, duration, price,
what it includes - in the member app, giving the Buy tab's renewal request its
context: a member sees what exists, not only what they already hold.

**Edge cases.**
- Only active plans are visible; inactive or hidden plans never leak to members.
- The price shown is the plan's current price; a member's existing membership keeps its recorded price (the existing snapshot rule) - the two may differ and the copy must not imply the old price still holds.
- Plan ordering follows the existing sort order; no re-sorting on the member side.
- Read-only: the member may request a renewal of their current plan; any other plan change stays a desk conversation (consistent with the GL043 plan-change refusal rules).
- GST is displayed per the existing GST-rate storage; no tax math is invented client-side.
- Offline: the catalogue is cached read-only like the other member read views; no stale-price purchase is possible because no purchase happens in the app.

## F17. Staff invites (STI)

**What.** INV's self-linking token machinery extended to staff rows: an owner
invites a desk member, trainer or manager by email, they self-link with
Google, and manual staff provisioning retires for new gyms.

**Edge cases.**
- Only a gym_owner (and /platform) may send a staff invite - role boundary enforced at the console and revalidated at redemption.
- The role (front_desk / trainer / gym_manager) is assigned by the inviter and never editable by the invitee; a trainer invite lands on trainer-only surfaces (TRV boundaries).
- One staff identity per row, reusing the one-binding rule; the same person staffing two gyms is refused with the same clear copy (owner decision 2026-10-02: one account, one identity, ever).
- Owner-level invitations: only /platform links gym_owners (the existing boundary) - an owner may not create another owner.
- Expiry, resend and revoke reuse INV's token machinery; expiry frees nothing but the token.
- Unbinding a staff member revokes their sessions through the existing identity-change hook.
- Every invite, link and unlink is audited.
- The invited email must match the staff row exactly, with the same refuse-generic copy as member invites.

## F18. PDF reports and GST invoice export (RPE)

**What.** Owner-console exports: payments, attendance and member lists as
CSV; GST-compliant invoice PDFs from the existing invoices table. Download
only - no email sending, no scheduling.

**Edge cases.**
- Exports are tenant-scoped by RLS: a gym can never export another gym's data, and export runs under the requesting staff member's role.
- Every export carries a generated-at timestamp and data-range stamp inside the file - no undated numbers.
- Money renders from integer paise through the existing formatter only; no float anywhere in an export, ever.
- GST invoice layout follows the stored per-line tax breakup; a mismatch between invoice and payments tables is an export-time refusal, not a rendered guess.
- Export is a data-egress event: audited (who, what, when, range), visible in the audit log.
- Large exports get row caps or async generation - never a timeout that silently truncates a tax filing.
- Owner console only in v2; a member-facing invoice download is a later candidate.

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

## F16-F18 promoted to committed features (owner decision, 2026-10-02)

The three gap-review items below were promoted by the owner into the
committed v2 list as F16 (PLC), F17 (STI) and F18 (RPE) - see their own
sections above, before "What stays in add-ons".

## F15. Parked candidates - build only on real demand

- **Free trial class booking.** A lead books a trial class from CLS's
  timetable - the standard dance/yoga acquisition move. Waits for CLS.
- **Dues / credit ledger ("pay later").** Owner records a trusted member's
  purchase as credit; the member app shows pending dues. Real Indian small-gym
  behavior; extends the money rules rather than bypassing them (credit is a
  recorded state, never negative money). Builds when a real gym runs credit.
- **Coupons, member-facing.** The `coupons` table exists owner-side; members
  never see a discount. Waits for marketing maturity.
- **Class waitlists.** Full class -> waitlist with auto-notify on a freed
  spot; requires NTF. Only if small gyms hit capacity walls.

## Deliberately out of scope (decided 2026-10-02, revisit only on real demand)

1. **Full accounting and payroll.** Expense tracking, staff salaries - that is
   accounting software's job. This product records money a business collects
   from its members; it does not run the business's books.
2. **Diet and workout plan builder.** A content business with a different
   loop; dilutes the churn-retention core.
3. **Two-way WhatsApp chat.** Reminders and requests go out; replies happen
   in person at the desk. No inbound message handling.
4. **Trainer commission tracking.** Dropped by owner decision 2026-10-02:
   money-adjacent niche view, not worth the blind-rigor overhead. Trainers'
   share is settled outside the app.
5. **Referral programs.** Dropped by owner decision 2026-10-02. Lead source
   attribution already exists; anything more is marketing overhead.
6. **Birthday/anniversary auto-greetings.** Dropped by owner decision
   2026-10-02. An owner who wants this sends an announcement; no feature.
7. **Progress tracking (dance levels / fitness measurements).** Dropped by
   owner decision 2026-10-02: scope-heavy and pulls toward a fitness-content
   product, away from the churn-retention core.
