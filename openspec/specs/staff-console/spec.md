## Purpose

The first screens: a staff member signs in with email and password, and sees the members of their own gym. This is the slice that makes Phase 2's identity layer observable — until now every claim has been set by hand in a pgTAP fixture and no real token has ever been issued.

## Requirements

### Requirement: Only a signed-in staff session reaches the console
THE SYSTEM SHALL redirect an unauthenticated visitor from every console route to the sign-in page, and SHALL NOT render any console content before the session is established.

#### Scenario: An unauthenticated visitor
- **WHEN** a visitor with no session requests a console route
- **THEN** they SHALL be redirected to the sign-in page

#### Scenario: A signed-in visitor on the sign-in page
- **WHEN** a visitor with a valid session requests the sign-in page
- **THEN** they SHALL be redirected to the console

### Requirement: Sign-in is by email and password, and there is no self-signup
THE SYSTEM SHALL authenticate a staff member by email and password. It SHALL NOT offer a route by which a visitor creates their own account — gym accounts are created by the gym, and platform accounts by an existing super admin.

#### Scenario: Correct credentials
- **WHEN** a staff member submits an email and password matching an active identity
- **THEN** a session SHALL be established and they SHALL land on the console

#### Scenario: Wrong credentials
- **WHEN** the password does not match
- **THEN** an error SHALL be shown, no session SHALL be established, and the message SHALL NOT reveal whether the email exists

### Requirement: A session with no Gymloop identity is told so, not broken
A signed-in `auth.users` row that no gym has linked receives a token with no `app_role` claim — a supported state (`openspec/specs/identity/`). THE SYSTEM SHALL show such a session a page saying the account is not linked to a gym, and SHALL NOT show an empty member list, an error page, or a crash.

#### Scenario: A linked-to-nothing account signs in
- **WHEN** a session whose token carries no `app_role` reaches the console
- **THEN** a page SHALL explain the account is not yet linked to a gym

### Requirement: The member list is filtered by the database, never by the application
THE SYSTEM SHALL read members through the caller's own session so that Row-Level Security performs the filtering, and SHALL NOT add a tenant predicate of its own. An application-side tenant filter would mask exactly the defect the pgTAP suite exists to catch.

#### Scenario: A gym's staff sees its own members
- **WHEN** a staff session lists members and the database holds members of two gyms
- **THEN** only their own gym's members SHALL be shown

#### Scenario: The query carries no tenant of its own
- **WHEN** the member-list query is inspected
- **THEN** it SHALL contain no `tenant_id` filter, that being the policy's job

### Requirement: A member is findable by phone
THE SYSTEM SHALL let staff find a member by phone number, which is how a front desk identifies someone standing in front of them.

#### Scenario: Searching by a full phone number
- **WHEN** staff search for a member's phone number
- **THEN** that member SHALL be listed

#### Scenario: Searching for a member of another gym
- **WHEN** staff search for the phone number of a member of a different gym
- **THEN** no member SHALL be listed

### Requirement: Signing out ends the session
THE SYSTEM SHALL provide a sign-out that clears the session, after which console routes redirect to sign-in again.

#### Scenario: Signing out
- **WHEN** a signed-in staff member signs out and then requests a console route
- **THEN** they SHALL be redirected to the sign-in page

### Requirement: Every endpoint validates its request through a declared schema
THE SYSTEM SHALL validate each Route Handler's request against a zod schema before it reaches the database (gate 12), and SHALL answer a request it cannot read with the typed failure envelope rather than with a 500.

**The two failures are different and answer differently, and this is the part a brief written from the gate alone gets wrong.** These handlers are reached by a native `<form method="post">`, not by `fetch`:

- **A body that is not a form at all** — nothing readable in it, no member id, no screen to go back to. This answers with the envelope, `ok: false`, a `bad_request` status. Two handlers used to call `await request.formData()` unguarded, so this case was a 500 for a request that was merely wrong.
- **A form whose fields are wrong** — a missing plan, a reversed date range, a blank reason. This answers **303 back to the form**, never JSON. A form POST that returns `{"ok":false}` leaves the person at the front desk looking at raw JSON with no way back.

**How that 303 carries the error differs between the two forms, and the difference is deliberate.** The membership and pause forms put a short stable code in the query string (`?error=dates_reversed`) — a code and not a sentence, because the screen owns the wording and a message in the URL would let anyone hand a member of staff a link displaying whatever they like. The member form does **not**: it redirects with a one-shot `HttpOnly` echo cookie instead, because a rejected member submission has to come back with every value that was typed, and a native `<form>` has no state of its own. Those values are a person's phone number, email and date of birth, and a query string is written into the server's access log, the browser's history, and the `Referer` of everything the page then loads. DPDP is exactly about that. So: the two-field forms use the URL, the form carrying personal data uses the cookie, and a test asserting one shape against the other endpoint is asserting the wrong thing.

In the membership and pause schemas, ids are validated as uuids because that is what the columns are, and a calendar day is validated by round-tripping it rather than by regex alone, so `2026-02-31` and `2026-13-01` are both refused — the first parses as 3 March, and the second makes an Invalid Date whose `toISOString()` throws.

