# Maintainer guide

Runbooks for the people who run releases, the bot and the signing key. Contributors and reviewers need
[CONTRIBUTING.md](../CONTRIBUTING.md) and [reviewing.md](reviewing.md) instead.

Contents: [Settings the workflows assume](#settings-the-workflows-assume) -
[Release runbook](#release-runbook) - [Pages and rollback](#pages-and-rollback) -
[Signing key rotation](#signing-key-rotation) - [Bumping HOLEALIGN_REF](#bumping-holealign_ref) -
[Keeping the shared rules identical](#keeping-the-shared-rules-identical) -
[Bot operations](#bot-operations) - [Incident response](#incident-response)

## Settings the workflows assume

These live in GitHub, not in the repository, so check them when something does not work. The release and bot
workflows rely on the first four.

| Setting | Value |
|---|---|
| Environment `rules-release` | Secret `RULES_SIGNING_KEY`; required reviewers; deployment branches limited to `main`. |
| Pages | Source: the `gh-pages` branch. The release creates the branch on the first run. |
| Repository variables | `ANTHROPIC_*` for the bot, see [bot-setup.md](bot-setup.md). |
| Label `rule-request` | Used by the issue template. |
| Private vulnerability reporting | Enabled, so that [SECURITY.md](../SECURITY.md) works. |
| Branch protection on `main` | Recommended: require the `validate` check and a code owner review ([`CODEOWNERS`](../.github/CODEOWNERS)). |

## Release runbook

### What triggers a release

`.github/workflows/release.yml` runs on:

- a push to `main` that changes `rules/**` or `tests/**` (a merged rule pull request);
- `workflow_dispatch`, run on `main`. The job has `if: github.ref == 'refs/heads/main'`, so it does nothing
  on another ref.

A change to `HOLEALIGN_REF`, a script or a workflow alone does not release. Releases do not run in parallel
(concurrency group `rules-release`, never cancelled).

### Approve it

The job uses the `rules-release` environment, which holds the signing key, so it waits for a required reviewer.
Before you approve, read the commit: the run builds the tip of `main`, which is what you are about to sign
and publish to every server.

```sh
gh run list --workflow release.yml --repo DonSosiska/holealign-rules --limit 5
gh run view <run-id> --repo DonSosiska/holealign-rules --log          # after it finished
```

### What the job checks and does

| Step | Check or action |
|---|---|
| Require HEAD to be the tip of main | `git ls-remote origin refs/heads/main` must equal `HEAD`. If another commit landed meanwhile, or you re-run an old run, the job fails: it must not publish an older rule set under a newer `seq`. The newer commit has its own run. |
| Require the public key | `keys/rules-public.key` must exist and be non-empty. |
| Build holealign-server | `HOLEALIGN_REF` must be a 40-hex SHA that is an ancestor of Holealign `main` ([why](#bumping-holealign_ref)). |
| Next sequence number | `scripts/next-seq.sh`: highest `rules-<n>` among tags and GitHub releases, plus one (1 when none). Releases are consulted too, so a deleted tag cannot lead to a reused number. |
| Build bundle | `rules build -rules rules -tests tests -seq <seq>` with `SOURCE_DATE_EPOCH` set to the commit time, so the archive is deterministic. Any invalid, draft or untested rule, or failing test, stops the job. |
| Write signing key, sign, remove key | The secret is read in the one step that writes a mode 0600 file; the signer reads the file; the file is removed in an `always()` step. |
| Verify | `rules verify` of the bundle against `keys/rules-public.key`. This catches a secret that does not match the committed public key. |
| GitHub release | `rules-<seq>` with `rules-<seq>.tar.gz`, `.sig` and `latest.json`, targeting the commit. |
| Publish to GitHub Pages | `scripts/publish-pages.sh`, see below. |

### Failures

| Symptom | Cause and action |
|---|---|
| `HEAD ... is not the current tip of main` | Superseded. Approve the run of the newest commit instead. |
| `keys/rules-public.key is missing` | See [keys/README.md](../keys/README.md#first-setup). |
| `secret RULES_SIGNING_KEY is not set` | The secret is missing from the `rules-release` environment (an environment secret, not a repository secret). |
| Verify fails | The secret and `keys/rules-public.key` are not a pair. Nothing was published. Fix the secret or the file. |
| `HOLEALIGN_REF ... is not an ancestor of ... main` | See [Bumping HOLEALIGN_REF](#bumping-holealign_ref). |
| Failure after `GitHub release` (Pages step) | The release `rules-<seq>` exists but servers do not see it yet. Re-run the job: it takes the next `seq` (gaps are harmless) and publishes. |

### A release without a rule change

Run the workflow by hand on `main` to publish the current tree under a new `seq` (after a key rotation, for
example):

```sh
gh workflow run release.yml --repo DonSosiska/holealign-rules --ref main
```

### Verify what was published

```sh
seq=<n>
curl -fsSLO "https://donsosiska.github.io/holealign-rules/rules-$seq.tar.gz"
curl -fsSLO "https://donsosiska.github.io/holealign-rules/rules-$seq.tar.gz.sig"
holealign-server rules verify -pub "$(tr -d '[:space:]' < keys/rules-public.key)" "rules-$seq.tar.gz"
```

## Pages and rollback

`scripts/publish-pages.sh <dist> <seq>` updates the `gh-pages` branch in **one commit**:

- adds `rules-<seq>.tar.gz` and its `.sig`;
- keeps the newest `KEEP_BUNDLES` bundles (default 5) and deletes older ones;
- regenerates `index.html` (links and SHA-256 of each kept bundle);
- copies `latest.json` last, so that the pointer never names a missing file.

Servers fetch `https://donsosiska.github.io/holealign-rules/latest.json`, which points at the newest bundle.
To check the script without pushing: `DRY_RUN=1 bash scripts/publish-pages.sh <dist> <seq>` from a checkout.

### Roll back with a new, higher seq

To undo a bad rule set, **release a corrected bundle with a higher `seq`. Never republish an old bundle or
point `latest.json` at one.** Reasons:

- Servers accept a bundle only if its `seq` is higher than the installed one. A server that already installed
  `N` ignores an old `N-1` and logs a possible rollback, so re-publishing the old bundle fixes nothing there
  and only confuses servers that have not polled yet.
- Anti-rollback is what stops an attacker who can write to Pages from reinstating an old, known-weak rule set.
  Rolling back by hand would need the same capability, so it must stay impossible for everyone.
- `seq` numbers must never be reused. `next-seq.sh` derives the next one from tags and releases; a hand-made
  bundle would collide with it.

Procedure:

1. Open a pull request that reverts the commit that introduced the problem (or fixes or deletes the rule).
2. Get the code owner approval, merge. The merge starts the release, which gets the next `seq`.
3. Approve the release. Servers install it at their next poll (`rules.feed.interval`, default 6 hours), or
   operators import it by hand (`holealign-server rules import`).

Keep the tags and releases `rules-<n>` of the highest numbers: they are what keeps `seq` increasing.

## Signing key rotation

The key and the procedure are in [keys/README.md](../keys/README.md#rotation). The order matters because servers
reject a bundle signed by a key they do not trust:

1. Generate the new key offline and keep a backup. Do not touch the secret or `keys/rules-public.key` yet.
2. Announce the new public key to operators. They add it to `rules.feed.trusted_keys` next to the old one.
3. Wait until the servers run with both keys.
4. Replace the `RULES_SIGNING_KEY` secret, commit the new `keys/rules-public.key` in a pull request and merge.
   The release triggered by a rule change, or one started by hand, signs with the new key.
5. Operators remove the old key later.

## Bumping HOLEALIGN_REF

[`HOLEALIGN_REF`](../HOLEALIGN_REF) holds a full commit SHA of Holealign. CI (`validate`, `release`, `bot`) builds
`holealign-server` from it. That binary validates, tests and packs every rule, and the release workflow runs it
with access to the signing key, so which code it is matters.

Rules enforced by `.github/actions/build-holealign`:

- the value is a 40-hex SHA, not a branch or tag (a moving ref would change the build tool without a review here);
- the commit is an ancestor of Holealign `main`, so a commit from a fork, an unmerged branch or a history that
  was force-pushed away cannot become the build tool.

Dependabot does not manage it. To bump:

```sh
sha="$(git ls-remote https://github.com/DonSosiska/holealign refs/heads/main | cut -f1)"
echo "$sha" > HOLEALIGN_REF

git clone https://github.com/DonSosiska/holealign.git ../holealign     # skip if you have one
git -C ../holealign checkout --detach "$sha"
cp ../holealign/rules/*.yaml rules/
cp ../holealign/rules-tests/*.yaml tests/
(cd ../holealign && CGO_ENABLED=0 go build -trimpath -o /tmp/holealign-server ./cmd/holealign-server)
make validate HOLEALIGN_SERVER=/tmp/holealign-server
git status                                   # only HOLEALIGN_REF, and the shared rules if they changed
```

Open a pull request. `validate` repeats the build with the new binary and the shared-rules comparison. If it
fails because an existing rule no longer passes, the new engine changed behavior: fix the rule or the tests in
the same pull request, do not pin an older commit to avoid it. A bump that changes `rules/` or `tests/` releases
after the merge.

## Keeping the shared rules identical

Eight rules exist in both repositories: the files in Holealign `rules/` and `rules-tests/` and the same names
in `rules/` and `tests/` here. The `validate` step "Shared rules are identical to holealign" compares them byte
for byte at `HOLEALIGN_REF` and fails when a file differs, is missing here, or when Holealign has none.

- The direction is always Holealign to here. A change goes into Holealign first and onto its `main`; then
  bump `HOLEALIGN_REF` (above), which copies the new files.
- A rule added to Holealign `rules/` must be copied here too, or `validate` fails after the next bump.
- Do not fix a shared rule in this repository "temporarily": the next bump overwrites it, and `validate`
  fails until then.

## Bot operations

### Schedule and runs

| Item | Value |
|---|---|
| Schedule | Daily at 06:00 UTC (`cron: "0 6 * * *"`). GitHub may delay scheduled runs, and disables schedules of a public repository after 60 days without repository activity. |
| Manual run | `gh workflow run bot.yml --repo DonSosiska/holealign-rules --ref main -f max=5` |
| `max` | Maximum drafts (pull requests) per run, 1 to 100, default 20. It also caps the candidate list. |
| Concurrency | One run at a time (group `bot`, not cancelled). Timeout 60 minutes. |
| Dry run | `DRY_RUN=1 scripts/bot-drafts.sh candidates.json <max>` lists what would be drafted; it touches neither git, GitHub nor the LLM. |
| Model | `claude-sonnet-5-5`, set as `HOLEALIGN_LLM_MODEL` in `bot.yml`. |

A run: find candidates (`rules candidates`, from `coverage/`), draft one rule per candidate
(`rules draft`), commit it on `bot/<vuln>-<source>`, push, open a draft pull request. It skips a candidate whose
branch or pull request (in any state) already exists, or whose rule already exists. Exit code 1 means at least
one draft failed with an error; the others are still processed.

Each draft prints a `usage:` line in the job log (calls, input, output, cache read and cache write tokens,
estimated USD at list prices). The system prompt is cached between drafts of one run.

### Evaluating models (cost vs quality)

`mode=eval` re-drafts every reviewed rule in `rules/` with each model variant, without showing that rule
to the model, and scores each draft against the reviewed tests in `tests/`. It opens no pull requests and
writes nothing to the repository.

```bash
gh workflow run bot.yml --repo DonSosiska/holealign-rules --ref main -f mode=eval \
  -f variants=claude-sonnet-5-5@medium,claude-haiku-5-5@medium,claude-haiku-5-5@high -f runs=3
```

The summary appears on the run page; the full `report.json` is the `eval-report` artifact. It spends real
money: about 8 rules × variants × runs drafts (the default above is 72 drafts, roughly $2-3 at list prices,
almost all of it the Sonnet variant). Metrics:

| Metric | Meaning |
|---|---|
| Success rate | Drafts that passed validation and their own tests within the attempt limit |
| Agreement | Share of the reviewed test cases (for the drafted package type) where the draft gives the reviewed verdict |
| Unsafe | Reviewed cases that want `exploitable` or `conditions_unknown` where the draft says not exploitable: the dangerous direction |
| Missed exploitable | Reviewed cases that want `exploitable` where the draft says anything else |
| Est. USD per success | Estimated list-price cost of one successful draft, retries included |

Change the bot's model (`HOLEALIGN_LLM_MODEL` in `bot.yml`) only on evidence from an evaluation, and never to a
variant with a higher unsafe count.

### Disabling

| Goal | How |
|---|---|
| Pause | `gh workflow disable bot.yml --repo DonSosiska/holealign-rules` (`enable` to resume). |
| Make runs do nothing | Delete one of the four required `ANTHROPIC_*` variables; the job logs `bot disabled` and succeeds. |
| Cut off the LLM | Disable or delete the federation rule or the service account in the Anthropic Console. No key to rotate. |

### Costs and limits

- Every draft is one to two model calls (a failed draft is retried once); a run makes at most `max` candidate
  attempts, so at most `2 * max` calls. Candidates for which no valid draft comes out cost calls but produce no
  pull request.
- The spend limit is set on the Anthropic workspace of the service account ([bot-setup.md](bot-setup.md)). A run
  that reaches it fails for the remaining candidates; nothing else breaks.
- The OSV bulk exports (about 90 MB) are cached per ISO week. Adding ecosystems or packages in `coverage/` grows the
  candidate list, not the cap.
- Review time is the real cost: every draft needs a human ([reviewing.md](reviewing.md)). Lower `max` or the
  coverage lists when drafts pile up.

### Anthropic federation: the token and the rule

The job asks GitHub for an OIDC token for the audience in `ANTHROPIC_OIDC_AUDIENCE` and the Anthropic SDK exchanges
it ([bot-setup.md](bot-setup.md#3-how-a-run-authenticates)). The federation rule decides which tokens are accepted.
Match on identifiers that cannot be re-created by someone else, not on names that can be.

`sub` in the immutable format, for a run on `main`:

```
repo:<OWNER>@<OWNER_ID>/<REPO>@<REPO_ID>:ref:refs/heads/main
```

Look up the ids once:

```sh
gh api repos/DonSosiska/holealign-rules --jq '{repo_id: .id, owner_id: .owner.id}'
```

| Claim | Condition | Why |
|---|---|---|
| `repository_owner_id` | the owner id | The account cannot be re-created under the same id after a rename or delete. |
| `repository_id` | the repository id | The same, for the repository. |
| `ref` | `refs/heads/main` | Only runs on `main`: PR branches and forks never get credentials. |
| `job_workflow_ref` | `DonSosiska/holealign-rules/.github/workflows/bot.yml@refs/heads/main` | Only this workflow file at `main`. |
| `workflow` | `bot` | The workflow name. |
| `event_name` | one of `schedule`, `workflow_dispatch` | No pull request or push can authenticate. |
| audience | the value of `ANTHROPIC_OIDC_AUDIENCE` | A token minted for another audience is rejected. |

If a claim cannot be matched by id, match the readable one (`repository` is `OWNER/REPO`), but prefer ids.

Pitfall seen in practice: the Console doubled the owner in the `repository` claim condition (the owner was
added to a value that already had it), so no token matched and the exchange failed with
`match_claim_value_mismatch`. When you see that error: open the rule in the Console, read back every stored
condition value character by character against the claim it names, and fix the one that differs. Check `ref`
and `job_workflow_ref` the same way, and check that the run is on `main` and one of the two events.

## Incident response

Contain first, then fix forward, then find the cause. Report security-relevant incidents following
[SECURITY.md](../SECURITY.md).

### The signing key leaked

Anyone who holds it can publish rules to every server that trusts it.

1. **Stop publishing.** Delete the value of the `RULES_SIGNING_KEY` environment secret (the release then fails at
   "Write signing key") and disable the workflow: `gh workflow disable release.yml --repo DonSosiska/holealign-rules`.
2. **Tell operators** to remove the key from `rules.feed.trusted_keys` now. A persisted bundle signed only by it is
   ignored at the next server start, and the feed stays idle until a new key is trusted. Operators who cannot
   wait can set `rules.feed.enabled: false`.
3. **Generate a new key** offline, as in [keys/README.md](../keys/README.md#first-setup). Give operators the new
   public key. They add it to `trusted_keys`.
4. **Switch.** Put the new private key in the `RULES_SIGNING_KEY` secret, commit the new `keys/rules-public.key` in
   a pull request, merge, enable the workflow and publish a release (an ordinary rule merge, or
   `gh workflow run release.yml --ref main`). Verify it as described under [Release runbook](#verify-what-was-published)
   using the new key.
5. **Clean up.** Older bundles on Pages are pushed out as new ones are published (the last five are kept). Releases
   `rules-<n>` signed with the leaked key stay downloadable: delete their assets if you do not want them offered, but
   keep the tags, so `seq` keeps increasing.
6. **Find the cause.** Review the workflow runs of `release.yml`, the access history of the `rules-release`
   environment, the `gh-pages` commit history (every commit must be `Publish rules-<n>` by `github-actions[bot]`),
   and whether the key was ever on an operator's machine or in a log.

### A bad rule was shipped

A rule that says "not exploitable" when it is, or "exploitable" when it is not.

1. Assess: which rule, which `seq` first carried it (`gh release list`), which findings it changes. A wrong
   "not exploitable" is the urgent case.
2. Fix forward, as in [Roll back with a new, higher seq](#roll-back-with-a-new-higher-seq): a pull request that fixes
   the rule, or deletes the file when you cannot fix it quickly (a rule cannot be published as `rejected`).
   A bundle that lacks a rule no longer carries it.
3. Release. Servers take it at their next poll, so the exposure lasts at most the poll interval plus your time;
   tell operators who must not wait to import the bundle by hand.
4. Learn: add the test that would have caught it, and the checklist item to [reviewing.md](reviewing.md) if
   a class of error got through.

### The bot misbehaves

Examples: pull requests with wrong or hostile content, runaway cost, a leaked token suspected.

1. Disable it: `gh workflow disable bot.yml --repo DonSosiska/holealign-rules`.
2. Cancel runs in progress: `gh run cancel <run-id>`.
3. Close the drafts: `gh pr list --label bot-draft --state open`, then `gh pr close <number>` with a comment. Delete
   the `bot/*` branches only if nothing should be kept. Check that no bot pull request was merged
   (`gh pr list --label bot-draft --state merged`); a merged draft is a rule and goes through the bad-rule
   procedure above.
4. If credentials may be exposed, delete or disable the federation rule or the service account in the Console, and
   review the audit trail there. The tokens are short-lived and there is no key, but the rule decides who can
   obtain them: re-check its conditions against the table above.
5. If a draft contained instructions aimed at the reviewer or at tools, it came from advisory text. Do not
   follow them; report it ([SECURITY.md](../SECURITY.md)).
6. Re-enable after the cause is fixed; start with `-f max=1`.
