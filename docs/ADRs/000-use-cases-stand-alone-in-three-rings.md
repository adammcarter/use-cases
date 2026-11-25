# ADR 000: Use cases stand alone in three rings

## Status

Accepted - 2026-09-25

## Context

Use cases describe what a product does and how each behaviour is proved. Something must connect them to the code and tests that make them true, and that connection decides how the whole system is built.

The obvious design puts a test command on every check (`swift test --filter X`, for example) and reads its exit code as the verdict. Measured against a real Swift package, it fails three ways:

- **Slow.** Each check is its own launch. That is about 1 s each even on an empty package (0.75 s with the build step skipped), so 600 checks cost around 10 minutes of pure overhead.
- **Unsafe.** A filter that matches no tests still exits 0, so a check "passes" without its test running.
- **Coupled.** Use cases name tools and commands, so they can't survive a change of language or test tool and can't stand alone.

Scope: the overall layering. The detailed rules each have their own ADR (001–010).

## Decision

The system is three rings. Each ring works without the rings outside it.

```text
 ┌ 3 HELPERS (optional) ─ result transformers · run commands · use-cases-bridge.yml ┐
 │  ┌ 2 LINKS (optional) ─ markers in code  OR  file/line bindings in the YAML ─┐  │
 │  │  ┌ 1 USE CASES CORE ─ use cases · record · judge · status · results ─┐    │  │
 │  │  └────────────────────────────────────────────────────────────────────┘    │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

- **Core (ring 1):** use case files, recording verdicts, judging, status, and the results store. Use cases name no commands, runners or test tools.
- **Links (ring 2, optional):** tie use cases to code, so editing linked code makes a use case stale (ADR 001).
- **Helpers (ring 3, optional):** turn test runs into automatic verdicts (ADRs 003, 006, 009).

The rings describe what each layer needs, not where files live. Use case files and `.use-cases/` sit in the repo folder but belong to the core.

## Consequences

- Good: the core alone is useful. You can write use cases, record verdicts and see status with no links and no helpers.
- Good: use cases survive a change of language or test tool unchanged.
- Good: one test run can give many use cases their verdicts (ADR 003).
- Cost: automatic verdicts need a transformer for each test tool or report format. Eight are bundled; others must be written.
- Cost: there are three places a behaviour's setup can live (use case YAML, code, bridge settings), and people must learn which is which.

## Considered Options

- **A command on every check:** rejected for the three failures above.
- **Shared "suite" runs, where one command covers many checks and a pass counts for all of them:** faster, but a failure can only be traced by re-running smaller groups, and use cases still name commands.
- **The core parses test output itself:** fast and precise, but it ties the core to every tool's format.

## Confirmation

- The acceptance suite (`UseCases/Acceptance/`) runs the build against a real Swift package, nine realistic repos across eight languages plus Cucumber, a mixed-language monorepo, conformance, the store and a scale run. It includes the core working with no bridge settings at all.
- `docs/schemas/engine/validate.py` checks the specs and schemas agree.

## Related Links

- ADRs 001–020
- `docs/design/01-core-foundation.md`
