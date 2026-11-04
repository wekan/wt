# Changelog

# Upcoming wt release

**In short:** The first release of **wt** (v0.01), which reads the raw data files of a MongoDB 3.0 - 8.x
database without mongod, knows which MongoDB wrote them, replays the journal or salvages damaged
files on a copy when it has to, and turns them into FerretDB (SQLite) data. Built for the 23
platforms of wekan/node-patches: **Linux, macOS, Windows, FreeBSD, OpenBSD and NetBSD** on 64-bit CPUs, and a stub
where WiredTiger cannot run (32-bit, Android, LoongArch).

This release adds the following new features:

<details>
<summary><a href="https://github.com/wekan/wt/commit/1ea4573">wt reads MongoDB 3.0 - 8.x data files without mongod</a>. Thanks to xet7.</summary>

`wt-mongo-dump` links WiredTiger, the storage engine inside every mongod, and writes each
collection as a `.bson` file; `wt.mjs` finds the MongoDB version in `WiredTiger.turtle`, picks the
WiredTiger that opens it (11.3 for mongod 4.4 - 8.0, 3.1 for 3.2 - 4.2, 2.5 for 3.0) and escalates
only as far as the files need: read-only, then the journal replayed on a copy after an unclean
shutdown, then salvage of every table on a copy, as `mongod --repair` does. The original is never
modified.

Read through WeKan's importer into FerretDB (SQLite) from the official mongo images 3.0, 3.2, 3.6,
4.0, 4.2, 4.4, 5.0, 6.0, 7.0 and 8.0: documents, nested values, dates, int64 above 2^53 and
GridFS bytes all identical. An mongod killed with SIGKILL was recovered completely; a file with
256 KB of random bytes overwritten lost the documents in the damaged pages (9,751 of 20,000
survived) and nothing else.

</details>

<details>
<summary><a href="https://github.com/wekan/wt/commit/0b95e4b">wt is built for macOS, Windows, FreeBSD, OpenBSD and NetBSD, and for every platform of node-patches</a>. Thanks to xet7.</summary>

`platforms.json` is the one list: the 23 platforms of wekan/node-patches, under its names (`x64`, `arm64`,
`mac-arm64`, `win64`, `freebsd-x64`, ...), so WeKan fetches `wt-<platform>` and `node-<platform>` with one
vocabulary. `build.yml`, a reusable workflow, builds each platform and attaches its tarball to the release as
soon as it is built; `release-all.yml` and `release-all-missing.yml` only decide which platforms to ask for.

| Platforms | What the tarball holds |
| --- | --- |
| `x64`, `arm64`, `s390x`, `ppc64le`, `riscv64` | readers 11.3 and 3.1 (and 2.5 on `x64`), built in a container of that CPU |
| `mac-arm64`, `mac-x64` | readers 11.3 and 3.1, built on macOS runners |
| `freebsd-x64`, `openbsd-x64`, `openbsd-arm64`, `netbsd-x64` | readers 11.3 and 3.1, built in a VM |
| `win64`, `win-arm64` | reader 11.3 (mongod 4.4 - 8.0), built with MSVC |
| `i386`, `armv6`, `armhf`, `armv7`, `win32`, `android-*`, `loong64` | `wt.mjs` and an explanation: WiredTiger needs a 64-bit CPU, MongoDB never ran on Android, WiredTiger has no LoongArch port |

macOS, Windows and the BSDs are `best_effort`: nobody had built WiredTiger there, so a failure there does not
fail the run, its log says why, a summary job lists what the release lacks, and Release All Missing builds only
that. `wt.mjs` runs a reader as `.exe` with its DLLs on `PATH` on Windows and with `DYLD_LIBRARY_PATH` on macOS,
and a smoke step starts each reader on the runner that built it. None of the new platforms has been built yet.
`tests/platforms.sh` pins the list against node-patches' names, the modes, and which platforms are stubs.

</details>

and fixes the following bugs:

<details>
<summary><a href="https://github.com/wekan/wt/commit/b88b40f">The release builds: 32-bit ARM, RISC-V, s390x, and wt.mjs through a symlink</a>. Thanks to xet7.</summary>

What the first two release runs showed:

- `linux-s390x` and `linux-riscv64`: `debian:bookworm` has no image for either. `Dockerfile.release`
  takes `BASE`, and the workflows pass `debian:trixie` for those two.
- A failing reader build went unnoticed: each was built in `( set -e; ... ) || fallback`, where bash
  ignores errexit. Each build is now its own script run by `bash -e` (`build/w11.sh`, `w31.sh`,
  `w25.sh`), and `build/try.sh` prints the tail of the build log when a reader is left out.
- `linux-armv7`: WiredTiger requires a 64-bit build, and MongoDB never ran WiredTiger on 32-bit
  systems, so there is nothing to read or build. The platform publishes a stub tarball (`wt.mjs` and
  an explanation, `build/stub.sh`) instead of failing, and `wt dump` says there is no reader.
- `linux-riscv64`: WiredTiger 3.1 has no memory barriers for the architecture; `build/w31.sh` adds
  RISC-V's fence instructions. Not run yet: if it is wrong the reader is left out with the log.
- `wt.mjs` printed nothing and exited 0 when run through a symlink (`/var` on a Mac, or a `wt` link
  in `/usr/local/bin`), because it compared a resolved path with a real one.
- The test step died when the `mongo:8.0` container exited: that image does not start on kernels
  6.19 and newer (SERVER-121912). `make-data.sh` shows the container's log, and
  `tests/ci-roundtrip.sh` skips a version whose mongod would not start, and also tests 7.0.

`tests/stub-platform.sh` pins the stub, the symlink fix and that the workflows build nothing for
armv7.

</details>

and has the following release-tooling change:

<details>
<summary><a href="https://github.com/wekan/wt/commit/0c40918">Releases are numbered v0.01, v0.02, and so on</a>. Thanks to xet7.</summary>

The first release is v0.01, the next v0.02, and v0.99 is followed by v1.00, as WeKan goes from 9.99 to
10.00. The minor is always two digits: `releases/lib.sh` has the rule (`bump_version`, decimal so that
08 and 09 are not refused as octal) and `valid_version` accepts only `v<major>.<two digits>`, so
`v1.0`, `v0.1` and a bare `0.01` are refused. `tests/version-numbers.sh` pins the sequence.

</details>

Thanks to above GitHub users for their contributions and translators for their translations.
