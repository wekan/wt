#!/usr/bin/env bash
#
# build.sh - interactive helper for wt (raw MongoDB 3.0 - 8.x data files -> FerretDB), like
# FerretDB's build.sh.
#
# Usage:
#   ./build.sh                   # interactive menu
#   ./build.sh <command>         # run one action non-interactively:
#   ./build.sh deps              # check docker, node and gh
#   ./build.sh dist              # build wt-<this platform>.tar.gz into dist/ (Docker)
#   ./build.sh test [versions]   # read real mongod data (default 4.4 6.0 8.0) with that tarball
#   ./build.sh test-all          # ... every mongod from 3.0 to 8.0 (3.0 needs the amd64 reader)
#   ./build.sh data <version>    # make real mongod data with the official image (data/<version>)
#   ./build.sh release [version]         # trigger release-all.yml only (no commit)
#   ./build.sh release-all [version]     # audit, rename Upcoming, commit + push, run release-all.yml
#   ./build.sh release-all-missing [v]   # audit the release and build only the missing platforms
#   ./build.sh audit             # offline checks only (what release-all runs first)
#   ./build.sh clean             # remove dist/, out/, run/
#
# The release commands push and dispatch GitHub workflows: they are for the human maintainer.
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
. "$ROOT/releases/lib.sh"

host_platform() {
  local os arch
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$(uname -m)" in x86_64|amd64) arch=amd64;; aarch64|arm64) arch=arm64;; s390x) arch=s390x;; ppc64le) arch=ppc64le;; riscv64) arch=riscv64;; armv7l) arch=armv7;; *) arch="$(uname -m)";; esac
  # Docker on a Mac builds Linux images
  [ "$os" = darwin ] && os=linux
  echo "$os-$arch"
}

act_deps() {
  local bad=0
  for c in docker node bash; do command -v "$c" >/dev/null 2>&1 && info "$c: ok" || { err "$c is missing"; bad=1; }; done
  command -v gh >/dev/null 2>&1 && info "gh: ok" || warn "gh is missing (only the release commands need it)"
  docker info >/dev/null 2>&1 || { err "the docker daemon is not running"; bad=1; }
  return $bad
}

act_dist() {
  act_deps || return 1
  local p; p="$(host_platform)"
  info "Building wt for $p (WiredTiger 11.3, 3.1 and, on x86_64, 2.5) - the first build takes a while ..."
  docker build -f Dockerfile.release --target dist -t "wt-release:$p" . || return 1
  rm -rf "$ROOT/run/dist-$p"; mkdir -p "$ROOT/run/dist-$p" "$ROOT/dist"
  local c; c="$(docker create "wt-release:$p" /x)"
  docker cp "$c:/." "$ROOT/run/dist-$p/" >/dev/null 2>&1; docker rm "$c" >/dev/null
  rm -rf "$ROOT/run/dist-$p"/{dev,etc,proc,sys,.dockerenv}
  tar -C "$ROOT/run/dist-$p" -czf "$ROOT/dist/wt-$p.tar.gz" .
  (cd "$ROOT/dist" && { sha256sum "wt-$p.tar.gz" 2>/dev/null || shasum -a 256 "wt-$p.tar.gz"; } > "wt-$p.tar.gz.sha256sum")
  info "dist/wt-$p.tar.gz ($(du -h "dist/wt-$p.tar.gz" | cut -f1)); readers: $(ls -d "$ROOT"/run/dist-$p/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"
}

act_data() { bash "$ROOT/make-data.sh" "$1"; }

act_test() {
  local p; p="$(host_platform)"
  [ -f "$ROOT/dist/wt-$p.tar.gz" ] || act_dist || return 1
  bash "$ROOT/tests/ci-roundtrip.sh" "$ROOT/dist/wt-$p.tar.gz" "$@"
}

act_test_all() { act_test 3.2 3.6 4.0 4.2 4.4 5.0 6.0 7.0 8.0; }

act_audit() { audit "$ROOT"; }

act_clean() { rm -rf "$ROOT/dist" "$ROOT/out" "$ROOT/run" "$ROOT/dist-test"; info "removed dist/, out/, run/"; }

act_release() { trigger_workflow release-all.yml "${1:-$(next_version)}"; }

menu() {
  while true; do
    printf '\nwt - build.sh\n'
    cat <<EOF
  1) Check tools                  (docker, node, gh)
  2) Build wt for this platform   (-> dist/wt-<platform>.tar.gz, via Docker)
  3) Test with real mongod data   (4.4, 6.0 and 8.0 from the official images)
  4) Test every mongod 3.2 - 8.0
  5) Make mongod data             (enter a version -> data/<version>)
  6) Audit                        (offline checks that Release All runs first)
  7) Release via GitHub Actions   (trigger release-all.yml, no commit)
  8) Release All                  (audit, rename Upcoming, commit + push, run release-all.yml)
  9) Release All Missing          (build only the platforms the release lacks)
 10) Clean
  0) Exit
EOF
    printf 'Select: '; read -r choice
    case "$choice" in
      1) act_deps ;;
      2) act_dist ;;
      3) act_test ;;
      4) act_test_all ;;
      5) printf 'mongod version (e.g. 6.0): '; read -r v; act_data "$v" ;;
      6) act_audit ;;
      7) printf 'Release tag (e.g. v0.01; empty = the next one): '; read -r v; act_release "$v" ;;
      8) bash "$ROOT/releases/release-all.sh" ;;
      9) bash "$ROOT/releases/release-all-missing.sh" ;;
      10) act_clean ;;
      0|q|Q) info "Bye."; exit 0 ;;
      *) warn "Unknown option: $choice" ;;
    esac
  done
}

case "${1:-}" in
  "")  if [ -t 0 ]; then menu; else err "No command given and stdin is not a terminal. Run '$0 --help'."; exit 2; fi ;;
  deps) act_deps ;;
  dist) act_dist ;;
  test) shift; act_test "$@" ;;
  test-all) act_test_all ;;
  data) shift; act_data "${1:?mongod version}" ;;
  audit) act_audit ;;
  release) shift; act_release "${1:-}" ;;
  release-all) shift; bash "$ROOT/releases/release-all.sh" "$@" ;;
  release-all-missing) shift; bash "$ROOT/releases/release-all-missing.sh" "$@" ;;
  clean) act_clean ;;
  -h|--help|help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//' ;;
  *) err "Unknown command: $1"; err "Run '$0 --help' for usage."; exit 2 ;;
esac
