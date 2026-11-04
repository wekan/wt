#!/bin/bash
# pipeline.sh <version>  - raw MongoDB files (data/<version>) -> wt-mongo-dump -> .bson ->
# staging FerretDB -> WeKan's own importer (releases/migrate-mongodb-to-ferretdb.mjs) ->
# final FerretDB (SQLite) + files/attachments + files/avatars. No mongod anywhere.
set -eu
V="$1"; HERE="$(cd "$(dirname "$0")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
W="$HERE/run/$V"; rm -rf "$W"; mkdir -p "$W/stage" "$W/final" "$W/files"
export TMPDIR="$ROOT/.tools/tmp" WEKAN_ROOT="$ROOT"
FDB="$HERE/ferretdb-darwin"
cleanup() { for p in 27070 27071; do kill $(lsof -tiTCP:$p -sTCP:LISTEN 2>/dev/null) 2>/dev/null || true; done; }
trap cleanup EXIT; cleanup
DO_NOT_TRACK=1 "$FDB" --handler=sqlite --sqlite-url="file:$W/stage/" --listen-addr=127.0.0.1:27070 --debug-addr=- --telemetry=disable >"$W/stage.log" 2>&1 &
DO_NOT_TRACK=1 "$FDB" --handler=sqlite --sqlite-url="file:$W/final/" --listen-addr=127.0.0.1:27071 --debug-addr=- --telemetry=disable >"$W/final.log" 2>&1 &
for i in $(seq 1 30); do lsof -tiTCP:27070 -sTCP:LISTEN >/dev/null 2>&1 && lsof -tiTCP:27071 -sTCP:LISTEN >/dev/null 2>&1 && break; sleep 1; done
node "$HERE/restore-bson.mjs" "$HERE/out/$V" "mongodb://127.0.0.1:27070/?directConnection=true" | tail -3
SOURCE_MONGO_URL="mongodb://127.0.0.1:27070/wekan?directConnection=true" \
TARGET_MONGO_URL="mongodb://127.0.0.1:27071/wekan?directConnection=true" \
WRITABLE_PATH="$W/files" MIGRATION_PORT=18999 NODE_PATH="$ROOT/node_modules" \
  node "$ROOT/releases/migrate-mongodb-to-ferretdb.mjs" > "$W/import.log" 2>&1 && echo "importer rc=0" || echo "importer rc=$?"
tail -5 "$W/import.log" | cut -c1-200
node "$HERE/verify.mjs" "$W"
