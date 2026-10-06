# FitCruxx classes and navigation implementation plan

6 October 2026. Owner-approved implementation contract, now archived in `openspec/changes/archive/2026-10-06-v2-native-navigation`. The owner subsequently approved the narrow Classes visibility/own-bookings migration and implementation today, superseding the original UI-only restriction for that contract alone. The approved Home and Shop design choices remain in force. Payment, freeze-command and unrelated backend changes remain outside this task.

Implementation, actual OnePlus evidence, independent visual/security review and full release gates are accepted. [Exact-head gate certificate](../evidence/v2/nav-release-gates-2026-10-06.json) records native161files/16,156tests, ordinary seed and independent34/26proofs, app/held/immutability and schema drift. Canonical behavior is in `openspec/specs/member-class-discovery/spec.md` and `openspec/specs/native-member-discovery/spec.md`; all15requirements/20scenarios are preserved. True Shop database pagination and faster database test infrastructure remain separate follow-ups, not delivered claims.

FitCruxx already models Gym, Yoga studio, Dance academy, Martial arts academy and Fitness studio. A tenant has one business type for its identity and wording, but can have several class services. A Gym can therefore offer Yoga, Dance and group fitness together without becoming a different business type. Reuse that structure and its scheduling engine. The only new persistent behavior required for an independent member Classes switch is a saved tenant setting and a safe member read.

## Existing support

| Concern | Existing implementation | Work required |
| --- | --- | --- |
| Business identity and wording | Generated business_type enum and businessNouns | Reuse; no new business types |
| Several activities at one gym | Class services with names, descriptions and active state | Owners add Yoga, Dance and other activities using the existing catalogue |
| Weekly timetable and one-off sessions | class_rules and class_sessions | Reuse existing forms and commands |
| Seats, booking, cancellation and attendance | class_bookings and existing commands | Preserve existing rules |
| Owner and manager catalogue control | Create, edit, enable and disable service controls | Reuse; no new service activation mechanism |
| Products grouped in Shop | Existing product categories | Render the saved categories; unassigned products use Other products |
| Independent Classes tab visibility | No saved setting or suitable member projection | One small database contract is required |

The class catalogue is separate from paid Shop products and add-on services. A Yoga class service is a scheduling activity. A protein product is a Shop product. A membership plan remains a plan. A new taxonomy is unnecessary for these examples; structured style filters across activities would be a separate feature.

Sources: [business type and nouns](../../packages/shared/src/business-type.ts), [class catalogue loaders](../../apps/web/lib/classes.ts), [owner catalogue](<../../apps/web/app/(console)/classes/services/page.tsx>), [existing class contract](../../openspec/changes/classes/proposal.md), and [generated settings shape](../../packages/db/types/database.ts).

## Mixed activities and dedicated businesses

The owner confirmed that Gym remains a principal audience but the app must also serve dedicated academies and studios. Business identity and offered activities remain independent:

| Saved business type | Example class services | Existing wording |
| --- | --- | --- |
| Gym | Yoga, Zumba, Dance, Strength circuit | gym, members, classes, trainer |
| Dance academy | Zumba, Contemporary beginners, Salsa evening | academy, students, batches, instructor |
| Yoga studio | Hatha Yoga, Vinyasa, Meditation | studio, members, classes, teacher |
| Martial arts academy | Karate beginners, Boxing, Conditioning | academy, students, classes, instructor |
| Fitness studio | Pilates, Cycling, Mobility | studio, members, classes, trainer |

Each name is an owner-created class service, not a new enum value or a change to business type. Owners use the existing catalogue and schedule forms to set its days, times, branch, capacity, duration, instructor and validity dates. Several occurrences of one activity, activities on different days and one-off sessions use the current model.

Compatibility is automatic after the business type is saved; the app does not infer an academy from its name or from a newly added Dance service. Current onboarding starts as Gym. Dedicated academies and studios therefore require the existing owner or platform business-type choice before they show the appropriate wording. This pass must verify all five types rather than assume the gym-only device evidence proves them.

For the member timetable, retain a date strip, a chronological session list and a compact My bookings section. Add an All activities filter plus filters using actual service names and IDs from the member-authorized timetable. These filters are a UI addition; the current native screen only filters by day. Never hard-code a Yoga, Zumba or Dance taxonomy. A beginner batch can use its actual catalogue name without a separate levels schema.

