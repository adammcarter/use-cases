# ADR 0006 — Trusted user-approval path (showcase sign-off)

Status: proposed (roadmap row `roadmap.deferred.trusted_host_confirmation_path`).

## Context

A showcase run can require user approval (`approval_policy.mode: predefined`,
`approver_type: user`). The trust thesis is: an autonomous agent may **perform
and record** work but must **not be able to mint a human's sign-off**.

Today the negative half holds and the positive half is missing:

- `appendShowcaseApproval` accepts an approval only from a **trusted authority**
  (`trusted_interactive_cli` with `stdinIsTty && confirmed`, or
  `trusted_host_token` with `verified`); anything else is `untrusted_automation`
  and is rejected with `showcase.trusted_user_confirmation_required`.
- But the **CLI `showcase approve` hard-codes `authority: untrusted_automation`**.
  There is no code path that ever produces a trusted authority. So a real human
  cannot grant sign-off either — user-required runs sit at `approval_state:
  pending` forever.

This ADR records the design for the path that lets a real human approve while an
agent cannot — without weakening the guarantee.

## Decision

Approval trust comes from a **non-forgeable signed token**, not from "a process
saw a `y` on a TTY". The boundary is: a trusted issuer **outside the agent's
controllable I/O** signs an approval statement **bound to the exact run**
(run id, ledger head, evidence digest, git commit, CI-freshness digest, a
short-lived single-use nonce). The plugin **verifies** the signature against a
protected keyring (the same model already used for CI freshness proof).

### Why not TTY confirmation

A modern coding agent already drives interactive terminals — it can allocate a
pseudo-TTY, read the prompt, and type the answer. A randomized challenge phrase
only converts *blind* automation into *interactive* automation, which agents
already are. TTY confirmation is therefore a **speed bump, not a trust root**: it
defends against pipes / `yes` / CI / blind scripts, never against an agent that
controls the terminal.

### Invariant (load-bearing)

The verifier **computes** trust; it must **never** accept a caller-supplied
`verified`/`confirmed` boolean. The current `TrustedApprovalAuthority` type
(`{ kind: "trusted_host_token"; token; verified: boolean }`) is a footgun — the
boolean is asserted by the caller. The future implementation MUST replace it with
a caller input that carries only the token, and a verifier that derives
`verified` from a signature check. (No code path constructs a trusted token
today, so this is latent, not yet exploitable — but it must not ship wired.)

### Assurance levels, not a boolean

Replace `trusted iff stdinIsTty && confirmed` with explicit tiers, and let
`approval_policy` choose the floor:

| Authority input | Assurance | trustedForHumanSignoff |
|---|---|---|
| `untrusted_automation` | none | false |
| `interactive_cli_challenge` (hardened TTY) | `same_channel_operator_confirmation` (agent-spoofable) | **false** |
| `host_signed_approval_token` (verified) | `trusted_host_user_presence` | true |
| `webauthn_approval_assertion` (UP/UV) | `hardware_user_presence_or_verification` | true |

`trusted_interactive_cli` is **relabelled** to make its spoofability explicit; it
is excluded from any policy that requires non-spoofable human sign-off.

### Flow

```
agent / CLI / MCP may REQUEST approval
   -> ApprovalRequested { run_id, showcase_id, ledger_head_hash, evidence_digest,
                          git_commit, ci_freshness_digest, nonce, exp }
   -> trusted issuer confirms with a real human OUTSIDE agent control
      (host dialog / OS auth / WebAuthn / out-of-band page)
   -> issuer signs an approval token bound to that exact request
   -> plugin verifies signature against the protected keyring + checks
      audience, run binding, nonce/jti single-use, expiry, policy floor
   -> append ApprovalGranted
```

### MCP

MCP **elicitation** is the UX transport, not the proof. A raw `accept` from an
MCP client is protocol data, not a human signature. Elicitation (form mode, or
URL mode for out-of-band) requests the approval and shows context; the proof is
the resulting signed token the plugin verifies.

## Ranked build plan

1. `ApprovalRequested` object (nonce + run/evidence/ledger digest binding) and a
   **signed approval-token verifier** (reuse the existing keyring/Ed25519 infra).
2. A **local approval broker / host token issuer** — signing key outside the
   workspace (OS keychain / hardware-backed), native dialog or browser page,
   optional WebAuthn.
3. **MCP elicitation** integration that hands off to the issuer.
4. **Hardened TTY** (`/dev/tty`, both ends ttys, randomized single-use challenge,
   nonce-bound) as a clearly-labelled **weak** fallback, excluded from
   non-spoofable-required policies.

Defer: WebAuthn-only mode, separate-device approval, org key policy + revocation,
approval transparency log, multi-approver quorum.

## Threat boundary

| Boundary | Agent can spoof? |
|---|---|
| CLI flag / stdin / `/dev/tty` prompt / TTY challenge | yes (agent drives the terminal) |
| MCP raw `accept` | depends on client; not proof alone |
| Host-signed token (protected key) | no, unless host/key compromised |
| WebAuthn / OS biometric assertion | much harder |
| Separate-device approval | hardest locally |

## Product language

> "An agent can REQUEST approval but cannot MINT it. Trusted approvals require a
> signed confirmation from a configured approval issuer."

Never claim "a terminal prompt proves a human approved."

## Provenance

Design reviewed with an external reasoning model (an external reasoning model / GPT-Pro). This ADR is
the spec for `roadmap.deferred.trusted_host_confirmation_path`; the row stays
`lifecycle: planned` until the verifier + an issuer ship.
