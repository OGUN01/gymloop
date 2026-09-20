# Android production release

This runbook covers HARD-002 and HARD-008. It separates repository readiness,
a production-signed AAB, physical-device smoke evidence and Play publication;
none implies the next.

## Repository preflight

1. Start from the intended clean commit and record its full SHA.
2. Verify `apps/mobile/eas.json` uses the `production` profile with
   `android.buildType: "app-bundle"`. Production must not use internal
   distribution or `withoutCredentials`.
3. Verify `apps/mobile/app.json` requests Android camera permission, configures
   Expo Camera with `recordAudioAndroid: false`, and does not request
   `android.permission.RECORD_AUDIO`.
4. Verify the release environment supplies only public mobile configuration and
   an HTTPS production API base. A service-role key, localhost, USB-reversed
   loopback or cleartext transport is a release blocker.
5. Run the focused Android release-configuration test and mobile package tests;
   record the exact commands, UTC time, commit and complete result in the Phase
   8 ledger. Do not rerun a passing suite unless relevant code changed.

The configuration/test commits are `cdd99fb` and `674255e`. They prove a
reviewable app-bundle/least-permission configuration, not signing or upload.

## Build and artifact evidence

With an authorized production signing owner present:

1. Authenticate EAS under the intended Gymloop project and verify the displayed
   owner/project id before starting work.
2. Run `eas build --platform android --profile production` from the recorded
   commit. Use managed EAS credentials or an owner-supplied production keystore;
   do not generate an unrecorded substitute merely to turn the step green.
3. Record the EAS build id, profile, Expo/React Native versions, source commit,
   signing-key certificate fingerprint and downloadable `.aab` artifact path.
4. Compute and record the AAB SHA-256 (`Get-FileHash -Algorithm SHA256` on
   Windows or `sha256sum` on Unix). A filename without a digest is insufficient.
5. Inspect the built artifact/manifest and attach the permission list, proving
   camera is present and audio recording is absent.

If the signing credential is unavailable, stop at **External — signing owner
action required**. An unsigned bundle or debug APK is not a production AAB.

## Physical-device smoke checklist

Install from a Play internal track, or install an APK set derived from the exact
signed AAB with a recorded tool/version. Record device manufacturer/model,
Android version, app version/build id, artifact SHA-256, install path and tester
role. On a physical Android device verify:

- clean install and cold startup use HTTPS and show the English sign-in screen;
- member authentication shows only Home, Activity, My gym and You;
- front-desk authentication shows only Check-in, Members, Follow-ups and More;
- each role is denied the other role's routes/data, and sign-out clears session
  plus queued commands;
- a live QR check-in confirms exactly once;
- airplane-mode QR capture says saved on this device/awaiting confirmation,
  survives force-stop/cold restart, replays once on reconnect and does not
  duplicate after another restart;
- Light, Dark and System modes remain complete;
- device-maximum text and Remove animations preserve all actions;
- camera denial has an actionable state and the app never requests microphone;
- one final restart has no crash, red screen or unexpected permission prompt.

For every step record UTC time, audience/test account label (not credentials),
gym/tenant label, expected result, observed result and screenshot/video/log
artifact. Restore device settings and airplane mode and record cleanup.

The Phase 7 OnePlus DN2101 debug evidence at
`docs/evidence/2026-09-20-phase7-android-device.md` is a valid product-behavior
baseline. It is not a production-signed AAB smoke result.

## Play release boundary

Keystore/EAS production signing, Google Play developer-account access, Play App
Signing enrollment, internal-track upload, policy/data-safety declarations,
review and publication are external actions. Owner: Android release owner with
the Play account holder. Evidence required: signing certificate fingerprint,
AAB SHA-256, EAS build id, Play artifact/version id, internal-track install
record, physical-device checklist and console review/publication status. Never
record upload or publication from a local build alone.
