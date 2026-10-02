# INV bar — member invites and self-linking (V2-A1, feature F1)

Status: bar for Gauntlet Loop step 1. The blind critic scores the implemented INV screens against section 6. Written 2026-10-02; **every reference below was fetched on 2026-10-02**.

Method (per `docs/architecture.md`, "Quality bars"): public pages only, read and screenshotted through a browser. No third-party account was signed into, no form was submitted, cookie banners were declined where one appeared. Screenshots are in `docs/design/v2/inv-bar/` (8 PNG files, each under 150 KB).

Scope: what an invitee sees from opening an invite link or QR to landing in the member app, and what gym staff see from sending an invite to revoking one. Out of scope: staff invites (STI reuses these criteria later), guardian flows (GRD), WhatsApp delivery (WSP). Tone only is borrowed from `docs/design/phase9/direction.md`: a ledger, status as dot plus word, nothing decorative.

## 1. Limits of this evidence, stated up front

- The live invitee screens of Linear, Slack, Stripe, GitHub and Notion sit behind a token or a login, and the rule is never to authenticate. What is observable is their **published documentation** and the UI shown in it. Criteria below are derived from documented behaviour, not from watching a live accept screen.
- Where the public docs are silent (wrong-account copy, what the invitee sees after a revoke, a failed delivery), the criterion is FitCruxx's own and is tagged **[own]**. Nobody should assume a best-in-class product does it.
- Two things were searched and not found: a Mindbody consumer help article on first sign-in to a studio, and a Slack article describing the invitee's accept screen. Neither is cited. WHOOP's article is dated 2019; treat it as a pattern, not as today's UI.

## 2. References

| ID | Reference | URL | Screenshot |
|---|---|---|---|
| R1 | Linear Docs, "Invite members" | https://linear.app/docs/invite-members | `linear-invite-members.png` |
| R2 | Slack Help, "Manage pending invitations and invitation links for your workspace" | https://slack.com/help/articles/360060363633-Manage-pending-invitations-and-invite-links-for-your-workspace | `slack-manage-pending-invitations.png` |
| R3 | Slack Help, "Invite new members to your workspace" | https://slack.com/help/articles/201330256-Invite-new-members-to-your-workspace | none |
| R4 | Stripe Docs, "Start a team" | https://docs.stripe.com/get-started/account/teams | `stripe-start-a-team.png` |
| R5 | GitHub Docs, "Inviting users to join your organization" (and "Canceling or editing an invitation to join your organization") | https://docs.github.com/en/organizations/managing-membership-in-your-organization/inviting-users-to-join-your-organization and https://docs.github.com/en/organizations/managing-membership-in-your-organization/canceling-or-editing-an-invitation-to-join-your-organization | `github-inviting-users.png` |
| R6 | Clockify Help, "Invitation link expired" | https://clockify.me/help/troubleshooting/basics/invitation-expired | `clockify-invitation-expired.png` |
| R7 | WHOOP, "Join and Create Teams on WHOOP" (2019) | https://www.whoop.com/thelocker/join-create-teams-on-whoop/ | `whoop-join-a-team.png` |
| R8 | Strava Support, "Clubs on the Mobile App" and "Clubs on Strava" | https://support.strava.com/en-us/articles/15401837-clubs-on-the-mobile-app and https://support.strava.com/en-us/articles/15402172-clubs-on-strava | none |
| R9 | Glofox Support, "An Overview of the Member App and Standalone App" (Feb 2026) | https://support.glofox.com/hc/en-us/articles/46466949130900 | `glofox-member-app-overview.png` |
| R10 | Google for Developers, "Sign in with Google Branding Guidelines" (last updated 2026-07-07) | https://developers.google.com/identity/branding-guidelines | `google-signin-branding.png` |
| R11 | Android Developers, "Play Install Referrer Library" (mechanism, not a UX bar) | https://developer.android.com/google/play/installreferrer/library | none |

