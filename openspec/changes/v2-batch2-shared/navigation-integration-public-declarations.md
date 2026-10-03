# Batch-2 console navigation and privacy integration

Frozen delegated engineering composition, 2026-10-03. The original CLS scope
requires a desk Classes tab and CLS-Q6's roster tap budget; original ANC requires
front-office/support-preview console surfaces and its supplied privacy sentence.
This packet specifies placement, not a new actor or access grant.

- Web console adds Classes immediately after Check-in for its four existing
  staff roles and read-only support preview. The label is humanize(nouns.classes).
- Announcements appears for front office (owner, manager, front desk) and
  read-only support preview; it stays absent for trainer. Preview access remains
  the existing approved definer reads, with no platform table policy or writes.
- The existing ConsoleNavigation component owns active-route indication for
  these new destinations exactly as for its existing destinations.
- Native RoleTabs({desk:true}) composes Check-in, Classes, Members, Follow-ups,
  More. Existing four desk destinations retain their relative order. Classes
  uses the vertical noun (Batches for dance). Remove the duplicate hidden desk
  Classes registration; the existing route supplies the screen and permissions.
- RoleTabs({desk:false}) retains exactly Home, Classes, Shop, Activity, You,
  with Gym hidden from the primary bar. No member/desk route is reclassified.
- Public Privacy renders the exact registered ANNOUNCEMENT_PRIVACY_SENTENCE
  supplied by the original ANC legal-integrator contract. No new legal promise.

Declarations: apps/mobile/components/role-tabs.tsx exports
RoleTabs({desk?:boolean}): React.JSX.Element. It reads the registered useMobile
and useBusinessNouns host, and uses Tabs.Screen names/options from Expo Router.
Web ConsoleLayout({children:ReactNode}) is the existing default async server
layout, using requireAudience('console'), loadBusinessOrganization and the
existing AccountFrame/ConsoleNavigation/PreviewProvider. Privacy is its existing
default server page. Tests may mock these caller/platform hosts; actual layout,
navigation and privacy under test remain real. Rendered checks are not device
acceptance or a test of permissions in the database.

Independent visible integration regressions precede the source. The earlier
four-desk-destination preservation oracle is superseded only by this specified
Classes insertion; member-five-tab and all other original assertions remain.
Root updates registry/docs and runs full final web/native acceptance.

Owner-approved neutral-privacy-copy-amendment.md (2026-10-03) replaces only the registered disclosure's venue wording with 'The business', retaining verbatim rendering and every privacy rule.
