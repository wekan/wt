#!/bin/bash
# make-unclean.sh <mongo-version> - like make-data.sh, but the mongod is KILLED with SIGKILL right
# after the seed (no clean shutdown, no final checkpoint), leaving data/<version>-unclean whose
# journal still has to be replayed before the tables are consistent.
set -eu
V="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"
D="$HERE/data/$V-unclean"; rm -rf "$D"; mkdir -p "$D"
N="wtunclean-${V//./_}"; docker rm -f "$N" >/dev/null 2>&1 || true
docker run -d --name "$N" -v "$D:/data/db" -v "$HERE/seed.js:/seed.js:ro" "mongo:$V" --bind_ip 127.0.0.1 >/dev/null
SH=mongosh; docker exec "$N" which mongosh >/dev/null 2>&1 || SH=mongo
for i in $(seq 1 120); do docker exec "$N" $SH --quiet --eval 'db.runCommand({ping:1}).ok' 2>/dev/null | grep -qx 1 && break; sleep 1; done
docker exec "$N" $SH --quiet /seed.js
docker kill -s KILL "$N" >/dev/null; docker rm "$N" >/dev/null
echo "data/$V-unclean: mongod killed without a clean shutdown"
