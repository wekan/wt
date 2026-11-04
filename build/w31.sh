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
if ! grep -q '__riscv' "$WORK/src/include/gcc.h"; then
WT_GCC_H="$WORK/src/include/gcc.h" python3 - <<'PY'
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
PY
fi
mkdir -p "$OUT/3.1/lib"; cd "$WORK/build_posix"
sh reconf > "$LOG" 2>&1
../configure --enable-snappy --enable-zlib --disable-python CFLAGS="-O2 -Wno-error" >> "$LOG" 2>&1
make -j"$JOBS" >> "$LOG" 2>&1
cp -a .libs/libwiredtiger*."$SO"* "$OUT/3.1/lib/"
cp -L ext/compressors/snappy/.libs/libwiredtiger_snappy."$SO" ext/compressors/zlib/.libs/libwiredtiger_zlib."$SO" "$OUT/3.1/lib/"
"$CC" -O2 -Wall -I. -o "$OUT/3.1/wt-mongo-dump" "$READER" -L"$OUT/3.1/lib" -lwiredtiger -Wl,-rpath,"$RPATH"