**The member form validates less on purpose, and the line is worth stating so nobody "fixes" it.** It checks the two columns that are `not null` and the one field that is an enum — a name, a branch, and a status read from the generated `member_status` vocabulary, never a hand-written list. It does **not** re-check the phone format, because `members_phone_format_chk` is the rule and `refusalMessage()` turns that refusal into the best sentence on the screen; a copy here would be a second phone rule to keep in step, and it would be the copy that goes stale. The general form: **validate what makes the request readable, and leave what makes it correct to the constraint that cannot be bypassed.** Where a schema and a constraint say the same thing, the schema exists to give a better message, not to be the enforcement.

#### Scenario: A body that is not a form
- **WHEN** a request arrives whose body cannot be read as a form
- **THEN** the response SHALL be a `bad_request` failure in the envelope, and SHALL NOT be a 500

#### Scenario: A membership or pause field that is wrong
- **WHEN** a submission names no plan, or reverses a date range, or gives a blank reason
- **THEN** the response SHALL be a 303 back to the member's screen carrying a stable error code in the query string, and no row SHALL be written

#### Scenario: A member field that is wrong
- **WHEN** a member submission gives no name, or no branch, or a status outside the enum
- **THEN** the response SHALL be a 303 back to the member form carrying the message and every submitted value in a one-shot `HttpOnly` cookie — never in the query string, because those values are personal data and a URL is written into logs, history and `Referer`

#### Scenario: A form that names no member at all
- **WHEN** a submission carries no usable member id
- **THEN** the response SHALL be a `bad_request` failure in the envelope — there is no screen to redirect to without one

#### Scenario: A date that is not a calendar day
- **WHEN** a submission carries `2026-02-31` or `2026-13-01` as a date
- **THEN** it SHALL be refused, and SHALL NOT be silently rolled forward into March or throw

### Requirement: The member list is bounded
THE SYSTEM SHALL return a bounded page of members with a documented default and maximum, and SHALL give the caller what it needs to ask for the next page (gate 26). A gym with four thousand members otherwise renders four thousand rows into a page a front desk reads three of.

#### Scenario: The default page
- **WHEN** the member list is read with no page size given
- **THEN** at most the default number of members SHALL be returned

#### Scenario: Asking for more than the maximum
- **WHEN** a caller asks for a page larger than the maximum
- **THEN** the maximum SHALL be returned — clamped, not refused, because a page size is a hint and not an instruction

#### Scenario: Asking for the next page
- **WHEN** more members exist than one page holds
- **THEN** the result SHALL carry what is needed to request the next page, and SHALL NOT carry it when the list is exhausted

#### Scenario: Everything that shaped the page travels with the cursor
- **WHEN** a page reached by a cursor was reached from a search or a non-default page size
- **THEN** that search and that page size SHALL still apply — a cursor names a place in an ordering, and a page reaching it with different parameters is looking at a different ordering

### Requirement: A cursor is validated, not merely decoded
THE SYSTEM SHALL check that a decoded cursor's parts are what they claim to be before any of them reaches a query, and SHALL answer an unusable cursor with the first page rather than with an error.

**Encoding is not validation and base64 is not a signature.** A cursor arrives in a query string; a caller can write whatever they like into one. The member cursor carries a name and an id, and both are interpolated into a PostgREST filter — where `,` `.` `(` `)` are grammar, so an unescaped value is not a value but a clause. A crafted cursor therefore appended its own `WHERE` fragment and returned rows the keyset had excluded. It crossed no tenant boundary — row security still filtered, and the caller was already staff of that gym — but *an attacker-controlled filter fragment reaching the database from a query string* is the shape, not the blast radius, and this codebase's whole argument is that the endpoint is not the boundary. An id that is a uuid must be checked to be one; a name must be quoted as `fullName` already is.

The same check answers the second half: an id of `"x"` decodes, passes a `typeof` guard, and reaches Postgres as `22P02 invalid input syntax for type uuid`, whose message the screen renders verbatim.

#### Scenario: A crafted cursor carrying filter syntax
- **WHEN** a cursor is supplied whose parts contain PostgREST filter grammar
- **THEN** it SHALL NOT alter which rows the query selects

#### Scenario: A cursor that decodes to nonsense
- **WHEN** a cursor decodes successfully but its id is not a uuid
- **THEN** the first page SHALL be shown, and no database error message SHALL be rendered

### Requirement: A form post returns the front desk to the screen it came from
WHEN a console form post succeeds or is refused, THE SYSTEM SHALL return the
caller to the screen that submitted it, carrying any short error code, and SHALL
NOT land them somewhere that cannot act on the answer.

The payments handler answered **every** outcome — success and refusal alike —
with a redirect to the general ledger, which is not where the form was. A front
desk that mistyped an amount got an accurate, actionable message on a page with
no link back to the member: click Members, find the person again, retype
everything. `/api/memberships` had already built `backToMember()` for exactly
this reason, and `memberId` was in scope in every failing branch.

