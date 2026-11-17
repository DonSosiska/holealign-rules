#!/usr/bin/env bash
# Print the next rules bundle sequence number: (highest rules-<n> tag or GitHub
# release) + 1, or 1 when there is none yet.
#
# Needs a checkout with tags (fetch-depth: 0) and, to also look at releases,
# GH_TOKEN and GH_REPO (or a gh default repository). Releases are consulted so a
# deleted tag can never lead to a reused number.
set -euo pipefail
export LC_ALL=C

names="$(git tag --list 'rules-*' || true)"
if command -v gh >/dev/null 2>&1 && [[ -n "${GH_TOKEN:-}" ]]; then
  rel="$(gh release list --limit 1000 --json tagName --jq '.[].tagName')"
  names="$names"$'\n'"$rel"
fi

max=0
while IFS= read -r name; do
  if [[ "$name" =~ ^rules-([0-9]+)$ ]]; then
    n=$((10#${BASH_REMATCH[1]}))
    if (( n > max )); then
      max=$n
    fi
  fi
done <<< "$names"

echo $((max + 1))
