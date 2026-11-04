#!/bin/bash
# run-reader.sh <tag> <dbpath> <outdir> [flags]   - run the reader built for image wt-build:<tag>
set -eu
T="$1"; DB="$2"; OUT="$3"; shift 3
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/reader-$T.env"
docker run --rm -v "$HERE:/w" -v "$DB:/src" wt-build:$T bash -c "export WT_EXTENSIONS='$EXTS' LD_LIBRARY_PATH='$LIBDIR'; /w/wt-mongo-dump-$T $* /src /w/out/$OUT"
