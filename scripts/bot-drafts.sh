#!/usr/bin/env bash
# Draft rules for the candidates in a candidates.json and open one PR per draft.
#
# usage: scripts/bot-drafts.sh <candidates.json> <max>
#
# Environment: PANOPTES_SERVER (path to panoptes-server), GH_TOKEN, and the
# PANOPTES_LLM_* variables read by "rules draft". Run from a checkout of this
# repository whose origin allows pushing, on a clean tree.
#
# Candidate fields come from vulnerability databases and are treated as
# untrusted: ids and package names are validated before they reach a branch name.
set -euo pipefail
export LC_ALL=C

if (( $# != 2 )); then
  echo "usage: $0 <candidates.json> <max>" >&2
  exit 2
fi
cand="$1"
max="$2"
: "${PANOPTES_SERVER:?PANOPTES_SERVER is required}"
if [[ ! "$max" =~ ^[0-9]+$ ]]; then
  echo "error: max must be a number: $max" >&2
  exit 2
fi

bot_name="github-actions[bot]"
bot_email="41898282+github-actions[bot]@users.noreply.github.com"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

gh label create bot-draft --color FBCA04 \
  --description "Rule drafted by the bot; needs human review" >/dev/null 2>&1 || true

total="$(jq 'length' "$cand")"
echo "candidates: $total, draft limit: $max"
created=0
for ((i = 0; i < total && created < max; i++)); do
  vuln="$(jq -r ".[$i].vuln" "$cand")"
  pkg="$(jq -r ".[$i].package" "$cand")"
  if [[ ! "$vuln" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$ ]]; then
    echo "skip #$i: unexpected vulnerability id"
    continue
  fi
  if [[ ! "$pkg" =~ ^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$ ]]; then
    echo "skip #$i ($vuln): unexpected package name"
    continue
  fi
  branch="bot/$vuln-$pkg"

  if git ls-remote --exit-code --heads origin "$branch" >/dev/null 2>&1; then
    echo "skip $branch: branch exists"
    continue
  fi
  existing="$(gh pr list --head "$branch" --state all --json number --jq 'length')"
  if [[ "$existing" != "0" ]]; then
    echo "skip $branch: a pull request already exists"
    continue
  fi

  git switch --quiet --detach origin/main
  git reset --quiet --hard
  git clean -fdq -- rules tests
  git switch --quiet -c "$branch"

  body="$work/body-$i.md"
  rc=0
  "$PANOPTES_SERVER" rules draft -candidate-file "$cand" -index "$i" \
    -rules rules -tests tests -out-rules rules -out-tests tests > "$body" || rc=$?
  if (( rc == 2 )); then
    echo "skip $branch: drafter refused or produced an invalid rule"
    continue
  fi
  if (( rc != 0 )); then
    echo "::warning::rules draft failed for $branch (exit $rc)"
    continue
  fi

  git add rules tests
  if git diff --cached --quiet; then
    echo "skip $branch: nothing to commit"
    continue
  fi
  {
    echo
    echo "---"
    echo "This rule was drafted by an LLM and has status draft. Check every condition against the"
    echo "advisory before approving, set status: reviewed, and make sure validate passes."
  } >> "$body"

  git -c user.name="$bot_name" -c user.email="$bot_email" \
    commit --quiet -m "Draft rule for $vuln ($pkg)"
  git push --quiet origin "$branch"
  gh pr create --base main --head "$branch" --label bot-draft \
    --title "Draft rule: $vuln ($pkg)" --body-file "$body"
  created=$((created + 1))
done

git switch --quiet --detach origin/main
echo "pull requests opened: $created"
