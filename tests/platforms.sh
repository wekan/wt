#!/bin/bash
# platforms.sh - platforms.json, the one list of platforms, agrees with node-patches' platform names, with the
# workflow that builds them and with the scripts each mode runs. Needs node and jq.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$HERE"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }

# the platforms wekan/node-patches builds Node.js for; wt keeps the names so WeKan fetches wt-<platform>
# and node-<platform> with one vocabulary
node_patches="i386 armv6 armhf armv7 loong64 x64 arm64 ppc64le s390x riscv64 win64 win-arm64 mac-x64 mac-arm64 freebsd-x64 openbsd-x64 openbsd-arm64 netbsd-x64 android-arm64 android-armv7 android-x64 android-x86 win32"
have="$(jq -r '.[].platform' platforms.json | sort | tr '\n' ' ')"
want="$(echo $node_patches | tr ' ' '\n' | sort | tr '\n' ' ')"
[ "$have" = "$want" ] && ok "platforms.json lists exactly node-patches' 23 platforms" || bad "platforms differ from node-patches': have [$have] want [$want]"
[ "$(jq -r '.[].platform' platforms.json | sort | uniq -d | wc -l | tr -d ' ')" = 0 ] && ok "negative: no platform is listed twice" || bad "a platform is listed twice"

modes="docker mac windows freebsd openbsd netbsd stub"
for m in $(jq -r '.[].mode' platforms.json | sort -u); do
  echo " $modes " | grep -q " $m " && grep -q "matrix.mode == '$m'" .github/workflows/build.yml && ok "mode $m has a build step in build.yml" || bad "mode $m has no build step in build.yml"
done
jq -e 'all(.[]; has("platform") and has("mode") and has("runner"))' platforms.json >/dev/null && ok "every entry has platform, mode and runner" || bad "an entry lacks platform, mode or runner"
jq -e 'all(.[] | select(.mode == "docker"); has("docker"))' platforms.json >/dev/null && ok "every docker platform names its container platform" || bad "a docker platform has no docker field"
jq -e 'all(.[] | select(.mode == "openbsd"); has("vm_arch"))' platforms.json >/dev/null && ok "every OpenBSD platform names its VM architecture" || bad "an OpenBSD platform has no vm_arch"
# WiredTiger builds with MSVC for x64 only; win-arm64 ships the x64 build, which Windows on ARM runs (.tools/log/wt1)
jq -e 'all(.[] | select(.mode == "windows"); .arch == "x64")' platforms.json >/dev/null && ok "every Windows platform builds x64" || bad "a Windows platform asks MSVC for an arch WiredTiger does not build"
jq -e '.[] | select(.platform == "win-arm64") | .runner == "windows-11-arm"' platforms.json >/dev/null && ok "win-arm64 still runs on an ARM runner, so its smoke test runs the x64 build there" || bad "win-arm64 is not tested on ARM"

# what can have no reader is a stub, with a reason build/stub.sh knows
for r in $(jq -r '.[] | select(.mode == "stub") | .reason' platforms.json | sort -u); do
  T="$(mktemp -d)"; bash build/stub.sh "$T/o" "$r" >/dev/null 2>&1 && ok "stub reason '$r' is one stub.sh knows" || bad "stub reason '$r' is unknown to stub.sh"; rm -rf "$T"
done
# every 32-bit platform is a stub: WiredTiger needs 64 bits
for p in i386 armv6 armhf armv7 win32 android-armv7 android-x86; do
  [ "$(jq -r --arg p "$p" '.[] | select(.platform == $p) | .mode' platforms.json)" = stub ] && ok "32-bit $p is a stub" || bad "32-bit $p is not a stub"
done
# negative: the 64-bit platforms WiredTiger supports are not stubs
for p in x64 arm64 s390x ppc64le riscv64 mac-x64 mac-arm64 win64 win-arm64 freebsd-x64 openbsd-x64 openbsd-arm64 netbsd-x64; do
  [ "$(jq -r --arg p "$p" '.[] | select(.platform == $p) | .mode' platforms.json)" != stub ] && ok "negative: 64-bit $p is built, not a stub" || bad "64-bit $p is a stub"
done
# the platforms nobody has built WiredTiger on may fail without failing the run
for p in mac-x64 mac-arm64 win64 win-arm64 freebsd-x64 openbsd-x64 openbsd-arm64 netbsd-x64; do
  [ "$(jq -r --arg p "$p" '.[] | select(.platform == $p) | .best_effort // false' platforms.json)" = true ] && ok "$p is best effort" || bad "$p is not best effort"
done
# the Linux ones are not: a failure there is a real failure
for p in x64 arm64 s390x ppc64le riscv64; do
  [ "$(jq -r --arg p "$p" '.[] | select(.platform == $p) | .best_effort // false' platforms.json)" = false ] && ok "negative: $p is not best effort" || bad "$p is best effort"
done

# the workflows read the one list; neither repeats it
for wf in build release-all release-all-missing; do
  f=".github/workflows/$wf.yml"
  ../pyyaml-venv/bin/python -c "import yaml,sys; yaml.safe_load(open('$f'))" 2>/dev/null && ok "$wf.yml parses" || bad "$wf.yml does not parse"
done
! grep -qE 'linux/(amd64|arm64|s390x)' .github/workflows/release-all.yml .github/workflows/release-all-missing.yml && ok "negative: the entry workflows do not repeat the platform list" || bad "an entry workflow still lists platforms"
grep -q 'uses: ./.github/workflows/build.yml' .github/workflows/release-all.yml && grep -q 'uses: ./.github/workflows/build.yml' .github/workflows/release-all-missing.yml && ok "both entry workflows call build.yml" || bad "an entry workflow does not call build.yml"

# the scripts each mode runs exist, parse, and are executable
for s in build/native.sh build/windows.sh build/stub.sh build/w11.sh build/w31.sh build/w25.sh build/try.sh; do
  [ -f "$s" ] && bash -n "$s" && ok "$s parses" || bad "$s is missing or does not parse"
done
# the reader builds without a compiler for the host: it must stay portable C
grep -q '_mkdir' wt-mongo-dump.c && ok "the reader has the Windows mkdir" || bad "the reader cannot create directories on Windows"
exit $fail
