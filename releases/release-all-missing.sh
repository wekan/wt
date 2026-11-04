#!/usr/bin/env bash
# release-all-missing.sh [vMAJOR.MINOR]  - HUMAN MAINTAINER ONLY. Builds only what the release does
# not have yet: a platform counts as present only when BOTH wt-<platform>.tar.gz and its .sha256sum
# are on the release. Without a version it completes the newest release.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. "$root/releases/lib.sh"
need_gh
version="${1:-}"
if [ -z "$version" ]; then
  version="$(gh release list -R "$(repo_slug)" --limit 100 --json tagName -q '.[].tagName' | grep -E '^v[0-9]+\.[0-9]{2}$' | sort -V | tail -1 || true)"
fi
[ -n "$version" ] || { err "no release to complete: run releases/release-all.sh first"; exit 1; }
valid_version "$version"
assets="$(gh release view "$version" -R "$(repo_slug)" --json assets -q '.assets[].name' 2>/dev/null || true)"
missing=""
for p in $PLATFORMS; do
  echo "$assets" | grep -qx "wt-$p.tar.gz" && echo "$assets" | grep -qx "wt-$p.tar.gz.sha256sum" || missing="$missing $p"
done
[ -n "$missing" ] || { info "$version already has every platform."; exit 0; }
info "$version is missing:$missing"
git push origin "$(git rev-parse --abbrev-ref HEAD)" || warn "nothing to push, or the push failed; continuing"
trigger_workflow release-all-missing.yml "$version"
