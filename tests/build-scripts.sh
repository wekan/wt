#!/bin/bash
# build-scripts.sh - what the third release run's logs (.tools/log/wt3) showed, pinned: the faults of the build
# scripts and the build workflow, each with a negative. Needs bash and python3.
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; cd "$HERE"
fail=0; ok() { echo "PASS $1"; }; bad() { echo "FAIL $1"; fail=1; }
has()  { grep -q -- "$2" "$1" && ok "$3" || bad "$3"; }
hasnt(){ grep -q -- "$2" "$1" && bad "$3" || ok "$3"; }

# 1. a dist/ that came with the checkout made every job upload another platform's tarball
git -C "$HERE" ls-files --error-unmatch dist >/dev/null 2>&1 && bad "dist/ is tracked" || ok "negative: nothing under dist/ is tracked"
has .gitignore '^dist/$' ".gitignore ignores dist/"
has .github/workflows/build.yml 'rm -rf dist' "Pack starts from a clean dist/"
hasnt .github/workflows/build.yml 'upload "\$VERSION".*dist/\*' "negative: the upload no longer sends dist/*"
has .github/workflows/build.yml 'dist/wt-\${{ matrix.platform }}.tar.gz" "dist/wt-\${{ matrix.platform }}.tar.gz.sha256sum"' "each job uploads its own tarball and checksum, by name"

# 2. macOS: the compressors are MODULE libraries, .so there too
has build/w11.sh "libwiredtiger_\*.so' -o -name 'libwiredtiger_\*.dylib" "w11.sh copies the compressors with either suffix"
has build/w31.sh "libwiredtiger_snappy.dylib" "w31.sh copies the compressors with either suffix"
hasnt build/w11.sh 'for f in ext/compressors/\*/libwiredtiger_\*."\$SO"' "negative: w11.sh no longer globs one suffix"

# 3. the BSDs: WiredTiger 11.3 knows linux, darwin and windows only
has build/w11.sh 'OSFLAGS=(-DWT_OS=linux' "w11.sh builds as Linux where the OS is not Linux or macOS"
has build/w11.sh 'x86_64|amd64) wtarch=x86' "and names the CPU the way WiredTiger does (x86, not amd64)"
has build/w11.sh 'Linux|Darwin) ;;' "negative: Linux and macOS keep their own detection"

# 4. NetBSD's python is python3.13, OpenBSD's autoconf is autoconf%2.71
has build/w31.sh 'python3.13' "w31.sh finds a versioned python"
has .github/workflows/build.yml 'autoconf%2.71 automake%1.16' "OpenBSD packages are named stem%branch"
hasnt .github/workflows/build.yml 'autoconf-2.71' "negative: autoconf-2.71 is not a package name"

# 5. riscv64: barriers and the checksum, applied once, harmless elsewhere
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/wt/src/include" "$T/wt/src/checksum/software"
printf '#if defined(__s390x__)\n#define WT_X 1\n#else\n#error "No write barrier implementation for this hardware"\n#endif\n' > "$T/wt/src/include/gcc.h"
printf 'uint32_t\n__wt_checksum_sw(const void *chunk, size_t len)\n{\n    return 0;\n}\n' > "$T/wt/src/checksum/software/checksum.c"
sed -n '/^PYTHON=""/,/^fi$/p' build/w31.sh > "$T/patch.sh"
WORK="$T/wt" LOG="$T/log" bash -e "$T/patch.sh" && ok "the riscv64 patch runs" || bad "the riscv64 patch fails"
grep -q 'defined(__riscv)' "$T/wt/src/include/gcc.h" && grep -q 'fence rw,rw' "$T/wt/src/include/gcc.h" && ok "gcc.h has RISC-V fences" || bad "gcc.h has no RISC-V fences"
grep -q 'wiredtiger_crc32c_func' "$T/wt/src/checksum/software/checksum.c" && ok "checksum.c gets wiredtiger_crc32c_func" || bad "no wiredtiger_crc32c_func (the riscv64 link error)"
cp "$T/wt/src/checksum/software/checksum.c" "$T/c1"; cp "$T/wt/src/include/gcc.h" "$T/g1"
WORK="$T/wt" LOG="$T/log" bash -e "$T/patch.sh"
cmp -s "$T/c1" "$T/wt/src/checksum/software/checksum.c" && cmp -s "$T/g1" "$T/wt/src/include/gcc.h" && ok "negative: a second run changes nothing" || bad "the patch is not idempotent"

# 6. Windows: a static library, built-in compressors, no shared target
has build/windows.sh 'ninja wiredtiger_static' "windows.sh builds wiredtiger_static"
hasnt build/windows.sh 'ninja wiredtiger_shared' "negative: windows.sh does not ask for wiredtiger_shared (unknown target on Windows)"
has build/windows.sh 'HAVE_BUILTIN_EXTENSION_SNAPPY=1' "the compressors are built in"
has build/windows.sh 'x64-windows-static' "vcpkg's static triplet"
has wt-mongo-dump.c 'exts && exts\[0\]' "an empty WT_EXTENSIONS means none"
# 7. the fourth release run (.tools/log/wt1): Windows zlib, Windows arm64, macOS 3.1's install name
has build/windows.sh 'zlib-alias/z.lib' "windows.sh gives find_library(z) a z.lib (vcpkg's is zlib.lib)"
has build/windows.sh 'CMAKE_LIBRARY_PATH="\$work/zlib-alias"' "and points CMake at it"
hasnt build/windows.sh 'triplet=arm64-windows-static' "negative: windows.sh does not try MSVC arm64, which WiredTiger refuses"
has build/windows.sh '-DWT_ARCH=x86 -DWT_OS=windows' "the target is named, not taken from the host CPU (ARM64 on win-arm64)"
has build/w31.sh 'install_name_tool -id "@rpath/' "w31.sh gives the macOS library an @rpath install name"
# and that it works: a dylib with an absolute install name, then the loop, then the name
if [ "$(uname -s)" = Darwin ]; then
  D="$(mktemp -d)"; mkdir -p "$D/lib"
  echo 'int f(void){return 1;}' > "$D/f.c"
  cc -dynamiclib -install_name /usr/local/lib/libwiredtiger-3.1.0.dylib -o "$D/lib/libwiredtiger-3.1.0.dylib" "$D/f.c"
  ln -s libwiredtiger-3.1.0.dylib "$D/lib/libwiredtiger.dylib"
  OUT="$D/out"; mkdir -p "$OUT/3.1"; mv "$D/lib" "$OUT/3.1/lib"; SO=dylib
  eval "$(sed -n '/^if \[ "\$SO" = dylib \]; then$/,/^fi$/p' build/w31.sh)"
  otool -D "$OUT/3.1/lib/libwiredtiger-3.1.0.dylib" | grep -q '^@rpath/libwiredtiger-3.1.0.dylib$' && ok "the install name is @rpath/" || bad "the install name is still absolute"
  rm -rf "$D"
else
  ok "(the install-name run needs macOS; its source is pinned above)"
fi
exit $fail
