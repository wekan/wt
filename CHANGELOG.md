# Changelog

# Upcoming wt release

**In short:** The release builds that failed in v1.0 are fixed: **s390x** and **riscv64** build on Debian
trixie, a failing reader build now says why instead of failing silently, and the test step no longer
dies when a **mongod** image cannot start on the runner.

This release fixes the following bugs:

<details>
<summary><a href="https://github.com/wekan/wt/commit/7321395">The v1.0 release builds for s390x, riscv64 and armv7 and its test step</a>. Thanks to xet7.</summary>

The first release run failed in three ways:

- `linux-s390x` and `linux-riscv64`: `debian:bookworm` has no image for either ("no match for
  platform in manifest"). `Dockerfile.release` takes `BASE`, and the workflows pass `debian:trixie`
  for those two. The bookworm and trixie builds were both run: the 11.3 and 3.1 readers build, and
  2.5 is left out on arm64.
- `linux-armv7`: a cmake failure went unnoticed. Each reader was built in `( set -e; ... ) || fallback`,
  where bash ignores errexit, so the steps after the failed one ran against a header that was never
  made, and the log showed only "wiredtiger.h: No such file". Each build is now its own script run by
  `bash -e` (`build/w11.sh`, `w31.sh`, `w25.sh`), and `build/try.sh` prints the tail of the build log
  when a reader is left out, so the next log says why.
- `linux-amd64` and `linux-arm64`: the test step died when the `mongo:8.0` container exited.
  `make-data.sh` now shows that container's log, and `tests/ci-roundtrip.sh` skips a version whose
  mongod would not start (with the log) instead of failing, and also tests 7.0.

</details>

Thanks to above GitHub users for their contributions and translators for their translations.

# v1.0 2026-11-04 wt release

**In short:** The first release of **wt**, which reads the raw data files of a MongoDB 3.0 - 8.x
database without mongod, knows which MongoDB wrote them, replays the journal or salvages damaged
files on a copy when it has to, and turns them into FerretDB (SQLite) data.

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

Thanks to above GitHub users for their contributions and translators for their translations.
