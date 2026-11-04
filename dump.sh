#!/bin/bash
# dump.sh <mongo version>  - reads data/<version> with the WiredTiger that wrote it.
# 3.0 -> WiredTiger 2.5 (no readonly mode: reads a COPY), 3.2 - 4.2 -> WiredTiger 3.1,
# 4.4 - 8.0 -> WiredTiger 11.3. Output goes to out/<version>/.
set -eu
V="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
case "$V" in 3.0*) L=3.0; COPY=1;; 3.2*|3.4*|3.6*|4.0*|4.2*) L=4.0; COPY=0;; *) L=8.0; COPY=0;; esac
. "$HERE/reader-$L.env"
rm -rf "$HERE/out/$V"
if [ "$COPY" = 1 ]; then
  docker run --rm -v "$HERE:/w" -v "$HERE/data/$V:/src:ro" wt-build:$L bash -c "export WT_EXTENSIONS='$EXTS' LD_LIBRARY_PATH='$LIBDIR'; cp -a /src /copy; /w/wt-mongo-dump-$L --allow-recovery /copy /w/out/$V" 2>&1 | grep -v WARNING
else
  "$HERE/run-reader.sh" "$L" "$HERE/data/$V" "$V" 2>&1 | grep -v "WARNING"
fi
echo "dumped $V with WiredTiger lib $L: $(grep -c . "$HERE/out/$V/_manifest.tsv") collections"
