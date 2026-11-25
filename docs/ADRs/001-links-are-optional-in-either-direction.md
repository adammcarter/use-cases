# ADR 001: Links are optional, in either direction

## Status

Accepted - 2026-09-25

## Context

Freshness and automatic verdicts both need to know which code a use case depends on. The core must stay isolated from code (ADR 000), yet teams link in different ways:
- Some can put comments in their code.
- Some can't: generated files, binary fixtures, JSON, vendored code.
- Some don't want use-case text in their sources at all.

## Decision

Linking is optional, and the core understands two kinds:

```text
 code ── @use-case: marker ──▶ use case                  (no YAML entry needed)
 use case YAML ── manual binding: file + lines ──▶ code (code stays untouched)
```

- **Markers** are comment pairs in any file, identified by the use case's ID. They need no YAML entry.
- **Manual bindings** are written in the use case YAML: a file, optionally with a line and column range.
- **Resources** (file or glob) are route inputs for freshness only, such as fixtures and golden files.
- Link transformers may add further links (ADR 009).

Placement decides the role: links on the use case are implementation links, and links on a route are validation links.

## Consequences

- Good: works for any file, including ones that can't hold a comment.
- Good: code can stay free of use-case text.
- Good: a use case with no links still works (ADR 002).
- Cost: a line-range binding can point at the wrong lines once code moves. Markers move with the code.
- Cost: two ways to link means two sets of validity rules (chapter 08).

## Considered Options

- **Markers only, inside the core:** simple, but excludes files that can't hold comments and forces use-case text into every codebase.
- **YAML bindings only:** keeps code clean, but every refactor that moves code means editing use cases.

## Confirmation

The acceptance tests check that a manual binding links code with no marker, goes stale when that code is edited, and receives test results. It also checks that a missing file is refused, and that resources never expect a result.
## Related Links

- `docs/design/08-links.md`
- `docs/design/06-validation-model.md` (resources)
