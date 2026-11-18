# Bot setup

The rules bot (`.github/workflows/bot.yml`) drafts rules with an LLM. It calls Anthropic through
**workload identity federation**: the workflow presents its GitHub OIDC token, Anthropic exchanges it for
short-lived credentials bound to a service account. **No API key is stored anywhere**: not in the
repository, not in a secret, not in the workflow. The bot has no `HOLEALIGN_LLM_API_KEY` secret any more;
delete it if it still exists.

## 1. Anthropic Console

1. Create a dedicated service account for the bot, in a workspace that has a monthly spend limit.
2. Create a GitHub Actions federation rule. Match on the immutable identifiers, the workflow and the event,
   not only on names. The conditions, with the exact values and the pitfall seen in the Console, are in
   [maintainers.md](maintainers.md#anthropic-federation-the-token-and-the-rule). In short: `repository_owner_id`,
   `repository_id`, `ref` `refs/heads/main`, `job_workflow_ref` of `.github/workflows/bot.yml` at `main`, workflow
   `bot`, `event_name` in `schedule` and `workflow_dispatch`, and the audience.
3. Bind the rule to that service account. Note the federation rule ID, the organization ID, the
   service account ID, the workspace ID (only if the rule spans several workspaces), and the OIDC
   audience the rule expects. The Console shows the audience when the rule is created.

## 2. Repository variables

Set these as repository **variables** (Settings, Secrets and variables, Variables). They are
identifiers, not secrets. The bot stays disabled until the first four are set.

| Variable | Value |
|---|---|
| `ANTHROPIC_FEDERATION_RULE_ID` | ID of the federation rule |
| `ANTHROPIC_ORGANIZATION_ID` | ID of the Anthropic organization |
| `ANTHROPIC_SERVICE_ACCOUNT_ID` | ID of the bot's service account |
| `ANTHROPIC_OIDC_AUDIENCE` | OIDC audience the federation rule expects |
| `ANTHROPIC_WORKSPACE_ID` | optional; only if the federation rule spans several workspaces |

With the GitHub CLI:

```sh
gh variable set ANTHROPIC_FEDERATION_RULE_ID --repo DonSosiska/holealign-rules --body '<rule id>'
gh variable set ANTHROPIC_ORGANIZATION_ID --repo DonSosiska/holealign-rules --body '<organization id>'
gh variable set ANTHROPIC_SERVICE_ACCOUNT_ID --repo DonSosiska/holealign-rules --body '<service account id>'
gh variable set ANTHROPIC_OIDC_AUDIENCE --repo DonSosiska/holealign-rules --body '<audience>'
gh variable set ANTHROPIC_WORKSPACE_ID --repo DonSosiska/holealign-rules --body '<workspace id>'   # optional
gh secret delete HOLEALIGN_LLM_API_KEY --repo DonSosiska/holealign-rules                          # if present
```

If any of the three IDs or the audience is empty, the job logs `bot disabled: workload identity
variables are not set` and succeeds without doing anything.

## 3. How a run authenticates

- The job has `id-token: write`. `scripts/bot-drafts.sh` requests a GitHub OIDC token for the audience and writes it to a
  file under `$RUNNER_TEMP` (umask 077, masked in the log). The file is removed in a final `always()` step.
- The Anthropic SDK inside `holealign-server rules draft` reads the token file and exchanges it for
  credentials. It needs no key.
- GitHub OIDC tokens last only a few minutes. `scripts/bot-drafts.sh` re-fetches the token file before each
  draft when it is older than four minutes.
- The checkout stores no credentials (`persist-credentials: false`). The workflow token reaches the script as
  `BOT_TOKEN`, which the script moves into an unexported variable and hands only to `git push` and to each `gh`
  command. `rules candidates` and `rules draft`, which parse untrusted OSV, KEV and LLM data, run with `GH_TOKEN`,
  `GITHUB_TOKEN`, `ACTIONS_ID_TOKEN_REQUEST_TOKEN` and `ACTIONS_ID_TOKEN_REQUEST_URL` removed from their environment;
  only the token-refresh function in the script reads the two `ACTIONS_*` variables.
- Pull requests are opened as GitHub drafts.
- The script refuses to run if `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_PROFILE` or
  `HOLEALIGN_LLM_API_KEY` is set, because those would take precedence over the federation.

## 4. Checks

- Model: `claude-sonnet-5-5` (`HOLEALIGN_LLM_MODEL` in `bot.yml`).
- Start with a small manual run: `gh workflow run bot.yml --repo DonSosiska/holealign-rules --ref main -f max=1`.
  A `match_claim_value_mismatch` error means a federation rule condition differs from the token.
- Revoke the bot's access by deleting or disabling the federation rule or the service account in the
  Console. No key needs rotating, because none exists.

Day-to-day operation (schedule, `max`, disabling, costs, incidents) is in [maintainers.md](maintainers.md#bot-operations);
reviewing the drafts is in [reviewing.md](reviewing.md).
