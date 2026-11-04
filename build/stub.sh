#!/bin/bash
# stub.sh <outdir>  - the tarball content for a platform where wt cannot have a reader.
#
# WiredTiger - the storage engine every mongod since 3.2 writes its files with - requires a 64-bit
# build ("configure: error: WiredTiger requires a 64-bit build"; WiredTiger 11.3's CMake cannot even
# size a size_t there), and MongoDB never shipped a 32-bit server with WiredTiger. So on 32-bit ARM
# (armv7) there is no data to read and no reader to build. The tarball is still published, with
# wt.mjs only, so that a script which fetches wt-<platform> for every platform WeKan supports finds one
# instead of a 404, and wt says plainly what it cannot do instead of failing obscurely.
set -euo pipefail
out="$1"
here="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out"
cp "$here/wt.mjs" "$out/wt.mjs"
cat > "$out/README-no-readers.txt" <<'TXT'
This platform has no wt readers.

wt reads the raw files of a MongoDB 3.x - 8.x database through WiredTiger, and WiredTiger needs a
64-bit CPU. MongoDB never ran WiredTiger on 32-bit systems, so there is no such database to read
here. `wt detect` still identifies a copy of one, and `wt dump` says so.

If the database files come from a 64-bit machine, run wt there, or on any 64-bit Linux, and move
the .bson output.
TXT
