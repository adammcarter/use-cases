# Key management: signing keys, the keyring, rotation & revocation

Use Case Matrix proofs are **ed25519-signed** trusted-CI events. A row is only
`FRESH` when scan/validate-ledger can verify the signature on a matching proof
against a **trusted public key**. This page covers how those keys are managed:
generating a keypair, the keyring file, rotating keys, revoking them, and the
fail-closed guarantee that ties it all together.

There are two ways to tell the tool which public key(s) to trust:

| Flag | Trust model | Use when |
|---|---|---|
| `--public-key <file.pem>` | A **single** key, trusted unconditionally — only as safe as the file the verifier is pointed at, so commit it where the agent cannot swap it (see [threat model](../security.md#threat-model--what-holds-on-its-own-and-what-needs-setup)). | One signer, no rotation. The original, simplest path. |
| `--keyring <file.json>` | A **registry** of keys, each with a status and validity window. | You need rotation and/or revocation. **Opt-in**, additive. |

Both flags are accepted by `scan`, `verify`, `prove`, and `validate-ledger`.
`--keyring` is strictly additive: if you never pass it, nothing changes. When
both are present, the keyring wins.

> The private signing key lives **only in trusted CI** (passed to `prove` via
> `--signing-key-env <ENV>`, never written to the repo). The repo/config holds
> only **public** keys.

## Generating an ed25519 keypair

The signing key is a **PKCS8 ed25519 PEM**; the public key is an **SPKI ed25519
PEM**. Generate the pair with Node — this works everywhere the CLI runs and needs
no external tools (macOS's bundled LibreSSL cannot `genpkey -algorithm ed25519`):

```sh
node -e 'const c=require("crypto"),f=require("fs");const{publicKey,privateKey}=c.generateKeyPairSync("ed25519");f.writeFileSync("ci-signing-key.pem",privateKey.export({type:"pkcs8",format:"pem"}));f.writeFileSync("ci-signing-key.pub.pem",publicKey.export({type:"spki",format:"pem"}));'
```

This writes `ci-signing-key.pem` (the **private** key — keep in CI secrets only,
never commit) and `ci-signing-key.pub.pem` (the **public** key, for `--public-key`
or the keyring). If you have OpenSSL ≥ 3 (not macOS LibreSSL) you can instead run:

```sh
openssl genpkey -algorithm ed25519 -out ci-signing-key.pem
openssl pkey -in ci-signing-key.pem -pubout -out ci-signing-key.pub.pem
```

In CI, load the **private** PEM into an environment variable and point `prove`
at it; tag the proof with the matching key id:

```sh
export UCM_CI_SIGNING_KEY="$(cat ci-signing-key.pem)"
uc prove --all --trusted-ci \
  --signing-key-env UCM_CI_SIGNING_KEY \
  --key-id ci-key-1
```

The `--key-id` you sign with must match a `key_id` in the keyring (or be
irrelevant under the single `--public-key` path, which ignores it).

## The keyring file

A keyring is a JSON file conforming to
[`schemas/v1/keyring.schema.json`](../../schemas/v1/keyring.schema.json)
(`$id: https://use-cases.dev/schemas/v1/keyring.schema.json`). It is a
list of keys; each carries a stable id, the PEM public key, a validity window,
and a status:

```json
{
  "keyring_schema_id": "ucase-public-key-registry-v1",
  "keys": [
    {
      "key_id": "ci-key-1",
      "algorithm": "ed25519",
      "public_key": "-----BEGIN PUBLIC KEY-----\n…\n-----END PUBLIC KEY-----\n",
      "valid_from": "2026-01-01T00:00:00Z",
      "valid_until": null,
      "status": "active"
    }
  ]
}
```

| Field | Meaning |
|---|---|
| `key_id` | Stable id referenced by a proof signature's `key_id`. |
| `algorithm` | Always `ed25519`. |
| `public_key` | PEM-encoded ed25519 public key. |
| `valid_from` | Start of the validity window (inclusive). |
| `valid_until` | End of the window (inclusive), or `null` for open-ended. |
| `status` | `active` (may verify proofs) or `revoked` (must not). |

A `key_id` resolves to its public key **only when** the key exists, its status
is `active`, and the **proof's `created_at`** falls inside
`[valid_from, valid_until]`. The validity window is checked against the moment
the proof was signed, not "now" — so a proof minted while a key was valid keeps
verifying after the window closes only if you keep the key active; once the
window closes or the key is revoked, the proof no longer verifies.

Pass it to any verifying command:

```sh
uc scan --keyring keyring.json
uc validate-ledger --keyring keyring.json
```

## Rotation

Rotation introduces a new signing key without invalidating proofs already in the
ledger. The order matters — **add then re-prove, revoke last**:

1. **Generate** a new keypair (`ci-key-2`).
2. **Add** `ci-key-2` to the keyring as `active`, and **keep `ci-key-1` active**.
   At this point both keys verify, so every existing `ci-key-1` proof stays
   `FRESH`.
3. **Re-prove** the rows under `ci-key-2` (`prove … --key-id ci-key-2`). Because
   the ledger is append-only, this appends fresh proofs signed by the new key;
   the old proofs remain.
4. **Revoke** `ci-key-1` (flip its `status` to `revoked`) only after every row
   you care about has a current-key proof.

A proof minted under an old key that is **still active** stays `FRESH`. The
moment you revoke that old key, any row whose only proof was signed by it drops
out of `FRESH` — which is exactly why you re-prove (step 3) before revoking
(step 4).

> Because the evidence ledger is append-only and **fail-closed**, revoking a key
> that signed earlier, still-present ledger entries makes those specific entries
> fail verification (a ledger-integrity error). Re-prove the affected rows under
> a current key so each row again has a verifiable proof.

## Revocation

To stop trusting a key immediately (e.g. it leaked), set its `status` to
`revoked` in the keyring. From that point:

- Any proof signed by the revoked key no longer verifies.
- A row whose only proof was that key falls to `UNPROVEN`/`SUSPECT` — **never
  `FRESH`**.
- Re-prove the row under a current, `active` key to restore `FRESH`.

You do not delete the revoked entry: keeping it (as `revoked`) documents that
the key was once known and is now untrusted.

## The fail-closed guarantee

Verification is **fail-closed**. A proof is `FRESH` only when the keyring
positively vouches for its signing key at signing time. Every other case yields
**not `FRESH`**:

| Situation | Result |
|---|---|
| `key_id` not in the keyring | not FRESH (`UNKNOWN_KEY_ID`) |
| key present but `status: revoked` | not FRESH |
| proof `created_at` before `valid_from` | not FRESH |
| proof `created_at` after `valid_until` | not FRESH |
| signature does not verify | not FRESH (`BAD_SIGNATURE`) |
| **active key, in window, valid signature** | **FRESH** |

There is no "unknown key, allow anyway" path: an unrecognised, revoked, or
out-of-window key resolves to nothing, so the proof cannot verify and the row
cannot be `FRESH`.
