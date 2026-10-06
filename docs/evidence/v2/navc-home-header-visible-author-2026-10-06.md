# Independent Home-header regression author

Author: `/root/nav_home_header_visible_author`, 2026-10-06.

The author read NAVC-012 in the approved native-member-discovery spec, the frozen Home-header seam in `openspec/changes/v2-native-navigation/design.md` (contract commit `45ccf934`), registered `UI_TOKENS` declarations, and the existing visible rendered Home harness. The author did not read production Home/component bodies, holdout tests, or implementation notes, and changed no production file.

Two focused cases were added to `apps/mobile/app/__tests__/navc-home-context-visible.test.tsx`. They use a long business/branch fixture (`IronBox Fitness · Vijay Nagar`) and a 1.35 font-scale fixture, resolve the documented React Native Pressable style callback with `{ pressed: false }`, and reuse the registered touch-size token.

Before implementation, `pnpm --filter @gymloop/mobile test -- app/__tests__/navc-home-context-visible.test.tsx` produced **19 passing / 1 failing out of 20** on 2026-10-06 at 13:04 IST (5.23 s). The new layout case failed for two contract conditions: the business target lacks `flex: 1` / `minWidth: 0`, and the token-sized 48-by-48 You target lacks `flexShrink: 0`. The existing target dimensions were already correct.

The second new case passes preservation of complete business/branch text and the full member's accessible You label, one-line visual business text with normal font scaling permitted, and the canonical business-hub/You destinations. The host harness establishes the layout contract; actual large-text device geometry remains the independent device check.

Scoped ESLint for the changed visible test and the mobile TypeScript check both pass.

No commit or push was performed by this author. Root must commit this red test unit before applying the layout fix.
