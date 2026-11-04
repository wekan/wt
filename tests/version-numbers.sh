#!/bin/bash
# version-numbers.sh - wt releases are v0.01, v0.02, ... (two-digit minor), and v0.99 is followed by v1.00.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
. "$HERE/releases/lib.sh"
fail=0
eq() { [ "$2" = "$3" ] && echo "PASS $1: $2" || { echo "FAIL $1: got '$2', wanted '$3'"; fail=1; }; }
eq "the first release"            "$(bump_version)"       v0.01
eq "the second"                   "$(bump_version v0.01)" v0.02
eq "08 and 09 are decimal"        "$(bump_version v0.08)" v0.09
eq "09 -> 10"                     "$(bump_version v0.09)" v0.10
eq "10 -> 11"                     "$(bump_version v0.10)" v0.11
eq "99 rolls the major"           "$(bump_version v0.99)" v1.00
eq "1.00 -> 1.01"                 "$(bump_version v1.00)" v1.01
for ok in v0.01 v0.02 v0.99 v1.00 v12.34; do valid_version "$ok" 2>/dev/null && echo "PASS valid: $ok" || { echo "FAIL valid: $ok"; fail=1; }; done
for bad in v1.0 v0.1 0.01 v0.001 v0 latest "v0.01 "; do valid_version "$bad" 2>/dev/null && { echo "FAIL negative: '$bad' accepted"; fail=1; } || echo "PASS negative: '$bad' refused"; done
# the order is numeric, so v0.10 is after v0.09 and v0.99 after v0.100's predecessors
eq "sort -V orders them"          "$(printf 'v0.10\nv0.02\nv0.09\nv0.01\n' | sort -V | tr '\n' ' ')" "v0.01 v0.02 v0.09 v0.10 "
exit $fail
