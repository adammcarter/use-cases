# ADR 0006 — Trusted user-approval path (showcase sign-off)

Status: **accepted / implemented (0.2.0, feature F3)**. The signed-token approval
path described below now ships: `uc approve-run` mints a run-bound signed request,
and `uc showcase approve --approval-token <token> (--keyring <path> | --public-key
<path>)` verifies it and records a trusted human sign-off. See the *Shipped flow*
section for the end-to-end example. (Originally raised as roadmap row
`roadmap.deferred.trusted_host_confirmation_path`.)

## Context

A showcase run can require user approval (`approval_policy.mode: predefined`,
`approver_type: user`). The trust thesis is: an autonomous agent may **perform
and record** work but must **not be able to mint a human's sign-off**.

Historically the negative half held and the positive half was missing:

- `appendShowcaseApproval` accepts an approval only from a **trusted authority**;
  anything else is `untrusted_automation` and is rejected with
  `showcase.trusted_user_confirmation_required`.
- The CLI `showcase approve` used to hard-code `untrusted_automation` with no code
  path that produced a trusted authority, so a real human could not grant sign-off
  either — user-required runs sat at `approval_state: pending` forever.

**As of 0.2.0 this gap is closed.** `showcase approve` now ingests a signed
approval token (from `approve-run`) and drives the verify+append gate, so a real
human CAN sign off while an agent still cannot forge one. This ADR records the
design; the *Shipped flow* section documents the delivered commands.

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
`verified`/`confirmed` boolean. **As shipped (0.2.0)** the caller passes only the
signed token plus a public-key resolver; `verifyApprovalToken` derives trust from
the signature, the run binding, the nonce, the expiry, and the key's keyring-bound
assurance tier — no caller-supplied `verified` boolean exists on the path. The old
footgun (`{ kind: "trusted_host_token"; token; verified: boolean }`) is not the
delivered shape.

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

### Shipped flow (0.2.0)

The delivered end-to-end human sign-off, request → approve-run → showcase approve
→ approved:

```bash
# 0. A user-required showcase run is finished (approval_state: pending).

# 1. REQUEST. The plugin mints a run-bound ApprovalRequest (run id, ledger head,
#    evidence/CI digests, short-lived single-use nonce). The agent/host can ask
#    for it — e.g. via the MCP `showcase_request_approval` tool (mode
#    `approval_request`) — but cannot sign it. Save it to approval-request.json.

# 2. APPROVE-RUN — the human, in their OWN shell, signs the request with a key
#    held OUTSIDE the agent's scope, producing a token bound to that exact run.
uc approve-run --request approval-request.json \
  --key-file ~/.ucase/human-approval.pem --key-id human-key-1 \
  --decision approved --out approval-token.json --json

# 3. SUBMIT. `showcase approve` re-verifies the signature, the live-run binding,
#    the nonce (single-use), the expiry, and the key's keyring-bound assurance
#    tier — trust is COMPUTED, never asserted. A verified token is by definition a
#    USER sign-off (actorType is forced to `user`).
uc showcase approve --repo . --run <run-id> \
  --statement "I reviewed the live run." \
  --approval-token approval-token.json \
  --keyring keyring.json --json          # or --public-key human.pub

# 4. CONFIRM. `showcase status` needs the SAME trusted key material to verify the
#    embedded token; WITHOUT --keyring / --public-key it fails closed and the
#    approval reads `pending` (a signature it cannot check is never trusted).
uc showcase status --repo . --run <run-id> --keyring keyring.json --json
#    -> approval_state: approved
```

Key points a reader must not miss:

- The signing key lives **outside** the run ledger (in `--keyring` /
  `--public-key`), so the ledger alone can never mint trust.
- `showcase status` **requires** `--keyring` or `--public-key` to *display* a
  recorded approval; without it the embedded token cannot be verified and the run
  reads `pending` (fail-closed), not approved.
- Every spoof — no token, wrong-run token, expired token, forged signature, or an
  automation-tier key — is rejected non-zero and the run stays `pending`.

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

1. ✅ **Shipped (0.2.0).** `ApprovalRequested` object (nonce + run/evidence/ledger
   digest binding) and a **signed approval-token verifier** (reuses the existing
   keyring/Ed25519 infra): `approve-run` mints the request/token, `showcase
   approve --approval-token` verifies + records it.
2. A **local approval broker / host token issuer** — signing key outside the
   workspace (OS keychain / hardware-backed), native dialog or browser page,
   optional WebAuthn. *(In 0.2.0 the signing key is supplied via env/keyring; a
   dedicated OS-backed issuer is still future work.)*
3. **MCP elicitation** integration that hands off to the issuer.
4. **Hardened TTY** (`/dev/tty`, both ends ttys, randomized single-use challenge,
   nonce-bound) as a clearly-labelled **weak** fallback, excluded from
   non-spoofable-required policies.

Defer: OS-backed / WebAuthn issuer, separate-device approval, org key policy +
revocation, approval transparency log, multi-approver quorum.

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

Design reviewed with an external reasoning model. The verifier + the
`approve-run` / `showcase approve --approval-token` submit path shipped in 0.2.0
(feature F3); a dedicated OS-backed / WebAuthn issuer and the hardened-TTY
fallback remain future work.
