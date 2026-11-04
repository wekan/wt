#!/bin/bash
# windows.sh <outdir> <x64|arm64>  - WiredTiger 11.3 (mongod 4.4 - 8.0) and its reader for Windows, with MSVC,
# run from Git Bash on a GitHub Windows runner after the Visual Studio developer environment is set up
# (ilammy/msvc-dev-cmd in the workflow). Windows gets 11.3 only: WiredTiger 3.1 and 2.5 are autotools
# builds. Data files are the same on every operating system, so older databases are read by wt on Linux or
# macOS. If this does not build, the reason is the tail of the log in the output, and the job fails.
set -euo pipefail
out="$1"; arch="${2:-x64}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${WT_WORKROOT:-$(mktemp -d)}"; log="$work/build-11.3.log"
mkdir -p "$out/11.3/lib"; out="$(cd "$out" && pwd)"
case "$arch" in x64) triplet=x64-windows ;; arm64) triplet=arm64-windows ;; *) echo "windows.sh: unknown arch $arch" >&2; exit 2 ;; esac
fail() { echo "---- WiredTiger 11.3 did not build for Windows $arch; last lines of its log:"; tail -40 "$log" 2>/dev/null | cut -c1-240; exit 1; }
trap 'fail' ERR
vcpkg="${VCPKG_INSTALLATION_ROOT:-C:/vcpkg}"
"$vcpkg/vcpkg.exe" install snappy zstd zlib --triplet "$triplet" > "$log" 2>&1
git clone --depth 1 -b mongodb-8.0 https://github.com/wiredtiger/wiredtiger "$work/wt" >> "$log" 2>&1
mkdir -p "$work/wt/build"; cd "$work/wt/build"
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$vcpkg/scripts/buildsystems/vcpkg.cmake" \
  -DVCPKG_TARGET_TRIPLET="$triplet" -DENABLE_SNAPPY=1 -DENABLE_ZLIB=1 -DENABLE_ZSTD=1 -DENABLE_STATIC=0 -DENABLE_PYTHON=0 .. >> "$log" 2>&1
ninja wiredtiger_shared wiredtiger_snappy wiredtiger_zlib wiredtiger_zstd >> "$log" 2>&1
# the DLLs: the engine and the three compressors, and the vcpkg DLLs they load
find . -name 'wiredtiger*.dll' -exec cp -f {} "$out/11.3/lib/" \;
cp -f "$vcpkg/installed/$triplet/bin/"*.dll "$out/11.3/lib/" 2>/dev/null || true
lib_file="$(find . -name 'wiredtiger.lib' | head -1)"
[ -n "$lib_file" ] || { echo "no wiredtiger.lib" >> "$log"; fail; }
# the reader, next to its libraries' directory
( cd "$out/11.3" && cl.exe /nologo /O2 /W3 "/I$work/wt/build/include" "$here/wt-mongo-dump.c" "/Fe:wt-mongo-dump.exe" /link "$work/wt/build/$lib_file" ) >> "$log" 2>&1
cp "$here/wt.mjs" "$out/wt.mjs"
echo "windows.sh: built $out/11.3 ($(ls "$out/11.3/lib" | wc -l | tr -d ' ') DLLs)"
