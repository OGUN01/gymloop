# Member app — minimalist direction v2

Status: member direction approved by the owner on 2026-09-18; implementation is outstanding. The owner rejected the earlier Iron Pulse direction and requested a contemporary minimalist, Apple-inspired experience with equal light/dark support and prominent gym identity/code. The subsequent owner instruction gives the gym-owner console equal visual priority; only platform super-admin remains function-first. The production specification is `../../planning/phase7-experience-prd.md`.

Generated with the built-in image-generation tool. Artifact: `member-minimal-light-dark-v2.png`. Four screens: Home light/dark and My gym light/dark. Generated imagery illustrates hierarchy and appearance; it does not amend functional, identity, or check-in contracts.

Reference: [Apple — integrating the new design and Liquid Glass](https://developer.apple.com/videos/play/meet-with-apple/208/). Interpretation: restrained translucent navigation, clear opaque content, strong typography, and considered light/dark appearances.

## Generation prompt

Use case: ui-mockup
Asset type: Gymloop member mobile application, new visual direction proposal, September 2026.
Create one exceptionally polished high-resolution design presentation with FOUR large, readable mobile app screens side by side: Home light, Home dark, My Gym light, My Gym dark. A single coherent interface in matched light and dark appearances. Each screen has the same size, straight-on front view, fine rounded screen edge, no bulky phone hardware or perspective. Minimal warm-gray presentation background with small understated captions below each screen, no marketing headline.

ART DIRECTION:
Contemporary Apple-inspired consumer product craft: disciplined typography similar to SF Pro, generous negative space, precise alignment, large but quiet titles, subtle continuous corners, content-led hierarchy. Elegant tactile clarity and tiny hairline separators. Translucent liquid-glass treatment ONLY on the floating bottom navigation and a small gym-switcher, with crisp high-contrast labels. Main content is opaque and beautifully legible. Light mode: warm porcelain #F7F7F5, white surfaces, near-black text. Dark mode: ink #101214, elevated charcoal #1C1F22, soft white text. One restrained deep emerald #167C65 brand accent in light mode, pale mint #93DCC0 in dark mode. Secondary text is accessible gray. No neon lime, no rainbow metrics, no gradients behind content, no decorative glow. Small high-quality monochrome outline icons.

PRODUCT:
This is a gym MEMBER app, not a gym admin dashboard or generic workout tracker. The gym identity and gym code are central. Friendly, effortless and calm. Member: Aarav. Gym: Iron Box Fitness, Vijay Nagar. Six-character gym code: IRNBX1. Gym code identifies the gym; check-in uses scanning the gym QR. Do not depict the gym code as a private credential or a substitute for an attendance confirmation. Do not invent payment checkout functionality or calorie/sleep analytics.

HOME screens (first two are identical content and layout, themed):
Top safe-area status bar. Small gym switcher “Iron Box Fitness” with chevron; beneath “Vijay Nagar · IRNBX1”; small circular initials avatar AA at top right.
Large two-line editorial greeting “Hey, Aarav.” then smaller “Ready when you are.”
Lots of breathing space.
One dominant, generously sized emerald action with minimal scan icon and exact text “Scan to check in”. Under it, subtle “Scan the QR at your gym”.
A beautifully simple weekly attendance section: heading “Your week”; a strong numeral “3 / 4” and small “visits this week”; seven evenly spaced day labels M T W T F S S, exactly three completed mint or emerald dots and four quiet empty circles. Supportive caption “One more visit to your weekly goal.”
A compact membership summary row, not a giant card: “Membership” / “Active” small green indicator; “Renews 30 Sep” with right chevron.
Below, one restrained message preview row with speech-bubble icon: “A note from your gym” / “Open until 10 PM today” and tiny unread dot.
Bottom navigation is a floating pill on subtle frosted material, four equally spaced tabs with icons and labels: “Home”, “Activity”, “My gym”, “You”. Home selected. Precisely spaced, beautiful native proportions, comfortable thumb reach.

MY GYM screens (second pair identical content and layout, themed):
Same safe-area, simple title “My gym” and small circular icon button for gym switcher.
Large elegant gym identity “Iron Box” / “Fitness”, supporting “Vijay Nagar, Indore”. Tiny simple abstract gym monogram, no photograph or ornamental illustration.
One restrained membership-pass-like region: caption “GYM CODE”, beautifully typeset monospaced “IRNBX1”, small copy icon, subtle caption “Your gym. One place.”
Then the same prominent “Scan to check in” button.
Calm grouped list with fine separators and chevrons: “Membership & receipts”, “Messages” with a small count 1, “My add-ons”. One secondary small text link “Switch or join a gym”.
Bottom floating navigation with the same Home / Activity / My gym / You tabs; My gym selected.

CONSTRAINTS:
Render four complete screens with sufficient margins, no clipping. Show honest coherent data. Both themes must look deliberately designed, equally premium, not simple inverted colors. Body type large enough to read; generous 48pt touch targets. Text mostly sentence case. Main action immediately identifiable. No confetti, glossy neon, chunky bordered cards, huge QR graphics, stock fitness photos, charts, flame icons, crown icons, slogans, desktop/admin elements, Apple logo, or watermark. Refined restraint and user utility are the visual impact. Aim for the finish of an Apple Design Award finalist, with original Gymloop identity rather than copying an Apple app.
