# FitCruxx navigation Shop and Home analysis

6 October 2026. Analysis and reference design only, following the owner's instruction to analyse before implementation.

The member app should foreground the next useful action: visit, browse what the studio offers, manage membership, and review activity. Shop currently puts reservation history before its catalogue, while Home puts long studio announcements before membership and the last visit. Reordering these surfaces addresses the clutter without changing Chalkline.

## Device findings

Fresh captures came from the connected OnePlus DN2101, serial INPZT8DQPJROKFXC, running the existing `in.fitcruxx.v2check` app. The installed member bar still contains seven items, including the unintended Buy and Freeze routes.

Shop shows an active whey reservation followed by repeated expired and cancelled reservations. Products and services appear after that history. The visible catalogue contains Whey Protein 1 kg Chocolate at ₹2,400 and a Fat Loss Diet Plan of eight weeks at ₹2,500. The product is labelled Uncategorised and has a placeholder image. These are presentation and catalogue-content problems; a redesigned tile cannot supply a missing verified photo or an assigned category.

Home shows three large announcement previews and an inline Show all action above the membership and Last visit rows. The announcement list competes with the scan action and daily visit information.

## Proposed navigation

| Surface | Primary destinations | Contextual destinations |
| --- | --- | --- |
| Member with Classes enabled | Home, Classes, Shop, You, Activity | Buy and purchase requests from Shop; renewal and Freeze requests from Studio |
| Member with Classes disabled | Home, Shop, You, Activity | Same contextual destinations; retain booked classes and personal training outside the bottom tabs |
| Front desk | Check-in, Classes, Members, Follow-ups, More | Training through More with the existing role permissions |

