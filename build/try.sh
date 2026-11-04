#!/bin/bash
# try.sh <lib> <script> [branch]  - run one build script; when it fails, SAY WHY (the tail of its
# log goes to the build output) and leave that reader out instead of failing the platform.
lib="$1"; script="$2"; shift 2
if bash -e "$script" "$@"; then
  echo "WiredTiger $lib built on $(uname -m)"
else
  echo "---- WiredTiger $lib did not build on $(uname -m); last lines of its log:"
  tail -25 /build.log 2>/dev/null | cut -c1-240
  echo "---- WiredTiger $lib is left out on $(uname -m)"
  rm -rf "/out/$lib"
fi
mkdir -p /out
exit 0
