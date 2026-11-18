# Panoptes rules

[![validate](https://github.com/DonSosiska/panoptes-rules/actions/workflows/validate.yml/badge.svg)](https://github.com/DonSosiska/panoptes-rules/actions/workflows/validate.yml)
License: [CC0 1.0](LICENSE) (public domain).

The public rules repository for [Panoptes](https://github.com/DonSosiska/panoptes). Everything here is
dedicated to the public domain under [CC0 1.0](LICENSE).

A rule says when a vulnerable package is actually exploitable, as a CEL expression over facts that
Panoptes agents collect from the host. A scanner says "this version is vulnerable"; a rule says "and
here the conditions are met" or "but sshd runs with LoginGraceTime 0, so not exploitable". Rules do
not depend on the host, so they are written and reviewed once, here, and delivered to every server as
a signed feed.

```
rules/<id>.yaml   one rule
tests/<id>.yaml   its test cases (required)
coverage/         what the bot looks at (packages.txt, ecosystems.txt)
keys/             the public key servers trust
```

## Format

Full documentation: [rules](https://github.com/DonSosiska/panoptes/blob/main/docs/rules.md) and
[rules feed](https://github.com/DonSosiska/panoptes/blob/main/docs/rules-feed.md) in the Panoptes
repository. In short, a rule is strict YAML (unknown keys are errors):

```yaml
id: CVE-2024-6387
vulns: [CVE-2024-6387]                  # CVE/GHSA ids covered
title: "OpenSSH regreSSHion: unauthenticated RCE in sshd"
packages:
  - {name: openssh*, type: deb}         # name is a glob
facts: [os.libc, sshd.config]           # every fact read; absent fact -> "conditions unknown"
exploitable_if: >                       # CEL, must return bool
  pkg.name.startsWith("openssh-server") &&
  facts["os.libc"] == "glibc" &&
  facts["sshd.config"][?"logingracetime"].orValue("120") != "0"
explanation: "Needs glibc and a non-zero LoginGraceTime."
fix: {upgrade: "...", mitigation: "..."}
status: reviewed                        # only `reviewed` can be merged; CI fails otherwise (`rejected` exists for the server's own database)
source: user
references: [https://...]
```

Optional keys: `not_affected_if` (CEL bool; true means affected but not exploitable), `fact_requests`
(restricted `file.match` requests) and `targets` (list of `host` / `container_image`, default `host`; being
added in Panoptes). Test cases may set the host keys `os_id`, `arch`, `os_version_id` and `labels`. See
[panoptes docs/rules.md](https://github.com/DonSosiska/panoptes/blob/main/docs/rules.md) for the full list.

Conventions:

- `id` is `<VULN>-<lowercased source>`, for example `CVE-2023-44487-nginx`, and the file names are
  `rules/<id>.yaml` and `tests/<id>.yaml`.
- `source` says where a rule comes from: `builtin` for the 8 rules shipped inside Panoptes, `llm:<model>` for bot
  drafts (for example `llm:claude-sonnet-5-5`), `user` for hand-written rules.
- The 8 shipped rules exist in both repositories and CI checks that the copies here are byte-identical to the ones at
  the commit in `PANOPTES_REF`.
- A rule reading `services.active` must accept both the systemd unit names (`php8.2-fpm`, `ssh`) and the `/proc`
  fallback names (`php-fpm`, `sshd`), because the agent reports whichever it can see (`services.source` tells which).

Package selectors are `{name, type}` (name is a glob on the binary package) or `{source, type}` (the
source package, exact name). A source selector covers every binary package built from that source:
`packages: [{source: openssl, type: deb}]` matches `openssl` and `libssl3` alike. Inside the expression
`pkg["name"]` and `pkg["source"]` tell the binaries apart.

Version ranges are already handled by the scanner, so rules express reachability with facts, never
with `true`. Facts must exist in the Panoptes fact catalog and be collected by the agent. Requests for
files (`file.match`) are restricted and must not target sensitive paths.

A test file is a list of cases run by the real engine:

```yaml
- name: glibc, default LoginGraceTime
  finding: {vuln: CVE-2024-6387, package: openssh-server, type: deb, severity: High, kev: false}
  facts: {os.libc: glibc, sshd.config: {logingracetime: "120"}}
  host: {os_id: debian, arch: amd64}
  want: exploitable    # exploitable | affected_not_exploitable | conditions_unknown | not_affected
```

Every rule needs at least one `exploitable` case and one non-exploitable case (the only exemption is
`exploitable_if: 'false'`).

## Using the feed

Servers poll the feed and install a bundle only after verifying its signature, its contents and its
tests. In the Panoptes server configuration:

```yaml
rules:
  feed:
    enabled: true
    url: https://donsosiska.github.io/panoptes-rules/latest.json
    trusted_keys:
      - "UuFW4nYSCwI3xfHhwapVhYrjYhVO6i7yaxOTv9KFCuM="    # contents of keys/rules-public.key
```

`UuFW4nYSCwI3xfHhwapVhYrjYhVO6i7yaxOTv9KFCuM=` is the base64 key in [`keys/rules-public.key`](keys/rules-public.key) (see [keys/README.md](keys/README.md)).
Bundles are also attached to the GitHub releases `rules-<seq>` for air-gapped servers
(`panoptes-server rules import`).

## Contributing

Open a pull request with the rule and its tests; see [CONTRIBUTING.md](CONTRIBUTING.md). Check locally with:

```sh
make validate PANOPTES_SERVER=/path/to/panoptes-server
```

Review policy: every pull request, including those from the bot, needs a human approval, and merging
is the review. A merge to `main` that touches `rules/` or `tests/` is published to every server that
trusts the feed key, so reviewers check the rule against the advisory, not just that CI is green.

### Bot drafts

A daily workflow picks recent advisories for the source packages in `coverage/packages.txt` on the
ecosystems in `coverage/ecosystems.txt` (by default Debian 12 and Alpine 3.20; Ubuntu is left out because
its OSV bulk export is about 820 MB and querying it package by package is slow). It asks an LLM to draft
a rule and tests for each candidate, and opens a draft pull request labelled `bot-draft`, branch
`bot/<vuln>-<source>`.

Drafts are LLM-generated and can be wrong. They are written with `status: draft`, so `validate` fails on them
(red means awaiting review). The pull request is a GitHub draft too; marking it ready for review and setting
`status: reviewed` after checking every condition against the advisory is the review. That
commit is what triggers CI on the pull request. Bot pull requests are created with the workflow token,
so CI does not start on them by itself; push a commit or close and reopen to trigger it the first time.
Source-package selectors (`{source: <package>, type: deb}`) are common in bot drafts: one rule covers all
binary packages of that source.

The bot calls Anthropic through workload identity federation; no API key is stored. Maintainer setup:
[docs/bot-setup.md](docs/bot-setup.md).

## Releases

On every merge that changes rules or tests, the release workflow builds a deterministic bundle,
signs it, verifies it against
`keys/rules-public.key`, creates a GitHub release and updates the `gh-pages` branch (latest.json and
the last five bundles). Signing happens in CI in the protected `rules-release` environment; the private key was
generated offline and a backup is kept offline. A release only runs from the current tip of `main`, so an old or
re-run release cannot republish an older rule set under a newer sequence number.

## CI and the panoptes version

CI builds `panoptes-server` from the public Panoptes repository at the commit in
[`PANOPTES_REF`](PANOPTES_REF), which must be a full 40-hex SHA that is an ancestor of Panoptes `main`. Dependabot does not manage it. To bump: pick a commit on Panoptes `main`
(`git ls-remote https://github.com/DonSosiska/panoptes refs/heads/main`), replace the SHA in
`PANOPTES_REF`, and open a pull request; `validate` runs with the new binary.

## License

[CC0 1.0 Universal](LICENSE). Security reports: [SECURITY.md](SECURITY.md).