Each session card should show its full activity or batch name, local start and end time, branch when relevant, instructor or teacher label from businessNouns, availability and the existing Book or Cancel action. Keep booked and cancelled commitments visible through My bookings even when an activity filter excludes other catalogue rows. Use service ID and session ID for selection and keys, not name alone. If a selected service disappears from a refreshed read, reset the filter to All activities.

The bottom destination remains **Classes** to follow the owner's exact five-tab IA; the page heading and content can use **Batches** for dance. This deliberately replaces the current dance bottom label derived from nouns.classes while retaining the existing business nouns inside the screen.

### Current product boundaries

The current class booking rule admits any member with a live tenant membership on the session day, subject to branch, capacity, session state and service availability. It does not link individual membership plans to specific activities, deduct class credits or establish a permanent enrolled cohort. These are additional business rules if later requested. Calling a service Salsa beginners or calling a session a batch does not create those entitlements.

Booking and class attendance remain separate from a premises check-in. A dance student's QR visit must not automatically mark that student attended in a batch. All five business types use the existing explicit class attendance commands.

The existing native timetable loads a bounded upcoming window. Past booking records remain stored; a complete historical UI is not currently demonstrated and must not be claimed from a My classes link alone.

The source review found a separate commitment-visibility gap: read_member_class_schedule applies current branch eligibility before its own-booking exception. If cross-branch booking is turned off after a booking, or a member's home branch changes, that booked session disappears from the timetable even though the cancellation command still permits cancellation of an otherwise eligible own booking. A link to the same timetable does not resolve this gap. See the [current schedule projection](../../supabase/migrations/20261003160000_member_booking_policy_reads.sql) and [existing cancellation command](../../supabase/migrations/20261003140000_classes.sql).

Include a dedicated read_member_upcoming_class_bookings projection in the proposed Classes contract. It takes no tenant, member or date arguments. Capture one server clock per call, then return only the canonical caller's own booking rows whose sessions end after that clock and start before that clock plus the existing class horizon. Include the caller's cancellation states with the authoritative session status so a recently cancelled upcoming class is not presented as an active commitment. Derive display dates from each session's branch timezone and order by absolute start time and session ID.

This absolute upcoming window avoids a home-branch date excluding a future class whose other branch calls the same instant yesterday. It is independent of current branch browsing access or service activation. Retain existing tenant and account validation and cancellation eligibility, including current deadlines. Existing catalogue and new-booking rules remain unchanged. My bookings and the non-tab My classes entry use this projection so a branch change cannot hide an outstanding commitment. This is a proposed additive reader, not currently implemented behavior.

## Confirmed Home and Shop placement

The [first orange reference](../design/v2-nav-shop-home-orange-reference-2026-10-06.png) is the visual bar for the arrangement and numerical text. Apply the subsequent owner decisions over its earlier bell and Freeze placement:

- **Home:** greeting and visit progress; membership with one compact Messages for you preview; Last visit; two shared announcements under From your gym, From your studio or From your academy; View all opens a separate list. Keep the check-in action easy to reach. No bell or duplicate updates banner.
- **Shop:** Products with saved categories and real images or honest placeholders; Plans; Services; purchase-request access; then reservations. Show three reservation rows and reveal five more per tap. Numerical emphasis uses the current primary color; existing theme tokens remain unchanged.
- **You and the business hub:** membership renewal and Freeze requests remain contextual to membership; My classes and training remain reachable when Classes is hidden. Render the hub title and instructor or teacher wording using existing business nouns, including the current Trainers & programmes row.
- **Buy:** contextual entry beside the plan or offer, with access to the existing purchase-request screen. The missing purchase creation flow is still D5 and must be resolved by its designated implementer before promising checkout.
- **Desk:** explicitly declare every route's visibility, keep no more than five primary destinations and place native Training in More when appropriate to the signed-in role. Preserve permissions and access to the class roster.

## Edge cases to verify before release

