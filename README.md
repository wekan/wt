# wt

Reads the raw data files of a MongoDB (3.0 - 8.x, WiredTiger) **without mongod** and turns them
into something WeKan's importer can take to FerretDB (SQLite): every collection as a `.bson` file,
GridFS chunks included.

```
wt detect <dbpath>                 which MongoDB wrote these files, which reader opens them
wt dump [--repair] <dbpath> <out>  <out>/<db>/<collection>.bson  +  _manifest.tsv  +  _catalog.bson
```

## It knows which MongoDB wrote the files

`WiredTiger.turtle` records the WiredTiger version that last opened the database; `wt` maps it to the
reader that can open it, and after the dump reads `admin.system.version` for the exact feature
compatibility version.

| WiredTiger | mongod | reader | opened |
| --- | --- | --- | --- |
| 2.5 | 3.0 | 2.5 (x86_64 only) | on a copy (no read-only mode) |
| 2.9, 3.1, 3.3 | 3.2, 3.4, 3.6, 4.0, 4.2 | 3.1 | read-only |
| 10.0 | 4.4, 5.0, 6.0 | 11.3 | read-only |
| 11.2, 11.3 | 7.0, 8.0 | 11.3 | read-only |

MMAPv1 (mongod 3.0's old default engine) is recognised and refused: it is not WiredTiger.

## It repairs only as far as the files need, and never touches the original

1. **Read-only.** A cleanly stopped mongod's files need nothing more; the source is not modified
   (checked by checksum in the tests).
2. **Unclean shutdown** (`mongod.lock` not empty, a journal to replay): the journal is replayed on a
   **copy**, because replaying writes. Every document inserted since the last checkpoint is recovered.
3. **Damaged files** (`--repair`, or automatically when 2 fails): WiredTiger *salvage* of every table
   on a fresh copy, which is what `mongod --repair` does. Documents in unreadable pages are lost and
   the count says so. In the corrupted-file test 9,751 of 20,000 documents were recovered and nothing else broke.

## Tested

`make-data.sh <version>` runs the official `mongo:<version>` image, seeds 20,000 documents plus both
GridFS layouts WeKan has used (CollectionFS and Meteor-Files), and stops it cleanly;
`make-unclean.sh` kills it instead. `pipeline.sh <version>` then runs wt, restores into a staging
FerretDB and runs WeKan's own `releases/migrate-mongodb-to-ferretdb.mjs`, and `verify.mjs` checks the
result: counts, a 20,000-character field, nested arrays, dates, an int64 above 2^53, and **GridFS bytes
identical to the pattern that was inserted**. All of mongod 3.0, 3.2, 3.6, 4.0, 4.2, 4.4, 5.0, 6.0,
7.0 and 8.0 pass.

Not yet tested: mongod 3.4 and MMAPv1 data; data written with `journalCompressor` other than snappy,
zstd, zlib or none; encrypted-at-rest databases (not supported); databases larger than the test data.

## Platforms

`platforms.json` is the one list; its names are the platform names of wekan/node-patches (`x64`, `arm64`,
`mac-arm64`, `win64`, `freebsd-x64`, ...), so WeKan fetches `wt-<platform>` and `node-<platform>` with the same
vocabulary. Every release has a `wt-<platform>.tar.gz` and a `.sha256sum` for each of the 23.

| Platforms | What the tarball holds | Built by |
| --- | --- | --- |
| x64, arm64, s390x, ppc64le, riscv64 (Linux) | readers 11.3 and 3.1, and 2.5 on x64 | `Dockerfile.release`, in a container of that CPU |
| mac-arm64, mac-x64 | readers 11.3 and 3.1 | `build/native.sh` on a macOS runner |
| freebsd-x64, openbsd-x64, openbsd-arm64, netbsd-x64 | readers 11.3 and 3.1 | `build/native.sh` in a VM |
| win64, win-arm64 | reader 11.3 (mongod 4.4 - 8.0; older data files are read on Linux or macOS), one static .exe | `build/windows.sh`, MSVC |
| i386, armv6, armhf, armv7, win32, android-armv7, android-x86 | `wt.mjs` only | WiredTiger needs a 64-bit CPU, and MongoDB never ran it on 32-bit |
| android-arm64, android-x64 | `wt.mjs` only | MongoDB never ran on Android |
| loong64 | `wt.mjs` only | WiredTiger has no LoongArch port |

macOS, Windows and the BSDs are marked `best_effort`: nobody had built WiredTiger there before, so a failure
there does not fail the run, its log says why, and the summary job names what the release lacks. Run
`Release All Missing` after fixing one. A WiredTiger that does not build on a platform is left out of that
platform's tarball and `wt` says so when it meets data it has no reader for.

## Build

`build.sh` has the commands (`dist`, `test`, `release-all`, `release-all-missing`, ...). The release workflows
(`release-all.yml`, `release-all-missing.yml`) call `build.yml`, which builds each platform in
`platforms.json` and attaches its tarball to the GitHub Release at https://github.com/wekan/wt/releases as soon
as it is built. Releases are numbered v0.01, v0.02, ...
