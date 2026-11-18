# Holealign rules

[![validate](https://github.com/DonSosiska/holealign-rules/actions/workflows/validate.yml/badge.svg)](https://github.com/DonSosiska/holealign-rules/actions/workflows/validate.yml)
[![release](https://github.com/DonSosiska/holealign-rules/actions/workflows/release.yml/badge.svg)](https://github.com/DonSosiska/holealign-rules/actions/workflows/release.yml)
[![license: CC0 1.0](https://img.shields.io/badge/license-CC0%201.0-lightgrey.svg)](LICENSE)

The public rules repository for [Holealign](https://github.com/DonSosiska/holealign). Everything here is
dedicated to the public domain under [CC0 1.0](LICENSE).

A rule says when a vulnerable package is actually exploitable, as a CEL expression over facts that
Holealign agents collect from the host. A scanner says "this version is vulnerable"; a rule says "and
the conditions are met", or "but sshd runs with `LoginGraceTime 0`, so not exploitable". Rules do not
depend on the host, so they are written and reviewed once, here, and delivered to every server as a
signed feed.

## Use the feed

Servers poll the feed and install a bundle only after verifying its signature, its contents and its
tests. In the Holealign server configuration:

```yaml
rules:
  feed:
    enabled: true
    url: https://donsosiska.github.io/holealign-rules/latest.json
    trusted_keys:
      - "UuFW4nYSCwI3xfHhwapVhYrjYhVO6i7yaxOTv9KFCuM="    # contents of keys/rules-public.key
```

The trusted key is the base64 ed25519 public key in [`keys/rules-public.key`](keys/rules-public.key); see
[keys/README.md](keys/README.md) for how it is managed and rotated. Compare the value above with the file
before you copy it. Every bundle is also attached to the GitHub release `rules-<seq>` for air-gapped
servers (`holealign-server rules import`). What the server checks and how the layers combine is described in
the Holealign [rules feed documentation](https://github.com/DonSosiska/holealign/blob/main/docs/rules-feed.md).

## Repository layout

| Path | Contents |
|---|---|
| `rules/<id>.yaml` | One rule per file. |
| `tests/<id>.yaml` | Test cases for that rule. Required. |
| `coverage/packages.txt`, `coverage/ecosystems.txt` | What the bot looks at: source packages and OSV ecosystems. |
| `keys/` | The public signing key that servers trust, and key management notes. |
| `scripts/` | `bot-drafts.sh` (draft rules, open PRs), `next-seq.sh` (bundle sequence number), `publish-pages.sh` (GitHub Pages). |
| `.github/workflows/` | `validate` (PRs and `main`), `release` (sign and publish), `bot` (draft rules). |
| `HOLEALIGN_REF` | The Holealign commit CI builds `holealign-server` from. |
| `Makefile` | `make validate`, `make bundle` (both need `HOLEALIGN_SERVER=/path/to/holealign-server`). |
| `docs/` | Guides, see below. |

## Rule lifecycle

```
bot draft  --\
              >-- pull request --> review --> merge to main --> release --> GitHub Pages --> servers
human PR   --/     (validate)      (human)                      (signed)    (latest.json)
```

1. **Propose.** Either the bot opens a draft pull request (branch `bot/<vuln>-<source>`, label
   `bot-draft`, `status: draft`), or a person opens a pull request with a rule and its tests
   ([CONTRIBUTING.md](CONTRIBUTING.md)).
2. **Validate.** The `validate` workflow builds `holealign-server`, runs `rules build` over every rule and test,
   and checks that the 8 shared rules are identical to Holealign. A rule with `status: draft` fails it by
   design: red means awaiting review.
3. **Review.** A code owner checks the rule against the advisory, not only that CI is green
   ([docs/reviewing.md](docs/reviewing.md)). Merging is the review.
4. **Release.** A merge to `main` that touches `rules/` or `tests/` starts the `release` workflow. It builds a
   deterministic bundle, signs it in the protected `rules-release` environment, verifies the signature against
   `keys/rules-public.key`, creates the GitHub release `rules-<seq>` and updates the `gh-pages` branch
   ([docs/maintainers.md](docs/maintainers.md)).
5. **Deliver.** GitHub Pages serves `latest.json` and the newest five bundles. Servers pick up a new `seq`
   at their next poll.

## Rule format

A rule is strict YAML (unknown keys are errors):

```yaml
id: CVE-2024-6387
vulns: [CVE-2024-6387]                  # CVE/GHSA ids covered
title: "OpenSSH regreSSHion: unauthenticated RCE in sshd"
packages:
  - {name: openssh*, type: deb}         # name is a glob on the binary package
facts: [os.libc, sshd.config]           # facts that must be known; absent fact -> "conditions unknown"
exploitable_if: >                       # CEL, must return bool
  pkg.name.startsWith("openssh-server") &&
  facts["os.libc"] == "glibc" &&
  facts["sshd.config"][?"logingracetime"].orValue("120") != "0"
explanation: "Needs glibc and a non-zero LoginGraceTime."
fix: {upgrade: "...", mitigation: "..."}
status: reviewed
source: user
references: [https://...]
```

Optional keys: `not_affected_if`, `fact_requests` (restricted `file.match`) and `targets`. The full format, the
fact catalog and the `file.match` policy are in the Holealign
[rules documentation](https://github.com/DonSosiska/holealign/blob/main/docs/rules.md). A test file is a list of
cases run by the real engine:

```yaml
- name: glibc, default LoginGraceTime
  finding: {vuln: CVE-2024-6387, package: openssh-server, type: deb, severity: High, kev: false}
  facts: {os.libc: glibc, sshd.config: {logingracetime: "120"}}
  host: {os_id: debian, arch: amd64}
  want: exploitable    # exploitable | affected_not_exploitable | conditions_unknown | not_affected
```

### Status values

| `status` | Meaning here |
|---|---|
| `draft` | Written by the bot (`source: llm:<model>`), not reviewed. `validate` and `rules build` reject it. |
| `reviewed` | A human checked it against the advisory. The only status that can be merged and published. |
| `rejected` | Exists in the Holealign server database, so that the drafter does not regenerate a rule. Not used in this repository: a rejected draft is closed, and a rule that must go is deleted. |

### `source` values

| `source` | Meaning |
|---|---|
| `builtin` | One of the 8 rules shipped inside Holealign. These are copies and must stay identical to the ones at `HOLEALIGN_REF`. |
| `llm:<model>` | Drafted by the bot, for example `llm:claude-sonnet-5-5`. |
| `user` | Written by hand. |

## Documentation

| Document | For | Contents |
|---|---|---|
| [CONTRIBUTING.md](CONTRIBUTING.md) | Contributors | Propose a rule by hand, tests, local validation, conventions. |
| [docs/reviewing.md](docs/reviewing.md) | Reviewers | Checklist for bot draft pull requests, with a worked example. |
| [docs/maintainers.md](docs/maintainers.md) | Maintainers | Release runbook, Pages and rollback, `HOLEALIGN_REF`, bot operations, incident response. |
| [docs/bot-setup.md](docs/bot-setup.md) | Maintainers | One-time setup of the bot's keyless Anthropic access. |
| [keys/README.md](keys/README.md) | Maintainers, operators | The signing key: setup and rotation. |
| [SECURITY.md](SECURITY.md) | Everyone | What to report and how. |
| [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) | Everyone | Contributor Covenant 2.1. |

## License

[CC0 1.0 Universal](LICENSE): public domain. Contributions are dedicated to the public domain on the same
terms ([CONTRIBUTING.md](CONTRIBUTING.md#license-of-contributions)).