Consulted, no criterion derived: Notion Help, "Manage members & guests" (https://www.notion.com/help/add-members-admins-guests-and-groups). It documents join-by-link and allowed domains, and is silent on resend and cancel.

## 3. What each reference shows

### R1 Linear — invite members (admin send, link policy)
- Sending is a short numbered path: Settings > Administration > Members, **Invite**, enter addresses separated by commas, pick a role on paid plans. Plain verbs, no jargon.
- The hero image in the docs is one members table: name, email, role, and a per-row ••• menu. The admin's list is the invitee's destination, not a separate screen.
- Invited people can be assigned work **before they accept** (via "Invite and assign…"), so a pending person is a first-class row, not a limbo.
- The shareable invite link is "persistent and reusable" and is reset with a **Reset invite link** button. Anyone holding it can join; the docs warn to share it internally only.
- Silent on: expiry, resend, revoke, and what the invitee sees when something is wrong.

### R2 Slack — manage pending invitations (admin status, resend, revoke)
- A dedicated **Pending** tab under Admin > Workspace settings > People > Invitations. Reaching a single invite's actions takes five numbered steps.
- Three verbs per pending invite, on the row: **Extend invitation**, **Resend invitation**, **Delete invitation**. The docs explain each in one sentence ("to prevent an invited member from accepting it").
- Expiry is stated in a yellow note before any step: invitations and invitation links expire after 30 days.
- The **Invitation links** tab lists every link with who created it and when, and offers **Deactivate** and renew-when-expired.
- Silent on: any named status labels beyond the tab names.

### R3 Slack — invite new members (limits, link policy)
- Email invitations stay valid 30 days and owners and admins can resend a pending one to make it active again.
- A link is valid 30 days and accepts up to 400 people; "Edit link settings" lets an admin set an expiry date and choose to be notified when someone uses it.
- When a link has expired, the stated invitee remedy is to find an owner or admin; there is no self-serve dead end described.
- Sending many invites with few accepted can trigger an invitation limit, and the docs say so plainly.
- Silent on: the invitee's accept screen.

### R4 Stripe — start a team (send flow, expiry, audit)
- Five numbered steps ending in an explicit **review the configuration, then Send invites**: nothing goes out on the first tap.
- One sentence on expiry, no hedging: invites expire after 10 days.
- Roles are editable after acceptance from the row's ••• menu > **Edit**, so the invite carries intent and the row carries the truth afterwards.
- The same page points to **Security history**, which logs team activity for the past 180 days: who did what is a first-class screen.
- Stripe's support article adds: an invitee with no login is asked to set one up, one with a login signs in, then moves between accounts. The pages fetched say nothing about resend or revoke.

### R5 GitHub — inviting users and cancelling an invitation (identity match, limits, failed list)
- Identity match is explicit: an email invitation can only be accepted if the address matches a verified email on the invitee's account. Strict matching is a documented, shipped norm.
- Pending invitations expire automatically after seven days. Expired ones move to a separate **Failed invitations** list, where each row's ••• menu offers **Retry invitation** or **Cancel invitation**, singly or in bulk.
- Owners can edit (role, team) or cancel a pending invitation any time before acceptance, from a ••• menu on the row. The People > Invitations list filters by role and source.
- Abuse limits are published numbers: 50 invitations per 24 hours, 500 for older or paid organisations.
- Silent on: what the invitee sees after a cancel.

### R6 Clockify — "Invitation link expired" (the refusal-copy anti-pattern and its repair)
- One message, "the invitation link has expired", is shown for **two different causes**: the invite was already accepted (the link then goes invalid automatically), or it lapsed after 14 days. The page asks the invitee to work out which. This is the named failure to avoid.
- The repair is good and concrete: sign in at clockify.me to check whether an account already exists; if it does, the pending invite waits in the bell-icon notification card ("Workspace invite … ACCEPT / Decline", visible in the screenshot).
- Admin side: on the team page a **"not joined yet"** tag sits inline on the person; ••• > **send an invite email** resends. Three steps.
- Only account owners can delete a person who has not accepted; the permission boundary is stated on the page.
- If it still fails, the page routes the case to support, asking for the invitee's email and a screenshot of both sides: the screen does not explain itself, so a person has to.

### R7 WHOOP — join a team (in-app pending invite, data disclosure at join)
- An invite arrives as a **pending invite inside the app**; accepting it is the join step. The article describes no form or code on this path.
- A team code is the fallback when a profile is not searchable, so the happy path and the fallback are different things.
- Disclosure sits next to the join: members are told to check which personal data they share on the leaderboard, that the owner sets the selection, and that "your data is only visible once you've joined the team".
- Silent on: expiry, revoke, wrong-account.

### R8 Strava — clubs on mobile (pending as a visible state, link as plain URL)
- After tapping Join on a private club, the button itself changes to **Pending**: the state lives where the person is looking.
- Admins get a **Pending Requests** queue with **Approve** and **Decline** per request, and can turn on push notifications for new requests.
- No separate accept-invite flow is documented: the support text describes an invite as sharing the club's link. Email invitations from inside Strava have been switched off.
- Silent on: expiry and link handling, which is why Strava is a state-labelling reference only.

### R9 Glofox — member app overview (the zero-bar baseline for discovery)
- The shared Member App flow is: download "Glofox" from the store, **enter a location, search the studio's name** (the screenshot shows "Find your studio or gym"), then sign up. The member does the matching work.
- A branded Standalone App is found by searching the store for the studio's name. Either way, discovery is a search the member performs.
- Once the studio is found, the member can sign up, look at classes, book and buy memberships.
- The page documents no invite link, no deep link and no pre-matched account. This is what INV must beat: the link already knows the gym and the member row.

### R10 Google — Sign in with Google branding (button and consent wording)
- Allowed call-to-action text is one of "Sign in with Google", "Sign up with Google" or "Continue with Google"; the text should make clear the person is signing in to **your app** with Google credentials, not creating a Google Account.
- The word "Google" alone as the label is shown under Don't (screenshot). The "G" alone is acceptable only where an action button is needed.
- The Google button must be at least as prominent as any other sign-in option. Custom buttons use Google's approved light, dark or neutral colour modes and may not recolour the "G".
- Following these guidelines is required to pass app verification, so a non-conforming button is a release blocker, not a style choice.

### R11 Play Install Referrer — mechanism for "the invite survives the install"
- The API lets an app read the referral string that Google Play attached to its install.
- Android's guidance is to read it once, at first run; the data is available for 90 days and does not change unless the app is reinstalled.
- The page does not itself walk through carrying a custom value from a link to first launch, so the spec must verify that an invite token can ride this referrer before relying on it. It says nothing about copy or states; it is cited only for criterion INV-Q2.

## 4. Where the references are silent, so FitCruxx sets the bar itself [own]

| Gap | Why it matters here |
|---|---|
| Wrong-Google-account copy | GitHub states the email-match rule but the page does not show the refusal words. A gym member opening a link on a shared family phone will hit this. |
| What the invitee sees after a revoke | No reference documents it. Staff revoke because they invited the wrong person; the invitee must not be blamed or told why. |
| Failed delivery surfaced to the admin | Only GitHub separates "Failed". A WhatsApp or SMS link that never arrived must not sit as "Invited" forever. |
| Account already linked elsewhere | Owner decision D1 (2026-10-02): one Google account, one member, ever. No reference has this rule; the copy and the no-picker rule are ours. |
| Data notice before linking | Only WHOOP discloses at join, and only about leaderboard data. |

## 5. Deliberately not copied

- **Persistent, reusable invite links** (Linear, Slack, Notion): they admit anyone holding the URL. INV is a single-use token bound to one member row (feature map F1); a reusable link would defeat both single-use and D1.
- **Open join by approved domain** (Linear, Notion): gyms have no company domain.
- **Slack's "Extend invitation"**: INV expiry is fixed and resend issues a new token that invalidates the old one. Two actions on the row, not three.
- **Studio search** (Glofox, Strava): the token resolves the gym. If a member has to search, INV failed.
- **Role pickers at invite time** (Linear, Stripe, GitHub): member invites carry no role. Roles arrive with STI.

## 6. Bar for INV

The critic scores each criterion pass / fail with evidence (a screenshot, an accessibility-tree dump, or the exact string). The bar is met when all twelve pass. A repeat fail on the same criterion three times is escalated to the human as a spec problem, per the Gauntlet Loop. Tags show provenance.

**Invitee side**

**INV-Q1 — Arrives pre-matched, nothing to search or type.** Opening the link or scanning the QR lands on a screen that names the gym first and offers one primary action. No studio search, no code entry and no text field on the happy path. Before Google sign-in the screen shows the gym's name and nothing about the person: no member name, phone, email, plan or branch-specific data. *Probe:* open the link signed out and read every string on screen. *From:* R9 (baseline), R7, R8. **[own]** for the pre-auth minimum.

**INV-Q2 — Tap budget.** From landing to the member Home, at most 2 taps in FitCruxx-owned UI and zero typed fields, on Android and on web. Google's own account chooser and consent screen are not counted. With the app not installed, the path link > store > install > first launch resumes the same invite without the person reopening the link; a typed code is allowed only as a fallback, never as the primary path. *Probe:* count taps on a fresh device and a fresh install, with the screen recording attached. *From:* R7 (accept is the join), R8, R11, R9 (the search it replaces).

**INV-Q3 — Data notice before the button.** On the invite screen, above the Google button and in plain English: which gym the person is joining and that the gym decides how their data is used; that FitCruxx processes it on the gym's behalf; exactly which items are read from Google at link time (only what the build actually reads); what linking does (connects this Google account to the person's membership at this gym); a link to the full notice. No pre-ticked box, no "DPDP compliant" badge or any claim of statutory compliance (`docs/planning/privacy-operations-contract.md` does not make one). *Probe:* compare the listed items against the Google scopes requested, string for string. *From:* R7 (disclosure at join), R10, F1 edge case "invite text must say what data is processed".

