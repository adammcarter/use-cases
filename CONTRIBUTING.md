# Contributing to Use Cases

Thanks for helping improve Use Cases. This guide covers local setup,
the repo layout, the trust model you should keep in mind, and what we expect on
a pull request.

By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
Security issues go through private advisories — see [SECURITY.md](SECURITY.md),
never a public issue.

## Development setup

Use Cases is a Swift package set. You need the Swift toolchain pinned by
[ADR 0007](docs/adr/0007-swift-rewrite.md) (Xcode's Swift 6.1 or newer) on
Apple Silicon, plus `swiftformat` and `swiftlint` (`brew install swiftformat
swiftlint`). Node is needed for one thing only: the OpenCode plugin module is
JavaScript, and the oracle runs it.

```bash
swift build --package-path UseCasesCLI                # the CLI
swift test  --package-path UseCasesCore               # the library suite
swift test  --package-path UseCasesCLI                # the CLI suite
swift test  --package-path UseCasesMCP                # the MCP suite
swift test  --package-path UseCasesOracle             # the black-box suite
```

`UseCasesOracle` drives the real binaries. Point it at the ones you just built,
or it resolves whatever it can find:

```bash
UC_BIN="$(swift build --package-path UseCasesCLI --show-bin-path)/use-cases" \
UC_MCP_BIN="$(swift build --package-path UseCasesMCP --show-bin-path)/use-cases-mcp" \
  swift test --package-path UseCasesOracle
```

## Repository layout

| Path | What it is |
|---|---|
| `UseCasesCore` | Core domain library: matrix, bindings, verify/prove, freshness, ledger, evidence, showcase, capsule, plan, host. The published schemas live under `schemas/v1`; the three internal marker schemas under `schemas/markers`. |
| `UseCasesCLI` | The `use-cases` CLI. Thin command layer over core; owns the `--json` envelopes and exit codes. |
| `UseCasesMCP` | The `use-cases-mcp` MCP server. Wraps the same envelopes for agents over local stdio. |
| `UseCasesOracle` | The black-box suite. Links nothing; drives the built binaries and the shipped files as processes. |
| `bin/`, `hooks/`, `opencode/` | The host-facing entry points: the runtime resolver, the release bootstrap, the session hook, the OpenCode plugin module. |
| `docs/` | Reference and security docs. `docs/reference/stability.md` is the SemVer contract. |

The three products stay **on the same version**, which is the one in
`.claude-plugin/plugin.json`.

## The trust model in one paragraph

A row is **FRESH** only when a valid ed25519 signature from a configured trusted
authority covers proof that the current row, binding, span, and verifier context
all still match. **CI is the authority**: the private signing key lives only as
a CI secret. `verify` runs anywhere with no key and never writes; `prove` holds
the key, signs a successful verification, and appends it to the tamper-evident
hash-chained ledger — so contributors and PRs can `verify` freely but cannot
mint FRESH locally. Keep this split intact: do not add a path that lets `prove`
run without the trusted key, and do not expose `prove` or a generic shell over
MCP.

## Making changes

- **Behavioural changes need tests.** Any change to logic/behaviour must add or
  update tests in the same PR, and the full suite must stay green. Prose, docs,
  config, and schema-example edits do not need a failing test first.
- **Respect the public contract.** CLI command/flag names, `--json` output
  shapes, exit codes, MCP tool names + schemas, persisted file formats, and the
  documented `@adammcarter/use-cases-core` exports are versioned per
  [`docs/reference/stability.md`](docs/reference/stability.md). If your change is
  additive it's a **minor**; if it removes/renames/repurposes a contract or
  changes an output shape it's a **major** — call that out in the PR.
- **Keep it generic.** Use Cases is language/CI-neutral. Don't bake in a hidden
  dependency on a particular runner or on GitHub Actions; `js.vitest` is one
  verifier preset among several, not an assumption. That the product is written
  in Swift says nothing about the repositories it verifies.

## Pull request expectations

- **Green CI.** `.github/workflows/swift.yml` must pass: it builds the three
  products, runs all four suites, lints, and then gates the matrix with the
  binary it just built (`verify --repo . --all`, `scan --repo . --gate`).
- **Conventional-ish commits.** Use clear, imperative, prefixed messages
  (`feat:`, `fix:`, `docs:`, `test:`, `chore:`, `refactor:`). One logical change
  per commit.
- **SemVer impact noted.** State whether the change is patch / minor / major per
  the stability policy.
- **Docs updated.** If you change a contract or behaviour, update the relevant
  doc in the same PR.
- **Tests included** for behavioural changes, as above.

Open a draft PR early if you'd like feedback on direction before polishing.
