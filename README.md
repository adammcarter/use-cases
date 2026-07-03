# Use Case Matrix

**Keep your AI agent's "it works" honest.**

AI coding agents ship fast and claim confidently — "done", "tested", "this works". Some of those claims are true. Some were true last week. Some were never checked. You can't tell which by looking, and stale claims fail silently.

Use Case Matrix gives your repo a **living matrix of product behaviours**, binds each one to the code that satisfies it, and marks it **`FRESH` only when trusted CI has cryptographically signed proof that the current code still backs the claim.** Edit the code behind a behaviour and its row flips to `SUSPECT` on its own — the lie surfaces instead of being trusted.

It's the difference between *"the agent said the checkout flow works"* and *"the checkout flow has a behaviour row, bound to `applyCoupon()`, proven `FRESH` by CI at commit `a1b2c3`, demonstrated to a human who signed off."*

---

## The problem it solves

| You've seen this | What's actually happening |
|---|---|
| "Tests pass ✅" but the feature is broken | Green tests ≠ verified behaviour. Nothing ties a *behaviour* to the code or the proof. |
| An agent says "done" and moves on | The claim is prose. There's no durable, checkable record — and no way to know when it goes stale. |
| A slick generated "demo plan" gets treated as a demo | A plan is *prepared material*, not a performed, recorded result. |
| `TEST-MATRIX.md` rotted months ago | Hand-maintained status tables drift the moment code changes; old `PASS` marks lie. |
| "It's signed off" — by whom? when? | Approvals are vibes. An agent can type "approved" as easily as a human. |

Use Case Matrix replaces all of that with one append-only, content-addressed source of truth that an agent maintains as it works — and that *cannot* quietly lie.

---

## What you get

### 🧬 A living use-case matrix
Behaviours, not just tests. Each row captures intent, scenarios, value tier, and observable outcomes in readable YAML the agent keeps current during planning and implementation. Query it (`ucm matrix list`), validate it, and see coverage by value and journey role at a glance.

### 🔐 Cryptographic freshness (the headline)
Bind a row to the exact code that satisfies it with a one-line marker. Trusted CI runs the verifier and signs an Ed25519 proof — only then does the row read `FRESH`. **Change the bound code and the row automatically becomes `SUSPECT`** (the signed proof no longer matches the code span). No human can fake `FRESH`; the signing key lives only in CI. Freshness is math, not a checkbox.

### 📒 An honest evidence ledger
Append-only, content-addressed history of what was actually observed. It grades itself: a self-reported agent "pass" is stamped the **weakest** assurance tier, never dressed up as verified. Corrections are appended, never edited. Nothing is laundered into proof.

### 🎬 Live showcases with un-fakeable sign-off
Perform a behaviour live — observe, verdict, finish — recorded as an event-sourced run. An agent can drive the whole show **but is structurally barred from approving it as the user**: user sign-off requires a trusted confirmation path the agent can't command. "Approved by a human" finally means it.

### ♻️ Bring what you already have
You already track behaviour *somewhere* — a markdown table, a checklist, a CSV, a spreadsheet export, a `TEST-MATRIX.md`, a QA sign-off sheet. The bundled **`migration` skill** lets the agent read **any** of those formats and map each item into a reviewable draft use case, preserving the original text and provenance — while explicitly refusing to turn old `PASS` marks into evidence. (For a standard `TEST-MATRIX.md` there's also a deterministic `ucm migrate test-matrix` fast path.) Review the drafts, activate the keepers.

### 🔌 Works inside your agent
Ships for **Claude Code, Codex, Copilot, and OpenCode** as a CLI (`ucm`) and an MCP server, with the same JSON contract on both. On install it auto-injects a trusted bootstrap at session start, so the agent knows how to use it without being told.

---

## Who it's for

- **Teams building with AI agents** who want acceptance to stay true as the agent (and the code) churns.
- **Anyone who needs pre-merge proof** — a signed, demonstrable record that the behaviours a PR claims actually hold.
- **Demos & sign-offs** — turn "trust me" into a performed, human-approved showcase.
- **Inheriting a messy repo** — migrate its `TEST-MATRIX.md`, or backfill behaviours and audit current risk.

Typical workflows: **continuous** (keep the matrix live as you build), **backfill** (adopt onto an existing codebase), **showcase-only** (just perform a few high-value demos), **audit-only** (load and inspect risk), **migration** (import a legacy matrix safely).

---

## Quickstart

```bash
# Install the CLI + MCP server (provides the `ucm` and `ucm-mcp` binaries)
npm i -g use-case-matrix

# Scaffold a workspace (creates use-cases/ + config with one example behaviour)
ucm init

# Explore — output is human-readable by default; add --json to ANY command for
# the machine-readable result envelope.
ucm --help
ucm matrix validate --repo .            # is the matrix clean?
ucm matrix list --repo .                # what behaviours exist?  (lists example.feature.happy_path)

# Bind a behaviour to the code that satisfies it — point --file at your own code.
# Set --start-line/--end-line to a range that EXISTS in that file (1–20 is just
# an example; a range past the end of a short file is rejected).
ucm bind --row example.feature.happy_path \
  --file src/feature.ts --mode explicit --start-line 1 --end-line 20

# Pick a few high-value behaviours to demo
ucm plan showcase --repo . --max-items 3
```

Everything except `bind` runs as-is against the freshly scaffolded workspace;
`bind` ties the example row to *your* code, so point `--file` at a real source
file. From there, wire your test command as the row's verifier and let trusted CI
mint the first `FRESH` proof (see **[security & proofs](docs/security.md)**).

New here? Start with the **[documentation index](docs/README.md)**.

---

## Under the hood

For the technically curious — the high-level shape:

- **Contract-first.** Every command returns a versioned, schema-validated JSON envelope (`ok`, `complete`, `data`, `diagnostics`, `context`). The MCP tools wrap the exact same envelopes, so agents get identical behaviour over either transport.
- **The trust core.** A behaviour row → a code-span *marker* → an append-only *binding registry* → a *signed proof event* in the evidence ledger. CI is the only authority that can mint proof (Ed25519 key held as a CI secret; a public-key keyring verifies it). `scan` derives each row's freshness (`FRESH` / `SUSPECT` / `UNPROVEN` / `UNBOUND` / `INVALID`) from the current code, the registry, and the proofs.
- **Markers are language-agnostic.** `//: @use-case: <id>` … `//: @use-case: end <id>` with the comment prefix inferred per file type (`#` for Python/shell/YAML, shebang-detected for extensionless scripts, a dedicated mode for Swift functions).
- **Built-in CI + precommit.** `.github/workflows/use-cases.yml` runs `validate-ledger` and `scan`, and (on release) `verify → prove → release-gate` so required rows must be `FRESH` to ship. An optional local precommit hook gives fast, non-authoritative feedback. Publishing uses npm Trusted Publishing (OIDC) with build provenance — no tokens.
- **Append-only everywhere.** The matrix, the binding registry, the evidence ledger, and showcase runs are all event-sourced and content-addressed: status is *derived* from history, never asserted.

Ships as a single self-contained package: **`use-case-matrix`** (binaries `ucm` and `ucm-mcp`). The `core` / `cli` / `mcp` workspaces are bundled inside it, not published separately.

Deeper reading: [CLI reference](docs/cli.md) · [data model](docs/data-model.md) · [code markers & freshness](docs/markers-adoption.md) · [evidence & security](docs/security.md) · [showcase runs](docs/showcase.md) · [hosts & activation](docs/hosts.md) · [MCP](docs/mcp.md) · [migration](docs/migration.md).

---

## License

MIT — see [LICENSE](LICENSE).
