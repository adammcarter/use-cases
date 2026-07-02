# Security Policy

Use Cases Plugin keeps an agent's product claims honest: a row is marked
**FRESH** only when trusted CI has signed proof that the current code, binding,
span, and verifier context still match. Because that trust signal is the whole
point of the tool, we take its threat model seriously — and we are explicit
about what it does **not** guarantee.

## Reporting a vulnerability

**Do not open a public issue for a security vulnerability.**

Report privately through GitHub's private security advisories:

> https://github.com/adammcarter/use-case-matrix/security/advisories/new

Please include the affected version (`ucm --version --json`), a description of
the issue, reproduction steps, and the impact you observed. We will acknowledge
the report, work with you on a fix, and coordinate disclosure. Public issues are
for bugs and feature requests only.

## What it guarantees

These are the load-bearing security properties of the trust core. They are
covered by tests and documented in
[`docs/reference/stability.md`](docs/reference/stability.md),
[`docs/security/key-management.md`](docs/security/key-management.md), and
[`docs/security/ci-hardening.md`](docs/security/ci-hardening.md).

- **FRESH requires a valid signature from a trusted authority.** A FRESH row
  must carry a valid ed25519 signature from a configured trusted signing key
  (single `--public-key`, or a key in the `--keyring` registry).
- **The proof must match the current state.** The signed proof's hashed inputs
  (row, binding-set, span, verification-context) must equal the current values.
  Edit the row, the bound code span, the binding set, or the verifier context
  and the proof no longer matches — the row drops out of FRESH.
- **Tamper-evident hash-chained ledger.** The evidence/proof ledger is an
  append-only JSONL hash chain. Editing, reordering, or truncating earlier
  entries is detected as a ledger-integrity failure (exit code `3`).
- **Fail-closed keyring.** Key resolution is fail-closed: an unknown `key_id`,
  a `revoked` key, an out-of-window proof, or a signature that does not verify
  all resolve to **not FRESH**. There is no "unknown key, allow anyway" path.
- **Local users cannot mint FRESH — given a pinned key.** The private signing
  key lives only in trusted CI, so an actor without it can run `verify` (no key
  required) but cannot produce a proof that verifies **against the public key the
  repo pins**. This holds only when that public key is committed where the agent
  cannot swap it; point `scan` at a key the agent supplies and the guarantee is
  gone (see [threat model](docs/security.md#threat-model--what-holds-on-its-own-and-what-needs-setup)).
- **`prove` is never exposed over MCP.** The MCP server does not offer a signing
  / `prove` tool. Minting proofs is a CI-only, key-holding operation.
- **No generic shell over MCP.** The MCP server exposes no generic `run_shell`
  tool. The only command execution path is configured capsule command steps,
  gated behind explicit caller intent, capsule permission, and a server-side
  command-execution mode; commands run as executable + argv (no shell
  interpolation) with a small environment allowlist.
- **Workspace-root path containment.** File and command operations are contained
  to the configured workspace root; path escapes / unsafe data-root boundary
  violations are rejected (exit code `4`).

## What it does NOT guarantee

We would rather under-promise than ship "append-only" marketing that isn't true.
These are real limits — read them before relying on it for a security decision.

- **The trust anchor is your setup, not the tool.** `scan` proves a proof was
  signed by the key it was told to trust; that this key means *CI and not the
  local agent* depends on committing the public key where the agent cannot swap
  it, keeping the signing key CI-exclusive, and validating the ledger against a
  protected ref (`--base-ref`). The full boundary is the
  [threat model](docs/security.md#threat-model--what-holds-on-its-own-and-what-needs-setup).
- **It does not judge whether a verifier is semantically adequate.** It proves
  that the configured verifier ran and passed over the bound inputs. It does not
  decide whether that verifier actually tests the claimed behaviour. A row can
  be FRESH behind a weak or near-empty check.
- **Declared verifier inputs may be incomplete.** Freshness is only as honest as
  the binding/verification-context you declare. If a row's real behaviour
  depends on code or config that was never bound or fed into the verifier
  context, changes there will not invalidate the proof.
- **A malicious maintainer can approve a weak policy.** Anyone who can change the
  matrix, verifier config, or release-gate policy can lower the bar. It records
  what was approved; it does not stop an authorised maintainer from approving a
  weak verifier or a permissive gate.
- **A compromised CI runner or leaked signing key can mint proofs.** The signing
  key is the root of trust. If the CI environment that holds it is compromised,
  or the key leaks, an attacker can mint proofs that verify. Mitigation lives in
  CI hardening, branch protection, and key rotation — not in the tool alone.
- **`protected_ref` is provider-attested where available and otherwise
  unknown.** The proof `authority` block records branch-protection state only
  when the CI provider exposes it (e.g. GitLab's `CI_COMMIT_REF_PROTECTED`).
  GitHub Actions does not expose it in the runner env, so it is `null`
  (unknown) unless supplied out of band. A `null` value never satisfies a
  `require_protected_ref` gate — the gate fails closed.

For the full asset/threat enumeration and mitigations, see the threat-model
section of the [public v1 roadmap](docs/release/public-v1-roadmap.md) and the
[security & trust overview](docs/security.md).

## Signing-key handling

- **Never commit the private key.** The repo and config hold only **public**
  keys. The private ed25519 key lives only as a CI secret, loaded into an env
  var and passed to `prove` via `--signing-key-env` — never written to disk in
  the repo.
- **Rotation:** add the new key as `active` → re-prove the affected rows under
  it → revoke the old key last. Doing it in that order keeps existing rows FRESH
  throughout the rotation.
- **Revocation:** flip a leaked key's status to `revoked`; every proof signed by
  it immediately stops verifying, and affected rows must be re-proved under a
  current key.

Full procedure: [`docs/security/key-management.md`](docs/security/key-management.md).

## Supported versions

Security fixes target the latest released `1.x` line. See
[`SUPPORT.md`](SUPPORT.md) for the supported runtime/CI/transport matrix.
