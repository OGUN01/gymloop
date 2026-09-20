# Phase 8 production release evidence — 2026-09-20

This record separates deployed/signed evidence from actions that still require a
real external owner. It contains environment-variable names only; no credential
values, keystore material or account secrets are recorded.

## Production web/API

- Vercel account/project: `ogun01s-projects/gymloop`
  (`prj_mteQVcRk0VT6NMeVA3HLmBjPZEAs`).
- Ready production deployment: `9h745WmLGeD3YeMBtMkgCrb54qdm`, source commit
  `5e4b534207d826e57adcc9267ac26732f228e055`.
- Stable public alias: `https://gymloop-phi.vercel.app`.
- Git deployment source: `OGUN01/gymloop`, connected to the Vercel project.
- Build root/framework: `apps/web`, Next.js; function region: `bom1`
  (Mumbai, aligned with the Supabase `ap-south-1` region).
- Production environment names present: `NEXT_PUBLIC_SUPABASE_URL`,
  `NEXT_PUBLIC_SUPABASE_ANON_KEY`, and
  `WEB_APP_URL=https://gymloop-phi.vercel.app`. No service-role key, Google
  client secret or database password was added to Vercel.
- A production `GET /sign-in` returned HTTP 200 and exposed both `Continue with
  Google` and `Use email instead`.

The production-targeted Phase 8 Playwright run initially produced two passes and
one member-role timeout while the deployment was cold. A narrow rerun of that
failed role-landing case passed for member, front desk and owner. The existing
Light/Dark accessibility cases remained green. No production mutation was
performed, and this smoke does not replace the mutation-complete A–D journeys or
the distinct-second-gym fixture required by HARD-003.

## Production Google authentication

- Google Cloud project: `gymloop-auth-prod-2026`; OAuth web client:
  `Gymloop Supabase production`; registered Google redirect:
  `https://pecxrpskmfeuyzngvewq.supabase.co/auth/v1/callback`.
- GitHub auth-configuration workflow `35533772247` completed successfully from
  `6d30ce5`. Its narrow Management API PATCH returned HTTP 200 and reported the
  access-token hook enabled at
  `pg-functions://postgres/app/custom_access_token_hook`, JWT expiry `900`, site
  URL `https://gymloop-phi.vercel.app`, the exact production/local/mobile
  callback allow-list, Google enabled, and client-id/secret presence booleans.
  No credential value was printed or recorded.
- A public Auth settings check reported Google and email enabled.
- The first live click reached the generic failure state because the OAuth
  action used the broad `serverEnv()` parser and therefore demanded unrelated
  database/R2 secrets that are intentionally absent from Vercel. Independent
  visible and blind contracts landed in `90a6a2d` and `27df988`; `5e4b534`
  introduced the origin-only `webAppEnv()` seam. Focused tests/typechecks passed
  and a fresh Sol identity/security critic returned GO.
- Vercel deployment `9h745WmLGeD3YeMBtMkgCrb54qdm` became Ready from that
  repair. A controlled real Google account then completed consent and the
  Supabase callback, reached `https://gymloop-phi.vercel.app/not-linked`, and
  displayed the existing generic no-complete-identity state. This proves Google
  authentication alone granted no Gymloop role, tenant, membership or platform
  access. The test session was signed out and the browser returned to
  `/sign-in`.
- Android Google OAuth remains the separately implemented PKCE path using the
  fixed `gymloop://auth/callback`, the secure mobile session store and the same
  server-verified identity classifier. Its focused contracts are green; exact-
  AAB device installation remains the separate HARD-008 Play boundary.

## Android production bundle

- EAS project: `@harsh9887/gymloop`
  (`3708f347-96ac-4236-a74c-95808210292b`).
- Production environment names present: `EXPO_PUBLIC_API_BASE_URL`,
  `EXPO_PUBLIC_SUPABASE_URL`, and `EXPO_PUBLIC_SUPABASE_ANON_KEY`; the API base
  resolves to the stable HTTPS production alias above. No service-role key was
  supplied to the app.
- Final build id: `146221dd-dab2-4ef1-a99b-61dc14be4675`; profile
  `production`; distribution `STORE`; SDK `57.0.0`; package
  `in.gymloop.mobile`; source commit
  `7a313846c626271a92b51a7896a26be4aad64628`; version `1.0.0` (`2`).
- Completed UTC: `2026-09-20T18:43:25Z`.
- Local artifact: `dist/releases/gymloop-1.0.0-2-production.aab`
  (`95,188,310` bytes).
- AAB SHA-256: `129C5339A629C3AB2BFE937C7C304D44E4A3BEBEB1ED3CFCEB393F34A674C239`.
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
and sets the first public version. `d894ad5` added the unique-release-version
contract and `7a31384` configured remote version sourcing plus production
auto-increment. The focused HARD-002 suite passed 5/5 and the mobile typecheck
passed before the final build. Post-push CI, holdout and test immutability all
passed; current run ids are `35530050420`, `35530050474`, and `35530050390`.

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
