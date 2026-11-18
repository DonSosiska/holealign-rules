# Signing key

`keys/rules-public.key` holds the base64 ed25519 public key that servers trust (`rules.feed.trusted_keys`).
The release workflow refuses to publish when it is missing, and verifies every signed bundle against it.

The private half is the base64 seed written by `holealign-server rules keygen -out <file>`; keep an offline,
backed-up copy, and store the same content in the `RULES_SIGNING_KEY` secret of the `rules-release`
environment. Anyone who holds it can publish rules to every trusting server.

## First setup

```sh
holealign-server rules keygen -out rules-signing.key    # prints the public key
echo '<printed public key>' > keys/rules-public.key    # commit it
# put the contents of rules-signing.key in the RULES_SIGNING_KEY environment secret
```

## Rotation

Servers reject a bundle signed by a key they do not trust, so operators must trust the new key before the first
bundle signed with it appears.

1. Generate the new key offline, with a backup. Do not change the secret or `keys/rules-public.key` yet; give the
   new public key to server operators.
2. Operators list both public keys in `rules.feed.trusted_keys` and roll that out.
3. Wait until the servers run with both keys.
4. Replace the `RULES_SIGNING_KEY` secret with the new private key and commit the new `keys/rules-public.key` in a
   pull request. Merge it; the next release (a rule change, or `gh workflow run release.yml --ref main`) is signed
   with the new key and verified against the new public file.
5. Later, operators remove the old key from `trusted_keys`.

## If the key leaks

Stop releases, tell operators to remove the key from `trusted_keys` immediately, then rotate with a new key. The
step-by-step procedure is in [docs/maintainers.md](../docs/maintainers.md#the-signing-key-leaked); report it as
described in [SECURITY.md](../SECURITY.md).

See also the release runbook in [docs/maintainers.md](../docs/maintainers.md#release-runbook).
