#!/usr/bin/env bash
# Runs the file-size workflow's own check step against scratch git repos.
# The step is lifted out of the workflow, so this tests the code CI runs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

python3 - "$root/.github/workflows/file-size.yml" "$work/check.py" <<'PY'
import sys
import yaml

steps = yaml.safe_load(open(sys.argv[1]))["jobs"]["file-size"]["steps"]
step = next(s for s in steps if s.get("name") == "Check file sizes")
open(sys.argv[2], "w").write(step["run"])
PY

pass=0
fail=0

# lines <n> <path>: write a .rs file of exactly n lines.
lines() { mkdir -p "$(dirname "$2")"; awk -v n="$1" 'BEGIN { for (i = 1; i <= n; i++) print "// line " i }' > "$2"; }

# scenario <name> <expected exit> <expected output pattern> <setup function> [ENV=value ...]
scenario() {
  local name=$1 want=$2 pattern=$3 setup=$4
  shift 4
  local repo="$work/repo"
  rm -rf "$repo"
  mkdir -p "$repo"
  (
    cd "$repo" || exit 1
    git init -q
    "$setup"
    git add -A
    env EXCLUDE="" BASELINE=".github/rust-file-size-baseline.txt" RATCHET=false "$@" python3 "$work/check.py"
  ) > "$work/out" 2>&1
  local got=$?
  if [ "$got" = "$want" ] && grep -Eq -- "$pattern" "$work/out"; then
    pass=$((pass + 1))
    echo "ok    $name"
  else
    fail=$((fail + 1))
    echo "FAIL  $name (exit $got, wanted $want, pattern /$pattern/)"
    sed 's/^/        /' "$work/out"
  fi
}

baseline() { mkdir -p .github; printf '%s\n' "$@" > .github/rust-file-size-baseline.txt; }

s_clean()          { lines 999 src/a.rs; }
s_exactly_limit()  { lines 1000 src/a.rs; }
s_scratch_over()   { lines 1001 src/scratch.rs; }
s_unterminated()   { lines 1000 src/a.rs; printf 'tail' >> src/a.rs; }
s_not_rust()       { lines 2000 README.md; lines 5 src/a.rs; }
s_at_ceiling()     { lines 1030 src/big.rs; baseline '# tracked in #1' '1030 src/big.rs'; }
s_shrunk()         { lines 1010 src/big.rs; baseline '1030 src/big.rs'; }
s_grew()           { lines 1031 src/big.rs; baseline '1030 src/big.rs'; }
s_under_limit()    { lines 900 src/big.rs; baseline '1030 src/big.rs'; }
s_stale()          { lines 5 src/a.rs; baseline '1030 src/gone.rs'; }
s_baseline_other() { lines 1030 src/big.rs; lines 1001 src/scratch.rs; baseline '1030 src/big.rs'; }
s_excluded()       { lines 1500 src/generated/api.rs; }
s_exclude_scoped() { lines 1500 src/generated/api.rs; lines 1500 src/handwritten.rs; }
s_bad_baseline()   { lines 5 src/a.rs; baseline 'lots src/a.rs'; }
s_spaces()         { lines 1030 "src/my file.rs"; baseline '1030 src/my file.rs'; }

scenario "clean repo passes"                          0 'checked 1 \.rs files, 0 over'  s_clean
scenario "exactly 1000 lines passes"                  0 '0 over'                        s_exactly_limit
scenario "scratch file over 1000 lines FAILS"         1 'error file=src/scratch.rs.*1001 lines, over 1000' s_scratch_over
scenario "unterminated last line counts"              1 '1001 lines, over 1000'         s_unterminated
scenario "only .rs files are counted"                 0 'checked 1 \.rs files'          s_not_rust
scenario "baseline file at its entry passes"          0 '1 over 1000, 1 baselined'      s_at_ceiling
scenario "baseline file that shrank passes"           0 'notice.*Lower the entry to 1010' s_shrunk
scenario "baseline file that GREW FAILS"              1 'error file=src/big.rs.*1031 lines, but .* allows 1030' s_grew
scenario "baseline file under the limit passes"       0 'notice.*Remove it from'        s_under_limit
scenario "ratchet fails a shrunk baseline entry"      1 'error.*Lower the entry to 1010' s_shrunk RATCHET=true
scenario "ratchet fails a file now under the limit"   1 'error.*Remove it from'         s_under_limit RATCHET=true
scenario "stale entry passes with a notice"           0 'notice.*Remove the entry'      s_stale
scenario "ratchet fails a stale entry"                1 'error.*Remove the entry'       s_stale RATCHET=true
scenario "baseline does not shelter another file"     1 'error file=src/scratch.rs'     s_baseline_other
scenario "excluded generated file passes"             0 'checked 0 \.rs files'          s_excluded EXCLUDE='**/generated/*.rs'
scenario "exclusion is scoped to its glob"            1 'error file=src/handwritten.rs' s_exclude_scoped EXCLUDE='**/generated/*.rs'
scenario "several exclude globs, one per line"        0 'checked 0 \.rs files'          s_excluded EXCLUDE=$'src/nothing/*.rs\n**/generated/*.rs'
scenario "malformed baseline line fails"              1 'expected `<lines> <path>`'     s_bad_baseline
scenario "path with a space"                          0 '1 baselined'                   s_spaces
scenario "missing baseline file is empty"             1 'treating it as empty'          s_scratch_over BASELINE=nope.txt

echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
