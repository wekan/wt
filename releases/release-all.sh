#!/usr/bin/env bash
# release-all.sh [vMAJOR.MINOR]  - HUMAN MAINTAINER ONLY (it pushes). Audits, renames
# "# Upcoming wt release" to the new version, commits, pushes and dispatches release-all.yml, which
# builds wt-<platform>.tar.gz for every platform and publishes the GitHub Release.
# Without a version it takes the one after the newest release on GitHub.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"; cd "$root"
. "$root/releases/lib.sh"
need_gh
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || { err "release from main"; exit 1; }
audit "$root"
version="${1:-$(next_version)}"; valid_version "$version"
git ls-remote --exit-code --tags origin "refs/tags/$version" >/dev/null 2>&1 && { err "$version is already tagged"; exit 1; }
today="$(date +%Y-%m-%d)"
python3 - "$version" "$today" <<'PY'
import sys
v, d = sys.argv[1:]
s = open('CHANGELOG.md').read()
s = s.replace('# Upcoming wt release', f'# {v} {d} wt release', 1)
open('CHANGELOG.md', 'w').write(s)
PY
git add CHANGELOG.md
git commit -q -m "Prepare $version release."
info "Pushing main ..."
git push origin main
trigger_workflow release-all.yml "$version"
