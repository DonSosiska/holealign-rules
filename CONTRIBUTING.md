# Contributing

Thank you for improving the rules. This page is for people who write a rule by hand. If you review a
rule drafted by the bot, read [docs/reviewing.md](docs/reviewing.md); if you run releases, read
[docs/maintainers.md](docs/maintainers.md).

## What to send

One pull request per rule, adding or changing both files:

| File | Contents |
|---|---|
| `rules/<id>.yaml` | The rule. |
| `tests/<id>.yaml` | Its test cases. A rule without tests fails `validate`. |

The rule format, the CEL environment, the fact catalog and the `file.match` policy are documented in
the Panoptes [rules documentation](https://github.com/DonSosiska/panoptes/blob/main/docs/rules.md); the
test format is in the [rules feed documentation](https://github.com/DonSosiska/panoptes/blob/main/docs/rules-feed.md#rule-tests).
The [README](README.md#rule-format) has a short example.

No rule for the vulnerability you care about? You can also open a
[rule request](https://github.com/DonSosiska/panoptes-rules/issues/new?template=rule_request.md).

## Naming

- `id` is `<VULN>-<lowercased source>`: `CVE-2023-44487-nginx`, `CVE-2026-109618-php8.2`. `<VULN>` is the
  CVE (or GHSA) id the rule covers, `<source>` the product or the source package, lowercased.
- The file names are `rules/<id>.yaml` and `tests/<id>.yaml`. The `id` inside the file must equal the file name.
- Set `source: user` for a hand-written rule. `builtin` and `llm:<model>` are taken.
- Write `vulns` with every identifier of the same vulnerability that the scanner may report (for example the
  CVE and the distribution's `DEBIAN-CVE-...` id) and nothing else.

## Writing the rule

- Base the conditions on the advisory (vendor or upstream text) and link it in `references`.
- Express reachability with facts, never `true`. Version ranges are already handled by the scanner.
- List in `facts` every fact that must be known to decide. An absent fact means "unknown", never "false".
- Use the exact values the agent reports. Check them in the fact catalog and, on a host, with
  `panoptes-agent -print-facts`. For example `php.sapi` holds `cli`, `php-fpm` and `apache2handler`.
- Keep the selectors as narrow as the advisory: `packages` must not cover products or versions the advisory does
  not.
- A `file.match` request must not target a sensitive path (keys, credentials, shadow files, tokens) and must
  follow the policy in the Panoptes documentation.
- Set `status: reviewed` only after you have checked the rule against the advisory yourself. The maintainer
  review on the pull request is a second check, not a replacement for yours.

## Required tests

`rules build` fails unless every rule has at least one `exploitable` case and at least one non-exploitable case
(`affected_not_exploitable` or `not_affected`). The only exemption is `exploitable_if: 'false'`. Beyond that
minimum, a rule needs:

| Case | When |
|---|---|
| An `exploitable` case | Always (except `exploitable_if: 'false'`). |
| A non-exploitable case | Always. |
| `conditions_unknown`: the key facts are absent | When the rule reads facts. |
| The systemd name and the `/proc` fallback name | When the rule reads `services.active`: the agent reports `php8.2-fpm` and `ssh` from systemd, but `php-fpm` and `sshd` from `/proc`; `services.source` tells which. One exploitable case per spelling. |
| A `container_image` case | When the rule reads host facts (`facts`, `fact_requests`, `host.*`): `finding: {..., target_kind: container_image}` must give `conditions_unknown`, see `tests/CVE-2024-6387.yaml`. |

Use fact values a real agent produces, not values you made up. A test that passes against an invented value
proves nothing; see the example in [docs/reviewing.md](docs/reviewing.md#worked-example-a-wrong-fact-value-that-the-tests-did-not-catch).

## Validate locally

CI builds `panoptes-server` from the commit in [`PANOPTES_REF`](PANOPTES_REF). Do the same, then run the same
check as `validate` (needs Git and the Go version named in Panoptes `go.mod`):

```sh
# in a checkout of this repository
git clone https://github.com/DonSosiska/panoptes.git ../panoptes
git -C ../panoptes checkout --detach "$(grep -v '^[[:space:]]*#' PANOPTES_REF | head -n 1 | tr -d '[:space:]')"
(cd ../panoptes && CGO_ENABLED=0 go build -trimpath -o /tmp/panoptes-server ./cmd/panoptes-server)

make validate PANOPTES_SERVER=/tmp/panoptes-server
```

`make validate` runs `panoptes-server rules build -rules rules -tests tests -seq 1` into a temporary directory.
It validates every rule, runs every test with the real engine and applies the coverage policy. It prints
every problem; fix them all and run it again. Also run `shellcheck scripts/*.sh` if you touch a script.

## The shared rules

Eight rules (`CVE-2023-44487-apache`, `CVE-2023-44487-nginx`, `CVE-2023-48795`, `CVE-2024-1086`,
`CVE-2024-21626`, `CVE-2024-3094`, `CVE-2024-4577`, `CVE-2024-6387`) also ship inside Panoptes
(`rules/` and `rules-tests/` in that repository). CI fails if the copies here differ by a single byte from the
ones at `PANOPTES_REF`. Do not edit them here. Change them in Panoptes first; once the change is on Panoptes
`main`, bump `PANOPTES_REF` and copy the files here in one pull request (see
[docs/maintainers.md](docs/maintainers.md#bumping-panoptes_ref)).

## Commits and pull requests

- One rule per pull request, unless the rules are one logical change (the same vulnerability in two products).
- Commit subject in the imperative, with the rule id: `Rule CVE-2024-1086: also select the Debian linux source
  package`, `Add rule CVE-2024-0000-foo`. Explain why in the body when it is not obvious from the advisory.
- Fill in the pull request template: advisory, packages and the reviewer checklist. Say which fact values you
  verified and where.
- Do not mix rule changes with workflow, script or `PANOPTES_REF` changes.
- Do not push to `bot/*` branches unless you are reviewing that draft ([docs/reviewing.md](docs/reviewing.md)).

## Review

Every pull request needs an approval from a code owner ([`.github/CODEOWNERS`](.github/CODEOWNERS)). Merging is
the review, and a merge that touches `rules/` or `tests/` is published to every server that trusts the feed.
CI green is necessary, not sufficient.

## License of contributions

By contributing you dedicate your contribution to the public domain under
[CC0 1.0 Universal](LICENSE), to the extent possible, and confirm that you have the right to do so.
A sign-off line (`Signed-off-by: Name <email>`, `git commit -s`) is welcome but not required.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md). Security problems go to
[SECURITY.md](SECURITY.md), not to a public issue.
