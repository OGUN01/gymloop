## Context

See proposal.md for motivation and the accepted 2026-10-06 planning document for the edge-case matrix. Current Expo tab route discovery includes unnamed secondary files. Current schedule reads combine browsing and own bookings but filter branch eligibility first. organization_settings has no independent discovery flag.

## Goals / Non-Goals

Preserve existing routes, canonical identities, booking commands, class status vocabularies and theme tokens. The only privileged additions are discovery configuration and an own-commitment read. Full database pagination, paid hosted runners, purchase creation, freeze-hook repairs and accounting changes remain separately owned work.

## Decisions

- Declare secondary screens explicitly with no tab button. Preserve their existing paths to avoid breaking push routing and confirmation flows; do not move their public routes as part of this pass.
- Separate discovery from service activation. Use one boolean with a one-time compatibility backfill instead of type heuristics or current-day session counts.
- Reuse canonical class actor and audit helpers and existing safe schedule projection fields for own commitments. Keep existing table RLS and settings clients intact. A new-field write guard prevents direct authenticated changes while the validated definer command owns saves.
- Keep native cache keyed by exact user/tenant/member with request-lifetime guards. Unknown is distinct from false. Refresh on resume/focus rather than promising realtime subscription.
- Reuse existing Shop response and grouping helper. The 3/+5 control changes rendered rows only; it does not reduce the existing database fetch.
- Retain the general announcement component's existing default for other consumers. Home explicitly selects compact two-card presentation and navigates to the full-list route, preserving the feed's existing read and consent lifecycle.

## Public contract for independent test authors

This declaration is fixed before fan-out. Authors read these contracts/specs, not application or migration implementation. Existing declarations and generated schema are allowed where fixture construction needs them; holdout authors read neither visible tests nor implementation.

### Database and owner API

- `organization_settings.member_classes_enabled boolean NOT NULL DEFAULT false`.
- `public.read_member_class_visibility()` returns TABLE `(enabled boolean)`, exactly one row for the canonical member's tenant; failure for absent settings or non-member/invalid canonical identity. No args.
- `public.set_member_classes_enabled(p_enabled boolean)` returns TABLE `(enabled boolean, changed boolean)`. Null is invalid (22023); canonical active owner/manager only (42501 refusal). Missing settings fail (22023). Changed save audits action `organization.class_visibility_changed`, record_type `organization_settings`, record_id tenant ID, before/after objects `{member_classes_enabled: boolean}`. No-op has no successful change audit.
- `public.read_member_upcoming_class_bookings()` returns exactly the existing `read_member_class_schedule` column names/types, restricted to caller-owned booking rows in the absolute server horizon described by NAVC-013/014. `my_booking_id`/`my_booking_status` are non-null in valid rows. Availability reflects existing booking/session state; cancelled rows SHALL NOT become open purchase opportunities. No caller args.
- Functions are postgres-owned definer functions with empty search_path, EXECUTE only to authenticated, canonical audience/tenant/member/staff validation before rows or writes. Preserve other existing policies and commands.
- Owner command `PUT /api/class-visibility`, strict body `{enabled: boolean}`; existing ApiEnvelope result `{enabled: boolean, changed: boolean}` and classCommand error conventions. No tenant identifier input.
- Shared declarations in `packages/shared/src/api/classes-data.ts`: extend existing `ClassReadClient`; add `readMemberClassVisibility(client): Promise<boolean | null>` and `readMemberUpcomingClassBookings(client): Promise<MemberClassSession[] | null>`. Malformed/error projections return null, never false or an empty success.
- Shared request/result declarations: `memberClassVisibilityRequestSchema`, `parseMemberClassVisibilityResult`. Existing class-settings request/result shapes stay unchanged.
- Native wrappers in `apps/mobile/lib/classes.ts`: `loadMemberClassVisibility(client)` and `loadMemberUpcomingClassBookings(client)`.

### Native presentation

