# Contributing

Thank you for improving the rules.

## What to send

A pull request that adds or changes `rules/<id>.yaml` together with `tests/<id>.yaml`. The file name
is the rule id. Format: see the README. Before opening it:

```sh
make validate PANOPTES_SERVER=/path/to/panoptes-server
```

`panoptes-server` is built from https://github.com/DonSosiska/panoptes (`go build ./cmd/panoptes-server`).
The check validates the rule, runs the tests and requires one exploitable and one non-exploitable case.

Guidelines:

- Base conditions on the advisory (vendor or upstream text), not on guesses. Link it in `references`.
- Use facts, not `true`. An absent fact means "unknown", never "false".
- No `file.match` requests for sensitive paths (keys, credentials, shadow files, tokens).
- New rules are `status: reviewed` only after a human has checked them against the advisory.

## Review

Every pull request needs a human approval from a code owner. Merging is the review, and a merge is
published to all servers that trust the feed. Bot drafts get the same review and are never merged
unchecked.

## License of contributions

By contributing you dedicate your contribution to the public domain under
[CC0 1.0 Universal](LICENSE), to the extent possible, and confirm you have the right to do so.
A sign-off line (`Signed-off-by: Name <email>`, `git commit -s`) is welcome but not required.
