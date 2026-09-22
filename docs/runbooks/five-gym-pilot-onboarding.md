# Five-gym controlled-pilot onboarding

This is the operating checklist for the first five **real** gyms on the one
Gymloop Supabase project. It does not create customers by itself and must not
be used to turn a synthetic database rehearsal into a customer-launch claim.
Online gateway charging is disabled: gyms collect money outside Gymloop and
record the payment and receipt through the authenticated staff UI.

## Release stop line

Before inviting the first gym, the production owner checks the current Phase 8
ledger against `PILOT-002` through `PILOT-004` and the frozen HARD gates. In
particular: the rotated database credential and GitHub secret must authenticate
and DB CI must be green; privacy export/erasure and legal/DPA review, recoverable
backup/restore, delivered alert route, core-loop two-gym acceptance, final
Android artifact and owner visual acceptance must have actual evidence. A
rollback SQL test, local mock, preview APK or policy draft does not pass these.
If any gate is red, continue internal preparation but do not invite a gym.

## Protected intake, one gym at a time

Keep real names, emails, phone numbers, commercial terms and agreements in a
restricted pilot roster, not this public repository or a test fixture. For each
gym, record its authorized contact, legal/display name, city/timezone, one
default branch name, selected registered settings preset, exact owner Google
account email, consent/DPA decision and support contact route. Do not request
the owner's Google password or a service-role key. Confirm INR and that the
owner understands the manual-payment-only scope and service/marketing consent
split.

1. The authorized owner signs in through Gymloop Google Auth with the exact
   intended email. Verify that account independently before linking; an email
   typed on the platform form is not an invitation or identity proof.
2. A non-preview `super_admin` creates the gym in `/platform` with a fresh
   request key. Record the returned tenant id/code privately. Confirm one
   settings row, one default branch, one unlinked active owner profile and one
   zero-credit wallet. Retry the **same** request only with identical facts;
   never submit a changed gym under the old key.
3. Link that exact existing Auth account to the gym's owner profile through the
   platform detail page. Check the audit event and make the owner refresh/sign
   in again; an old token is not evidence of the new claim. The owner confirms
   only the intended gym name/code, member roster and dashboard are visible.
4. Review readiness on the platform detail page. Activate manually only when
   settings, default branch, linked non-platform owner, timezone and INR are
   ready. A trial has a gym-local expiry; do not leave an expired trial as a
   workaround for failed activation. Tier is a label, not a charge or cap.
5. Provision only the staff roles actually needed and verify a fresh front-desk
   session can use check-in and member search but cannot enter platform or
   owner-only commercial controls. A member signs in to their own gym only.

## First working-day acceptance

With the gym's permission and clearly identified pilot data, perform and log
one legitimate check-in, one follow-up/return path, one externally collected
manual payment with exact paise/currency/receipt/renewal, and one add-on
sale/fulfilment. Confirm the member sees their own attendance, membership,
receipt, messages/consent and add-on history; confirm the owner dashboard uses
the same tenant's facts. Test the second gym's authenticated session against
known *synthetic* foreign IDs: member/payment/add-on/message/metrics reads and
mutations must be refused with zero foreign side effects. Do not use another
real customer's private record as a probe. Record exact request/event IDs and
the refusal outcome in restricted evidence; never delete audit or paid rows to
make a test look clean.

Repeat the intake and first-day checks for each of the five gyms. After each,
record the deployment version, tenant id/code, owner-link/activation audit
references, role sessions, core-loop receipts/events, cross-tenant refusals,
alert acknowledgement, backup recovery point, and unresolved issues in the
protected pilot roster. The public ledger may contain redacted references and
verdicts, not member PII. Pause further onboarding on any cross-tenant leak,
money inconsistency, unavailable check-in, unowned incident route or failed
backup/alert. Suspension and session revocation are the containment path;
resetting the shared database is not.

## Capacity and exit

Watch active connections, database/storage size, API/check-in latency, failed
requests, alert delivery and support load during this controlled cohort. Five
working gyms and a 5 × 50 rollback rehearsal are not a measured 100 × 500
morning spike. Escalate measured limits and upgrade capacity before expanding
the cohort; a paid plan cannot fix an identity, RLS, money or recovery defect.
