# Panoptes rules

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
status: reviewed                        # draft | reviewed | rejected; only reviewed rules ship
source: user
references: [https://...]
```

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
      - "<PUBLIC_KEY>"    # contents of keys/rules-public.key
```

`<PUBLIC_KEY>` is the base64 key in [`keys/rules-public.key`](keys/) (see [keys/README.md](keys/README.md)).
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

A daily workflow picks recent advisories for the packages in `coverage/packages.txt`, asks an LLM to
draft a rule and tests, and opens a pull request labelled `bot-draft`. Drafts are LLM-generated: they
can be wrong, and they are `status: draft` (so CI fails until a human sets `reviewed`). Check every
condition against the advisory before approving. Bot pull requests are created with the workflow
token, so CI does not start on them automatically; push a commit or close and reopen to trigger it.

## Releases

On every merge that changes rules or tests, the release workflow builds a deterministic bundle,
signs it with the offline-generated key stored as a secret, verifies it against
`keys/rules-public.key`, creates a GitHub release and updates the `gh-pages` branch (latest.json and
the last five bundles).

## CI and the panoptes version

CI builds `panoptes-server` from the public Panoptes repository at the commit in
[`PANOPTES_REF`](PANOPTES_REF). Dependabot does not manage it. To bump: pick a commit on Panoptes `main`
(`git ls-remote https://github.com/DonSosiska/panoptes refs/heads/main`), replace the SHA in
`PANOPTES_REF`, and open a pull request; `validate` runs with the new binary.