- `useMemberClassVisibility()` in `apps/mobile/lib/use-member-class-visibility.ts` returns `{enabled: boolean | null, loading: boolean, error: string | null, reload: () => Promise<void>}`. Exact identity cache/late-read/resume behavior is NAVC-006.
- Existing `RoleTabs` accepts optional `memberClassesEnabled: boolean` (default true for isolated callers). Member layout obtains the authorized hook before presenting tabs. Primary member labels/order are fixed; desk names retain existing business noun mapping.
- Keep `(member)/buy`, `(member)/freeze-requests`, `(member)/gym`, `(desk)/training`. Add `(member)/announcements` with a default `AnnouncementsScreen`; all are explicitly hidden tab buttons.
- Business hub accepts `section=membership|plans|addons|messages|notifications|consent`; contextual Home messages target `gym?section=messages`, renewal targets plans. My classes targets `classes?section=bookings`; existing training parameter remains supported.
- `ClassesPane` adds optional `bookingsOnly: boolean` (default false). My bookings uses the separate reader, not filtered catalogue rows. Default timetable adds All activities and real service-name filters keyed by service ID.
- `AnnouncementsSection` accepts optional `previewLimit: number`, `onViewAll: () => void`, `showAll: boolean`. Existing default behavior remains available; Home sets the new native limit and opens the non-tab route, full route uses showAll.
- `Display` adds optional `accent: boolean` (default false), using the existing palette primaryAction.
- `NATIVE_MEMBER_LAYOUT` in shared constants: `homeAnnouncementCards: 2`, `reservationPreview: 3`, `reservationLoadMore: 5`. Register this and every added exported hook/helper/schema/screen.
- Home's business-header target must take only remaining row width (`flex: 1`, `minWidth: 0`), while the existing You avatar target keeps its token-sized touch area (`flexShrink: 0`). Long business/branch text may ellipsize visually but retains the full accessible label, ordinary text scaling and canonical routes. This fixes NAVC-012 device overflow at OnePlus font_scale1.35 without shrinking or recoloring the avatar.
- Member layout's Off redirect must use the currently focused child route's global query parameters; individual Classes/Gym screens retain local parameters. The layout reads `useGlobalSearchParams` for exact scalar `section=bookings|training`, preserving contextual commitments while redirecting primary Classes when hidden. Stale or absent layout-local values must not close a legitimate contextual route, and arrays remain invalid. This is NAVC-003/007 routing repair, with no change to the saved visibility or booking contract.
- Primary labels must never shrink below the existing eyebrow's unscaled size. Retain native font scaling and one-line width fitting, but bound fitting with `minimumFontScale >= 1 / max(fontScale, 1)`, keep label `flexShrink: 0`, and reserve vertical bar space for the token-sized icon slot plus the scaled eyebrow line height and existing spacing/insets. Labels retain full canonical children and colors. This NAVC-012 refinement follows actual 1.35-scale desk/trainer captures whose unconstrained native fitting reduced labels to micro-text; host tests verify the fit floor and allocated vertical space, while actual screenshots decide legibility.
- Label sizing reads the standard React Native `useWindowDimensions().fontScale` input. The existing icon slot is `currentStrokeWidth + spacing[0] + navigationSize + spacing[0]`. Above existing bottom padding (`insets.bottom + spacing[0]`), allocate at least that slot plus `eyebrow.lineHeight * max(fontScale, 1) + spacing[3]`; overall height also retains the existing `touch + spacing[3] + insets.bottom` minimum. No new palette, font or magic value is introduced.

## Risks / Trade-offs

- A saved owner switch requires a migration → test the isolated contract first, land through CI and generate types afterward; no hand-edited metadata or local schema apply.
- Current DB CI is slow and has baseline failures → build independent UI while it runs, record unrelated failures precisely and never claim full release green from local UI tests.
- First visual reference contains superseded bell/Freeze-Shop ideas → written accepted IA controls those placements; preserve its orange numeric emphasis and overall spacing.
- Missing native purchase creation → contextual Buy opens current request management truthfully; release readiness tracks D5 separately.

## Migration Plan

Commit frozen contract, then independently authored red tests, then the additive migration. Wait for previous DB workflow before another migration push. CI applies schema; use Supabase CLI on pecxrpskmfeuyzngvewq to regenerate types, then land typed clients/settings UI/native visibility. Never alter applied migrations, class booking logic or freeze hook. Forward-fix a defect; do not destructively roll back data. Device verify only in.fitcruxx.v2check and preserve the Play-signed pilot.
