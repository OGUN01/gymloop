# Classes wall-clock date boundary

Status: proposed owner decision; affected date-boundary implementation and tests
remain paused until the owner chooses the behavior.

A fresh blind critic found that PostgreSQL accepts `time '24:00'`, resolving a
requested day to midnight on the following day. The draft stores the requested
day unchanged, contradicting CLS-006/026 and making membership and holiday checks
use the wrong day. Weekly rule identity also fixes its session date, so silently
moving such an occurrence to another weekday cannot satisfy both clauses.

Recommended amendment: class start wall times are `00:00:00` inclusive through
`24:00:00` exclusive. Owner/manager rule creation and one-off creation/edit reject
`24:00` with `22023`, atomically and after ordinary actor validation. Store the
resolved branch-local start date and require it to match the requested date;
reject any explicit edit that would move a rule occurrence to another day. The
generator skips a local occurrence whose resolved start belongs to another date,
preserving its existing no-error-on-data-conditions requirement. It does not
create a next-day occurrence under an earlier date or rule weekday. Normal DST
gap/overlap resolution remains PostgreSQL `AT TIME ZONE`; crossing midnight at the
end of a session still belongs to its start date. No booking/money/permission
change is authorized.

Alternative owner decision: support `24:00` as the following day's midnight.
That needs a revised weekly occurrence identity, weekday, validity and holiday
contract before separate tests and implementation; it cannot be a source-only
date substitution.

For the recommended boundary, separate visible and holdout authors add exact
midnight/end-of-day and refusal/no-effect cases before the isolated source fix.
A fresh blind critic then reviews the frozen public wording and final source;
the complete rollback sweep and later real browser/native timetable evidence
remain mandatory.
