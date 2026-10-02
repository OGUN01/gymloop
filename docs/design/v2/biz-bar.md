# BIZ quality bar — business vocabulary

Fetched 2026-10-02. Applies to BIZ-001…022 and authoritative batch-2 decisions. All contracts and bars freeze before implementation-blind tests. Public docs are evidence of vocabulary behavior, not native UI proof.

## Fetchable reference

[Salesforce: Rename Object, Tab, and Field Labels](https://help.salesforce.com/s/articleView?id=platform.customize_rename.htm&language=en_US&type=5) describes terminology users already know, separate singular/plural forms and article handling, and surfaces retaining standard names. Adopt one consistent vocabulary map, correct grammar and explicit exceptions. Stripe/Linear dashboard candidates were not inspected and are not scored evidence.

## Testable criteria

| Criterion | Pass condition | Verification |
|---|---|---|
| BIZ-Q1 vocabulary | Exactly eight golden keys; singular class=batch for dance, class otherwise; other primitive-5 values unchanged; unknown falls back to gym. | Pure golden-table/generated-enum tests |
| BIZ-Q2 consistency | Dance Tier A text/accessibility names contain no stray gym/member/members/trainer; gym unchanged except explicit neutral rewrites. | Every Tier A rendered route and Tier B scoped audit |
| BIZ-Q3 setting | Current value and words-used preview; confirm says who sees the change and preserves plans/payments/check-ins/messages. | Complete settings state matrix |
| BIZ-Q4 interactions | Open Settings → choose → Confirm change, at most three interactions. Selection reveals inline before/after and warning; no autosave or preliminary Save. | Touch/keyboard review |
| BIZ-Q5 grammar | No a/an before place/trainer slots; singular class and plural classes use distinct keys; stored text unchanged. | Golden rows, singular/count and accessible-name tests |
| BIZ-Q6 boundaries | BIZ owns one neutral privacy/terms rewrite; integrator adds INV/STI/GRD sentences, keeps date. Platform Gym/Gyms and pinned invites stay; non-gym glyph is neutral building. | Legal/chrome exact exceptions |
| BIZ-Q7 authority | Real active owner only; platform stale/replay preserved; guarded direct writes refused; audit actor/tenant correct; other commercial behavior unchanged. | Separate visible/holdout DB authors |
| BIZ-Q8 accessibility | Radio legend, Current word, Confirm change absent until changed, focus return, status/alert, 44px targets, 200% wrapping, light/dark. No threshold changes by type. | axe/browser and rule regression |

Confirmation and the three-interaction ceiling are **[own]** requirements. The inline panel combines Save and confirm into one explicit final Confirm change; selecting a type alone never writes. Screens remain relaxed; command and guard retain visible plus independent holdout. No native pass is inferred.
