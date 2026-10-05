# FitCruxx v2 device-testing handoff (2026-10-05)

You are the **Android device-testing agent**. Your job is to verify the v2
feature set on a real Android device and produce a defect report. You are NOT
an implementer: **you do not edit application code, migrations, or test files;
you test, record, and report.** A defect report is a file you write; fixes are
routed back to the implementing sessions.

## Hard rules (constitutional — read before anything)

1. **Never use the Supabase MCP server.** It is authenticated to a different
   account (`sageharsh9887@gmail.com`) and would silently hit the wrong
   database. All Supabase work in this repo goes through the `supabase` CLI
   (project `pecxrpskmfeuyzngvewq`) — and you should not need it at all.
2. **Migrations are applied by CI only.** You never run `supabase db push`,
   never apply SQL by hand, never edit `packages/db/types/database.ts`.
3. **Never weaken or touch test files** (`supabase/tests/**`,
   `supabase/tests-holdout/**`). Read them if useful for understanding
   expected behaviour; never edit them.
4. **Do not push to `main`.** Your deliverable is a defect report file plus
   screenshots under `docs/evidence/screens/`. If you need to commit evidence
   only, ask the owner first.
5. **Never print a password or token in any log, file, or tool argument.**
   Demo credentials live in `.env.local` (gitignored) and
   `docs/demo-accounts.md` names the accounts only.
6. If a fix seems obvious and small, **still report it — do not fix it.** A
   device defect is evidence for the implementing session, not your work item.

## Environment (verified against this machine, 2026-10-05)

- Android SDK: `%LOCALAPPDATA%/fitai-toolchain/sdk` (`ANDROID_HOME`); adb in
  `platform-tools`. JDK 17 alongside.
- Device: OnePlus DN2101 over USB (`adb -s DN2101` / `--device DN2101`).
- **Build recipe** (from the repo root; these constraints are real, not
  preferences):
  - Building from `C:\Users\Harsh\Desktop\gymloop` fails (CMake/ninja path
    length). `subst` drives break Gradle. What works:
    ```
    git worktree add C:/gc HEAD
    ```
    then **in that worktree only**, append to `pnpm-workspace.yaml`:
    ```yaml
    virtualStoreDir: .p
    virtualStoreDirMaxLength: 24
    ```
    then `pnpm install` inside the worktree.
  - Build: `npx expo run:android --variant release` with the env vars below
    exported for the command.
  - Env vars (values from repo root `.env.local`; the names differ on purpose):
    - `EXPO_PUBLIC_SUPABASE_URL` ← `NEXT_PUBLIC_SUPABASE_URL`
    - `EXPO_PUBLIC_SUPABASE_ANON_KEY` ← `NEXT_PUBLIC_SUPABASE_ANON_KEY`
    - `EXPO_PUBLIC_API_BASE_URL=https://gymloop-phi.vercel.app`
    - `EXPO_PUBLIC_WEB_URL` ← the web console URL (same Vercel origin)
  - Gradle does not see `packages/shared` changes without
    `app:createBundleReleaseJsAndAssets --rerun` — pass it or the JS bundle is
    stale.
  - In Git Bash, prefix `MSYS_NO_PATHCONV=1` for any `adb shell ... /sdcard/...`
    push/pull.
