#!/bin/bash
# windows.sh <outdir> <x64|arm64>  - WiredTiger 11.3 (mongod 4.4 - 8.0) and its reader for Windows, with MSVC,
# run from Git Bash on a GitHub Windows runner after the Visual Studio developer environment is set up
# (ilammy/msvc-dev-cmd in the workflow). Windows gets 11.3 only: WiredTiger 3.1 and 2.5 are autotools
# builds. Data files are the same on every operating system, so older databases are read by wt on Linux or
# macOS. If this does not build, the reason is the tail of the log in the output, and the job fails.
#
# WiredTiger's CMake builds a STATIC library on Windows ("We force a static compilation to generate a .lib
# file", cmake/configs/base.cmake): there is no wiredtiger_shared target, which is what the first run stopped
# on ("ninja: error: unknown target 'wiredtiger_shared'"). So the engine is linked into the reader, and the
# compressors are BUILT IN (HAVE_BUILTIN_EXTENSION_*, which replaces ENABLE_*), against vcpkg's static
# snappy, zstd and zlib. The result is one wt-mongo-dump.exe with no DLLs next to it.
set -euo pipefail
out="$1"; arch="${2:-x64}"
here="$(cd "$(dirname "$0")/.." && pwd)"
work="${WT_WORKROOT:-$(mktemp -d)}"; log="$work/build-11.3.log"
mkdir -p "$out/11.3"; out="$(cd "$out" && pwd)"
# WiredTiger supports MSVC on x64 only (src/include/msvc.h: #error "Only x64 is supported with MSVC", and there
# is no cmake/configs/aarch64/windows). win-arm64 therefore gets the x64 build, which Windows 11 on ARM runs
# through its x64 emulation; platforms.json gives that job arch x64, and the smoke test runs it on the ARM runner.
case "$arch" in
  x64) triplet=x64-windows-static ;;
  arm64) echo "windows.sh: WiredTiger does not build with MSVC for arm64; build x64, which Windows on ARM runs" >&2; exit 2 ;;
  *) echo "windows.sh: unknown arch $arch" >&2; exit 2 ;;
esac
fail() { echo "---- WiredTiger 11.3 did not build for Windows $arch; last lines of its log:"; tail -40 "$log" 2>/dev/null | cut -c1-240; exit 1; }
trap 'fail' ERR
vcpkg="${VCPKG_INSTALLATION_ROOT:-C:/vcpkg}"
"$vcpkg/vcpkg.exe" install snappy zstd zlib --triplet "$triplet" > "$log" 2>&1
# WiredTiger looks for zlib as find_library(z), the Unix name; vcpkg's is zlib.lib, so the second run stopped at
# "Failed to find zlib library". A copy named z.lib, in a directory of its own, is what find_library finds; the
# reader still links vcpkg's own zlib.lib below, so there is one zlib, not two.
mkdir -p "$work/zlib-alias"
zlib_lib="$(ls "$vcpkg/installed/$triplet/lib/"zlib*.lib | head -1)"
cp "$zlib_lib" "$work/zlib-alias/z.lib"
git clone --depth 1 -b mongodb-8.0 https://github.com/wiredtiger/wiredtiger "$work/wt" >> "$log" 2>&1
mkdir -p "$work/wt/build"; cd "$work/wt/build"
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="$vcpkg/scripts/buildsystems/vcpkg.cmake" \
  -DCMAKE_LIBRARY_PATH="$work/zlib-alias" -DWT_ARCH=x86 -DWT_OS=windows \
  -DVCPKG_TARGET_TRIPLET="$triplet" -DENABLE_STATIC=1 -DENABLE_SHARED=0 -DDYNAMIC_CRT=0 -DENABLE_PYTHON=0 \
  -DHAVE_BUILTIN_EXTENSION_SNAPPY=1 -DHAVE_BUILTIN_EXTENSION_ZLIB=1 -DHAVE_BUILTIN_EXTENSION_ZSTD=1 .. >> "$log" 2>&1
# say which targets exist, so a wrong name is seen in the log next time
ninja -t targets all 2>/dev/null | grep -i 'wiredtiger' | grep -v '\.obj\|\.o:' | head -20 >> "$log" || true
ninja wiredtiger_static >> "$log" 2>&1
lib_file="$(find . -name 'wiredtiger*.lib' | head -1)"
[ -n "$lib_file" ] || { echo "no wiredtiger*.lib was built" >> "$log"; fail; }
# the reader: /MT like the library and the vcpkg triplet; the system libraries WiredTiger uses on Windows
deps="$(ls "$vcpkg/installed/$triplet/lib/"*.lib | tr '\n' ' ')"
( cd "$out/11.3" && cl.exe /nologo /O2 /W3 /MT "/I$work/wt/build/include" "$here/wt-mongo-dump.c" "/Fe:wt-mongo-dump.exe" \
    /link "$work/wt/build/$lib_file" $deps advapi32.lib bcrypt.lib psapi.lib ws2_32.lib ) >> "$log" 2>&1
cp "$here/wt.mjs" "$out/wt.mjs"
echo "windows.sh: built $out/11.3/wt-mongo-dump.exe ($(du -k "$out/11.3/wt-mongo-dump.exe" | cut -f1) KB, no DLLs)"
