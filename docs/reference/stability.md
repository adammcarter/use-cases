# Stability & Versioning Policy

Use Cases Plugin follows [Semantic Versioning](https://semver.org). At
`1.0.0` the surfaces listed under **Public API** below are a contract: they only
change in breaking ways across a **major** version bump. This page is the
authoritative declaration of what is stable, what is experimental, and how
versions move.

> Packages are released together at the same version:
> `@use-cases-plugin/core`, `@use-cases-plugin/cli`, `@use-cases-plugin/mcp`.
> See the [publishing runbook](../release/publishing.md) for how a release is cut
> (npm Trusted Publishing + provenance) and the owner one-time npm setup.

## SemVer policy

| Bump | What may change |
|---|---|
| **patch** (`1.0.x`) | Bug fixes. No schema, CLI, MCP, or output-shape changes. Human-readable text may change. |
| **minor** (`1.x.0`) | Additive only: new commands, new MCP tools/resources/prompts, new **optional** schema fields, new error codes, new exit-code *meanings* for previously-unused codes. Existing contracts keep working. |
| **major** (`x.0.0`) | Anything removed, renamed, or changed in meaning: a command/flag/tool/field/error-code removed or repurposed, an output shape changed, a schema field made required, exit-code semantics changed. |

A change is "breaking" if a correct integration written against `1.0.0` could
observe different behaviour. When in doubt, treat it as major.

## Public API (stable at 1.0.0)

These are versioned contracts:

- **CLI command + subcommand names and their flags** — e.g. `ucp matrix validate`, `ucp verify`, `ucp prove`, `ucp bind`, `ucp scan`. Renames/removals are breaking.
- **CLI `--json` output** — the envelope and every command's `data` shape (see below). Human/text output is **not** part of the contract.
- **CLI exit codes** and their meanings (see below).
- **The result envelope** shared by CLI `--json` and MCP structured results.
- **MCP tool names** and their input/output schemas, plus the MCP **safety policy** defaults (mutations gated, no signing/`prove`, no generic shell, workspace-root locking).
- **Persisted file formats**, each carrying `schema_version`: the matrix / use-case files, the binding registry (`bindings.jsonl`), the proof/evidence ledger (`evidence.jsonl`), evidence events, showcase specs/runs, capsules, plans, host profiles, and workspace config.
- **JSON Schemas** published under the `https://use-cases-plugin.dev/schemas/v1/...` `$id` namespace (resolved locally; not fetched).
- **The use-case marker grammar** (`//: @use-case: <slug>` … `//: @use-case: end <slug>`) and slug rules.
- **The proof/trust model**: ed25519 signed proof events, the hashed inputs (row, binding-set, span, verification-context), and the freshness states (`FRESH`, `SUSPECT`, `UNPROVEN`, `UNBOUND`, `INVALID`). Signing-key management — the single `--public-key` path, the opt-in `--keyring` registry, and key rotation/revocation — is documented in [key management](../security/key-management.md).
- **Documented `@use-cases-plugin/core` TypeScript exports.** Undocumented internals are not public.
- **Error codes** declared in the [error-code registry](./error-codes.md) (`UCP_*`).

### Result envelope

Every CLI `--json` response and MCP structured result uses this envelope:

```json
{
  "schema_version": 1,
  "protocol_version": 1,
  "command": "matrix.validate",
  "ok": true,
  "complete": true,
  "data": { },
  "diagnostics": [],
  "context": { }
}
```

- `schema_version` / `protocol_version` — bumped only on breaking envelope changes.
- `command` — stable dotted command id.
- `ok` — success boolean. `complete` — whether the operation ran to completion.
- `data` — the command-specific payload (validated against that command's schema).
- `diagnostics` — array of structured items, each with a stable `code` (see [error codes](./error-codes.md)).
- `context` — workspace/component metadata.

### Exit codes

| Code | Meaning |
|---:|---|
| `0` | Success. |
| `1` | Command failed / validation issues / required rows not FRESH. |
| `2` | Unknown command or invalid arguments. |
| `3` | Integrity blocked (matrix/evidence/ledger integrity failure). |
| `4` | Unsafe path escape (data-root / repo boundary violation). |

Additional trust-engine exit codes used by `prove` (e.g. untrusted append,
signing-key missing) are documented in the CLI reference and are stable.

## Experimental / not yet covered by the v1 contract

These ship and work, but their **shape** may change in a minor release until
promoted. They are called out here so adopters can depend on them with eyes open:

- MCP **resources** (`ucp://…`) and **prompts** are exposed and read-only, but
  the exact URI/prompt set may grow in minor releases; treat the MCP *tool*
  surface as the most stable MCP contract.
- MCP output **rate-limiting** and **size caps**.
- **Host profiles are a fixed built-in set for v1** (`claude`, `codex`,
  `copilot`, `opencode`). The host-applicability/projection engine is generic,
  but registering *custom* host profiles is a post-v1 extension; the trust core
  (bind/verify/prove/freshness) is host-independent and unaffected.
- The **trust-engine commands** (`bind`, `scan`, `verify`, `prove`,
  `validate-ledger`) always emit JSON — they are machine/CI-oriented and have no
  separate human-formatted mode (other commands gate JSON behind `--json`).
- Non-GitHub-Actions CI authority adapters (the proof model is CI-neutral; only
  the GitHub Actions reference workflow is a supported path at 1.0.0). The
  CI-neutral authority contract, per-provider authority population, and the
  opt-in release-gate authority requirement are documented in
  [CI hardening](../security/ci-hardening.md).
- Any other CLI command's **human-readable** (non-`--json`) formatting.
- Internal `@use-cases-plugin/core` modules not listed in the documented export surface.

## Supported environments

- **Node**: active LTS lines.
- **CI**: GitHub Actions is the reference, first-class path. The verify/prove
  contract is CI-neutral and documented for other providers (best-effort) in
  [CI hardening](../security/ci-hardening.md), which also covers the opt-in
  release-gate authority requirement (`release_gate.required_authority` /
  `require_protected_ref`).
- **Verifiers**: command verifiers for any language/toolchain. `pnpm`/`vitest`
  is one preset, not an assumption.
- **MCP transport**: local stdio. Remote/HTTP transport is **not** a v1 contract.

## Changing a contract

A breaking change to anything above requires: a major version bump, a CHANGELOG
entry, and a migration note under `docs/migration/`. Additive changes ship in a
minor with a CHANGELOG entry.
