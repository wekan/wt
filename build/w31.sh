#!/bin/bash
# WiredTiger 3.1 (mongod 3.2 - 4.2): autotools. See w11.sh for why this is its own process and for the
# environment (WT_OUT, WT_WORK, WT_LOG, WT_READER, WT_SO, WT_RPATH).
set -euo pipefail
BRANCH="${1:-mongodb-4.0}"
OUT="${WT_OUT:-/out}"; WORK="${WT_WORK:-/wt}"; LOG="${WT_LOG:-/build.log}"
READER="${WT_READER:-/src/wt-mongo-dump.c}"; SO="${WT_SO:-so}"; RPATH="${WT_RPATH:-\$ORIGIN/lib}"
CC="${CC:-gcc}"; JOBS="${WT_JOBS:-$( (nproc || sysctl -n hw.ncpu) 2>/dev/null || echo 4 )}"
[ -d "$WORK/.git" ] || git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger "$WORK"
# riscv64: this WiredTiger predates the architecture, so src/include/gcc.h has no memory barriers for it
# (the build stopped at "implicit declaration of function WT_FULL_BARRIER"). RISC-V's own fence
# instructions are the barriers; the rest of the build is architecture independent.
PYTHON=""
for candidate in python3 python3.14 python3.13 python3.12 python3.11 python3.10 python; do
  if command -v "$candidate" >/dev/null 2>&1; then PYTHON="$candidate"; break; fi
done
[ -n "$PYTHON" ] || { echo "w31.sh: no Python (python3, python3.13, ...): NetBSD's package is python3.13, not python3" > "$LOG"; exit 1; }
if ! grep -q '__riscv' "$WORK/src/include/gcc.h"; then
WT_GCC_H="$WORK/src/include/gcc.h" "$PYTHON" - <<'PY'
import os
p = os.environ['WT_GCC_H']
s = open(p).read()
marker = '#else\n#error "No write barrier implementation for this hardware"'
riscv = (
    '#elif defined(__riscv)\n'
    '#define WT_PAUSE() __asm__ volatile("" ::: "memory")\n'
    '#define WT_FULL_BARRIER() __asm__ volatile("fence rw,rw" ::: "memory")\n'
    '#define WT_READ_BARRIER() __asm__ volatile("fence r,r" ::: "memory")\n'
    '#define WT_WRITE_BARRIER() __asm__ volatile("fence w,w" ::: "memory")\n\n'
)
assert marker in s, 'gcc.h has changed: no barrier fallback to put riscv before'
open(p, 'w').write(s.replace(marker, riscv + marker, 1))
# and a checksum: wiredtiger_crc32c_func() exists only in the x86, arm64, PowerPC and s390x directories, so a
# riscv64 library linked with "undefined reference to wiredtiger_crc32c_func". The software one is what they
# all fall back to.
c = os.path.join(os.path.dirname(p), '..', 'checksum', 'software', 'checksum.c')
t = open(c).read()
if 'wiredtiger_crc32c_func' not in t:
    t += ('\n#if defined(__riscv)\n'
          'extern uint32_t (*wiredtiger_crc32c_func(void))(const void *, size_t);\n'
          'uint32_t (*wiredtiger_crc32c_func(void))(const void *, size_t)\n'
          '{\n    return (__wt_checksum_sw);\n}\n'
          '#endif\n')
    open(c, 'w').write(t)
PY
fi
mkdir -p "$OUT/3.1/lib"; cd "$WORK/build_posix"
sh reconf > "$LOG" 2>&1
../configure --enable-snappy --enable-zlib --disable-python CFLAGS="-O2 -Wno-error" >> "$LOG" 2>&1
make -j"$JOBS" >> "$LOG" 2>&1
cp -a .libs/libwiredtiger*."$SO"* "$OUT/3.1/lib/"
# libtool modules: .so also on macOS
find ext/compressors \( -name 'libwiredtiger_snappy.so' -o -name 'libwiredtiger_zlib.so' -o -name 'libwiredtiger_snappy.dylib' -o -name 'libwiredtiger_zlib.dylib' \) -exec cp -L {} "$OUT/3.1/lib/" \;
"$CC" -O2 -Wall -I. -o "$OUT/3.1/wt-mongo-dump" "$READER" -L"$OUT/3.1/lib" -lwiredtiger -Wl,-rpath,"$RPATH"
