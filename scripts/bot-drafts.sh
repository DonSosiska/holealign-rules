#!/usr/bin/env bash
# Draft rules for the candidates in a candidates.json and open one PR per draft.
#
# usage: scripts/bot-drafts.sh <candidates.json> <max>
#
# Environment: PANOPTES_SERVER (path to panoptes-server), GH_TOKEN, and the
# PANOPTES_LLM_* variables read by "rules draft". Run from a checkout of this
# repository whose origin allows pushing, on a clean tree.
#
# DRY_RUN=1 only lists the candidates and whether each would be drafted. It touches
# neither git, GitHub nor the LLM.
#
# "rules draft" exit codes: 0 a rule was written (commit and pull request), 2 no valid
# draft (skipped), 3 a rule with that ID already exists (skipped), anything else is an
# error: the remaining candidates are still processed and the run fails at the end.
#
# Candidate fields come from vulnerability databases and are treated as
# untrusted: ids and source package names are validated before they reach a branch name.
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

vuln_re='^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'
source_re='^[A-Za-z0-9][A-Za-z0-9.+_-]{0,127}$'

total="$(jq 'length' "$cand")"

if [[ "${DRY_RUN:-0}" == 1 ]]; then
  echo "dry run: candidates: $total, draft limit: $max"
  listed=0
  for ((i = 0; i < total && listed < max; i++)); do
    vuln="$(jq -r ".[$i].vuln" "$cand")"
    src="$(jq -r ".[$i].source" "$cand")"
    eco="$(jq -r ".[$i].ecosystem" "$cand")"
    sev="$(jq -r ".[$i].severity" "$cand")"
    kev="$(jq -r ".[$i].kev" "$cand")"
    published="$(jq -r ".[$i].published" "$cand")"
    status="would draft"
    if [[ ! "$vuln" =~ $vuln_re ]]; then
      status="skip: unexpected vulnerability id"
    elif [[ ! "$src" =~ $source_re ]]; then
      status="skip: unexpected source package name"
    fi
    echo "#$i $vuln source=$src ecosystem=$eco severity=$sev kev=$kev published=$published -> $status"
    listed=$((listed + 1))
  done
  echo "dry run: nothing drafted"
  exit 0
fi

bot_name="github-actions[bot]"
bot_email="41898282+github-actions[bot]@users.noreply.github.com"
work="$(mktemp -d)"
trap 'rm -rf -- "$work"' EXIT

gh label create bot-draft --color FBCA04 \
  --description "Rule drafted by the bot; needs human review" >/dev/null 2>&1 || true

echo "candidates: $total, draft limit: $max"
created=0
failed=0
for ((i = 0; i < total && created < max; i++)); do
  vuln="$(jq -r ".[$i].vuln" "$cand")"
  src="$(jq -r ".[$i].source" "$cand")"
  if [[ ! "$vuln" =~ $vuln_re ]]; then
    echo "skip #$i: unexpected vulnerability id"
    continue
  fi
  if [[ ! "$src" =~ $source_re ]]; then
    echo "skip #$i ($vuln): unexpected source package name"
    continue
  fi
  branch="bot/$vuln-$src"

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
  git switch --quiet -C "$branch"

  body="$work/body-$i.md"
  rc=0
  "$PANOPTES_SERVER" rules draft -candidate-file "$cand" -index "$i" \
    -rules rules -tests tests -out-rules rules -out-tests tests > "$body" || rc=$?
  case "$rc" in
    0) ;;
    2)
      echo "skip $branch: no valid draft"
      continue
      ;;
    3)
      echo "skip $branch: rule already exists"
      continue
      ;;
    *)
      echo "::error::rules draft failed for $branch (exit $rc)"
      failed=$((failed + 1))
      continue
      ;;
  esac

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
    commit --quiet -m "Draft rule for $vuln ($src)"
  git push --quiet origin "$branch"
  gh pr create --base main --head "$branch" --label bot-draft \
    --title "Draft rule: $vuln ($src)" --body-file "$body"
  created=$((created + 1))
done

git switch --quiet --detach origin/main
echo "pull requests opened: $created, drafts failed: $failed"
if (( failed > 0 )); then
  exit 1
fi