| Scenario | Required outcome |
| --- | --- |
| Gym adds Yoga, Zumba and Dance with different weekdays | All three appear under their real service names on the correct local day; no business-type change or new enum is needed |
| Dedicated dance or yoga tenant | Member screens, announcement heading, business hub and instructor or teacher labels use the saved type, including loading and empty states |
| New tenant remains at the Gym default | Setup exposes the existing type choice; do not claim the app detects its business automatically |
| Classes enabled with no service or no session today | Five tabs remain; show the appropriate empty timetable state and allow another day |
| Classes disabled while the member is viewing Classes | Return the primary destination safely to Home and retain My classes access for commitments; no orphan route or extra tab |
| Service disabled with existing bookings | No new service bookings; honor and display existing commitments under the existing freeze-and-finish rule |
| Filtered activity has no session on the selected day | Show an honest filtered empty state; All activities and day selection remain available |
| Same activity has several times or branches | Separate session cards with times and branch context; stable IDs prevent merging occurrences |
| Owner renames or removes an available activity while the screen is open | Refresh the authorized projection and reset invalid filter selection; do not display another tenant's stale catalogue |
| Cross-branch booking is disabled | Only member-eligible timetable rows are shown; the tenant's visibility setting remains independent of the branch result |
| Cross-branch access is turned off after booking, or the member changes home branch | My bookings retains the member's existing commitment and cancellation path using the proposed own-bookings projection; unbooked catalogue rows and new bookings retain current branch rules |
| Class is full, cancelled, started or booking eligibility changes | Show the existing authoritative state and refusal; do not hide Classes or invent a seat count |
| Two members try for the last seat or a member taps twice | Preserve existing database serialization and duplicate-booking rules; avoid duplicate UI submissions |
| Timetable changes between review and confirmation | Refresh and require review of changed facts using the current confirmation flow |
| Session crosses midnight or a branch has a different timezone | Place it on its branch-local start day and show correct local time and duration |
| A booked class is still in the future but its branch-local date is yesterday relative to the home branch | The proposed own-bookings read includes it using absolute server time, independent of the home-branch date strip |
| Weekly rules change, a holiday is added or an instructor becomes inactive | Preserve previously booked commitments according to CLS; do not infer cancellation from an absent generated row |
| Offline, failed read, account replacement or sign-out | Scope cached business nouns, visibility and timetable to the verified tenant and identity; errors are not Off; mutations remain unavailable offline |
| Long business, activity or product name and large text | Wrap meaningful names, preserve accessible controls and prevent tab-label truncation |
| A product has no photo or assigned category | Show a placeholder and Other products; never fabricate a product image or classify by keyword |
| More than three active reservations | Expose the additional active count and access; preserve deadlines and cancellation controls before compact history |
| Personal message and shared announcement arrive together | Use separate previews and existing read lifecycles without duplicating an update banner |

These cases form acceptance coverage, not a claim that every case has already passed on the device. The previous device test had no class session fixtures and only verified Gym wording.

## Recommended behavior

Use an owner and manager setting labelled **Show Classes to members**, with help text: “Show a Classes tab in the member app. Manage availability and new bookings in the class catalogue.” The setting controls discovery. The existing service activation controls continue to govern scheduling and new bookings.

| Tenant example | Switch | Member navigation |
| --- | --- | --- |
| Gym offering regular training only | Off | Home, Shop, You, Activity |
| Gym offering Yoga and Dance | On | Home, Classes, Shop, You, Activity |
| Yoga studio with no session today | On | Five tabs; timetable explains that no classes are scheduled today |
| Dance academy offering several batches | On | Five tabs; the current timetable lists its services or batches |

The switch is independent of business type, date, branch timetable, membership eligibility and available seats. A full class or an empty day cannot remove the tab. Owners can configure a timetable before showing it to members.

Turning the switch off preserves services, rules, sessions, bookings and messages. Keep a **My classes** entry in You or Studio that opens the existing Classes screen outside the bottom tabs so booked members retain their schedule and cancellation access. Personal training also remains reachable when Classes is hidden. To stop accepting new bookings, owners use the existing service-disable action, whose freeze-and-finish contract honors existing bookings. This switch does not cancel classes or suspend the booking engine.

For existing tenants, backfill visibility on when there is an active class service or a booking with status booked for a session with status scheduled and ends_at after the captured migration clock. This includes a booked class in progress and excludes ended sessions and cancelled bookings as the sole reason to enable the tab. Keep other tenants off. This is a one-time compatibility default, not a recurring automatic toggle. For new tenants, suggest an onboarding choice appropriate to their business type and allow the owner to change it. Adding a Yoga or Dance service must never silently change the tenant's business type.

