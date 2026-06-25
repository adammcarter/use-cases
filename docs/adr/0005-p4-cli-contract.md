# ADR 0005: P4 CLI Contract Semantics

## Status

Accepted.

## Context

P4 makes the CLI the normative public contract that later MCP tools will reuse.
P2 and P3 already expose schema-backed JSON envelopes, so P4 must refine the
existing contract without introducing a second envelope shape.

an external reasoning model reviewed P4 before implementation and found that the plan conflated
command execution success, domain validity, input completeness, and process
exit status.

## Decision

The v1 JSON envelope remains:

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

Meanings are separate:

```text
ok
  the requested command contract executed successfully

complete
  every relevant input was safely considered

data.*
  command-specific domain result

exit status
  shell-level classification
```

For example, `matrix validate` on damaged input exits `1`, keeps `ok:true`,
sets `complete:false`, and returns `data.valid:false`.

Strict mode is an integrity policy. It does not change parsing, diagnostics, or
domain state; it only changes whether incomplete state is accepted for the
requested operation.

Workflow mode is advisory configuration, not evidence history. `workflow
set-mode` updates the owning workspace config atomically and persists canonical
P1 enum values. It cannot relax schema validation, path policy, evidence
integrity, strictness, or approval requirements.

P4 also adds read-only `doctor roots`, composed `matrix status`, and evidence
voiding. Evidence void appends a terminal event and leaves prior JSONL bytes
unchanged.

## Consequences

P9 can map MCP calls onto the same CLI/application semantics without treating
negative domain results as transport failures.

Future presentation and showcase layers can rely on workflow mode as guidance
only, not as a hidden enforcement switch.
