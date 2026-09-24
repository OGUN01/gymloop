# Chalkline — Gymloop visual direction (Phase 9 redesign)

Status: **selected by the owner 2026-09-24** ("the chalkline is best — use that design for all"). Supersedes the visual parts of ADR-125/128/136 (see ADR-170). Owner visual acceptance of the *implemented* screens (HARD-010) remains open until the owner gives it.

Reference boards (generated with Codex image generation, `docs/design/phase9/concepts/`):
- `A-chalkline-member-home-light.png`, `A-chalkline-member-home-dark.png`, `A-chalkline-owner-overview-light.png` — the selected direction.
- `chalkline-*.png` — the extension set (auth, member tabs, check-in results, desk check-in, follow-ups, membership detail, platform, desk Android).
- `B-cobalt-*`, `C-plum-*` — rejected alternatives, kept for the record.

Boards are conformance references for layout, hierarchy, type, colour and density. Their illustrative content is not product data: no slogans/taglines, no trend percentages or sparklines, no staff photos, no fields the loaders do not return.

## Idea
Gym chalk on a warm paper ledger. Warm, honest, confident — a neighbourhood gym in Andheri at 6:30am, not a neon nightclub. The product is a ledger of people showing up, so the interface is built from **ruled rows and big numbers**, not boxed cards.

## Colour (semantic tokens in `UI_TOKENS.colors`)
| Token | Light | Dark | Use |
|---|---|---|---|
| canvas | `#F3F0EA` chalk paper | `#141311` warm charcoal | page |
| surface | `#FBFAF7` | `#1D1B18` | inputs, raised rows, sheets |
| elevatedSurface | `#E9E5DD` | `#282521` | sunken fills, selected rail item, skeletons |
| primaryText | `#171512` | `#F3EFE7` | ink |
| secondaryText | `#5F5A52` | `#B3AB9F` | captions, labels |
| primaryAction | `#AD4119` clay | `#FF8A57` | the one accent: primary button, current nav, check-in moment |
| textOnPrimary | `#FFFFFF` | `#1A0D06` | |
| decorativeSeparator | `#DDD7CC` | `#34302A` | hairline rules |
| requiredControlOutline | `#847D72` | `#7A7368` | input/button outlines (≥3:1) |
| successText | `#2E6A3E` moss | `#8FCB98` | On track, Paid, Confirmed |
| warningText | `#865300` ochre | `#E8B75A` | Drifting, Due, Pending, offline-saved |
| errorRiskText | `#B1242F` crimson | `#FF9A94` | At risk, Overdue, Failed, errors |

All text pairs ≥ 4.5:1 on canvas, surface and elevatedSurface in both themes; outlines ≥ 3:1 (checked 2026-09-24). Status is **always dot + word**, never colour alone.

## Type
- **Archivo** (OFL) only. Web: `@fontsource-variable/archivo` width+weight axes, bundled locally (ADR-127). Android: static instances in `apps/mobile/assets/fonts/` (Regular/Medium/SemiBold/Bold, plus ExtraCondensed ExtraBold cut from the same variable master).
- **Display** — ExtraCondensed (wdth 62) weight 800, tight line-height: page titles on console ("Overview"), big numerals ("3 of 4", "142", "₹3,48,200").
- **Text** — normal width 400/500/600; 16/24 body web, 17/25 body mobile.
- **Eyebrow** — 12px, 600, uppercase, +0.14em tracking, secondary colour: section labels ("VISITS TODAY", "LATEST FROM YOUR GYM").
- Tabular numerals for all money, counts, times.

## Shape & space
- Radii: control 10, row 12, section 16, sheet 24. No pills except status dots and the tab indicator.
- Hairline 1px rules separate sections and rows; boxed surfaces only for inputs, a single tappable summary row, and sheets/dialogs.
- Spacing scale 4/8/12/16/24/32/48; generous vertical rhythm; content max width 1440 console.
- Targets ≥ 44px web, ≥ 48dp touch.

## Icons
Lucide, 1.75 stroke, 16 control / 22 navigation. Line only, never filled except the current tab icon.

## Motion
120ms press, 180ms tabs, 240/180ms dialog in/out, check-in acknowledgement 240–320ms. All removed under reduced motion.

## Imagery
Warm documentary photography (generated, `apps/web/public/images/`, `apps/mobile/assets/`): sign-in hero only on auth; nothing decorative inside work screens.

## Layout by role
- **Member (phone-first, web + Android):** single column; gym line at top; greeting; condensed hero numeral; rhythm dots; ruled rows; one dominant clay "Scan to check in"; bottom tab bar Home / Activity / My gym / You with hairline top rule.
- **Front desk / trainer:** console rail; check-in is a roster ledger + gate panel; outcome strip is the loudest element until dismissed.
- **Owner / manager:** slim left rail (gym name in condensed caps + branch/code, nav with line icons, clay-tinted current item); page header = condensed title + actions; one ruled row of exactly four key numbers; ledger tables with uppercase column labels.
- **Platform:** top header bar (no rail), same ledger language, denser tables.
