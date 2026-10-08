## Purpose

Let members browse their own reservation history through small database pages while keeping current holds accessible, existing app versions compatible and private data bound to the current caller.

## ADDED Requirements

### Requirement: SHP-PAGE-001 Verified member-only read

WHEN a caller requests a Shop reservation page THE SYSTEM SHALL verify the complete current member identity before reading, derive tenant/member from the verified caller, return only that member's rows, and refuse anonymous, staff, platform, preview, malformed, contradictory, inactive or foreign-bound identities without a write. Requests SHALL accept no caller-supplied tenant/member identity.

#### Scenario: Another member or tenant cannot be read
- **WHEN** a verified member requests a page while other members and tenants have reservations
- **THEN** only their own reservation facts are returned and supplying identity fields is refused

#### Scenario: Wrong audience and stale binding
- **WHEN** a staff, preview or no-longer-bound caller requests even a malformed page
- **THEN** authorization refuses before feature data is returned

### Requirement: SHP-PAGE-002 Bounded initial and continuation reads

WHEN Shop initially loads THE SYSTEM SHALL return all current open holds, bounded by the existing five-hold rule, and at most three history rows. WHEN a history cursor is continued THE SYSTEM SHALL return at most five history rows and SHALL NOT reread the catalogue. Each history query SHALL use only one extra lookahead row to establish continuation; the probe SHALL never enter the response. An unexpected active population above the existing bound SHALL refuse rather than silently conceal additional holds.

#### Scenario: Many historical reservations
- **WHEN** a member has more than fifty historical reservations
- **THEN** the initial history contains at most three rows, each continued history contains at most five, and explicit continuation can reach the entire history

#### Scenario: Five active holds and no history
- **WHEN** all five permitted holds are active and history is empty
- **THEN** all five active rows are available and continuation is absent

### Requirement: SHP-PAGE-003 Exact total-order cursor

WHEN history is read THE SYSTEM SHALL order it by created timestamp descending and reservation UUID descending, continue strictly below the last returned pair, preserve the original database timestamp precision, and expose continuation only when a further row exists. Active rows SHALL retain expiry ascending, then created timestamp descending and UUID descending. Refresh is required to see newly inserted rows above a previous cursor; pages do not promise a frozen multi-request transaction snapshot.

#### Scenario: Equal millisecond timestamps and equal timestamps
- **WHEN** rows differ only in microseconds or have identical timestamps with different UUIDs
- **THEN** traversal neither skips nor duplicates them and preserves the precise cursor timestamp

#### Scenario: Empty and final pages
- **WHEN** no row remains beyond the returned page
- **THEN** nextAfter is null, including a full final page, and no empty speculative page is required to discover completion

### Requirement: SHP-PAGE-004 Strict page request and safe response

WHEN a page request contains a partial/malformed/non-offset cursor, unknown property, identity selector or page-size override THE SYSTEM SHALL return a sanitized invalid-request envelope without calling the feature RPC. Valid cursors SHALL contain exactly a timezone-aware timestamp and UUID. Page responses SHALL use the existing typed no-store envelopes and reservation schema; invalid backend data SHALL fail rather than enter a member view. Raw database messages, storage metadata and secrets SHALL not be returned.

#### Scenario: Invalid cursor cannot silently restart append
- **WHEN** a continuation contains an impossible date, missing UUID or extra tenant field
- **THEN** the request is refused and never becomes page one

### Requirement: SHP-PAGE-005 Preserve existing reservation facts and commands

WHEN a page is projected THE SYSTEM SHALL preserve existing snapshot names/prices, exact integer-paise decimal-string totals/currency, current derived expiry, open-hold termsChanged, gym-only cancellation reasons, fulfilled-only order IDs and confirmed undeleted product image IDs. Page reads SHALL change no reservation, stock, order, payment, audit or receipt. Existing reservation/fulfilment/cancellation rules and table policies SHALL remain unchanged.

#### Scenario: Every state and exact money
- **WHEN** reserved, expired, collected and both cancellation outcomes are read, including amounts above JavaScript's safe integer range
- **THEN** the established facts and redactions remain exact and all business state remains unchanged

### Requirement: SHP-PAGE-006 Native three/five disclosure

WHEN the native Shop opens THE SYSTEM SHALL show at most three total reservation rows, active first, disclose the exact number of fetched active holds hidden by that preview, and keep cancellation accessible. WHEN Load more is explicitly tapped THE SYSTEM SHALL reveal up to five additional rows, fetching one bounded continuation if needed, preserving scroll position and synchronously rejecting repeated taps while a continuation is pending. Already loaded rows may satisfy a tap without a database request. End of history SHALL remove Load more once no cached rows remain hidden.

#### Scenario: Initial active and history population
- **WHEN** five active holds and more history are returned initially
- **THEN** only three total rows appear, two hidden active holds are disclosed, and Load more first reveals those holds without losing them

#### Scenario: A continued read fails
- **WHEN** loading more fails transiently or returns malformed data
- **THEN** current rows, reveal count and cursor remain unchanged and a retry action is available

### Requirement: SHP-PAGE-007 Caller and refresh lifetime

WHEN identity, API capability, refresh, successful/refused mutation refresh or unmount invalidates a continuation THE SYSTEM SHALL ignore its late result in both view and cache. Refresh SHALL replace the page population and reset the visible count to three. Reservation IDs SHALL remain unique when a previously active row is returned as history after expiry/cancellation; returned facts SHALL update that existing identity rather than append a duplicate. A continuation SHALL not make catalogue/mutation state more authoritative than a fresh read.

#### Scenario: Old request completes after refresh or caller replacement
- **WHEN** an old continuation settles after refresh, account/tenant/member change, API replacement or unmount
- **THEN** it updates neither the current screen nor cache and cannot release a newer request's busy guard

#### Scenario: Active row later appears in history
- **WHEN** an initially active reservation is returned as expired or cancelled on a later page
- **THEN** only one row with that reservation ID exists and the returned facts replace its previous facts

### Requirement: SHP-PAGE-008 Offline and authorization refusal

WHILE connectivity or a transient read fails THE SYSTEM SHALL retain labelled last-good scoped data and disable live reservation mutations until refresh succeeds. Cached hidden rows may be disclosed offline, but loading unavailable history SHALL preserve the cursor and offer retry. WHEN authorization refuses THE SYSTEM SHALL clear private view/cache and prevent restoration of that refused caller's cached data until a successful authorized read.

#### Scenario: Refusal followed by network failure
- **WHEN** a previously cached caller receives an authorization refusal and a subsequent read is offline
- **THEN** the refused private rows remain absent

### Requirement: SHP-PAGE-009 Released-client compatibility

WHEN a released client uses the existing no-argument reservation RPC or empty-body catalogue HTTP read THE SYSTEM SHALL retain their established response shape, fifty-row legacy cap and behavior. The existing empty member-cancel body SHALL stay strict. New pagination SHALL use a separate opt-in contract; web legacy consumers SHALL remain compatible.

#### Scenario: Old app and member cancellation
- **WHEN** a released app reads the old catalogue or sends the established empty cancellation body
- **THEN** the old contract remains valid and new paging fields are not accepted in cancellation
