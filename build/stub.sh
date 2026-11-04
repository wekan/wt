#!/bin/bash
# stub.sh <outdir> [reason]  - the tarball content for a platform where wt cannot have a reader.
#
#   32-bit    WiredTiger - the storage engine every mongod since 3.2 writes its files with - requires a
#             64-bit build ("configure: error: WiredTiger requires a 64-bit build"; WiredTiger 11.3's CMake
#             cannot even size a size_t there), and MongoDB never shipped a 32-bit server with WiredTiger.
#   android   MongoDB never ran on Android, so there is no database to read on the device itself.
#   loong64   WiredTiger has no LoongArch port (no memory barriers, no CPU support), and the platform
#             has no MongoDB either.
#
# The tarball is still published, with wt.mjs only, so that a script which fetches wt-<platform> for every
# platform WeKan supports finds one instead of a 404, and wt says plainly what it cannot do.
set -euo pipefail
out="$1"; reason="${2:-32-bit}"
here="$(cd "$(dirname "$0")/.." && pwd)"
case "$reason" in
  32-bit)  why='WiredTiger needs a 64-bit CPU, and MongoDB never ran WiredTiger on 32-bit systems, so there is no such database to read here.' ;;
  android) why='MongoDB never ran on Android, so there is no database to read on this platform.' ;;
  loong64) why='WiredTiger has no LoongArch port and MongoDB does not run on this CPU.' ;;
  *) echo "stub.sh: unknown reason '$reason'" >&2; exit 2 ;;
esac
mkdir -p "$out"
cp "$here/wt.mjs" "$out/wt.mjs"
cat > "$out/README-no-readers.txt" <<TXT
This platform has no wt readers.

wt reads the raw files of a MongoDB 3.x - 8.x database through WiredTiger. $why
\`wt detect\` still identifies a copy of such a database, and \`wt dump\` says it cannot read it here.

If the database files come from another machine, run wt there, or on any 64-bit Linux, macOS or
Windows machine, and move the .bson output.
TXT
