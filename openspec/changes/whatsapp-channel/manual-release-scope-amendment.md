# WSP manual release scope — owner directed, frozen 2026-10-04

The owner explicitly directs: “We will not use WhatsApp API. User can manually
link their WhatsApp.” This supersedes automated Meta/WABA setup and live
provider activation for the v2 release. It does not reverse approved money
conversion, alter existing balances, delete history or claim that the former
automated WSP bar has been met.

## Release contract

- **WSP-M01.** WHEN authorized staff chooses the existing manual WhatsApp
  action THE SYSTEM SHALL reuse the registered `open_notification_whatsapp`
  command and its prefilled WhatsApp link. The user's installed WhatsApp or
  WhatsApp Web handles the conversation; the user presses Send there. No
  linked-account session, QR account synchronization or automated send is
  introduced.
- **WSP-M02.** WHEN preparing that handoff THE SYSTEM SHALL preserve current
  tenant/role checks, recipient and guardian resolution, applicable consent,
  opt-out and erased/blocked-recipient refusals. A manual handoff SHALL NOT
  disclose a different member's contact or bypass those safeguards.
- **WSP-M03.** WHEN a handoff succeeds THE SYSTEM SHALL record only the
  existing factual opening event. Opening SHALL NOT mark a message sent,
  delivered or read, charge or reserve wallet money, or imply that the user
  pressed Send. Failures SHALL retain honest retry/refusal copy.
- **WSP-M04.** WHILE this release uses manual WhatsApp THE SYSTEM SHALL keep
  paid dispatch and provider activation disabled: no enabled sender, Meta
  credentials, provider adapter, provider callback exposure, automated
  WhatsApp job or live paid-send requirement. A retained dormant transport
  model SHALL remain fail-closed and retain its money/security invariants.
- **WSP-M05.** WHEN presenting release capabilities THE SYSTEM SHALL describe
  WhatsApp as a manual handoff. Automated delivery/read tracking and paid
  messaging are deferred. Existing versioned consent controls and withdrawal
  safeguards remain; no inferred consent is introduced.

## Verification and remaining boundaries

Independent visible and holdout authors verify manual opening versus sending,
authorization, guardian/consent refusal and zero wallet movement. Existing
automated transport suites are not deleted or weakened: retained dormant
code must still pass its applicable invariants. A separate implementer and
fresh critic follow tests first. Meta/WABA credentials and their provider
activation paperwork are no longer prerequisites for this manual release.
Existing general privacy/legal gates remain. Firebase Android push is a
separate approved workstream, owned by `sharmaharsh9887@gmail.com`.
