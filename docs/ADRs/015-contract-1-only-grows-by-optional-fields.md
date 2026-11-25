# ADR 015: Contract 1 only grows by optional fields, and receivers ignore what they don't know

## Status

Accepted - 2026-09-25

## Context

Transformers are written by users and kept for years. If a later core adds a field to a request and a transformer validates requests strictly, every transformer breaks at once. The reverse also holds: a transformer written for a newer core may return fields an older core doesn't know. The contract had a version number but no rule for how it evolves.

## Decision

- Contract 1 is permanent.
- Within it, either side may gain optional fields. No field is ever removed, made required, or given a new meaning.
- Every receiver ignores fields it doesn't know. Transformers never validate requests strictly, and the core ignores unknown response fields and stores only the fields it defines.
- Any other change is contract 2. The core sends contract 2 only to a transformer that asks for it, and keeps speaking contract 1 to all the others.

## Consequences

- Good: a transformer written today keeps working with every future core, and the reverse, with no edits.
- Good: repositories never have to upgrade their transformers in step with the core.
- Cost: the core carries every contract version it has ever spoken.
- Cost: the published schemas are closed, because they describe exactly what this version sends so that a test can check it. Readers must not treat "closed" as a rule for transformers.

## Considered Options

- **Bump the contract for every addition:** simple versioning, but every transformer would need a release to keep up.
- **Content negotiation on every call:** flexible, but a transformer would need to understand the handshake before it can do anything.

## Confirmation

- `test_fields_from_a_future_version_change_nothing` runs in all nine fixture repos. It adds unknown fields to every request object and every response object, and the verdicts are identical. It fails if the core copies unknown response fields into its store (the schema hook catches it) or if any bundled transformer rejects them.

## Related Links

- `docs/design/10-bridge-settings-and-transformers.md` §10
- ADR 011
