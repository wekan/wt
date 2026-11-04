#!/bin/bash
# build-reader.sh <tag>   - compile wt-mongo-dump against the WiredTiger of image wt-build:<tag>
# and record where its compressor extensions are (reader-<tag>.env), for run-reader.sh.
set -eu
T="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
docker run --rm -v "$HERE:/w" "wt-build:$T" bash -c '
set -e
if [ -d /wt-src/build_posix ]; then
  LIBDIR=/wt-src/build_posix/.libs; INC=/wt-src/build_posix
  EXTS=$(ls /wt-src/build_posix/ext/compressors/{snappy,zlib}/.libs/libwiredtiger_*.so 2>/dev/null | paste -sd, -)
else
  LIBDIR=/wt-src/build; INC=/wt-src/build/include
  EXTS=$(ls /wt-src/build/ext/compressors/*/libwiredtiger_*.so | paste -sd, -)
fi
gcc -O2 -Wall -I$INC -o /w/wt-mongo-dump-'$T' /w/wt-mongo-dump.c -L$LIBDIR -lwiredtiger -Wl,-rpath,$LIBDIR
echo "LIBDIR=$LIBDIR" > /w/reader-'$T'.env; echo "EXTS=$EXTS" >> /w/reader-'$T'.env'