Buy, Freeze requests, Studio, announcement lists and drill-down screens must not acquire additional bottom-tab buttons. Declare their visibility explicitly or place detail screens in an appropriate stack; deleting them from the visible tab list alone does not prevent Expo Router from registering route files. Expo documents hidden route buttons through [href null](https://docs.expo.dev/router/advanced/tabs/#hiding-a-tab).

The current Training file is declared as a tab only for trainers, but its undeclared route still leaks into other desk bars. Hide it explicitly for other roles. A trainer's native Training destination must remain reachable with its existing authorization; moving it to More requires a native entry for that role, rather than replacing it with the generic web-console link.

Hiding Classes must not hide personal training: the existing member Classes route also hosts Training. Keep training discoverable from Shop Services and Studio Trainers and programmes even when the Classes tab is absent.

## Proposed Shop layout

1. Compact studio identity, Shop title and refresh affordance. Replace the large refresh button with a quiet control or pull to refresh.
2. Products, Plans and Services section links. These are links within Shop, not more bottom tabs.
3. Products first: show the image or honest placeholder, full name, variant or size, price and availability together. Use existing category names such as Protein when the catalogue supplies them. Never infer a business category from a product-name keyword; show Other products when none is assigned. The board's Protein label illustrates an intended category, not the demo product's current classification.
4. Plans as a separate compact section with View plans and Buy; keep the detailed catalogue in its existing surface. Avoid loading plan data before it is needed when the existing hook supports lazy reads.
5. Services separately, with their duration and price. Training links lead to the existing training surface.
6. Purchase requests as a small utility row.
7. Your reservations below the catalogue, with active holds ahead of compact history. Show three rows initially and reveal five more per explicit Load more tap. Preserve position and prevent duplicate taps while loading. Expired and cancelled rows need a concise date and state; the repeated Hold ended paragraph is unnecessary.

Use a continuous vertically scrollable page with manual Load more. Preserve every active hold's deadline and cancellation action. If more active holds exist than the initial preview allows, make the remaining-active count and access visible so history cannot conceal a reservation that needs collection.

The product action remains Reserve: it holds an item and the member pays at the desk. Buy is contextual to the plan or purchase-request flow. Freeze belongs in You → Studio → Membership through the existing Freeze requests row, with a renewal card alongside it.

## Proposed Home layout

Personal messages and shared announcements are separate content sources. The current Latest from your place row comes from the member's own in-app notifications, including reminders and owner-sent messages; it is not a chat thread. From your place comes from the announcement feed for eligible members. Both labels must use the existing business nouns, which map gym to gym, yoga and fitness studio to studio, and dance or martial arts to academy.

The owner confirmed this Home choice on 6 October: remove the bell and New studio updates banner, rename the personal row Messages for you, show one compact preview near membership, and retain the separate shared announcement previews below Last visit. Its full list opens the existing Studio Messages section. Personal messages and announcements retain their separate read lifecycles; this UI change does not fix D2.

Then show the greeting, weekly visits, week rhythm, membership summary and Last visit. Place From your studio below Last visit, with exactly two compact previews and View all. Each preview retains title, a short body preview, notice kind, a friendly posted or edited date, and the honest New or Updated state.

View all should open a separate non-tab announcement list or sheet instead of expanding Home into a long feed. Reuse the existing cache, read tracking and updated-version notice. Keep Scan to check in clearly reachable above the bottom navigation.

## Owner visual choice

On 6 October the owner chose the first generated reference's orange numerical text over the revised near-black numerical text and requested implementation. Use the existing Chalkline primary action color for prominent visit numbers and prices. Keep body copy and supporting information in their existing theme colors. The [orange reference](../design/v2-nav-shop-home-orange-reference-2026-10-06.png) records that visual choice; its earlier Freeze card placement inside Shop is superseded by the Studio entry point above.

## Classes capability proposal

The owner then asked whether Classes should be explicitly enabled by the gym owner, rather than inferred from an empty timetable. Recommended behavior: persist an Offer classes setting per tenant, editable by the roles authorized to manage its catalogue. Business type may suggest an onboarding default but cannot lock the capability: a gym may also offer yoga or group training.

When disabled, the member has four tabs. When enabled, the member has five tabs even if there are no sessions today; Classes shows the appropriate empty state. Scheduling continues through the existing catalogue, rules and sessions. Member views refresh their saved timetable when opened or refreshed. Disabling must preserve existing bookings and history; its handling of future bookings needs an explicit contract before backend implementation.

This proposal replaces inference from zero timetable rows. The owner subsequently requested the fastest reliable implementation plan, including migration-free alternatives. The [classes and navigation plan](v2-classes-and-navigation-plan-2026-10-06.md) defines the recommended discovery switch, existing mixed-service support and the smallest additive database contract. No toggle, migration or availability workaround has been implemented; backend implementation remains outside the original UI-only boundary.

## Constraints that affect implementation

**Database pagination is a separate dependency.** The mobile Shop calls `/api/shop/catalogue` with an empty request. `loadMemberShop` fetches both `read_member_shop` and the no-argument `read_member_shop_reservations`; the response includes the reservation array and no cursor. Hiding rows or slicing an array improves layout but does not reduce the initial database fetch. On 6 October the owner confirmed showing three reservations and revealing five more per tap for this UI pass, with true database pagination handed off separately. Do not claim a database performance fix from client-side Load more.

**A tenant catalogue existence check differs from an empty timetable.** Members cannot directly read the classes tables under the existing staff-only policies. The available `read_member_class_schedule` projection is constrained to a date window and the member's allowed branch; scheduled rows also depend on an active service. A zero-row result therefore does not prove that the tenant has zero class sessions anywhere. The later owner-controlled visibility proposal supersedes the original session-count rule; do not implement a timetable-empty approximation while the new contract is being planned. Errors and offline states must not be treated as empty data.

**Buy remains D5.** The existing Buy screen lists purchase requests, supports cancellation and proof upload, but does not expose request creation. Moving that screen and adding a link improve discovery; they do not create checkout or a request submission path. Keep that behavior with the designated implementer and do not change money logic in this UI slice.

**D6 and D7 can be presentation follow-ups.** Remove the visible route string, retain one approval notice, format displayed dates through existing helpers, and make focused fields scroll above the keyboard. Preserve the ISO command payload and leave `lib/member-freeze-requests.ts` untouched. These changes would not resolve D1.

**Palette discrepancy.** The owner's brief names canvas #F2EFE9 and primary #B34724; the checked-in `UI_TOKENS` currently contains #F3F0EA and #AD4119. The generated board follows the brief. No palette code changed. Reconcile that difference before anyone treats the image as a request to recolor the app; the current task is an arrangement change.

## Reference and evidence

The [generated reference](../design/v2-nav-shop-home-reference-2026-10-06.png) shows Home, Shop discovery, reservation history, both member navigation variants, and Studio entry points. It was generated and refined with the built-in imagegen tool. Announcement copy and the Protein category are illustrative; the image is a design proposal, not device acceptance evidence. The [complete prompt set](../design/v2-nav-shop-home-reference-2026-10-06-prompts.txt) records the generation and correction.

Fresh device evidence:

- [Shop top](../evidence/screens/2026-10-06-device-shop-before-top.png)
- [Shop reservation history](../evidence/screens/2026-10-06-device-shop-before-nav-redesign.png)
- [Shop catalogue below history](../evidence/screens/2026-10-06-device-shop-before-catalogue.png)
- [Home top](../evidence/screens/2026-10-06-device-home-before-top.png)
- [Home announcements above membership and Last visit](../evidence/screens/2026-10-06-device-home-before-nav-redesign.png)

Application code, backend, Supabase files, generated types and tests are unchanged by this analysis. No build, install, release upload or CI completion is claimed. The Play-signed pilot was not touched. Existing unrelated working-tree changes were preserved.
