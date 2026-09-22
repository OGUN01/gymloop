# Member HIG auth and core direction v4

Status: owner-approved implementation reference, 2026-09-20.

Artifact: `member-hig-auth-core-v4.png` (SHA-256
`4b91f2ecbd0155a43a94bb76df2fe21cc8c5139afd609d3a8c15a741c4af54ce`).

This revision applies the installed `ios-design-guidelines` skill pinned to
`brunoamaral/playlister` commit
`d790f919e4832b2d4d194f60ddbc479ef208b22d`. It retains Gymloop's approved
porcelain/ink/emerald language while correcting the previous board to use
44-point targets, safe areas, semantic type and surfaces, a standard persistent
four-tab bar, grouped lists, a single accent, and thumb-zone primary actions.

The iPhone sign-in reference includes Sign in with Apple before Google because
the skill correctly identifies that App Store requirement when a third-party
provider is offered. Android remains Google-first and does not render the Apple
provider. Email remains a disclosed secondary action instead of three competing
forms on first view.

Appearance is reached from one accessible gear icon. The first Settings sheet
shows the current appearance and pushes to its own screen; it does not expose a
large persistent selector or stack another modal. The board is visual guidance,
not evidence that Apple OAuth, Google OAuth, or provider console configuration
exists.

The You implementation presents the member name, an explicit verified-member
state, and the current gym name/code before optional contact text. Its grouped
account list contains Personal details, Membership, Gym, and Appearance. Each
row has a useful current-value summary and an accessible name; the Appearance
row opens the existing settings hierarchy. Long contact text wraps inside its
column and cannot displace the verified gym identity from the primary facts.
