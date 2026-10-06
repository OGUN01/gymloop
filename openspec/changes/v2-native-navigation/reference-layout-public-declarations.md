# Approved reference layout integration seam

2026-10-06. This completes the first approved orange board's compact spacing and Shop section links, under the existing NAVC-008/009/012 requirements. It changes arrangement only; palette, catalogue reads, cancellation, disclosure and notification semantics remain frozen.

- Existing native `Screen` accepts one optional `scrollRef?: React.RefObject<ScrollView | null>` and connects it to its existing scrolling column. Omitted callers keep their existing behavior. No new exported helper/type/hook is introduced.
- Shop presents quiet Products, Plans and Services section buttons near its compact heading. Each scrolls the same catalogue to that section's measured position; it does not hide another section, trigger a new read, create a bottom tab or change reservation disclosure. Repeated taps remain local scroll actions. Existing compact `RowAction` supplies the minimum touch target. Refresh shop remains accessible as a quiet header action.
- Home reuses the existing `Display` metric size instead of the oversized hero size for weekly visits and existing body/section tokens for supporting text. No bell, new banner or new metric appears. Shared Home previews remain two, with a shorter visible body preview; opening a card/full list retains existing complete text and lifecycle.
- Product cards retain the full product name, actual category, honest photo/placeholder, availability, prominent existing-primary price and reachable Reserve action. Supporting service cards remain compact.

Independent visible tests may import current public declarations, existing UI interfaces and visible fixture harnesses, but must not read the Home/Shop implementation or holdout suites. Test-first evidence precedes reference-layout source refinements.

## Device label fit refinement

The first five-tab desk capture exposed a truncated Follow-ups label at the OnePlus default text scale. Under NAVC-012, primary labels retain their complete canonical titles, use the existing eyebrow-size token and medium font, and render through native Text with one line and adjustsFontSizeToFit enabled. Font scaling stays enabled. Fitting is confined to the label's own tab width; existing colors, icons, touch targets, routes and role rules stay unchanged. Independent rendered tests precede the change; fresh OnePlus default and 1.3 text-scale captures must verify visual fit, with the original scale restored afterward.
