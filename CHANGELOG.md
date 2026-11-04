# Changelog

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
