# Rollback guard quoted-content repair

Frozen engineering contract, 2026-10-03. Preserves ADR-030 and the existing
registered `findNonRolledBackTests(files)` export in
`scripts/check-pgtap-rollback.mjs`. No database/business/API rule change.

The existing public input is `[{path:string, content:string}]`; output is an
array of `{path, reason}`. Retain existing reasons and transaction refusals:
first substantive command BEGIN or START TRANSACTION; last ROLLBACK; refuse
top-level COMMIT/END and the existing conservative COMMIT-in-body boundary.

Before identifying dollar bodies, semicolon boundaries or SQL comments, consume
single-quoted literals (doubled quotes), explicit E strings (backslash escapes),
and double-quoted identifiers (doubled double quotes) according to the project's
standard-conforming SQL profile. Dollar signs, semicolons and comment-looking
text inside those tokens have no structural effect. Recognize empty and named
dollar tags including valid digits after the first identifier character and
non-Latin identifier letters. Exact closing tags remain case-sensitive.
Ignore actual line/block comments, including nested block comments, without
removing content from quoted tokens. Unterminated constructs fail closed.
Actual COMMIT hidden by quoted decoys still refuses; actual body commits remain
refused. This is a static guard, not execution or arbitrary SQL interpretation.

The same lexical boundary includes newline-separated string continuation:
whitespace/comments containing a newline may join successive single-quoted
segments. An initial E prefix supplies escape semantics to every joined segment;
only that first segment needs the prefix. Retain this state through the entire
chain, then reset it at an intervening substantive token or statement boundary.
Comment-looking text inside a continued escaped literal stays quoted, and a real
completion command following the chain must remain visible to the guard.

Examples independently generated for this contract include a SELECT literal
`'demo$sha256$active$location$0001'`, a literal containing `; -- /*`, a quoted
identifier containing a dollar-tag-looking substring, an E literal with an
escaped quote, and a legal `$batch2$` or non-Latin-tagged DO body. These wrapped
rollback-only inputs must not acquire an invented executable COMMIT or lose
their final ROLLBACK. Add real COMMIT/END outside the token and refuse it.

Separate implementation-blind visible and holdout authors commit targeted
cases before the separate source builder, then a fresh source critic and
existing regression checks. No parser ignore or transaction exception.
Lexical reference: [PostgreSQL lexical structure](https://www.postgresql.org/docs/current/sql-syntax-lexical.html).
