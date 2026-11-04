#!/bin/bash
# WiredTiger 2.5 (mongod 3.0): autotools, x86_64 only in practice. See w11.sh.
set -euo pipefail
BRANCH="${1:-mongodb-3.0}"
git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger /wt
cd /wt
# WT_LOGSLOT asks for cache-line alignment that a current GCC refuses; it is only a performance hint
sed -i 's/typedef WT_COMPILER_TYPE_ALIGN(WT_CACHE_LINE_ALIGNMENT) struct {/typedef struct {/' src/include/log.h
mkdir -p /out/2.5/lib; cd build_posix
sh reconf > /build.log 2>&1
../configure --enable-snappy --enable-zlib --disable-python CFLAGS="-O2 -Wno-error" >> /build.log 2>&1
make -j4 libwiredtiger.la >> /build.log 2>&1
make -j4 -C ext/compressors/snappy >> /build.log 2>&1
make -j4 -C ext/compressors/zlib >> /build.log 2>&1
cp -a .libs/libwiredtiger*.so* /out/2.5/lib/
cp -L ext/compressors/snappy/.libs/libwiredtiger_snappy.so ext/compressors/zlib/.libs/libwiredtiger_zlib.so /out/2.5/lib/
gcc -O2 -Wall -I. -o /out/2.5/wt-mongo-dump /src/wt-mongo-dump.c -L/out/2.5/lib -lwiredtiger -Wl,-rpath,'$ORIGIN/lib'
