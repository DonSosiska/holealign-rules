#!/usr/bin/env bash
# Publish a signed rules bundle to the gh-pages branch (GitHub Pages).
#
# usage: scripts/publish-pages.sh <dist-dir> <seq>
#
# <dist-dir> holds rules-<seq>.tar.gz, rules-<seq>.tar.gz.sig and latest.json.
# The branch keeps the newest KEEP_BUNDLES bundles (default 5), an index.html
# listing them, and latest.json, which points at the newest one. Everything goes
# into one commit, so servers never see a pointer to a missing file.
#
# Run from a checkout of this repository whose origin allows pushing (the release
# workflow uses the job token with contents: write). Set DRY_RUN=1 to build the
# branch content in a temporary worktree and skip the push.
set -euo pipefail
export LC_ALL=C

if (( $# != 2 )); then
  echo "usage: $0 <dist-dir> <seq>" >&2
  exit 2
fi
dist="$(cd "$1" && pwd)"
seq="$2"
keep="${KEEP_BUNDLES:-5}"
if [[ ! "$seq" =~ ^[0-9]+$ ]]; then
  echo "error: seq must be a number: $seq" >&2
  exit 2
fi
if [[ ! "$keep" =~ ^[0-9]+$ ]] || (( keep < 1 )); then
  echo "error: KEEP_BUNDLES must be a positive number: $keep" >&2
  exit 2
fi
for f in "rules-$seq.tar.gz" "rules-$seq.tar.gz.sig" latest.json; do
  if [[ ! -f "$dist/$f" ]]; then
    echo "error: $dist/$f not found" >&2
    exit 1
  fi
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

tmp="$(mktemp -d)"
wt="$tmp/pages"
cleanup() {
  git worktree remove --force "$wt" >/dev/null 2>&1 || true
  rm -rf "$tmp"
}
trap cleanup EXIT

if git ls-remote --exit-code --heads origin gh-pages >/dev/null 2>&1; then
  git fetch --no-tags --depth=1 origin gh-pages
  git worktree add --detach "$wt" FETCH_HEAD
else
  git worktree add --detach "$wt"
  git -C "$wt" checkout --orphan gh-pages
  git -C "$wt" rm -rf --quiet . || true
  find "$wt" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf {} +
fi

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | cut -d' ' -f1
  else
    shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

cd "$wt"
touch .nojekyll
cp "$dist/rules-$seq.tar.gz" "$dist/rules-$seq.tar.gz.sig" .

# Drop everything but the newest $keep bundles (and never the one just added).
mapfile -t bundles < <(find . -maxdepth 1 -name 'rules-*.tar.gz' -printf '%f\n' 2>/dev/null \
  || find . -maxdepth 1 -name 'rules-*.tar.gz' | sed 's|^\./||')
numbers=()
for b in "${bundles[@]}"; do
  if [[ "$b" =~ ^rules-([0-9]+)\.tar\.gz$ ]]; then
    numbers+=("$((10#${BASH_REMATCH[1]}))")
  fi
done
mapfile -t sorted < <(printf '%s\n' "${numbers[@]}" | sort -rn)
kept=()
for i in "${!sorted[@]}"; do
  n="${sorted[$i]}"
  if (( i < keep )); then
    kept+=("$n")
  else
    rm -f "rules-$n.tar.gz" "rules-$n.tar.gz.sig"
  fi
done

{
  echo '<!doctype html>'
  echo '<meta charset="utf-8">'
  echo '<title>Panoptes rules feed</title>'
  echo '<h1>Panoptes rules feed</h1>'
  echo '<p>Servers poll <a href="latest.json">latest.json</a>. Bundles are signed (ed25519); verify them against the public key published in the repository.</p>'
  echo '<ul>'
  for n in "${kept[@]}"; do
    sum="$(sha256 "rules-$n.tar.gz")"
    echo "<li><a href=\"rules-$n.tar.gz\">rules-$n.tar.gz</a> (<a href=\"rules-$n.tar.gz.sig\">sig</a>) sha256 <code>$sum</code></li>"
  done
  echo '</ul>'
} > index.html

# The pointer goes in last, within the same commit.
cp "$dist/latest.json" latest.json

git add -A
if git diff --cached --quiet; then
  echo "gh-pages is already up to date"
  exit 0
fi
git -c user.name=github-actions[bot] \
    -c user.email=41898282+github-actions[bot]@users.noreply.github.com \
    commit --quiet -m "Publish rules-$seq"

if [[ "${DRY_RUN:-}" == "1" ]]; then
  echo "dry run: not pushing; would publish: ${kept[*]}"
  git log --stat -1 --format=%s
  exit 0
fi
git push origin HEAD:refs/heads/gh-pages
echo "published rules-$seq; bundles on pages: ${kept[*]}"
