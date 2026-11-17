## Rule

Advisory / CVE:
Package(s):

## Reviewer checklist

- [ ] The conditions match the advisory (what is exploitable, and under which configuration).
- [ ] Every fact used exists in the catalog and is collected by the agent; absent facts are not treated as false.
- [ ] No `file.match` request on sensitive paths.
- [ ] Tests cover both outcomes (exploitable and not exploitable) and the unknown case where relevant.
- [ ] `status` is `reviewed` and `validate` passes.
- [ ] For `bot-draft` pull requests: I read the advisory myself, not only the draft.
