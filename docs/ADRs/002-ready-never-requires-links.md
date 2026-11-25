# ADR 002: READY never requires links

## Status

Accepted - 2026-09-25

## Context

READY means a use case is fully written and ready for verification. If READY required a link to code, the isolated core (ADR 000) could not stand alone, and optional links (ADR 001) would be optional in name only.

## Decision

READY requires identity, title, value tier, intent, at least one scenario, at least one route, and every scenario covered by a gating route. It never requires links.

Missing links produce warnings that never block READY:

```text
use case has no implementation links
  -> freshness will not track its code

gating route has no validation links and no procedure
  -> only `use-cases record` can verify it
```

## Consequences

- Good: a team can write and verify use cases before any code exists, or without ever linking them.
- Good: the authored state reflects only the use case itself.
- Cost: a READY use case can be verified by hand while its code changes unnoticed. The warnings are the only signal.

## Considered Options

- **READY requires an implementation link:** guarantees freshness tracking, but contradicts optional links.
- **A separate LINKED state:** clear, but adds a state everyone must learn for information that a warning already carries.

## Confirmation

The acceptance test `test_links_are_never_required_to_be_ready`: a use case with every marker removed is still judged normally, with both warnings shown.

## Related Links

- `docs/design/02-use-case-schema.md`
- `docs/design/07-verification-state-model.md`
