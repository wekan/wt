#!/bin/bash
# WiredTiger 11.3 (mongod 4.4 - 8.0): cmake. Runs with `bash -e`, as its own process, so a failing
# step really stops it: inside `( set -e; ... ) || fallback` bash IGNORES errexit, and a cmake that
# failed on armv7 went on to "build" a reader against a header that did not exist.
set -euo pipefail
BRANCH="${1:-mongodb-8.0}"
git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger /wt
mkdir -p /wt/build /out/11.3/lib; cd /wt/build
cmake -G Ninja -DENABLE_SNAPPY=1 -DENABLE_ZLIB=1 -DENABLE_ZSTD=1 -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="-Wno-error" -DENABLE_STATIC=0 -DENABLE_PYTHON=0 .. > /build.log 2>&1
# the pinned compiler trips WiredTiger's own -Werror on harmless notes
sed -i -E 's/ -Werror(=[a-z-]+)?//g' build.ninja
ninja wiredtiger_shared wiredtiger_snappy wiredtiger_zlib wiredtiger_zstd >> /build.log 2>&1
cp -a libwiredtiger.so* /out/11.3/lib/
cp -L ext/compressors/*/libwiredtiger_*.so /out/11.3/lib/
gcc -O2 -Wall -Iinclude -o /out/11.3/wt-mongo-dump /src/wt-mongo-dump.c -L/out/11.3/lib -lwiredtiger -Wl,-rpath,'$ORIGIN/lib'
