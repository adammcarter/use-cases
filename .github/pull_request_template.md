# Summary

<!-- What does this change and why? Link any related issue. -->

## Checklist

- [ ] Tests added or updated for behavioural changes (the package test suites).
- [ ] All four suites are green locally: `swift test --package-path` for
      `UseCasesCore`, `UseCasesCLI`, `UseCasesMCP` and `UseCasesOracle` (the
      oracle needs `UC_BIN` / `UC_MCP_BIN` — see CONTRIBUTING.md).
- [ ] `swiftformat --lint .` and `swiftlint --strict` are clean.
- [ ] Docs updated (if a contract or behaviour changed).
- [ ] `CHANGELOG.md` updated under `## [Unreleased]`.

## SemVer impact

<!-- Per docs/reference/stability.md. Tick one. -->

- [ ] **patch** — bug fix, no schema / CLI / MCP / output-shape change.
- [ ] **minor** — additive only (new command/tool/optional field/error code).
- [ ] **major** — removes/renames/repurposes a contract or changes an output shape.

## Notes for reviewers

<!-- Anything that helps review: trade-offs, follow-ups, areas needing a closer look. -->
