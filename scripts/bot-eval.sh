#!/usr/bin/env bash
# Measures how well each model drafts rules: panoptes-server "rules eval" drafts every
# reviewed rule in rules/ again (without showing it to the model) and scores the draft
# against the reviewed tests in tests/. It spends real money (see docs/maintainers.md).
#
# usage: scripts/bot-eval.sh <variants> <runs> <out-dir>
#
# Environment: PANOPTES_SERVER, the ANTHROPIC_* workload identity variables and
# ANTHROPIC_OIDC_AUDIENCE (see scripts/bot-drafts.sh). No API key may be set.
set -euo pipefail

if [[ $# -ne 3 ]]; then
  echo "usage: $0 <variants> <runs> <out-dir>" >&2
  exit 2
fi
variants="$1"
runs="$2"
out="$3"
: "${PANOPTES_SERVER:?PANOPTES_SERVER is required}"
if [[ ! "$variants" =~ ^[a-z0-9.@,-]+$ ]]; then
  echo "error: variants must look like model[@effort],..." >&2
  exit 2
fi
if [[ ! "$runs" =~ ^[0-9]+$ ]] || (( runs < 1 || runs > 10 )); then
  echo "error: runs must be a number between 1 and 10" >&2
  exit 2
fi
for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN ANTHROPIC_PROFILE PANOPTES_LLM_API_KEY; do
  if [[ -n "${!v:-}" ]]; then
    echo "error: $v is set; the evaluation uses workload identity federation only" >&2
    exit 2
  fi
done

# shellcheck source=scripts/lib-oidc.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib-oidc.sh"

mkdir -p "$out"
refresh_identity_token
# Keep the token file fresh while the evaluation runs (it can take tens of minutes).
( while sleep 30; do refresh_identity_token; done ) &
refresher=$!
trap 'kill "$refresher" 2>/dev/null || true' EXIT

rc=0
env -u GH_TOKEN -u GITHUB_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_TOKEN -u ACTIONS_ID_TOKEN_REQUEST_URL \
  "$PANOPTES_SERVER" rules eval -rules rules -tests tests -variants "$variants" -runs "$runs" \
  -out "$out/report.json" > "$out/summary.md" 2> "$out/eval.log" || rc=$?
cat "$out/summary.md"
exit "$rc"
