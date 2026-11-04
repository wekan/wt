# shared by build.sh and releases/*.sh - sourced, not run
REPO_SLUG_DEFAULT="wekan/wt"
# The platforms are the ones in platforms.json (the platform names of wekan/node-patches), the one list the
# workflows, this script and the tests all read.
WT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLATFORMS="$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1] + "/platforms.json", "utf8")).map(p => p.platform).join(" "))' "$WT_ROOT")"

info() { printf '==> %s\n' "$*"; }
warn() { printf '==> %s\n' "$*"; }
err()  { printf '==> %s\n' "$*" >&2; }

repo_slug() {
  local r
  r="$(git remote get-url origin 2>/dev/null | sed -E 's#^(git@github.com:|https://github.com/)##; s#\.git$##')"
  printf '%s' "${r:-$REPO_SLUG_DEFAULT}"
}

# A release tag is v<MAJOR>.<MM>: the minor is always TWO digits. The first release is v0.01, the next
# v0.02, and so on; v0.99 is followed by v1.00 (the way WeKan goes from 9.99 to 10.00).
valid_version() { [[ "$1" =~ ^v[0-9]+\.[0-9]{2}$ ]] || { err "version must look like v0.01 (got '$1')"; return 1; }; }

# bump_version [last]  - the version after `last`; v0.01 when there is none. Pure, so it is testable.
# 10# makes the minor decimal: "08" and "09" are not octal numbers, and bash would refuse them.
bump_version() {
  local last="${1:-}" major minor
  [ -n "$last" ] || { echo v0.01; return; }
  major="${last#v}"; major="${major%%.*}"; minor="${last##*.}"
  minor=$((10#$minor + 1)); major=$((10#$major))
  if [ "$minor" -gt 99 ]; then major=$((major + 1)); minor=0; fi
  printf 'v%d.%02d\n' "$major" "$minor"
}

# The release after the newest one on GitHub (v0.01 when there is none).
next_version() {
  local repo last
  repo="$(repo_slug)"
  last="$(gh release list -R "$repo" --limit 100 --json tagName -q '.[].tagName' 2>/dev/null \
    | grep -E '^v[0-9]+\.[0-9]{2}$' | sort -V | tail -1 || true)"
  bump_version "$last"
}

need_gh() {
  command -v gh >/dev/null 2>&1 || { err "'gh' (GitHub CLI) is required: https://cli.github.com/"; return 1; }
  gh auth status -h github.com >/dev/null 2>&1 || { err "gh is not authenticated: run 'gh auth login' (or set GH_TOKEN)."; return 1; }
}

# trigger_workflow <workflow file> [version]   - dispatch on the current branch, retried for the
# race right after a new workflow was pushed, with the REST API as the fallback.
trigger_workflow() {
  need_gh || return 1
  local wf="$1" version="${2:-}" branch repo i ok=0
  repo="$(repo_slug)"; branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)"
  info "Triggering $wf on '$repo' ('$branch')${version:+ (version $version)} ..."
  for i in 1 2 3 4 5; do
    if [ -n "$version" ]; then gh workflow run "$wf" -R "$repo" --ref "$branch" -f version="$version" && { ok=1; break; }
    else gh workflow run "$wf" -R "$repo" --ref "$branch" && { ok=1; break; }; fi
    warn "trigger attempt $i/5 failed (GitHub may still be registering '$wf'); retrying in 5s ..."; sleep 5
  done
  if [ "$ok" -ne 1 ]; then
    warn "Falling back to the REST dispatch API ..."
    printf '{"ref":"%s","inputs":{"version":"%s"}}' "$branch" "$version" \
      | gh api "repos/$repo/actions/workflows/$wf/dispatches" --input - && ok=1
  fi
  [ "$ok" -eq 1 ] || { err "Could not dispatch $wf on $repo (a classic PAT needs the 'workflow' scope: gh auth refresh -h github.com -s workflow)."; return 1; }
  info "Triggered. Track progress at: https://github.com/$repo/actions"
}

# audit: everything that can be checked without the network
audit() {
  local root="$1" bad=0
  command -v node >/dev/null && { node --check "$root/wt.mjs" || bad=1; }
  for f in "$root"/build.sh "$root"/releases/*.sh "$root"/tests/*.sh "$root"/make-data.sh "$root"/make-unclean.sh; do
    bash -n "$f" || { err "syntax error in $f"; bad=1; }
  done
  grep -q '^# Upcoming wt release' "$root/CHANGELOG.md" || { err "CHANGELOG.md has no '# Upcoming wt release' section"; bad=1; }
  if [ -n "$(git -C "$root" status --porcelain)" ]; then err "the working tree is not clean: commit first"; bad=1; fi
  [ "$bad" -eq 0 ]
}
