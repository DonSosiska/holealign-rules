# Security policy

## What to report

- Exposure or suspected exposure of the rules signing key (`RULES_SIGNING_KEY`), or of the Anthropic or GitHub
  credentials the bot uses.
- A malicious or wrong rule: one that makes servers report a vulnerability as not exploitable when it is, hides a
  finding, requests sensitive files, or otherwise misleads operators. This includes rules already merged and rules in
  open pull requests.
- Tampering with the feed: a bundle, `latest.json`, a release asset or the `gh-pages` branch that was not produced by
  the release workflow, or a way to make the release workflow publish something that was not reviewed.
- Abuse of the bot: getting it to open pull requests from attacker-controlled input, leak credentials, or run with more
  access than intended.

## How to report

Please do not open a public issue. Report privately through GitHub private vulnerability reporting on this repository:
[Security tab, "Report a vulnerability"](https://github.com/DonSosiska/panoptes-rules/security/advisories/new).
The maintainers will enable private reporting on this repository; if the link does not work yet, contact the
[repository owner](https://github.com/DonSosiska) through GitHub without putting details in a public place.

Bugs in the Panoptes product itself (server, agent, rule engine) go to
https://github.com/DonSosiska/panoptes/security.

If the signing key leaks, operators must remove it from `rules.feed.trusted_keys`; see [keys/README.md](keys/README.md).
