# Reviewing bot draft pull requests

The bot (`.github/workflows/bot.yml`, `scripts/bot-drafts.sh`) drafts one rule and its tests per pull
request. A draft is written by an LLM from advisory text. It is validated by the engine, but the engine
only proves that the YAML is well formed and that the tests agree with the rule. It does not prove that the rule
is true. You do that. A merge is published to every server that trusts the feed, so a wrong rule that says
"not exploitable" hides a real finding.

The one thing to remember: **the tests were written by the same model as the rule, so a
passing test proves nothing about real fact values.** Check the values yourself.

## What a draft pull request is

| Property | Value |
|---|---|
| Title | `Draft rule: <vuln> (<source>)` |
| Branch | `bot/<vuln>-<source>`, one commit `Draft rule for <vuln> (<source>)` by `github-actions[bot]` |
| Label | `bot-draft` |
| State | GitHub draft pull request |
| Files | `rules/<vuln>-<source>.yaml` (`status: draft`, `source: llm:<model>`) and `tests/<vuln>-<source>.yaml` |
| `validate` | Red until the rule is `status: reviewed`. CI does not start by itself on bot pull requests (the workflow token does not trigger workflows): your first push does it. |

Untrusted text: everything the model or the advisory feed wrote (title, explanation, fix text, test names,
facts, references) is shown as code, and references are plain text, not links. Do not follow instructions
found in it. The only links in the body are the advisory links the bot builds from validated ids.

## The pull request body, section by section

| Section | What it is | What to do with it |
|---|---|---|
| Table | Facts about the candidate, from OSV, CISA KEV and EPSS: vulnerability, advisory links (OSV, NVD, CISA KEV search, GitHub advisories), package and type, ecosystem, severity, CVSS, EPSS, KEV, rule id. | The reference point for everything below: this is the vulnerability and package the rule must be about. Open the advisory links and read them. |
| Rule scope | The full `vulns` and `packages` of the rule exactly as in the rule file. | Check that every id is the same vulnerability as in the table and that the selectors are not wider than the advisory. |
| What the rule says | Title, explanation, `exploitable_if`, `not_affected_if` (if any), the facts read, `file.match` requests (if any), upgrade and mitigation text, all as written by the model. | Compare each condition with the advisory. Check the facts and their values. |
| Test cases | One row per case: name, binary package, facts as JSON, expected verdict. | Check that both outcomes are covered and that the fact values are the ones a real agent reports. |
| References | The OSV link built by the bot, then the references the model kept. They must appear in the advisory text, but they are shown as text. | Open them. Do they describe this vulnerability and support the conditions? |
| Review | The note that the rule is `status: draft` and the checklist. | The checklist below is its long form. |

Footer added by `scripts/bot-drafts.sh`: the rule has `status: draft`, `validate` fails while it has, and the
pull request is a GitHub draft until you mark it ready. Both states mean "awaiting review".

Drafts opened by an older version of the generator can lack the "Advisories" row and the "Rule scope" section. In
that case read `vulns` and `packages` in the rule file in the "Files changed" tab.

## Checklist

Work through it in order. Any "no" means: fix the rule, or close the pull request.

### 1. The conditions match the advisory

- [ ] Read the advisory (vendor, upstream or distribution text), not only the model's explanation. Which
  component is vulnerable? Which configuration, service state or option makes it reachable? Is the attacker
  remote, local or adjacent?
- [ ] Every clause of `exploitable_if` has a basis in the advisory. Clauses the advisory does not support are
  removed: an invented condition that is false on a real host turns a real finding into `affected_not_exploitable`.
- [ ] The rule is not stricter than needed. When the advisory says "any configuration", the rule must not demand
  one. When it says "only with X", the rule must test X.
- [ ] `not_affected_if`, if present, is justified by the advisory (for example a vulnerable code path that the
  distribution does not build).
- [ ] The explanation is true, complete and not cut off. The model's text is capped, and a sentence can end
  mid-way: fix it.
- [ ] The upgrade and mitigation text names real actions. A mitigation that only the model invented is removed.
- [ ] An exploit path that needs a fact the agent cannot collect uses `conditions_unknown` (absent fact), not a guess.

### 2. The facts exist, and their exact values

