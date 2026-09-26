#!/usr/bin/env bash
# Every rule IR-1..IR-N appears exactly once as a rule heading. Numbers are
# cited by history elsewhere, so a gap or a duplicate is a defect.
set -eu
rules=$(cd "$(dirname "$0")/.." && pwd)/plugins/rust-house-style/docs/rules.md
last=48
found=$(grep -oE '^- \*\*IR-[0-9]+\*\*' "$rules" | grep -oE '[0-9]+' | sort -n)
want=$(seq 1 "$last")
if [ "$found" = "$want" ]; then
  echo "ok    IR-1..IR-$last, once each"
else
  echo "FAIL  rule numbering differs from IR-1..IR-$last:"
  diff <(echo "$want") <(echo "$found") || true
  exit 1
fi
