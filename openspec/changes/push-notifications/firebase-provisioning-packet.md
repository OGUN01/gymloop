# Firebase provisioning packet — 2026-10-04

Project, Android registration and the exact approved server access/custody
below are completed. This packet does not claim deployment or live push.

## Verified project and client

- Account: `sharmaharsh9887@gmail.com`, explicitly selected by the owner.
- The owner authorized reusing Samurai API. Its active Firebase project
  `samuraiapi-51996` (number `762123271201`) is now named **FitCruxx**. It had
  no registered apps before this setup; no claim about other API usage is made.
- Spark plan. Android package `in.fitcruxx.app`, nickname FitCruxx Android,
  app id `1:762123271201:android:35e9d8498bea4f64113760` registered.
- Downloaded public `google-services.json` matches those identities. Receipt:
  `docs/evidence/v2/firebase/setup-20261004.json`. Client build wiring remains
  subject to the native configuration tests/build pass.

Info Hq and the other suspended candidate are not used. No deletion, appeal,
billing upgrade, authentication setup or unrelated app change was performed.

## Exact approved server access

1. Create project custom role
   `projects/samuraiapi-51996/roles/fitcruxxPushSender`, title FitCruxx Push
   Sender, General Availability, containing **only**
   `cloudmessaging.messages.create`. The Cloud role editor shows this
   permission as supported for the project custom role.
2. Create `fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com`
   and grant that custom role on this project. No other grant or impersonator
   is added. This permits the trusted adapter to submit push messages.
3. Create one JSON service-account key and transfer it without displaying
   its contents to `FCM_SERVICE_ACCOUNT_JSON` in the owner-protected
   GitHub environment `production-push` for `OGUN01/gymloop`. Protected CI
   provisions the corresponding Supabase Edge secret only after reviewed
   workflow, passing gates and exact deployment identity. Temporary local
   download is credential custody, not a repository or build artifact.
4. Use `FCM_PROJECT_ID=samuraiapi-51996`. The separately generated dedicated
   wakeup secret follows the existing transport amendment's GitHub/Edge/Vault
   boundary. No server credential goes to Vault, Vercel or Android.

The narrower custom role avoids the topic-management and data-reading
permissions in Google's predefined Cloud Messaging API Admin role. Official
permission reference: [Google Cloud IAM](https://docs.cloud.google.com/iam/docs/roles-permissions/firebasecloudmessaging).
Its creation does not authorize sends before provider deployment and live
acceptance prerequisites pass. Effective grants and private-key custody must
be verified without exposing the key.

The owner approved the exact role, service account, key and custody destination
at action time. The role and its sole permission are created; the dedicated
sender has only that project grant. GitHub environment `production-push`
requires owner review and permits deployment only from `main`. It contains
`FCM_SERVICE_ACCOUNT_JSON`, `FCM_PROJECT_ID` and `PUSH_DISPATCH_SECRET`.

The original Google-generated key's private download was unavailable. Its
equivalent replacement was generated locally and only its public RSA X.509
certificate uploaded to the same sender. Google OAuth verifies the replacement;
no token was displayed and no message was sent. The private JSON was transferred
by encrypted GitHub secret storage through stdin, then its exact temporary
Downloads file removed. The owner separately approved permanent deletion of
the lost original key; refreshed Google inventory confirms exactly one active
replacement, expiring 2027-10-04. This follows Google's documented
[existing-key upload](https://docs.cloud.google.com/iam/docs/keys-upload).

Public metadata receipt and screenshots are in `docs/evidence/v2/firebase/`.
No private key is a repository, browser, screenshot or build artifact. Edge
provisioning, native client wiring, scheduler observation and live acceptance
remain open. Neither protected storage nor successful OAuth establishes a
provider send or device receipt.
