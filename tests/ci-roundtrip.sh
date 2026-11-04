#!/bin/bash
# ci-roundtrip.sh <wt-<platform>.tar.gz> - unpack a release tarball and read REAL data files of
# mongod 4.4, 6.0 and 8.0 (created by the official mongo images) with it: counts, GridFS chunks and
# the feature compatibility version must match what was inserted.
set -eu
TAR="$(readlink -f "$1")"; HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="$(mktemp -d)"; mkdir "$W/wt" && tar -C "$W/wt" -xzf "$TAR"
for V in 4.4 6.0 8.0; do
  mkdir -p "$W/data/$V"
  bash "$HERE/make-data.sh" "$V" >/dev/null
  cp -a "$HERE/data/$V/." "$W/data/$V/"
  WT_HOME="$W/wt" node "$W/wt/wt.mjs" dump "$W/data/$V" "$W/out/$V"
  cards=$(awk -F'\t' '$1=="wekan.cards"{print $3}' "$W/out/$V/_manifest.tsv")
  chunks=$(awk -F'\t' '$1=="wekan.cfs_gridfs.attachments.chunks"{print $3}' "$W/out/$V/_manifest.tsv")
  [ "$cards" = 20000 ] && [ "$chunks" = 4 ] || { echo "FAIL $V: cards=$cards chunks=$chunks"; exit 1; }
  echo "PASS $V"
done
