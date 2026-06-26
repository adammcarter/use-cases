# MCP Contract

The presentation-skills MCP server is a convenience transport over the same application command contract used by the CLI. CLI JSON envelopes remain the compatibility contract:

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

Read-only behavior is the default. Write tools require `allow_write: true` in the tool arguments. Approval-sensitive behavior is request-only in v1.

```text
Tool                         Read-only   Write mode   Approval-sensitive
doctor_roots                 yes         yes          no
matrix_validate              yes         yes          no
matrix_list                  yes         yes          no
matrix_status                yes         yes          no
evidence_status              yes         yes          no
evidence_record              no          yes          no
evidence_void                no          yes          no
plan_showcase                yes         yes          no
plan_walkthrough             yes         yes          no
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
ucm_upsert_use_case
showcase_approve
showcase_reject
host_project
host_conformance
```

Use-case mutation needs a CLI/app contract first, including formatting and conflict policy. Approval writes need trusted confirmation. Host projection and conformance remain CLI-first until their mutation and evidence semantics are fully designed for MCP.
