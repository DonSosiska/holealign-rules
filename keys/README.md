# Signing key

`keys/rules-public.key` holds the base64 ed25519 public key that servers trust (`rules.feed.trusted_keys`).
The release workflow refuses to publish when it is missing, and verifies every signed bundle against it.

The private half is the base64 seed written by `panoptes-server rules keygen -out <file>`; keep an offline,
backed-up copy, and store the same content in the `RULES_SIGNING_KEY` secret of the `rules-release`
environment. Anyone who holds it can publish rules to every trusting server.

## First setup

```sh
panoptes-server rules keygen -out rules-signing.key    # prints the public key
echo '<printed public key>' > keys/rules-public.key    # commit it
# put the contents of rules-signing.key in the RULES_SIGNING_KEY environment secret
```

## Rotation

1. Generate the new key. Commit its public key as `keys/rules-public.key` only when the secret is switched (step 4);
   publish it to server operators now.
2. Operators list both public keys in `rules.feed.trusted_keys` and roll that out.
3. Wait until the servers run with both keys.
4. Replace the `RULES_SIGNING_KEY` secret with the new private key and commit the new `keys/rules-public.key`;
   the next release is signed with it.
5. Later, operators remove the old key from `trusted_keys`.

If the key leaks, tell operators to drop it from `trusted_keys` immediately and rotate as above.