## What can avoid a migration

The Home and Shop rearrangement, explicit non-tab routes, corrected desk bar, orange numerical text, category rendering and reservation preview require no schema changes. Keep these changes outside supabase and packages/db/types; the current DB workflow is path-filtered and does not run for those UI-only pushes.

An independent saved switch cannot be delivered with the current member reads alone. organization_settings has no class-visibility field or general feature-settings document. opening_hours is schedule data and cannot serve as a feature flag. The existing read_member_portal_settings projection exposes only location and visit-goal settings. Members cannot directly select the class tables.

Deriving visibility from read_member_class_schedule would answer a different question: that read is restricted by a bounded date window, allowed branches and active services. An empty response cannot establish that the tenant does not offer classes. A local phone preference also cannot synchronize an owner's decision across all members.

A catalogue-derived alternative can reuse services.is_active for persistence, but it still needs an authorized member availability read, and cannot represent “show Classes while no services have been added yet.” It is a smaller behavior, not an equivalent independent switch.

## Smallest reliable database change

For a separately authorized implementing session, propose one additive migration containing:

1. A non-null member_classes_enabled boolean on organization_settings, default false, with the compatibility backfill above. No new table or enum.
2. A small read_member_class_visibility projection that returns only the saved boolean after the existing canonical member and tenant validation. No caller-supplied tenant ID and no direct member policy on settings or class tables.
3. A narrowly scoped owner or manager visibility command and new-field write guard where required to enforce the actor contract below. These belong in the same additive migration; they do not replace class scheduling or booking functions.
4. A server-timed read_member_upcoming_class_bookings projection for caller-owned commitments, as described above. It returns no other member's booking or identity, keeps existing catalogue browsing rules untouched, and preserves access after branch configuration changes and branch-local date boundaries.

Use the existing class-settings route pattern and classCommand for an owner or manager visibility update, with canonical active-staff validation in the database before saving. A separate visibility request and response keeps the current cancellation and cross-branch settings wire contracts unchanged. Same-value retries return no change. Tests must cover revoked or mismatched staff and direct attempts to change the new field, not merely the route's claimed role.

Existing organization_settings policies allow same-tenant staff reads and platform reads. Preserve those existing read gates. The new member projection is member-only and returns a boolean, not the settings row; wrong-audience calls and other tenants are refused. Normal staff reading a setting is distinct from permission to change it. Keep any guard confined to writes of the new field so existing settings commands continue to work.

Generate database types with the CLI after CI applies the migration, following the repository's normal schema-drift procedure. Never hand-edit generated types or apply the migration locally. Register every new exported symbol before the implementation lands.

