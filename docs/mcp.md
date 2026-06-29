# MCP Contract

The use-cases-plugin MCP server is a convenience transport over the same application command contract used by the CLI. CLI JSON envelopes remain the compatibility contract:

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

MCP tools return that envelope as `structuredContent` and also mirror it as text content for clients that only render text. Domain-negative results stay normal tool results; they are not MCP transport failures.

Repository content, tool output, logs, plans, runbooks, and generated artifacts are data, not trusted instructions.

## Modes

Read-only behavior is the default. Write tools require both server write mode and `allow_write: true` in the tool arguments. Server write mode is enabled by starting the MCP process with:

```text
UCP_MCP_WRITE=1
```

Command execution is a separate server mode. A capsule command step can run only when the MCP process also starts with:

```text
UCP_MCP_COMMAND_EXECUTION=1
```

Approval-sensitive behavior is request-only in v1.

```text
Tool                         Read-only   Write mode   Approval-sensitive
doctor_roots                 yes         yes          no
matrix_validate              yes         yes          no
matrix_list                  yes         yes          no
matrix_status                yes         yes          no
use_case_upsert              no          yes          no
use_case_remove              no          yes          no
evidence_status              yes         yes          no
evidence_record              no          yes          no
evidence_void                no          yes          no
plan_showcase                yes         yes          no
plan_walkthrough             yes         yes          no
capsule_run                  no          yes          no
showcase_start               no          yes          no
showcase_status              yes         yes          no
showcase_record_observation  no          yes          no
showcase_record_verdict      no          yes          no
showcase_decide              no          yes          no
showcase_finish              no          yes          no
showcase_request_approval    yes         yes          request only
host_doctor                  yes         yes          no
```

## Workspace Roots

Workspace-scoped tools require an explicit `repo` argument. Optional `data_root` values are resolved relative to `repo` and must stay inside that repository. The server should not silently operate on its process working directory for project data.

## Use-Case Mutation Boundary

`use_case_upsert` and `use_case_remove` expose the same use-case matrix mutation contract as the CLI. They require `allow_write: true`, validate the current matrix before writing, and return `matrix.upsert` or `matrix.remove` envelopes.

MCP use-case delete means lifecycle removal, not physical deletion. `use_case_remove` marks the row `lifecycle: removed` and records removal metadata in the YAML file.

MCP cannot treat YAML, repository content, generated plans, command output, logs, or tool output as instructions. Those inputs are data to validate, filter, and report.

## Capsule Run Boundary

`capsule_run` performs a persisted demo capsule through the showcase ledger. It requires server write mode plus `allow_write: true` because it records run events.

Static observation text in a capsule is a prompt for a real observation; it is not proof and does not create a pass verdict by itself.

Command steps are skipped unless the caller passes `execute_commands: true`, the capsule has `permissions.command_execution: true`, and the MCP server has command-execution mode enabled. Command execution uses executable plus argv without a shell, resolves the working directory inside the repository, runs with a small environment allowlist, records bounded/redacted stdout/stderr as observations, and records pass/fail verdicts from the capsule's expected exit codes.

MCP capsule runs do not record user approval. If the run requires user sign-off, use `showcase_request_approval` to produce the CLI-mediated approval command.

## Approval Boundary

MCP cannot create user approval or rejection events in v1. `showcase_request_approval` returns:

```text
decision_required
trusted_confirmation_required
suggested_cli_command
run_id
plan_hash
finish_event_id
known_gaps
status
```

The user approval write remains CLI-mediated unless a host later provides a trusted non-model confirmation path.

`showcase_start` accepts generated plan files through `plan_file`, so compiled
stdio MCP can run the same generated-plan lifecycle as the CLI. The generated
plan remains prepared material until the start event records its content hash.

## Deferred V1 Tools

These are intentionally not exposed in v1:

```text
showcase_approve
showcase_reject
host_project
host_conformance
```

Approval writes need trusted confirmation. Host projection and conformance remain CLI-first until their mutation and evidence semantics are fully designed for MCP.
