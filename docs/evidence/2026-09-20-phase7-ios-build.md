# Phase 7 iOS cloud-build evidence — 2026-09-20

## Result

Gymloop's committed Expo SDK 57 sources compiled successfully on EAS Build's
macOS infrastructure without local Apple tooling or signing credentials.

- EAS project: `@harsh9887/gymloop` (`3708f347-96ac-4236-a74c-95808210292b`)
- Build: [`22ede637-bdad-428b-b091-ceda282e7fa5`](https://expo.dev/accounts/harsh9887/projects/gymloop/builds/22ede637-bdad-428b-b091-ceda282e7fa5)
- Source commit: `2f87addaaedf3da5b8bd9e10053596211b4113c8`
- Platform / SDK: iOS Simulator / Expo SDK 57
- Status: `FINISHED` at `2026-09-20T08:34:01Z`
- Fingerprint: `862b73a1af02373782749315db46e38aa636506f`

The `simulator` profile uses `ios.simulator: true` and
`withoutCredentials: true`. The required public mobile configuration was read
from EAS's `development` environment; no service-role credential was uploaded.

## Honest boundary

This proves the native iOS project compiles. It is not an iPhone-installable
IPA and no iOS runtime journey is claimed. Apple requires signing credentials
from an active Apple Developer Program team for EAS physical-device builds.
The App Store Expo Go client is not a fallback for this project because current
Expo Go on physical iOS does not support SDK 57. The owner has an iPhone but no
paid Apple Developer membership, so signed-device installation remains an
external access blocker rather than an implementation failure.

The Android physical-device journeys and accessibility evidence remain valid.
The mobile change stays open until the physical-iOS/signing boundary, real QR
airplane/reconnect journey and second-association product decision are resolved.

Official references:

- <https://docs.expo.dev/build-reference/simulators/>
- <https://docs.expo.dev/build/internal-distribution/>
- <https://docs.expo.dev/troubleshooting/expo-go-version-mismatch/>
