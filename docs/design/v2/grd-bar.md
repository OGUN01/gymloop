# GRD quality bar — guardian and minor protection

Fetched 2026-10-02. Applies to GRD-001…028 and authoritative batch-2 decisions. Public documents support the documented interaction, not a native UI pass. Contract writer is distinct from test authors; every batch-2 contract and bar freezes before tests.

## Fetchable references

[Google Family Link: consent and supervision](https://support.google.com/families/answer/9499456) identifies the consenting parent, parent account used at setup, review of consequences, and limits of supervision. Adopt consequence-first language and explicit confirmation. It does not establish the legality of gym scoring or verify Gymloop's consent mechanism.

[MeitY official Gazette: DPDP Act 2023](https://www.meity.gov.in/static/uploads/2024/02/Digital-Personal-Data-Protection-Act-2023-1.pdf), section 9, PDF page 8, separates verifiable parental consent from restrictions on child monitoring and permits prescribed exemptions. This is legal context, not a visual comparator or proof of compliance. Qualified review remains unresolved in ADR-168/178.

## Testable criteria

| Criterion | Pass condition | Verification |
|---|---|---|
| GRD-Q1 consequences | Exact scoring sentences; attested legacy member retains unknown age and shows attestation note. No blame or raw code. | Rendered app states |
| GRD-Q2 consent | Checkbox and source required; withdrawal confirmed; no optimistic eligibility. Known-minor form is inline: checkbox → source → Record, three interactions from open member page; withdrawal requires at most two. | Count actual required interactions; no preliminary disclosure/Record consent step |
| GRD-Q3 handover | Required reason and confirm name lost guardian sign-in and retained visits/payments/history; only owner/manager for known adult linked through guardian path. | DB/app refusal matrix and focus review |
| GRD-Q4 cutoff | Null timestamp fails safe. Owner first call stamps/audits once; repeat/concurrent calls preserve it. Before/equal cutoff missing-DOB cohort scores; later cohort and known minors do not qualify. | Independent visible/holdout boundary tests |
| GRD-Q5 disclosure | Banner and coverage note remain before attestation even at zero counts; non-owner/preview cannot attest. Afterward coverage excludes attested cohort. | App states and DB count tests |
| GRD-Q6 privacy | Account collision names no other person; minor invite/contact resolves guardian; non-minor behavior unchanged. | DB and app holdouts |
| GRD-Q7 accessibility | Dot plus word, 44px targets, wrapping at large text, light/dark, reduced motion, keyboard focus returned on confirmation close. | Web axe and 390/1440 browser review |
| GRD-Q8 audience | Guardian section hidden for trainer/member; support preview read-only. | Role render and DB posture tests |

Cutoff and interaction criteria are **[own]** owner/product requirements, not Google claims. No lower bar for legacy data. Four independent authors write visible DB, holdout DB, visible app and holdout app suites; holdout authors see neither visible suites nor implementation. No Android proof is inferred from these documents.
