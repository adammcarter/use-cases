# ADR 0002: P1 Schema Contracts

Date: 2026-06-25
Status: Accepted for P1

## Context

an external reasoning model reviewed the P1 schema plan before implementation and found that the
original phase was directionally right but underspecified. In particular, P2
would otherwise have to invent the CLI envelope, YAML parse profile, approval
authority, event ordering rules, workspace identity, host verification result
shape, and content hash semantics.

P1 therefore freezes a broader public contract than the initial plan listed.

## Decisions

### Public Schemas

P1 publishes these v1 schemas:

```text
common
cli-result
use-case-file
evidence-event
demo-capsule
presentation-plan
showcase-event
host-profile
host-status-result
workspace-config
workflow-mode
```

Every public persisted object uses `schema_version: 1`. Public CLI JSON also
uses `protocol_version: 1`.

### CLI Envelope

JSON CLI output uses one normative envelope:

```text
schema_version
protocol_version
command
ok
complete
data
diagnostics
context
```

`ok` means the command executed according to its contract. `complete` means all
relevant source data was considered. Damaged YAML can therefore return
`ok: false` and `complete: false` without crashing the command or hiding valid
sibling files.

### YAML Profile

P1 accepts a JSON-compatible YAML profile only:

```text
duplicate mapping keys  -> rejected
custom YAML tags        -> rejected
merge keys              -> rejected
timestamp-like scalars  -> preserved as strings
```

Validation is layered:

```text
parse validation
document schema validation
workspace validation
event replay and derived-state validation
```

P1 implements the first three layers and provides replay expectation fixtures
for later phases.

### Policies

Verification and approval are separate policies.

Verification requirements use arrays of verifier types instead of the ambiguous
`both` value. Approval policy supports `none`, `ask`, and `predefined`.

Only user approval events can satisfy user approval requirements. Agents can
record observations and verdicts, but cannot fabricate authoritative user
approval.

### Events

Evidence events are ordered by monotonic `sequence` within `aggregate_id`.
Showcase events are ordered by monotonic `sequence` within run aggregate IDs.
`recorded_at` is metadata only, not ordering authority.

Correction, void, supersession, and invalidation events carry typed target
fields. Generic JSON Patch payloads are not part of v1.

### Plans And Capsules

Demo capsules are declarative recipes. They do not contain proof, verdict,
approval, or final run state.

Presentation plans are the resolved immutable run input. They contain selected
items, content hashes, resolved steps, expected observations, policy snapshots,
selection reasons, and exclusions.

### Hosts

Host profiles are expectation data only. They cannot declare support as
verified. Derived host status lives in `host-status-result` and verified or
partial status requires evidence event IDs.

### Hashes

Semantic hashes use:

```text
algorithm       SHA-256
format          sha256:<64 lowercase hex characters>
representation  JSON-compatible semantic object with sorted object keys
excluded         YAML comments, source paths, parser positions, diagnostics
```

The implementation exposes `computeSemanticHash` and tests hash stability across
YAML formatting changes.

## Consequences

P1 is larger than the original schema-only scaffold, but P2 can now load and
diagnose use-case workspaces without inventing public behavior. The CLI, MCP,
and host adapters must use this contract rather than creating parallel warning,
status, or approval shapes.
