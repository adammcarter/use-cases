# Use Case Matrix — documentation

Use Case Matrix (UCM) keeps an agent's product claims honest: it gives a repo a
living use-case matrix, binds each row to the code that satisfies it, and marks a
row **FRESH** only when trusted CI has signed proof that the current code,
binding, and verifier context still match. Stale claims become visible instead of
silently trusted.

Ships as `@use-case-matrix/cli` (binary `ucm`) plus an MCP server
`@use-case-matrix/mcp` (binary `ucm-mcp`).

## Start here

- **[Getting started](./getting-started.md)** — the zero-to-first-FRESH tutorial
  for a new repo: install, author a row, bind code, declare a verifier, and let CI
  mint the proof.

## Tutorials

- **[Adopt the matrix in a pure-Python repo](./tutorials/python-pytest.md)** —
  proof that adoption is **not** JS-only: a tiny Python project reaches a signed
  **FRESH** row with `pytest` as the verifier and **no pnpm/vitest** anywhere.
  Runnable project at [`examples/python-pytest/`](../examples/python-pytest).

## Concepts

Read these in order for the full mental model:

1. [The use-case matrix](./concepts/matrix.md) — the living acceptance spec.
2. [Bindings, markers & freshness states](./concepts/bindings.md) — linking rows
   to code, and what FRESH / SUSPECT / UNPROVEN / UNBOUND / INVALID mean.
3. [Verifiers](./concepts/verifiers.md) — the config-driven command-verifier
   model, presets, the `{slug}` convention, and the verification context hash.
4. [Proofs & the ledger](./concepts/proofs-and-ledger.md) — signed proof events,
   the tamper-evident hash chain, the keyring, and CI as the authority.
5. [Evidence vs proof](./concepts/evidence.md) — observation versus the signed
   trust gate.

## Reference

- [CLI reference](./cli.md) — every command and its flags.
- [MCP contract](./mcp.md) — the MCP tools, modes, and safety boundaries.
- [Stability & versioning policy](./reference/stability.md) — what is a v1
  contract and how versions move.
- [Error-code registry](./reference/error-codes.md) — the stable `UCM_*` codes.
- [Data model](./data-model.md) — the persisted file shapes.

## Security

- [Key management](./security/key-management.md) — generating keys, the keyring,
  rotation, and revocation.
- [CI hardening](./security/ci-hardening.md) — the CI-neutral authority contract
  and the opt-in release-gate authority requirement.
