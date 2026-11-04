#!/bin/bash
# make-data.sh <mongo-version> [image]   - run a real mongod container of that version,
# seed it with seed.js (text data + both GridFS layouts), stop it CLEANLY and leave its
# dbpath in data/<version>/ for the raw reader. Uses the official mongo image.
set -eu
V="$1"; IMG="${2:-mongo:$V}"
HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/data/$V"; rm -rf "$D"; mkdir -p "$D"
N="wtseed-${V//./_}"
docker rm -f "$N" >/dev/null 2>&1 || true
docker run -d --name "$N" -v "$D:/data/db" -v "$HERE/seed.js:/seed.js:ro" "$IMG" --bind_ip 127.0.0.1 ${MONGOD_ARGS:-} >/dev/null
SH=mongosh; docker exec "$N" which mongosh >/dev/null 2>&1 || SH=mongo
for i in $(seq 1 120); do docker exec "$N" $SH --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -qx 1 && break; sleep 1; done
# a mongod that exited (mongo:8.0 did on the GitHub runners, for a reason only its log knows) is
# reported with that log instead of "container is not running" from the next docker exec
if [ "$(docker inspect -f '{{.State.Running}}' "$N" 2>/dev/null)" != true ]; then
  echo "make-data.sh: the mongo:$V container is not running; its log:" >&2
  docker logs --tail 40 "$N" >&2 || true
  docker rm -f "$N" >/dev/null 2>&1 || true
  exit 3
fi
docker exec "$N" $SH --quiet /seed.js
docker exec "$N" $SH --quiet --eval 'db.version()'
docker stop -t 60 "$N" >/dev/null; docker rm "$N" >/dev/null
echo "data/$V: $(du -sh "$D" | cut -f1), $(ls "$D" | wc -l) entries"
