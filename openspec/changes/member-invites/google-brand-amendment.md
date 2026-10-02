# Google provider font amendment — owner approved

Status: owner-approved 2026-10-02; frozen as INV v1.5 in `proposal.md`.

The third independent INV-Q4 review found that the existing custom Google
button uses Archivo while the frozen R10 reference requires Google Sans Medium.
Earlier reviews found the missing mark and then its outdated solid-color form;
those are repaired with the byte-verified official gradient PNG. AGENTS.md
requires escalation after three rejections of the same dimension. No font
waiver or reduction in the published bar is proposed.

## Approved contract clarification

- All shared Google controls used by ordinary sign-in, INV and STI SHALL use
  Google Sans Medium, loaded from the official Google Fonts distribution and
  bundled locally. Record the upstream URL, license and SHA-256 of the exact
  font bytes. Reuse one asset across web and Android and existing font-loading
  mechanisms; add no native dependency.
- Provider text SHALL retain its allowed Google action label, approved neutral,
  light or dark colors, the verified official gradient mark, and at least 44px
  web / 48dp Android targets. Body and display typography remain governed by
  Chalkline. Authentication, consent, routing and token behavior are unchanged.
- Loading or failure SHALL not falsely claim the required font is available.
  A font-loading failure SHALL offer honest recovery or use an unmodified
  pre-approved Google button image that already contains the correct text/font.
- Independent tests SHALL verify the actual provider font/asset and loading
  boundary before a separate implementation; a fresh blind critic SHALL check
  conformance against https://developers.google.com/identity/branding-guidelines.

Owner approval authorizes this focused clarification and its normal test/build/review
pass. Deployment still follows ADR-177 and every required gate remains in force.

## Verified candidate asset

Official release: https://github.com/googlefonts/googlesans/releases/tag/v14.000.
The candidate is `build/GoogleSans/static/GoogleSans-Medium.ttf` from the
upstream `GoogleSans-v14.000.zip`, SHA-256
`1c87b72912ef81b48ab4852976f3d5bf75c7205e0a58a97ffca947d171c722a7`.
The accompanying upstream license is
https://github.com/googlefonts/googlesans/blob/v14.000/OFL.txt
(SIL Open Font License 1.1). Candidate bytes and license are kept in the local
validation workspace; implementation follows independent red tests.
