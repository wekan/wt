#!/bin/bash
# stub-platform.sh - a platform with no readers (32-bit ARM) still gets a tarball, and wt says plainly
# what it cannot do there (build/stub.sh). Needs only node.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

bash "$HERE/build/stub.sh" "$W/out" >/dev/null 2>&1 && [ -f "$W/out/wt.mjs" ] && [ -f "$W/out/README-no-readers.txt" ] \
  && ok "the stub holds wt.mjs and an explanation" || bad "the stub is incomplete"
[ -z "$(ls -d "$W"/out/*/ 2>/dev/null)" ] && ok "negative: the stub has no reader directory (none can exist)" || bad "the stub contains a reader"

# a WiredTiger directory such as a copy brought from a 64-bit machine
mkdir -p "$W/db"
printf 'WiredTiger version string\nWiredTiger 11.2.0: (November 10, 2022)\nWiredTiger version\nmajor=11,minor=2,patch=0\n' > "$W/db/WiredTiger.turtle"
WT_HOME="$W/out" node "$W/out/wt.mjs" detect "$W/db" | grep -q '"mongod": "7.0"' && ok "detect still identifies the files as mongod 7.0" || bad "detect does not identify the files"
out="$(WT_HOME="$W/out" node "$W/out/wt.mjs" dump "$W/db" "$W/dump" 2>&1)"; rc=$?
[ $rc -ne 0 ] && echo "$out" | grep -q "has no reader 11.3" && ok "dump says there is no reader on this platform, and fails" || { bad "dump did not say so (rc=$rc): $out"; }

# the workflows build nothing for a stub platform
for wf in release-all release-all-missing; do
  f="$HERE/.github/workflows/$wf.yml"
  grep -q 'linux-armv7.*stub' "$f" && ok "$wf.yml: armv7 is a stub" || bad "$wf.yml: armv7 is not a stub"
  ! grep -q 'linux/arm/v7' "$f" && ok "negative: $wf.yml no longer builds armv7 in a 32-bit container" || bad "$wf.yml still builds armv7"
done
exit $fail
