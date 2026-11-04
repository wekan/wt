#!/bin/bash
# WiredTiger 3.1 (mongod 3.2 - 4.2): autotools. See w11.sh for why this is its own process.
set -euo pipefail
BRANCH="${1:-mongodb-4.0}"
git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger /wt
mkdir -p /out/3.1/lib; cd /wt/build_posix
sh reconf > /build.log 2>&1
../configure --enable-snappy --enable-zlib --disable-python CFLAGS="-O2 -Wno-error" >> /build.log 2>&1
make -j4 >> /build.log 2>&1
cp -a .libs/libwiredtiger*.so* /out/3.1/lib/
cp -L ext/compressors/snappy/.libs/libwiredtiger_snappy.so ext/compressors/zlib/.libs/libwiredtiger_zlib.so /out/3.1/lib/
gcc -O2 -Wall -I. -o /out/3.1/wt-mongo-dump /src/wt-mongo-dump.c -L/out/3.1/lib -lwiredtiger -Wl,-rpath,'$ORIGIN/lib'
