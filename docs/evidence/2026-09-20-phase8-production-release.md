# Phase 8 production release evidence — 2026-09-20

This record separates deployed/signed evidence from actions that still require a
real external owner. It contains environment-variable names only; no credential
values, keystore material or account secrets are recorded.

## Production web/API

- Vercel account/project: `ogun01s-projects/gymloop`
  (`prj_mteQVcRk0VT6NMeVA3HLmBjPZEAs`).
- Ready production deployment: `dpl_3NsE8maReu8xMMY4qorE3KPyYTz8`.
- Stable public alias: `https://gymloop-phi.vercel.app`.
- Build root/framework: `apps/web`, Next.js; function region: `bom1`
  (Mumbai, aligned with the Supabase `ap-south-1` region).
- Production environment names present:
  `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_ANON_KEY`. No service-role
  key or database password was added to Vercel.
- A production `GET /sign-in` returned HTTP 200 and the expected Gymloop title.

The production-targeted Phase 8 Playwright run initially produced two passes and
one member-role timeout while the deployment was cold. A narrow rerun of that
failed role-landing case passed for member, front desk and owner. The existing
Light/Dark accessibility cases remained green. No production mutation was
performed, and this smoke does not replace the mutation-complete A–D journeys or
the distinct-second-gym fixture required by HARD-003.

## Android production bundle

- EAS project: `@harsh9887/gymloop`
  (`3708f347-96ac-4236-a74c-95808210292b`).
- Production environment names present: `EXPO_PUBLIC_API_BASE_URL`,
  `EXPO_PUBLIC_SUPABASE_URL`, and `EXPO_PUBLIC_SUPABASE_ANON_KEY`; the API base
  resolves to the stable HTTPS production alias above. No service-role key was
  supplied to the app.
- Final build id: `2c0c4e0c-317d-4912-b50a-1f361d979b85`; profile
  `production`; distribution `STORE`; SDK `57.0.0`; package
  `in.gymloop.mobile`; source commit
  `2252bdc463371f00b2effaa1a210fdb8de03de0e`; version `1.0.0` (`1`).
- Completed UTC: `2026-09-20T14:09:13.634Z`.
- Local artifact: `dist/releases/gymloop-1.0.0-1-production.aab`
  (`93,166,619` bytes).
- AAB SHA-256: `42F3F9A1391E9CE63F18C3C6B07143EB83838EE4685EED929F6D40C79EB3474C`.
- Signing certificate SHA-256:
  `AA:92:3C:58:3E:2A:9D:E0:B2:54:46:DA:19:17:E6:40:19:8E:66:46:87:EE:DF:2B:38:75:0D:B1:33:33:C8:63`; signature
  `SHA256withRSA`, 2048-bit RSA, valid through 2054-02-05.
- Bundletool `1.18.3` validation exited successfully. Its merged-manifest
  inspection found camera, internet, vibration, network/Wi-Fi state,
  biometric/fingerprint and the app-scoped dynamic-receiver permission.
  `android.permission.CAMERA` is present;
  `RECORD_AUDIO`, `SYSTEM_ALERT_WINDOW`, `READ_EXTERNAL_STORAGE`, and
  `WRITE_EXTERNAL_STORAGE` are absent.
- `keytool` recovered the certificate above and `jarsigner` returned
  `jar verified`; the upload certificate is self-signed and has no timestamp,
  while bundletool independently accepted the AAB structure.

The first signed candidate (`1ab7836a-2ea2-4133-913c-ec1088c4c6ea`) was
rejected after merged-manifest inspection exposed overlay and legacy-storage
permissions contributed by dependencies. The independent visible contract was
corrected in `94f058fae5cc09428164b860056a0d45e6e5e352`; the implementation in
`2252bdc463371f00b2effaa1a210fdb8de03de0e` explicitly blocks those permissions
and sets the first public version. The focused HARD-002 suite passed 4/4 and the
mobile typecheck passed before the final build. Post-push CI, holdout and test
immutability all passed; the main CI run id was `35515082305`.

## Device and store boundary

The connected OnePlus DN2101 (Android 13) still carries the Phase 7 debug build
and its recorded product-behaviour evidence. The exact production AAB was not
installed by uninstalling that app because doing so would erase user device data;
an AAB also cannot be installed directly. Exact-artifact smoke therefore remains
external until a Play internal-track install, or an explicitly authorized
bundletool-derived APK-set install, is available. No Play upload, review or
publication is claimed.

## External items still open

- mutation-complete browser journeys and load execution against a separately
  provisioned non-production Supabase project and second tenant;
- a real monitoring/alert destination and receipt;
- qualified DPDP/DPA decisions and destructive data-lifecycle implementation;
- a disposable-target Supabase backup/PITR restore drill;
- Google Play developer-account access, internal-track upload/install, policy
  declarations, review and publication;
- Razorpay provider-signed payload evidence and Cloudflare edge
  rate-limit/Turnstile proof.
