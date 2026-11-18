# shellcheck shell=bash
# Shared by the bot scripts: keeps the GitHub OIDC token for Anthropic workload identity
# federation fresh in ANTHROPIC_IDENTITY_TOKEN_FILE. GitHub OIDC tokens live only a few
# minutes; the token is re-fetched when the file is older than 4 minutes.
#
# This is the only place that reads ACTIONS_ID_TOKEN_REQUEST_URL / _TOKEN. Callers run the
# panoptes-server process with those variables removed from its environment.
refresh_identity_token() {
  if [[ -z "${ACTIONS_ID_TOKEN_REQUEST_URL:-}" ]]; then
    return 0
  fi
  local jwt="${ANTHROPIC_IDENTITY_TOKEN_FILE:?ANTHROPIC_IDENTITY_TOKEN_FILE is required}"
  if [[ -f "$jwt" && -z "$(find "$jwt" -mmin +4 -print -quit)" ]]; then
    return 0
  fi
  : "${ANTHROPIC_OIDC_AUDIENCE:?ANTHROPIC_OIDC_AUDIENCE is required}"
  local url="$ACTIONS_ID_TOKEN_REQUEST_URL" sep='?' aud response token
  if [[ "$url" == *\?* ]]; then sep='&'; fi
  aud="$(jq -rn --arg a "$ANTHROPIC_OIDC_AUDIENCE" '$a | @uri')"
  response="$(curl --fail --silent --show-error \
    -H "Authorization: bearer ${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?}" \
    "${url}${sep}audience=${aud}")"
  token="$(jq -r '.value // empty' <<<"$response")"
  if [[ -z "$token" ]]; then
    echo "::error::GitHub did not return an OIDC token" >&2
    exit 1
  fi
  echo "::add-mask::$token"
  (umask 077 && printf '%s' "$token" > "$jwt.tmp" && mv -f "$jwt.tmp" "$jwt")
}