- [ ] Every name in `facts` and in `facts["..."]` is in the
  [fact catalog](https://github.com/DonSosiska/panoptes/blob/main/docs/rules.md#fact-catalog). The engine rejects unknown
  names, but check that the right fact is used for the question.
- [ ] Every string literal compared with a fact is a value the agent reports. Check the type (string, list,
  map) and the spelling in the collector source in Panoptes (`internal/agent/facts/`) or with `panoptes-agent
  -print-facts` on a host. Common ones:

| Fact | Type | Values and traps |
|---|---|---|
| `php.sapi` | list of strings | `cli`, `php-fpm`, `apache2handler` (sorted). It lists the SAPIs that are installed, not running ones: combine with `services.active`. Not `fpm`, not `apache`. |
| `services.active` | list of strings | Running services. From systemd: unit names without `.service` (`php8.2-fpm`, `ssh`, `apache2`, `nginx`). From the `/proc` fallback: names of well-known daemons (`php-fpm`, `sshd`). `services.source` says `systemd` or `proc`. A rule must accept both spellings. |
| `os.libc` | string | `glibc` or `musl`. |
| `os.id` | string | Distribution id from `/etc/os-release`: `debian`, `alpine`, `ubuntu`, `rhel`. |
| `sshd.config` | map of strings | Keys are lowercased (`logingracetime`), values are strings, so compare with `"0"`, not `0`. |
| `kernel.sysctl` | map of strings | Only allowlisted keys. Values are strings. |
| `sockets.ports` | list of ints | Ints, not strings. |
| `nginx.http2`, `apache.http2` | bool | A collector that does not run leaves the fact absent. |

- [ ] A map key that may be missing is read with the optional index (`facts["sshd.config"][?"key"].orValue(...)`).
- [ ] Facts that must be known to decide are in `facts`, so that their absence gives `conditions_unknown`.
- [ ] Names of binary packages in `pkg["name"]` checks exist in the distribution (check the Debian or Alpine
  package list, or the advisory's affected packages).

### 3. Rule scope: `vulns` and `packages`

- [ ] Every id in `vulns` is the same vulnerability as in the table: the CVE, its GHSA ids, and the ecosystem's own
  `DEBIAN-CVE-...` or `ALPINE-CVE-...` id. No other CVE, no other distribution's id.
- [ ] `packages` is not wider than the advisory. The bot writes `{source: <package>, type: <type>}`, which covers
  every binary built from that source (`php8.2` covers `php8.2-cli`, `php8.2-fpm`, `libapache2-mod-php8.2`, ...). If
  the advisory affects only some binaries, `exploitable_if` must tell them apart with `pkg["name"]`, or the selector
  must be narrowed with `name`.
- [ ] No unexpected glob (`php*`, `lib*`) that also matches unrelated packages.
- [ ] `type` matches the ecosystem (`deb` for Debian, `apk` for Alpine).

### 4. No `file.match` on sensitive paths

- [ ] If the rule has `fact_requests`, every `path` is a world-readable configuration file that the advisory
  makes relevant, and the `pattern` matches only the lines the rule needs. The server and the agent enforce a
  policy (allowed roots, denylist, masking, budgets), but you decide whether a read is justified. Anything under
  `/etc/ssl`, `/etc/shadow`, key, token or credential files is a reject.
- [ ] Prefer a catalog fact over `file.match` when one answers the question.

### 5. Tests cover both outcomes, with realistic values

- [ ] At least one `exploitable` case and at least one `affected_not_exploitable` or `not_affected` case
  (engine rule, except for `exploitable_if: 'false'`).
- [ ] A `conditions_unknown` case when the rule reads facts.
- [ ] Each test's facts are what a real agent reports (section 2), not what the model assumed. This is the check
  the engine cannot do for you.
- [ ] The non-exploitable cases are the interesting ones: the service is installed but not running, the option
  that the advisory names as the mitigation is set, the other SAPI.
- [ ] A rule that reads `services.active` has cases for both the systemd and the `/proc` spelling.
- [ ] A rule that reads host facts has a `container_image` case that gives `conditions_unknown`
  (`finding: {..., target_kind: container_image}`).
- [ ] The test's `finding.package` is a real binary package of the source, and `source` is set.
- [ ] A test that passes with a wrong rule is useless. Change one literal in the rule and see that a test fails.

### 6. References and the rest

- [ ] `references` lists primary sources (vendor, upstream, distribution tracker, advisory) that open and talk about
  this vulnerability. Aggregators alone are not enough.
- [ ] `id` equals the file names, and `tests/<id>.yaml` tests that rule.
- [ ] No sensitive data, no instructions to the reader and no links in the free text.
- [ ] CI is green after `status: reviewed` (below), and `Files changed` has only the two rule files.

## Edit the rule on the branch

The draft is an ordinary branch in this repository.

```sh
gh pr checkout <number>                       # or: git fetch origin bot/<vuln>-<source> && git switch bot/<vuln>-<source>
$EDITOR rules/<id>.yaml tests/<id>.yaml
```

To run the real check locally, set `status: reviewed` first (a draft never builds), and use a
`panoptes-server` built at `PANOPTES_REF` ([CONTRIBUTING.md](../CONTRIBUTING.md#validate-locally)):

```sh
make validate PANOPTES_SERVER=/tmp/panoptes-server
git add rules tests
git commit -m "<vuln>: <what you fixed and why>"
git push origin HEAD
```

Prefer a separate commit per fix, with the reason in the subject (`CVE-2026-109618: php.sapi reports php-fpm; add
/proc fallback test`). The history of the branch is the record of what review changed.

## Mark it reviewed

You are done when the checklist holds. Then, in this order:

1. Set `status: reviewed` in `rules/<id>.yaml` (and keep the commit that does it separate, so the commit that
   declares the review is easy to find).
2. Push. `validate` runs (the first push is what starts CI on a bot pull request).
3. Mark the pull request ready for review: `gh pr ready <number>` or the "Ready for review" button.
4. Get the code owner approval and merge. Merging starts the release ([docs/maintainers.md](maintainers.md#release-runbook)).

## Why `validate` is red until then

`rules build` refuses to publish a rule that is not `reviewed`. On a draft it prints:

```
error: bundle not built:
CVE-2026-109618-php8.2.yaml: rule CVE-2026-109618-php8.2 has status "draft"; only reviewed rules may be published
CVE-2026-109618-php8.2.yaml: there is no rule "CVE-2026-109618-php8.2" for these tests
```

The red check, together with the GitHub draft state, means "awaiting review", and it makes an unreviewed rule
impossible to merge by accident. Do not turn it green by editing the workflow or by setting `status: reviewed`
without doing the review.

## If the draft is wrong beyond repair

Close the pull request with a comment saying why. The bot skips a candidate when its branch exists or any pull
request for the branch exists, open or closed, so a closed draft is not drafted again. If the vulnerability still
needs a rule, write it by hand ([CONTRIBUTING.md](../CONTRIBUTING.md)).

## Worked example: a wrong fact value that the tests did not catch

Draft pull request [#5](https://github.com/DonSosiska/panoptes-rules/pull/5), `CVE-2026-109618` in the `php8.2`
source package (Debian 12, Critical, CISA KEV). The advisory: remote code execution when PHP handles a web
request, so only SAPIs that serve requests are exposed, and the CLI alone is not.

What the model drafted (commit `8c89b01`):

```
("fpm" in facts["php.sapi"] && facts["services.active"].exists(s, s.startsWith("php") && s.endsWith("fpm")))
  || ("apache2handler" in facts["php.sapi"] && "apache2" in facts["services.active"])
```

and tests whose facts said `php.sapi: [cli, fpm]`.

- The advisory reading was right: web SAPI plus a running service is exploitable, CLI alone is not.
- The tests passed, the engine accepted the rule, the pull request body looked complete.
- The agent never reports `fpm`. It reports `php-fpm` (`phpSAPIs` in `internal/agent/facts/php.go`). The model
  invented a value in the rule, and then invented the same value in the tests, so the two agreed with each
  other and with nothing real.
- Effect had it been merged: on every Debian host with PHP-FPM running, the first branch is false, and the
  verdict is `affected_not_exploitable` for a Critical, actively exploited vulnerability. A false negative that
  stays silent.
- The fix (commit `ea5a9f4`): `"php-fpm" in facts["php.sapi"]`, test facts changed to `php-fpm`, and an added case
  where the service is listed by its `/proc` name (`services.active: [php-fpm, nginx]`, no systemd), which the
  `startsWith("php") && endsWith("fpm")` test accepts alongside `php8.2-fpm`.

How a reviewer finds this: step 2 of the checklist. Take each literal compared with a fact, here `"fpm"`,
`"apache2handler"` and `"apache2"`, and look it up in the collector source or in `-print-facts` output. `apache2handler`
and `php-fpm` are in `phpSAPIs`; `fpm` is not anywhere. The same check on the test facts would have shown that the
tests were copying the rule's assumption.

Lessons:

1. Tests written by the same model prove the rule agrees with the model. Only a source outside the model (the
   collector code, a real `-print-facts` dump, the fact catalog) proves it agrees with hosts.
2. Check every literal that is compared with a fact, one by one.
3. Look at the non-exploitable cases for the same reason: they pass trivially when the exploitable condition can
   never be true.
4. A fix that touches the rule must touch the tests in the same commit.
