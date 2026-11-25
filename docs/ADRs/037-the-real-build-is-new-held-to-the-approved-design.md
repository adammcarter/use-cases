# ADR 037: The real build is a new build, held to exactly the approved design

## Status

Accepted - 2026-10-17

## Context

The real build (ADR 036) implements a design the owner approved chapter by chapter. The owner set two rules: the real build is a true new build, and it is exactly the design they approved.

## Decision

- **A true new build.** It is written from the chapters, schemas and ADRs. It is not translated from another implementation, nor from today's plugin: the chapters, schemas and ADRs are the source.
- **Exactly the approved design.** The chapters, schemas and ADRs are the specification. Anything found while building that they do not cover, or that seems to need changing, comes back to the owner as a decision, with an ADR, before it is built; it is never decided silently in code.
- **The acceptance suite is the acceptance test.** `UseCases/Acceptance/` runs `use-cases` as a program against whichever build it is pointed at, with every `--json` output, stored run and transformer exchange checked against the schemas.
- **The real build is done when it passes that suite** on macOS and Linux.

## Consequences

- Good: the real build is held to the behaviour the owner approved, by tests already held to the design, not by a new, unproven set.
- Good: a design gap found while building becomes a visible decision, not a quiet difference.
- Cost: the suite is in Python, so the acceptance runs need Python beside the Swift build.

## Considered Options

- **Port existing code to Swift:** faster to start, but it would carry that code's shortcuts into the product.
- **A new test suite for the real build:** native to Swift, but new tests not yet shown to hold the design.

## Related Links

- ADR 036 (Swift, macOS and Linux)
- `docs/architecture.md` §7 (how the build is tested)
- `UseCases/Acceptance/`
