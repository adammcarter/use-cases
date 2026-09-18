# Changelog

All notable changes to Use Cases are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project
follows [Semantic Versioning](https://semver.org) as declared in
[`docs/reference/stability.md`](docs/reference/stability.md).

> This file starts at 0.8.0. Releases up to and including 0.7.0 were cut before
> the project kept a changelog; their history is the git log and the tags
> `v0.4.1`…`v0.7.0`.

## [Unreleased]

Nothing yet.

## [0.8.0] — unreleased, awaiting the owner's sign-off

The whole product is rewritten in Swift and delivered as a checksum-verified
binary downloaded from GitHub Releases. The behaviour contract — the CLI JSON
envelope, the published schemas, the marker grammar and the ledger formats — is
unchanged, and was held to byte parity through the port ([ADR 0007][adr]
decision 8). What changed is the command's name, the way it is delivered, and
five behaviours the owner retired along the way.

**This release is breaking on every count below. Read the whole list before
upgrading: there are no aliases and no automatic migrations.**

[adr]: docs/adr/0007-swift-rewrite.md

### Removed — the command is renamed, with no alias

- **`uc` is now `use-cases`.** The CLI, the MCP server (`uc-mcp` →
  `use-cases-mcp`), the skills, the agents, the hooks and the docs all move
  together. **There is no alias and no tombstone**: `bin/uc` is deleted, so a
  shell that had it on `PATH` now answers `command not found: uc`
  ([ADR 0007][adr] decision 4, owner-confirmed 2026-09-18).
  - **What breaks for you:** any script, git hook, CI step or agent prompt that
    calls `uc`. In particular, a `.githooks/pre-commit` scaffolded by 0.7.0 or
    earlier calls `uc` and will fail with the shell's own error — the plugin
    cannot warn you, because nothing of the plugin is reached.
  - **The fix:** re-run `use-cases init`, which rewrites the hook block. The
    hook's shell variable and override also move: `uc="${UC:-…}"` is now
    `use_cases="${USE_CASES:-…}"`.
  - Row ids, scenario ids, binding slugs, the marker keyword (`@use-case:`),
    `use-cases.yml`, `.use-cases/` and every ledger format are **unchanged**. An
    id that contains the letters "uc" is not a rename target.
- **The MCP resource scheme and prompt names are renamed and the old ones are
  refused, not aliased.** `uc://…` is now `use-cases://…` (an unknown resource
  is `-32002`), and the four `uc/<prompt>` prompts are now `use-cases/<prompt>`
  (an unknown prompt is `-32602`). A URI scheme and a prompt name are on none of
  decision 8's frozen lists; the owner approved both the rename and the refusal
  on 2026-09-18.
- `UC_BIN`, `UC_MCP_BIN`, `UC_RUN_KEY_FILE` and the `UCM_*` error codes keep
  their names. The error codes are part of the frozen envelope; the others are
  test and environment knobs, not the surfaces decision 4 renames.

### Removed — the TEST-MATRIX importer and everything that served it

Retired by the owner on 2026-09-17 as dead weight. This is a deliberate
retirement, not a change made under the contract freeze.

- **`uc migrate test-matrix` is gone**, along with the `migration` skill (the
  agent-driven import of any hand-rolled acceptance document) and their docs.
  The command now answers with the unknown-command usage envelope.
- **`migration-test-matrix-result.schema.json` is removed. The published schema
  catalogue is now 27 schemas, not 28**, and `schema list` reports 27.
- **Two error codes are removed:** `UCM_MIGRATION_UNSAFE_SOURCE_PATH` and
  `UCM_MIGRATION_UNSAFE_OUTPUT_PATH`. The registry is 66 codes across 8
  surfaces.
- **The `migration` value of the workflow mode is retired** (2026-09-17). It
  leaves the enums in `workflow-mode`, `workspace-config` and
  `presentation-plan`; `use-cases workflow set-mode migration` is refused, and
  **a workspace config naming it no longer loads**.
  - **What breaks for you:** a `use-cases.yml` (or workspace config) whose
    `workflow.mode` is `migration`. Change it to `continuous` or `milestone`.
  - No recorded showcase run uses it, so no recorded data is invalidated.

### Removed — three behaviours that went with the TypeScript

Deleting the TypeScript deleted behaviour, not only an implementation. Each row
was released with `unbind --reason row_retired` first, so the binding ledger
records why it ended.

- **`diagnostics.contracts.missing_build_hint`** — the CLI's "run the build"
  hint. It existed only because the TypeScript CLI `await import`ed
  `core/dist/index.js` and translated `ERR_MODULE_NOT_FOUND`. SwiftPM links the
  core statically, so the condition cannot arise and the hint cannot be emitted.
- **`plugin.bundle.runs_from_clean_clone`** and
  **`plugin.runtime.pre_swift_versions_run_the_committed_bundle`** — both
  described the committed Node bundle in `dist/`, which this release deletes.
  The resolver's Node branch and the bootstrap's fallback hint went with it.
- The first two rows keep `lifecycle: removed` in the matrix because the
  evidence ledger holds signed proofs naming them, and a proof naming a row the
  matrix no longer knows makes the ledger INVALID. The third had no proof event
  and its text was removed outright.

### Changed — how the plugin is delivered

- **The plugin downloads a binary instead of shipping one.** On first run
  `bin/use-cases-bootstrap` fetches the release archive for this machine,
  verifies it against the release's `SHA256SUMS`, caches it and execs it.
  Nothing is committed to the repository and nothing is built on install
  ([ADR 0007][adr] decision 3).
  - **Node is no longer required to run the tool.** It is still needed for the
    OpenCode plugin module, which is JavaScript by OpenCode's own contract.
  - **There is no fallback.** A release that should carry the assets and does
    not exits 1 with nothing cached, rather than quietly running something
    older. That is deliberate: a silent fallback would mask a missing release.
  - `SHA256SUMS` authenticates **transport, not provenance** — it is fetched
    from the same release as the archive. A signed manifest would be a contract
    change, and is not this release.
  - Overrides: `USE_CASES_VERSION` (which release), `USE_CASES_RELEASE_BASE_URL`
    (where from), `USE_CASES_CACHE_DIR` (where to), `USE_CASES_PLATFORM` (which
    asset).
- **A release must exist before this version is tagged.** The runtime resolver
  branches on the plugin's own version: from 0.8.0 on it goes to the bootstrap,
  below it nothing runs. So the moment 0.8.0 is the version in
  `.claude-plugin/plugin.json`, every installed host tries to download — and if
  the release has not published its assets, the first command fails.
- **Apple Silicon only** (owner decision, 2026-09-17). The published platform
  list is exactly `macos-arm64`. Every universal build warned that x86_64 is
  deprecated for the deployment target, so the x86_64 asset was retired rather
  than shipped stale.
  - **What breaks for you:** an Intel Mac, or any non-Mac. The bootstrap refuses
    before downloading anything and names what it found and what is published:
    `no published binary for Darwin/x86_64.` / `Published platforms:
    macos-arm64.`
  - Adding a platform back is one line in `PUBLISHED_PLATFORMS`
    (`bin/use-cases-bootstrap`) and one in the release workflow's loop.
- **npm publishing is not resumed.** It was removed at 0.7.0; `package.json`
  survives only as the HOST manifest OpenCode resolves the plugin through, and
  is `private` with no scripts and no dependencies.

### Changed — the implementation

- **The product is Swift.** Four packages: `UseCasesCore` (the domain library),
  `UseCasesCLI` (the `use-cases` command), `UseCasesMCP` (the `use-cases-mcp`
  server) and `UseCasesOracle` (a black-box suite that links nothing and drives
  the built binaries as processes). The TypeScript, its toolchain and its
  lockfile are deleted.
  - Building from source now needs the Swift toolchain, `swiftformat` and
    `swiftlint` — see [CONTRIBUTING.md](CONTRIBUTING.md). It no longer needs
    `pnpm`, and there is nothing to build on install.
  - The MCP Swift SDK is a pinned dependency used for its `StdioTransport`
    only: the JSON-RPC dispatch and the response bytes stay ours, because the
    SDK's own encoder cannot emit the frozen envelope.
- **Verifier presets are unchanged.** `js.vitest`, `js.npm-test` and the rest
  are how the tool verifies *your* repository. That Use Cases is now written in
  Swift says nothing about the repositories it verifies.

### Unchanged

The CLI command and flag names (beyond the rename), the `--json` envelope, the
exit codes, the MCP tool names and their schemas, the 27 published schemas, the
marker grammar and slug rules, every persisted file format, and the proof and
trust model — signed ed25519 proofs, the four hashed inputs, and the `FRESH` /
`SUSPECT` / `UNPROVEN` / `UNBOUND` / `INVALID` states. Ledgers written by 0.7.0
are read by 0.8.0 unchanged, and the events they already hold keep the tool name
and version that wrote them.

[0.8.0]: https://github.com/adammcarter/use-cases/releases/tag/v0.8.0
