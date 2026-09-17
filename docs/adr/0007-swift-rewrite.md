# ADR 0007 — Rewrite in Swift, distributed from GitHub Releases

Status: **accepted 2026-09-16**. The decisions below were taken one at a time
with the owner and are the standing brief for the work; a ladder step that
finds one of them wrong stops and asks rather than working around it.

## Context

Use Cases is a TypeScript tool (core 19.4k lines, CLI 5.7k, MCP 1.9k, tests
30.6k) delivered as a git-installable agent plugin with a committed Node
bundle. The owner wants it rewritten in Swift — a core package, a CLI on
swift-argument-parser, an MCP server on the MCP Swift SDK — and renamed from
`uc` to `use-cases`. The plugin has to keep installing from GitHub on every
host with nothing to build, and every behaviour has to survive the rewrite
unchanged.

## Decisions

1. **The matrix is the spec, first.** Before any Swift, every behaviour the
   tool has today gets a row with golden, bad and edge scenarios; roadmap rows
   are parked; gaps are raised and written. Rows are language-neutral and are
   what survives the rewrite.
2. **Every row is proven through the binary, second.** One black-box test per
   scenario, talking only to the CLI or MCP and comparing JSON, bound with
   markers, green against `uc` before any port. That suite is the oracle the
   Swift binary must pass unchanged. White-box TypeScript tests stay TS-only
   and are rewritten in Swift Testing at the end.
3. **Distribution: binaries are downloaded from GitHub Releases on first run.**
   Not committed to the repo, not built on install. A `bin/` bootstrap fetches
   the asset for the machine, verifies its checksum, caches it and execs it.
4. **Hard rename `uc` → `use-cases`**, no alias: the command, the MCP server,
   skills, agents, hooks and docs. Markers (`@use-case:`), `use-cases.yml`,
   `.use-cases/` and the ledger formats are unchanged.
5. **Layout:** the same repository, three separate Swift packages, each with
   its own `Package.swift`: `UseCasesCore`, `use-cases` (CLI), `use-cases-mcp`.
   TypeScript stays in `packages/` until the final step deletes it.
6. **Platform and toolchain:** macOS, Swift 6.4. Packages are opened, built and
   tested through the Xcode MCP tools (`XcodeOpenWorkspace` on the package
   directory); the CLI is used only for what the MCP has no tool for.
7. **Libraries:** swift-argument-parser, Yams, swift-crypto (sha256, ed25519),
   swift-markdown (migration import), the MCP Swift SDK, and a small
   JSON-schema validator of our own driven by the 28 schema files.
8. **Contract freeze:** the CLI JSON envelope, the 28 schemas, the marker
   syntax and the ledger formats do not change for the whole ladder. A port
   that needs a change stops and asks.
9. **Versioning and releases:** no releases during the work. 0.8.0 is cut once
   everything is done and the owner has signed it all off.
10. **Stress thresholds:** 1,000 matrix rows, 10,000 ledger events, 8 parallel
    writers, each scenario with a stated time bound (scan and verify under 10s
    at 1,000 rows; ledger validate under 5s at 10,000 events; concurrent
    writers never corrupt a ledger).

## How the ladder runs without the owner

- Rows that describe existing behaviour are pre-approved and land without a
  replay. New behaviour, or retiring behaviour, stops and waits.
- A row is merged when the agent has personally verified it: rows
  `VERIFIED_LOCAL`, the full suite green, and the behaviour exercised by hand.
  Showcases the owner watches happen at the milestones the owner names.
- Each row is committed as it finishes.
- The ladder stops on: a decision above proving wrong, a needed contract
  change, a host live-check failing twice in a row. Nothing outside this
  repository is touched; agent-setup and other repos are out of scope.

## Consequences

- The TypeScript suite is split into black-box (survives the port, ~21 files
  today plus everything written under decision 2) and white-box (TS-only, ~87
  files, rewritten last). The count is measured, not assumed.
- Node stays in the plugin until the cut-over step; the plugin keeps working
  throughout.
- The 15 `roadmap.*` rows are parked, not ported.

## Amendments

- **2026-09-17 — migration retired.** The owner retired the TEST-MATRIX import
  command (`uc migrate`) and the `migration` skill (agent-driven import of any
  old acceptance document) entirely: the command, the skill, their docs, the
  command's result schema, the two `UCM_MIGRATION_*` error codes
  and the five `migration.*` rows are removed, and the Swift port drops them
  too. This is a deliberate retirement, not a change made under the freeze, so
  decision 8 does not apply to it. As a result swift-markdown leaves decision
  7's library list, and the schema count frozen by decisions 7 and 8 is 27.
- **2026-09-17 — migration workflow mode retired.** With the importer gone, the
  owner also retired the `migration` value of the workflow mode: it leaves the
  enums in `workflow-mode`, `workspace-config` and `presentation-plan`, and
  `uc workflow set-mode` refuses it. A workspace config naming it no longer
  loads. Every recorded showcase run uses `continuous`, so no recorded data is
  invalidated. The 0.8.0 release notes list both retirements as breaking.
