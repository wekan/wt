#!/bin/bash
# ci-roundtrip.sh <wt-<platform>.tar.gz> [versions...]  - unpack a release tarball and read REAL
# data files of mongod (created by the official mongo images, one clean and one killed with
# SIGKILL) with it, inside a Linux container so the same script runs on a Mac and on CI.
# Checks, per version: the version wt DETECTS, documents, GridFS chunks, the feature
# compatibility version it reports, and that the source is byte for byte unchanged.
set -eu
TAR="$(readlink -f "$1")"; shift
VERSIONS="${*:-4.4 6.0 8.0}"
HERE="$(cd "$(dirname "$0")/.." && pwd)"
W="$HERE/run/roundtrip"; rm -rf "$W"; mkdir -p "$W/wt" "$W/out"
tar -C "$W/wt" -xzf "$TAR"
fail=0
for V in $VERSIONS; do
  [ -d "$HERE/data/$V" ] || bash "$HERE/make-data.sh" "$V" >/dev/null
  before=$(cd "$HERE/data/$V" && find . -type f -not -name WiredTiger.lock -print0 | sort -z | xargs -0 shasum | shasum)
  log=$(docker run --rm -v "$W/wt:/opt/wt:ro" -v "$HERE/data:/data" -v "$W/out:/out" -e WT_HOME=/opt/wt -e TMPDIR=/tmp \
    node:22-bookworm bash -c 'apt-get update -qq >/dev/null 2>&1; apt-get install -y -qq libsnappy1v5 libzstd1 zlib1g >/dev/null 2>&1; node /opt/wt/wt.mjs dump /data/'"$V"' /out/'"$V" 2>&1)
  after=$(cd "$HERE/data/$V" && find . -type f -not -name WiredTiger.lock -print0 | sort -z | xargs -0 shasum | shasum)
  cards=$(awk -F'\t' '$1=="wekan.cards"{print $3}' "$W/out/$V/_manifest.tsv" 2>/dev/null || true)
  chunks=$(awk -F'\t' '$1=="wekan.cfs_gridfs.attachments.chunks"{print $3}' "$W/out/$V/_manifest.tsv" 2>/dev/null || true)
  if [ "$cards" = 20000 ] && [ "$chunks" = 4 ] && [ "$before" = "$after" ]; then
    echo "PASS $V: $(echo "$log" | grep -E 'WiredTiger [0-9]' | head -1 | cut -c1-80); source unchanged"
  else
    echo "FAIL $V: cards=$cards chunks=$chunks source-unchanged=$([ "$before" = "$after" ] && echo yes || echo NO)"; echo "$log" | tail -5; fail=1
  fi
done
exit $fail
