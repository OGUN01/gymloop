"""Pass/fail for one pgTAP file, in a way that can actually report a failure.

THE BUG THIS EXISTS TO NOT HAVE, because it cost six red CI runs I believed
were green:

    `supabase db query` returns only the LAST result set THAT HAS ROWS.
    On a passing file `finish()` returns no rows, so a `num_failed()` placed
    before it is what comes back.  On a FAILING file `finish()` emits its
    "# Looks like you failed N tests" diagnostic row — which shadows
    `num_failed()` entirely.

So the previous version of this script could only ever observe passes. A
failing file produced no matching output at all, its name was printed with no
result beside it, and the next file's name landed on the same line and donated
its result. The report said 42 files, all green, for a run in which one file
had failed and one had been swallowed.

**A checker whose failure mode is silence is worse than no checker**, because
it manufactures confidence. The fix is to stash the count in a temp table
before `finish()` (which drops the table `num_failed()` reads) and select it
back AFTER `finish()`, so the count is the last rows on the wire no matter
which way the file went.

usage: sweep.py <test.sql> <out.sql> [migration.sql ...]
"""
import io
import sys

test = io.open(sys.argv[1], encoding='utf-8').read()
migrations = ''.join(io.open(p, encoding='utf-8').read() + '\n' for p in sys.argv[3:])

marker = '\nbegin;\n'
i = test.index(marker) + len(marker)
spliced = test[:i] + '\n' + migrations + '\n' + test[i:]

# Anchored to a whole line and taking the LAST match: at least one file quotes
# `select * from finish();` inside its header comment, and a plain replace hit
# that copy and produced a syntax error indistinguishable from a broken test.
lines = spliced.split('\n')
hits = [n for n, line in enumerate(lines) if line.strip() == 'select * from finish();']
assert hits, sys.argv[1]

# **`num_failed()` alone cannot see a PLAN MISMATCH**, and a mismatch is how a
# file silently runs fewer assertions than it declares. pgTAP's own test
# counter is `__tresults___numb_seq`; capturing it beside the failure count
# turns 'planned 757, ran 756' from something only a second harness noticed
# into something this one reports. Found when `tapcount.py` -- a DIFFERENT
# script -- reported 756 of a planned 757 and this one reported zero
# failures, and neither was wrong: one assertion is written
# `with u as (...) select is(...) from c`, which tapcount's line anchor does
# not match. The suite was fine; both harnesses were partly blind.
lines.insert(hits[-1], "create temp table _sweep as select num_failed() as failures, "
                       "pg_catalog.currval('__tresults___numb_seq') as ran;")
lines.insert(hits[-1] + 2, 'select failures, ran from _sweep;')
io.open(sys.argv[2], 'w', encoding='utf-8', newline='\n').write('\n'.join(lines))
