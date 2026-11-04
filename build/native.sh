#!/bin/bash
# native.sh <outdir>  - build the readers ON the machine that runs them: macOS, FreeBSD, OpenBSD, NetBSD
# (the Linux release builds use Dockerfile.release, Windows build/windows.sh). WiredTiger 11.3 (mongod
# 4.4 - 8.0) and 3.1 (mongod 3.2 - 4.2); whichever does not build is left out, with the tail of its log
# in the output, and wt says so when it meets data it has no reader for. Layout as in the Linux
# tarballs: <outdir>/<lib>/wt-mongo-dump and <outdir>/<lib>/lib/*, found through @loader_path / $ORIGIN.
set -u
here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$1"; export WT_OUT; WT_OUT="$(cd "$1" && pwd)"
export WT_READER="$here/wt-mongo-dump.c"
WORKROOT="${WT_WORKROOT:-$(mktemp -d)}"
case "$(uname -s)" in
  Darwin)
    export WT_SO=dylib WT_RPATH='@loader_path/lib'
    # Homebrew's libraries (snappy, zstd); zlib is in the SDK
    for p in /opt/homebrew /usr/local; do [ -d "$p/include" ] && WT_CMAKE_PREFIX="${WT_CMAKE_PREFIX:+$WT_CMAKE_PREFIX;}$p"; done
    export WT_CMAKE_PREFIX
    export CPATH="${CPATH:-}:/opt/homebrew/include:/usr/local/include" LIBRARY_PATH="${LIBRARY_PATH:-}:/opt/homebrew/lib:/usr/local/lib"
    ;;
  *)
    export WT_SO=so WT_RPATH='$ORIGIN/lib'
    for p in /usr/local /usr/pkg; do [ -d "$p/include" ] && WT_CMAKE_PREFIX="${WT_CMAKE_PREFIX:+$WT_CMAKE_PREFIX;}$p"; done
    export WT_CMAKE_PREFIX
    export CPATH="${CPATH:-}:/usr/local/include:/usr/pkg/include" LIBRARY_PATH="${LIBRARY_PATH:-}:/usr/local/lib:/usr/pkg/lib"
    ;;
esac
export CC="${CC:-cc}"
WT_WORK="$WORKROOT/wt11" WT_LOG="$WORKROOT/build-11.3.log" bash "$here/build/try.sh" 11.3 "$here/build/w11.sh"
WT_WORK="$WORKROOT/wt31" WT_LOG="$WORKROOT/build-3.1.log" bash "$here/build/try.sh" 3.1 "$here/build/w31.sh"
cp "$here/wt.mjs" "$WT_OUT/wt.mjs"
# a platform where neither built is a failed build, not a platform without a reader
if [ -x "$WT_OUT/11.3/wt-mongo-dump" ] || [ -x "$WT_OUT/3.1/wt-mongo-dump" ]; then
  echo "native.sh: readers: $(cd "$WT_OUT" && ls -d */ 2>/dev/null | tr -d '/' | tr '\n' ' ')"
  exit 0
fi
echo "native.sh: no reader built" >&2
exit 1
