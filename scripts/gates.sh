#!/usr/bin/env bash
# Every gate CI runs, in one command, so "I ran the gates" means all of them.
#
# knip was missing from the list I was running by hand, and CI found an unused
# export I had already pushed. A checklist kept in a head is a checklist with a
# hole in it; this one is kept next to the thing it checks.
set -u
cd "$(git rev-parse --show-toplevel)"
fail=0
run() { printf '%-22s ' "$1"; shift; if out=$("$@" 2>&1); then echo "ok"; else echo "FAILED"; echo "$out" | tail -6; fail=1; fi; }
run "lint"            pnpm run lint
run "typecheck"       pnpm -r typecheck
run "jscpd"           pnpm run jscpd
run "knip"            pnpm run knip
run "web tests"       pnpm --filter @gymloop/web test --run
run "shared tests"    pnpm --filter @gymloop/shared test --run
run "registry-lint"   node scripts/registry-lint.mjs
run "escape-hatches"  node scripts/check-escape-hatches.mjs
run "pgtap-rollback"  node scripts/check-pgtap-rollback.mjs
echo "---"
[ "$fail" = 0 ] && echo "ALL GATES GREEN" || echo "SOME GATES RED — do not push"
exit "$fail"
