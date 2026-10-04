# Native Firebase configuration mechanics — frozen 2026-10-04

This declaration completes the already approved Android registration and
NTF-003/016 native FCM path. It changes no audience, consent, identity, device
binding, notification evidence, category or money rule. Tests are independently
authored before the separate native builder changes configuration or source.

- **NFC-001.** The Android application retains package `in.fitcruxx.app`, EAS
  project `3708f347-96ac-4236-a74c-95808210292b` and scheme `fitcruxx`.
  `android.googleServicesFile` points to `./google-services.json` in
  `apps/mobile`. That public client file is an exact copy of the approved
  registration, SHA-256
  `44babffefef9ca11f0de585ec45b5ac1a1f7f80f63328efe1b4fbf9d68a4d10a`:
  Firebase project `samuraiapi-51996`, number `762123271201`, Android app
  `1:762123271201:android:35e9d8498bea4f64113760`. No private service-account
  credential, wakeup secret or server access key belongs in native config.
- **NFC-002.** Configure the installed `expo-notifications` plugin exactly
  once. Its Android default channel is `fitcruxx-updates`. The existing native
  FCM path remains `getDevicePushTokenAsync`; no Expo Push Service, iOS provider
  registration, extra runtime permission or unrelated build setting is added.
- **NFC-003.** On Android, the member's enable-notifications action first awaits
  creation of channel `fitcruxx-updates`, named `FitCruxx updates`, with the
  module's `AndroidImportance.DEFAULT`. Only after channel creation succeeds
  may that action request permission and acquire/register the native device
  token. Channel creation is required by Expo for Android 13 token/permission
  setup; it is not a request for consent or an automatic permission prompt.
  Rendering, settings reads and listener attachment do not create the channel
  or request permission. A rejected/missing channel API refuses registration
  with an actionable error and leaves the in-app inbox available. No token or
  registration API call follows that failure. Existing permission-denied,
  offline, sign-out and caller-scoped registration safeguards remain in force.
- **NFC-004.** Channel identifiers/display text live in the existing shared
  constants file, with registry entries; SDK importance uses its named enum,
  not an invented numeric constant. iOS/web previews do not create an Android
  channel or gain a push provider. Tests distinguish configuration/prebuild
  proof from actual provider acceptance and physical device receipt.

Official native setup reference:
[Expo notifications](https://docs.expo.dev/versions/latest/sdk/notifications/)
and [native FCM sending](https://docs.expo.dev/push-notifications/sending-notifications-custom/).
The implementation must preserve the owner's public client identity and the
existing lazy-module behavior. This declaration authorizes no phone use,
installation, credential widening or production activation.
