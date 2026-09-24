# Google Play closed test — recruiting and onboarding testers

Why this exists: a Play personal developer account needs **at least 12 testers
opted in to a closed test for 14 consecutive days** before it may apply for
production access (Play help 14151465). Google also asks how engaged testers
were, so every tester gets a real, working Gymloop member login in the
**Gymloop Test Gym** (`9FA4B1`, active, owner linked) — never the Iron Box demo
gym, whose data CI reads. ADR-172/173.

Keep the tester roster (names, Gmail addresses, phone numbers, consent) in a
**private** place — a private sheet the owner controls — never in this public
repository, a test fixture, an issue or a commit message.

## 1. Recruit
Post (adapt freely):

> I'm testing **Gymloop**, an app for gym members to check in and keep their
> membership on track. I need testers on Android for two weeks. You'll get your
> own login in our test gym. Reply with the **Gmail address you use on the Play
> Store**, your name and a phone number (only used as your member record in the
> test gym). Please stay opted in for 14 days — leaving and re-joining restarts
> Google's count.

Collect for each tester: Gmail (the exact Play Store account), full name,
phone in E.164 (`+91…`), and their "yes" to being added. Recruit ~20 so at least
12 stay opted in for the whole window.

## 2. Add them to Play
Play Console → Gymloop → Test and release → Testing → **Closed testing** →
the track → Testers → the email list (add the Gmails) → Save. Share the
track's **opt-in link** (web) with each tester; they must open it while signed
in to that Gmail, tap "Become a tester", then install from the Play link.

## 3. Give each tester a working login
1. The Test Gym owner signs in on the web (`https://gymloop-phi.vercel.app`,
   Continue with Google) and adds the tester as a member in **Members → New
   member** with the tester's name, phone and **exact Gmail** in Email, plus a
   membership (a free or nominal plan; record no real money).
2. The operator binds that member to a confirmed sign-in identity — dry run
   first, then apply (PROV-001…010; the tool refuses any mismatch):

   ```bash
   node --env-file=.env.local scripts/provision-identity.mjs --email tester@gmail.com --gym 9FA4B1 --member <member-uuid>
   node --env-file=.env.local scripts/provision-identity.mjs --email tester@gmail.com --gym 9FA4B1 --member <member-uuid> --apply
   ```
   The member UUID is the last path segment of the member's page in the web
   console. Output is one JSON line with the email redacted; `linked` or
   `already_linked` means done.
3. The tester opens the app → **Continue with Google** with that same Gmail and
   lands on member Home. If they see "Not linked to a gym yet", the email on the
   member record and the Google account differ — fix the record, re-run step 2.

A front-desk tester is bound the same way with `--staff <staff-uuid>` (the
tool refuses gym owners — owners are linked only through `/platform`).

## 4. Keep them engaged (Google asks)
During the 14 days the owner, as Test Gym front desk, can: confirm assisted
check-ins, send a plain-text message, record a membership renewal, and log a
follow-up for a tester who has been away. Ask testers to try check-in, Activity,
My gym (membership, receipts, messages, add-ons), You → Appearance, and to send
feedback through the Play test's feedback link or `SUPPORT_EMAIL`.

## 5. After 14 days
Dashboard → **Apply for production**. Answer from real notes: how testers were
recruited, what they used, feedback received and what changed. Do not claim
engagement that did not happen.

## Removing a tester
Remove the Gmail from the Play list, and on the web set their member to
Cancelled (the token hook then stops issuing member claims). Deletion requests
follow `/delete-account`.
