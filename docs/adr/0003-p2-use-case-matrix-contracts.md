# ADR 0003: P2 Use-Case Matrix Contracts

## Status

Accepted.

## Context

P2 introduces the use-case matrix as the replacement foundation for the older
test-matrix habit. This phase must load intended behavior from sharded YAML,
preserve source provenance, and tolerate damaged files without claiming full
sign-off.

An external reasoning model reviewed the P2 plan before implementation and identified contract gaps
that would cause P3 evidence-ledger rework if left implicit.

## Decision

P2 owns intended-behavior discovery only. It does not compute evidence,
freshness, approval, pass, or verification state.

The public CLI data contracts are schema-backed:

```text
matrix-validation-result.schema.json
matrix-list-result.schema.json
```

Diagnostics remain in the outer CLI envelope. Matrix result data contains only
JSON-safe projections: integrity, source files, counts, ambiguity groups, and
listed use cases.

Integrity uses these meanings:

```text
clean
  every in-scope use-case source is structurally loadable and resolved

partial
  some addressable use cases exist, but relevant structural diagnostics exist

unusable
  sources exist, but no addressable matrix can be formed
```

Duplicate use-case IDs make every copy ambiguous. No duplicate copy wins, and
no implicit feature merge exists in v1.

References resolve by stable IDs, not by mirrored paths. Missing targets emit
`broken_reference`; duplicated targets emit `ambiguous_reference`.

Changed-source filtering is caller-supplied. P2 normalizes and matches local
`source_refs`; it does not invoke Git or choose a baseline.

The path policy rejects symlinks under `use-cases/`, reads regular YAML files
only, reports data-root-relative POSIX paths, and preserves valid siblings when
one file is damaged.

## Consequences

P3 can join evidence against `MatrixSnapshot` by stable IDs and resolvers
instead of reopening YAML or guessing which duplicate should receive evidence.

Presentation plans can bind selected use cases by semantic hash and source
provenance without depending on YAML file paths as identity.

Future Git-aware change detection belongs in an adapter above P2.
