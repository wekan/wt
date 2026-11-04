#!/bin/bash
# WiredTiger 3.1 (mongod 3.2 - 4.2): autotools. See w11.sh for why this is its own process.
set -euo pipefail
BRANCH="${1:-mongodb-4.0}"
git clone --depth 1 -b "$BRANCH" https://github.com/wiredtiger/wiredtiger /wt
# riscv64: this WiredTiger predates the architecture, so src/include/gcc.h has no memory barriers for it
# (the build stopped at "implicit declaration of function WT_FULL_BARRIER"). RISC-V's own fence
# instructions are the barriers; the rest of the build is architecture independent.
if ! grep -q '__riscv' /wt/src/include/gcc.h; then
python3 - <<'PY'
p = '/wt/src/include/gcc.h'
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
mkdir -p /out/3.1/lib; cd /wt/build_posix
sh reconf > /build.log 2>&1
../configure --enable-snappy --enable-zlib --disable-python CFLAGS="-O2 -Wno-error" >> /build.log 2>&1
make -j4 >> /build.log 2>&1
cp -a .libs/libwiredtiger*.so* /out/3.1/lib/
cp -L ext/compressors/snappy/.libs/libwiredtiger_snappy.so ext/compressors/zlib/.libs/libwiredtiger_zlib.so /out/3.1/lib/
gcc -O2 -Wall -I. -o /out/3.1/wt-mongo-dump /src/wt-mongo-dump.c -L/out/3.1/lib -lwiredtiger -Wl,-rpath,'$ORIGIN/lib'
