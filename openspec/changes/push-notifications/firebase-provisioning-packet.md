# Firebase provisioning packet — 2026-10-04

Project and Android registration are owner-authorized and completed. Server
access below is prepared, **not created or granted**; its action-time browser
confirmation is pending. This packet does not claim deployment or live push.

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

## Exact proposed server access

1. Create project custom role
   `projects/samuraiapi-51996/roles/fitcruxxPushSender`, title FitCruxx Push
   Sender, General Availability, containing **only**
   `cloudmessaging.messages.create`. The Cloud role editor shows this
   permission as supported for the project custom role.
2. Create `fitcruxx-push-sender@samuraiapi-51996.iam.gserviceaccount.com`
   and grant that custom role on this project. No other grant or impersonator
   is added. This permits the trusted adapter to submit push messages.
3. Create one JSON service-account key and transfer it without displaying
   its contents to `FCM_SERVICE_ACCOUNT_JSON` in the proposed owner-protected
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

The browser confirmation policy requires action-time approval for new
security-sensitive access and persistent credentials. The pending request
covers the exact role, service account, key and custody destination above.
Prepared screenshots are in `docs/evidence/v2/firebase/`; the final role
creation and account grant have not been submitted.
