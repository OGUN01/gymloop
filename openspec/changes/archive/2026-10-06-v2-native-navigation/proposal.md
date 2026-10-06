## Why

The physical Android review exposed undeclared Buy, Freeze and Training routes in the bottom bar, a reservation-first Shop and an oversized Home announcement feed. Owners also need an explicit Classes discovery setting that works for gyms, studios and academies with mixed activities.

The owner approved this behavior in the 2026-10-06 conversation, including the narrow Classes migration and implementation today. The visual bar is the first approved orange-number reference in docs/design/v2-nav-shop-home-orange-reference-2026-10-06.png, with the subsequently approved no-bell Home arrangement.

## What Changes

- Show Home, Classes, Shop, You, Activity when the tenant enables Classes; show four destinations otherwise. Hide all secondary routes explicitly. Keep the desk bar at five destinations.
- Persist a discovery-only Classes switch for owners/managers, with canonical actor checks and a compatibility backfill. Preserve existing bookings when the switch or branch access changes.
- Arrange Shop around Products, Plans and Services before purchase requests and reservations. Reveal three reservations initially and five more per explicit tap.
- Place one personal Messages for you preview near membership and two shared announcements below Last visit, with a separate View all destination. Retain the existing Chalkline palette and emphasize key numbers with its primary color.
- Add activity filters using existing service identities and retain personal training and My classes outside the bottom bar.

## Capabilities

### New Capabilities
- `native-member-discovery`: primary and secondary navigation, catalogue-first shopping, compact Home messages and announcements, and mixed-activity timetable presentation.
- `member-class-discovery`: tenant visibility setting and caller-owned upcoming commitments independent of catalogue branch eligibility.

### Modified Capabilities
- None. Existing identity, booking eligibility, class generation, payment and freeze contracts remain authoritative.

## Impact

Native member/desk navigation and presentation, the owner class-settings surface, one additive migration and CLI-generated database types after CI applies it. Tests precede implementation with independent visible and holdout authors for the privileged database boundary.

No payment creation, freeze submission, notification permission, invoicing, class credits, service entitlements or permanent course enrollment implementation belongs to this change. Those known release gaps are tracked separately. No Play upload or change to the Play-signed pilot is authorized.
