# Use Cases Plugin — documentation

Use Cases Plugin keeps an agent's product claims honest: it gives a repo a
living use-case matrix, binds each row to the code that satisfies it, and marks a
row **FRESH** only when trusted CI has signed proof that the current code,
binding, and verifier context still match. Stale claims become visible instead of
silently trusted.

Ships as `@use-case-matrix/cli` (binary `ucm`) plus an MCP server
`@use-case-matrix/mcp` (binary `ucm-mcp`).

## Start here

- **[CLI reference](./cli.md)** — every command and its flags. `ucm init`
  scaffolds a workspace that validates out of the box; `ucm bind` links a row to
  code; `ucm prove` (in trusted CI) mints the FRESH proof.
- **[Activation](./activation.md)** — when to use the plugin continuously during
  planning/implementation versus as a backfill, walkthrough, or live showcase.

## Adopting the matrix

- **[Code markers & adoption log](./markers-adoption.md)** — the in-code marker
  grammar (`//: @use-case: <slug>` … `//: @use-case: end <slug>`), the explicit
  and swift-func bind modes, the per-extension comment prefix, and a real
  dogfooded binding.
- **[Acceptance matrix](./acceptance.md)** — how this repo dogfoods its own
  use-case matrix through `use-cases/`.
- **[TEST-MATRIX migration](./migration.md)** — importing an existing
  `TEST-MATRIX.md` into the matrix (behaviour coverage is preserved; proof is
  not).
- Runnable examples live under [`examples/`](../examples) — including
  [`examples/python-pytest`](../examples/python-pytest), a pure-Python project
  that reaches a signed **FRESH** row with `pytest` and no pnpm/vitest.

## Reference

- [CLI reference](./cli.md) — every command and its flags, including the verifier
  configuration model.
- [MCP contract](./mcp.md) — the MCP tools, modes, and safety boundaries.
- [Data model](./data-model.md) — the persisted file shapes.
- [Host support](./hosts.md) — Claude, Codex, Copilot, and OpenCode as
  first-class hosts.
- [Showcases](./showcase.md) — live runs in front of a reviewer.
- [Architecture decision records](./adr) — the design decisions behind the
  contracts.

## Security & release

- [Security and trust](./security.md) — keys, signing, the keyring, CI as the
  proof authority, and the safety boundaries on generated output.
- [Release checklist](./release.md) — the production release gate.