- App id: `in.fitcruxx.v2check` (side-by-side v2 testing id, already set in
  `apps/mobile/android/app/build.gradle`). It installs next to the Play-signed
  pilot app. **Never install over a Play-signed build and never uninstall the
  Play-signed pilot app** (it wipes the owner's data) — if a signature mismatch
  appears, the app id is wrong; stop and report.
- The Play release app id is `in.fitcruxx.app` (Play app `4975754557722576970`,
  Ductx account `7649203845150858113`). Do not touch it in this phase.

## Test accounts (real rows — they exercise the JWT hook and RLS for real)

From `docs/demo-accounts.md`, demo gym "Iron Box" (gym code `9FA4B1`):

| Account | Role | Surface |
|---|---|---|
| `owner@ironbox.example.com` | `gym_owner` | full owner matrix |
| `divya@ironbox.example.com` | `front_desk` | desk surface (check-in, payments, members) |
| `aarav.member@ironbox.example.com` | `member` | member app |

Passwords are in `.env.local` (`DEMO_ACCOUNT_PASSWORD`). **Never type a
password into a device field without first confirming (uiautomator dump) that
the Password field is focused, and never print field text.**

For invite-link flows (INV/STI) you may need a fresh Google account — the
invite signs in with Google and self-links. Auth signup is owner-gated: if the
invite flow is refused at sign-up, that is a finding to report, not a blocker
to work around.

## What to test — the v2 feature checklist

Every feature below went through the full Gauntlet Loop and CI. Your job is
device truth: does it actually work in the hand, on this build, against
Supabase Cloud (`pecxrpskmfeuyzngvewq`)?

Member app routes live under `apps/mobile/app/(member)/`: `index` (home),
`activity`, `buy`, `classes`, `freeze-requests`, `shop`, `gym`, `you`.
Desk routes under `apps/mobile/app/(desk)/`: `index`, `members`, `classes`,
`follow-ups`, `training`, `more`.

Test in this order (identity first — everything else depends on it):

1. **Auth + INV/STI** — sign in with each demo account; the invite flow
   (`app/invite/[token]`): open an invite link, sign in with Google,
   self-link to the member row. Single-use and expiry behaviour: an already
   used or expired link must refuse cleanly.
2. **CLS (classes)** — member: browse the service catalogue, book a class
   session, cancel it. Desk: session roster, mark attendance, mark/cancel
   evidence flows.
3. **SHP (shop)** — member: browse products, place an order request.
4. **PTF (personal training)** — trainer profiles visible; desk/trainer:
   session scheduling surface.
5. **PAY (buy tab + payment screenshots)** — member: `buy` tab, request a
   plan/add-on purchase, upload a payment screenshot (camera + gallery paths).
   Desk: verify the proof appears for the desk role to approve. **This is the
   money path — test both success and refusal paths; a wrong approval here is
   the worst defect class in the product.**
6. **SLF (self-service freeze)** — member: request a freeze
   (`freeze-requests`), see its status; desk: approve/reject.
7. **PLC (plans catalogue)** — member: read-only plans view under `gym`.
8. **ANC (announcements)** — owner posts an announcement (web console);
   member app home shows it.
9. **NTF (push)** — Android push via FCM (Firebase project `samuraiapi-51996`,
   now named FitCruxx). The device should register a token on first launch.
   The push **scheduler is inert by design until the owner completes the
   activation workflow (the 8 operator revokes on the dashboard)** — if a
   manually-triggered campaign send does not arrive, note it and check the
   `push_delivery` tables via the web console rather than assuming device
   failure. Device-token registration itself IS testable now.
10. **WSP (WhatsApp)** — ships as the frozen manual handoff: owner-directed
    manual sends from the console. Verify the handoff list generates and the
    copy is right. Meta/WABA activation is deferred — do not test live sends.
11. **BIZ (business_type)** — check copy adapts per the tenant's
    `business_type` (gym | dance | yoga | martial arts).
12. **GRD (guardian/minor)** — if the demo gym has a minor member configured:
    guardian fields, minor protection gates.
13. **TRV (trainer view)** — a trainer-role account's "my clients today".
14. **OCC/RPE (analytics + exports)** — these are owner **web** console
    surfaces, not device: verify on the web console that peak-hours heatmaps
    render and PDF/GST exports download.

## Known states — do not misreport these as defects

- The push scheduler is intentionally inert until the owner runs the activation
  workflow (8 operator revokes, dashboard action). "Scheduler didn't send" is
  expected until then.
- WhatsApp live paid sends are deferred by owner decision — the manual handoff
  is the whole feature.
- A handful of `04_contract_meta` pins are deliberately red (source-defect
  findings on `member_devices` write policies, missing indexes) — those are
  server-side and tracked; do not hunt for their symptoms on device.
- The e2e accessibility suite's API-500 class was escalated to the owner; if
  the deployed web console 500s on an API route, report it with the route path.

## Deliverables

1. **Defect report**: `docs/planning/v2-device-testing-findings.md` — one
   entry per defect, each with: feature ID, exact steps, expected vs observed,
   screenshot path, severity (blocker / major / minor), and whether it
   reproduces on a second attempt.
2. **Screenshots**: `docs/evidence/screens/2026-10-05-device-<feature>-<n>.png`
   pulled off the device via adb (`MSYS_NO_PATHCONV=1 adb pull`).
3. **A go/no-go summary** at the top of the findings file: which features are
   device-verified, which are blocked, which are broken.

## The release gate (context — why your report matters)

After your report is triaged and fixes land, the sequence is: Play Console
release build from this same recipe (app id `in.fitcruxx.app`, EAS or local
bundle upload), closed-test track, ≥12 testers opted in 14 consecutive days
before production. Owner-gated items still open: support email, FCM restricted
server access, Meta/DLT WhatsApp activation (deferred), legal sign-off.