**INV-Q4 — Google button is conformant.** Label is "Continue with Google" or "Sign in with Google" (never "Google" alone); the "G" is the unmodified mark on a light, dark or neutral background; target at least 44px on web and 48dp on Android (Chalkline); no other sign-in option is given more prominence. *Probe:* inspect the element and compare with the R10 screenshot. *From:* R10.

**INV-Q5 — Every refusal names what happened and the next action.** Each of the refusal states is one or two sentences, in plain words, never a code, never blaming the person, and each carries a primary action or names who to contact (the gym, by name). No dead end. *Probe:* trigger every state, read the strings, confirm each has a verb the person can do next. *From:* R3 (find an owner or admin), R6 (the repair), D1 copy.

**INV-Q6 — Causes are distinct, never conflated.** At least these states have their own message: expired, already used, no longer active (revoked), wrong Google account, this Google account already linked (D1), and member no longer eligible. Two causes behind one sentence is a fail. *Probe:* trigger all six and diff the strings. *From:* R6 (the named anti-pattern). The already-linked state is the owner's D1 decision (paraphrased from `docs/planning/v2-campaign-goal.md`): this Google account is already joined as a member and cannot be linked again; ask your gym to use a different email. It never offers a picker and never names the other gym.

**INV-Q7 — No refusal reveals another person's record.** No state shows the member's name, phone or email from the row to anyone who has not been matched; the wrong-account message never states the address the invite was sent to; an unknown or malformed token gets the same wording as a no-longer-active one; the already-linked message never names a gym or member. The only personal data on screen is the viewer's own Google address. *Probe:* feed the screens tokens for other members, other gyms and garbage, and grep every response for the seeded member's name, phone and email. *From:* F1 edge case, D1. **[own]**

