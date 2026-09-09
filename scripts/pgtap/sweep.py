"""Run every pgTAP file against Cloud and decide GREEN per file.

**This lives in the repository, not in a session scratchpad.** It sat in the
OS temp directory for five critic rounds, where no future session and no CI job
could read it — a checker nobody else can run is a procedure somebody remembers,
which is the exact failure ADR-104 is about, one level up (ADR-105).

CI catches a plan shortfall independently: `db.yml`'s `pgtap` job runs
`supabase test db`, which is pg_prove, which fails on a TAP plan mismatch. This
is the local pre-push equivalent, and the two agreeing is the point.

**GREEN requires `failures = 0` AND `ran = plan(N)`** (ADR-104). `num_failed()`
alone returns zero for a file that runs FEWER assertions than it declared, which
is how a suite quietly stops testing things — an early return, a DO block that
swallows, an assertion form the file's own harness does not recognise.

The plan/ran comparison lives HERE rather than in `splice.py`, which only
rewrites one file and has no opinion about pass or fail. A fourth critic pointed
out that ADR-104 credited the tool with a check the runner performs, which is
the same gap in kind as the one that ADR is about — so the check is written
down where it actually happens.

Replaces sweep.sh, which spliced `num_failed()` BEFORE `finish()` and could
therefore only ever observe passes (ADR-073). It sat on disk looking superseded
for twenty rounds; a critic found it there.

usage: python scripts/pgtap/sweep.py <outdir> [migration.sql ...]   (run from the repo root)
"""
import glob, io, json, os, re, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
outdir = sys.argv[1]
migrations = sys.argv[2:]
os.makedirs(outdir, exist_ok=True)

green = fails = 0
total = 0
for f in sorted(glob.glob('supabase/tests/*.sql')) + sorted(glob.glob('supabase/tests-holdout/*.sql')):
    b = os.path.splitext(os.path.basename(f))[0]
    run = os.path.join(outdir, b + '_run.sql')
    subprocess.run([sys.executable, os.path.join(HERE, 'splice.py'), f, run] + migrations, check=True)
    raw = subprocess.run(['supabase', 'db', 'query', '--linked', '-f', run],
                         capture_output=True, text=True, shell=True).stdout
    planned = int(re.search(r'select\s+plan\((\d+)\)', io.open(f, encoding='utf-8').read()).group(1))
    try:
        d = json.loads(raw)
        if d.get('_tag') == 'Error':
            print(f'ERROR {b} {d["error"]["message"][:110]}'); fails += 1; continue
        r = d['rows'][0]
    except Exception as e:
        print(f'ERROR {b} {e!r}'); fails += 1; continue
    ok = r['failures'] == 0 and r['ran'] == planned
    print(f'{"GREEN" if ok else "FAIL "} {b} planned={planned} ran={r["ran"]} failures={r["failures"]}')
    green += ok; fails += (not ok); total += r['ran']

print(f'=== {green} green, {fails} not green, {total} assertions ===')
