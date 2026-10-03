# Responsive console repair boundary

Frozen engineering declarations, 2026-10-03. This implements the existing
ANC-Q9 / ANC-019 accessibility and state requirements; it changes no identity,
role, publication, audience, privacy or stored history rule.

- At a 390px viewport with 200% application text, the Announcements list and
  composer must remain readable in both themes without horizontal scrolling.
  Long page headings wrap inside the available content width.
- The visible FitCruxx console wordmark and appearance controls must occupy
  separate readable areas. Controls may wrap to another row; their accessible
  names, keyboard behavior and minimum 44px targets remain intact.
- Preserve all navigation, account and role guards. Reuse the registered
  appearance component; add no new helper, dependency or exported surface.
- Preserve the status word and one accompanying visual dot for each
  announcement state. Do not hide content, clip overflow or reduce the enlarged
  text to manufacture a layout pass.

An independent visible author writes a browser regression from these public
requirements and the frozen bar. Commit its observed RED result before a
separate source implementer proceeds. Then rerun the affected browser grid,
type/lint checks and a fresh independent rendered critique. Holdout authors and
identity/claim source remain outside this presentation-only repair.