**INV-Q8 — Recovery is one tap and re-opening is safe.** Every account-dependent refusal shows which Google account is in use and a one-tap "use a different account". The person who already redeemed an invite and opens the link again with the same account goes straight into the app, not into an "already used" error. *Probe:* redeem, then reopen with the same account, then with another. *From:* R6 (workaround is buried in a bell icon), R4 (existing login simply signs in). **[own]** for the wording.

**Staff side**

**INV-Q9 — Status at a glance, on the member row.** Each member row with an invite shows its state as dot plus word (never colour alone), drawn from the generated Postgres enum and not a hand-written constant, with the sent time and the expiry as absolute date-times in IST. A filter or queue lists everyone who has not joined yet. Staff never leave the member list or open a settings area to see it. *Probe:* load the list with one member per state; check the tree for dot plus word and the enum value; count navigations from the list. *From:* R6 (inline "not joined yet" tag), R8 (Pending on the button and a queue), R2 and R5 (separate tabs that cost five steps or a detour).

**INV-Q10 — Send is one reviewed action and ends with something usable.** From the member row, send is one action plus at most one confirmation that shows what will go out and to which contact. The result shows the link, a copy-link action, a QR to show on a tablet at the desk, and the expiry. The sent message itself states when it stops working. *Probe:* count taps from row to "sent"; read the result and the delivered text. *From:* R4 (review, then send), R5, R2. **[own]** for the QR at the desk.

**INV-Q11 — Resend and revoke say what they do, then show it done.** Resend is one action from the row and, before it is confirmed, says the previous link will stop working; revoke names the member and says the invite will stop working. After either, the row shows its new state immediately and the member's history shows one audit line: who, what, when. Revoke needs no reason. *Probe:* resend then open the old link (expect the "no longer active" state); revoke then open the link; read the history. *From:* R2 and R5 (three verbs on the row, not hidden), R4 (activity log), F1 (resend invalidates the old token).

**INV-Q12 — Limits and failures are legible, never silent.** When a staff member hits a send or resend limit, the refusal says why and when they can try again, in IST; no number is invented in the UI beyond what the spec fixes. A delivery that fails shows as a distinct status the staff can act on, not as "Invited" indefinitely. *Probe:* exhaust the limit and force a failed delivery on a fixture. *From:* R3 and R5 (published limits), R5 (Failed invitations list). **[own]** for the failed-delivery status.

## 7. Standing conditions (apply to every criterion above)

- Both Chalkline themes, at 200% text size and with reduced motion on; contrast pairs as in `docs/design/phase9/direction.md`.
- Each state's heading is the first thing read by a screen reader and states are not carried by colour alone.
- English only, no emoji, no marketing tagline on any refusal.
- The critic must be able to reach every state; if a state cannot be reached without a real token, that itself is a finding against the build, not an excuse to skip it.

## 8. Open points for the spec author (not decided here)

- Exact match or a looser match between the Google email and the member row. The feature map leaves this to the spec; INV-Q5 to Q8 must hold either way, and GitHub (R5) is the precedent for exact.
- Expiry length. The feature map says 24 to 48 hours; the bar only requires that it is shown as an absolute IST time and is the same in the message, on the staff row and in the refusal.
- Whether the invitee sees their own first name only after the match. This doc sets that as the minimum pre-auth rule (INV-Q1); a spec that wants a name before sign-in should argue it against INV-Q7.
