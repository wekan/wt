#!/bin/bash
# WiredTiger 11.3 (mongod 4.4 - 8.0): cmake. Runs with `bash -e`, as its own process, so a failing
# step really stops it: inside `( set -e; ... ) || fallback` bash IGNORES errexit, and a cmake that
# failed on armv7 went on to "build" a reader against a header that did not exist.
#
# In the release container the defaults below are right. On macOS and the BSDs (build/native.sh) the
# caller sets WT_OUT / WT_WORK / WT_LOG / WT_READER / WT_SO / WT_RPATH.
set -euo pipefail
BRANCH="${1:-mongodb-8.0}"
OUT="${WT_OUT:-/out}"; WORK="${WT_WORK:-/wt}"; LOG="${WT_LOG:-/build.log}"
READER="${WT_READER:-/src/wt-mongo-dump.c}"; SO="${WT_SO:-so}"; RPATH="${WT_RPATH:-\$ORIGIN/lib}"
CC="${CC:-gcc}"; JOBS="${WT_JOBS:-$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 4 )}"
[ -d "$WORK/.git" ] || git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger "$WORK"
mkdir -p "$WORK/build" "$OUT/11.3/lib"; cd "$WORK/build"
GEN=(); command -v ninja >/dev/null 2>&1 && GEN=(-G Ninja)
# `${GEN[@]+...}`: an empty array is an unbound variable to bash 3.2 (macOS) under set -u
cmake ${GEN[@]+"${GEN[@]}"} -DENABLE_SNAPPY=1 -DENABLE_ZLIB=1 -DENABLE_ZSTD=1 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Wno-error" -DENABLE_STATIC=0 -DENABLE_PYTHON=0 \
  ${WT_CMAKE_PREFIX:+-DCMAKE_PREFIX_PATH="$WT_CMAKE_PREFIX"} .. > "$LOG" 2>&1
# the compiler trips WiredTiger's own -Werror on harmless notes; strip it from whatever the generator wrote
find . \( -name build.ninja -o -name flags.make \) -exec sh -c 'sed -E "s/ -Werror(=[a-z-]+)?//g" "$1" > "$1.new" && mv "$1.new" "$1"' _ {} \;
TARGETS="wiredtiger_shared wiredtiger_snappy wiredtiger_zlib wiredtiger_zstd"
if [ -f build.ninja ]; then ninja $TARGETS >> "$LOG" 2>&1; else make -j"$JOBS" $TARGETS >> "$LOG" 2>&1; fi
cp -a libwiredtiger*."$SO"* "$OUT/11.3/lib/"
for f in ext/compressors/*/libwiredtiger_*."$SO"; do cp -L "$f" "$OUT/11.3/lib/"; done
"$CC" -O2 -Wall -Iinclude -o "$OUT/11.3/wt-mongo-dump" "$READER" -L"$OUT/11.3/lib" -lwiredtiger -Wl,-rpath,"$RPATH"