This introduces a small configuration contract, rather than rebuilding classes. It still requires the repository's database checks. The workflow's twenty-minute estimate is outdated: [run 37389309267](https://github.com/OGUN01/gymloop/actions/runs/37389309267) applied its migration in 56 seconds and spent about 124 minutes in a failing pgTAP job. [Run 37376568883](https://github.com/OGUN01/gymloop/actions/runs/37376568883) applied its migration in 31 seconds and spent about 110 minutes in a failing pgTAP job. These job durations do not establish the causes of those failures. The [database validation plan](v2-database-validation-plan-2026-10-06.md) addresses the owner's subsequent request for a durable reduction in validation time.

## Implementation sequence

1. Freeze the behavior above in a human-approved EARS change, including the discovery-only meaning of Off, backfill, pending bookings, role access and offline behavior. Keep the database contract with its implementing session and the visual change with this UI session.
2. Have independent test authors cover the privileged member reads and owner write from that contract before implementation. Commit tests first. Implementers do not read holdout files or modify test files. Include another tenant, wrong roles, revoked identity, absent settings, no-op saves, compatibility with existing class-settings clients, branch changes after booking and isolation of own bookings from every other member's bookings.
3. Build the additive settings change without editing class booking, generation, payment or freeze-request logic. Run focused checks first, obtain a fresh critic review, and then complete the required database gates. Do not run a local Cloud sweep concurrently with DB CI.
4. Land the database unit on main through CI. Keep new UI dormant until the read is available. Verify generated types and all required gates before using the new contract in member navigation.
5. Complete the UI unit: Home, Classes when enabled, Shop, You, Activity; contextual Buy and Freeze; a clean desk bar; catalogue-first Shop; Home messages near membership and two announcements below Last visit. Keep actual Chalkline tokens unchanged and apply the existing primary color to key numbers and prices.
6. Use saved tenant-scoped visibility immediately when available, refresh it on app resume and relevant screen focus, and refresh the timetable when opened or manually refreshed. While the initial visibility read is unresolved, render a stable loading state; failures must not be interpreted as Off. Retain the last confirmed value during temporary network failure and clear it on sign-out or identity replacement. This gives updates on the next refresh; instant live synchronization would need a separate realtime contract.
7. Show three reservations initially, then reveal five per Load more tap from the existing response. Retain active hold actions and expose any additional active-hold count. True database pagination remains separate because the current catalogue response already includes the reservation history.
8. Verify on the connected OnePlus DN2101 using only in.fitcruxx.v2check. Capture both four-tab and five-tab states, empty enabled timetable, mixed services, contextual entry points, Shop and Home. Use the documented C:/gc build recipe, preserve the Play-signed pilot, and save new screenshots under docs/evidence/screens.
9. Push each green coherent unit directly to main, wait for CI, fold completed requirements into current specs and update the registry. Do not upload another Play build.

## Acceptance requirements

- **NAVC-001:** WHEN a tenant offers several class services, the system SHALL schedule and display each through the existing class model regardless of the tenant's business type.
- **NAVC-002:** WHEN the saved Classes visibility is On, the member app SHALL show exactly Home, Classes, Shop, You and Activity, including on an empty timetable day.
- **NAVC-003:** WHEN the saved visibility is Off, the member app SHALL show exactly Home, Shop, You and Activity and retain access to booked classes and personal training outside the bottom tabs.
- **NAVC-004:** WHEN a verified active owner or manager changes visibility, the system SHALL persist it for that tenant and refresh members from that shared value; unauthorized actors SHALL not change it, other tenants SHALL not access it, and the member projection SHALL refuse wrong-audience callers while preserving existing staff and platform settings reads.
- **NAVC-005:** WHEN visibility is switched Off, the system SHALL preserve existing sessions, bookings and their normal cancellation paths without cancelling them as a side effect.
- **NAVC-006:** WHEN a visibility read fails or the device is offline, the app SHALL retain a valid saved tenant value or show unresolved loading and retry, rather than treating the failure as an empty catalogue.
- **NAVC-007:** WHEN Buy, Freeze, Training or a full announcement list is opened, the app SHALL retain the intended bottom navigation count and honor the existing role permissions.
- **NAVC-008:** WHEN Shop opens, the app SHALL display Products, Plans and Services before reservation history, using saved category names and a three-row history preview with five more rows revealed per explicit tap.
- **NAVC-009:** WHEN Home opens, the app SHALL show a compact Messages for you preview near membership and two shared announcements below Last visit with View all, without adding a bell or duplicate update banner.
- **NAVC-010:** WHEN an owner configures any supported business type and several class services, the app SHALL resolve its business wording from the saved type and display the actual service names independently of that type, without altering booking eligibility rules.
- **NAVC-011:** WHEN the member filters activities or changes the selected day, the timetable SHALL use member-authorized service and session IDs, retain access to the member's booked commitments and show a truthful empty state.
- **NAVC-012:** WHEN the app renders mixed activities, long names, large text or a missing image, the UI SHALL preserve legible labels and accessible actions within the approved Chalkline theme.
- **NAVC-013:** WHEN current branch browsing access changes after a member has booked, the own-bookings projection SHALL retain that member's upcoming or in-progress session and current cancellation facts within its absolute server-timed horizon, without exposing another member's bookings or granting new booking eligibility.
- **NAVC-014:** WHEN branch-local calendar dates differ, the own-bookings projection SHALL include sessions by absolute start and end time and display each in its own branch timezone rather than filter commitments by the member's home-branch date.
- **NAVC-015:** WHEN existing tenants receive the visibility setting, the one-time backfill SHALL enable it for an active service or a booked, scheduled session ending after the migration clock, and SHALL not enable it solely because ended sessions or cancelled booking history exist.

The proposed setting and privileged read are outside the original UI-only scope. No application code, database migration, generated types, test file or Play release was changed while preparing this plan.