**It also fed the defect below.** A front desk that cannot get back by clicking
gets back by pressing Back, and Back restores a page whose idempotency nonce has
already been spent.

#### Scenario: An amount that will not parse
- **WHEN** a payment is refused for an unreadable amount
- **THEN** the front desk SHALL be returned to that member's page with the message, ready to retype it

#### Scenario: A payment recorded
- **WHEN** a payment succeeds
- **THEN** the front desk SHALL be returned to that member's page, whose next render mints a fresh idempotency nonce

### Requirement: A duplicate submission is a question, not a silent success
WHEN a payment collides with an existing one on the idempotency key, THE SYSTEM
SHALL say so and SHALL NOT report success without a message.

**A nonce identifies a page render, and one render can legitimately produce two
different payments.** Round one keyed on the nonce alone, so a Back-and-edit was
silently dropped. Round two folded the member, the amount in paise and the
method into the key — which fixed Back-and-edit and left Back-and-**repeat**
exactly as broken: a front desk taking ₹1,500 from one member twice, arrears and
this month, presses Back and submits the identical form, the key matches, and
the second payment is discarded with no error shown at all.

That is the same silent money loss the composition was written to stop, moved
one step sideways, and it is worse than what it replaced because it produces no
code at all rather than a wrong one. **The conflation is "identical values" with
"identical transaction", and no key computed from the form can tell those
apart** — so the system must stop trying to and ask.

#### Scenario: The same form submitted twice by a double click
- **WHEN** an identical submission arrives twice
- **THEN** exactly one payment SHALL exist, and the front desk SHALL be told a matching payment was just recorded rather than shown a bare success

#### Scenario: A second, genuinely separate payment of the same amount
- **WHEN** a front desk records a second payment identical in member, amount and method to one just taken
- **THEN** they SHALL be told a matching payment already exists and SHALL be able to record it anyway from a freshly rendered page

### Requirement: A screen calls a membership live on the same terms the gate does
THE SYSTEM SHALL determine whether a membership is live from its status **and its
dates in the gym's own day**, in every screen that says so, and never from the
status column alone.

The member's page read `status in ('active','frozen')` and nothing else, so a
membership two months lapsed was displayed as **active** at the same moment
`app.enforce_check_in()` refused its member at the gate (ADR-084). A front desk
reading that screen has every reason to believe the member is covered, and to
dispute the refusal.

This is the same defect as ADR-084's, one layer up: a status column nothing ever
writes `expired` into, trusted to mean something it cannot.

#### Scenario: A membership whose end date has passed
- **WHEN** a member's page shows a membership whose `ends_on` is before the gym's today
- **THEN** it SHALL be presented as lapsed, and the page SHALL NOT describe it as live

### Requirement: A receipt without a number says why
WHEN a payment carries no receipt number, THE SYSTEM SHALL explain it, whatever
the payment's status.

The receipt page explained a missing number only for a payment that was not
`paid`, so a `paid` payment predating the numbering rule rendered "not issued"
with no explanation — a document that looks wrong and says nothing.

#### Scenario: A paid payment with no receipt number
- **WHEN** a receipt is opened for a paid payment that was never numbered
- **THEN** the page SHALL say so plainly rather than leaving the field bare

### Requirement: A refund is recorded from the receipt it refunds
THE SYSTEM SHALL let a gym owner or manager record a refund against a payment,
from that payment's own receipt, and SHALL show every refund already recorded
against it there.

Phase 5 enforced the whole of PAY-010 in the database — a refund is a new row,
never a mutation; it may not exceed what was paid, on insert or on update; its
amount and payment freeze once recorded; and it names the staff member who sent
the money. **None of it was reachable through the product**, which a critic
noted plainly: a gym could not refund a payment at all. A rule with no path to
it is a rule nobody can obey or break.

The receipt is where it belongs. It is the document the conversation is about,
it already names the payment, the member and the amount, and putting the control
anywhere else would mean re-finding all three.

**Narrower than taking money, deliberately.** `refunds_tenant_write` gates on
`is_gym_admin()` — owner or manager — where `payments_tenant_write` gates on
`is_front_office()`. A front desk may take money and may not send it back. The
screen does not re-implement that; the policy refuses and the screen reports it.

#### Scenario: A manager refunds part of a payment
- **WHEN** a gym manager records a refund below the payment's amount
- **THEN** it SHALL be recorded, the payment's own row SHALL be unchanged, and both SHALL be visible on the receipt

#### Scenario: A refund that would exceed the payment
- **WHEN** a refund is recorded that would take the total refunded past the amount paid
- **THEN** it SHALL be refused and the front desk SHALL be told how much is left to refund

#### Scenario: A front desk attempting a refund
- **WHEN** a front-desk session records a refund
- **THEN** the policy SHALL refuse it, and the screen SHALL say the role may not refund rather than reporting a failure it cannot explain

#### Scenario: A fully refunded payment
- **WHEN** a payment has been refunded in full
- **THEN** the receipt SHALL say so and SHALL NOT offer a control that can only be refused
