# 20 — MCP Tools

**Phase:** 4 — Agent Layer  
**Status:** Specification (locked)

## 1. Purpose

AI agents use Use Cases through tools instead of typed commands. Each tool runs one command of chapter 16 and returns that command's `--json` document unchanged. It is a second way in, not a second set of rules: nothing about judging, storing or gating changes for an agent.

```text
agent ── tool call ──▶ use-cases mcp ──▶ use-cases <command> --json ──▶ the same document ──▶ agent
```

## 2. The server

`use-cases mcp` runs an MCP server (Model Context Protocol) over stdio. An agent's host (Claude Code, Codex, an IDE) starts it; people do not type it. For example:

```json
{"mcpServers": {"use-cases": {"command": "use-cases", "args": ["mcp"]}}}
```

It serves tools only. Each call runs as a separate request, in the workspace found from the folder the server was started in (chapter 16 §3), unless the call names one. `use-cases mcp --workspace DIR` names the workspace for every call that names none; a `DIR` that is not a folder is refused when the server starts (exit 2, on standard error), as every command refuses one.

Standard output carries the protocol and nothing else, one whole message at a time: messages are written one after another, so a host that reads slowly never sees one cut by another.

### Arguments

A call's arguments reach the command exactly as the host wrote them: a text that looks like something else, such as `data: retention, deletion and export`, is the text it is. A value is passed so that the command never reads it as an option, even when it starts with `-`. What a command line cannot carry is refused as usage, before anything runs, naming the argument: a text that holds U+0000, and an item of a list that the command reads as one comma-joined value when that item holds a comma.

### Stopping

A call is cancelled in three ways, and each stops its command as if the command had been told to stop (chapter 13 §15): the host cancels it; the host closes its input; the process is told to stop (SIGINT, SIGTERM or SIGHUP). A cancelled call is not answered. Calls in flight when the input closes are cancelled and get no answer, and the server ends once their commands have ended; a call that arrives with the end of the input starts no command at all.

A cancelled command gets time to wind up: a `verify` run seals itself as cancelled and stops its own tests. The time the server allows must exceed the core's group grace (two seconds, chapter 14) plus the sealing, or a command that was cancelled would be killed before it could seal. The server allows ten seconds.

A host whose reading end has gone away ends a write with an error; the server then ends as it does when the input closes, with every call cancelled. The server is not ended by the signal a write to a closed pipe raises.

### Lifeline

A server that is killed outright, with no chance to cancel anything, must not leave its commands running. The server holds open, for as long as it lives, the write end of a pipe it never writes to, and hands each command the read end as descriptor 3, naming it in the environment variable `USE_CASES_LIFELINE_FD`. A command that finds the variable watches that descriptor, and when the pipe reaches its end, the server is gone: the command cancels exactly as if it had been told to stop (chapter 13 §15), so a write that has begun finishes, a `verify` run seals as cancelled, and the tests it started are stopped. The variable is read once and is not passed on to the tests or tools a command starts.

## 3. The tools

| Tool | Runs | Arguments |
|---|---|---|
| `use_cases_validate_files` | `validate` | `workspace` |
| `use_cases_status` | `status` | `workspace`, `target`, `group`, `state` (a list), `gate`, `strict` |
| `use_cases_verify_tests` | `verify --start \| --finish \| --run \| --abort` | `workspace`, `step`, `only` (a list), `run_id` |
| `use_cases_record_verdict` | `record` | `workspace`, `use_case`, `route`, `status`, `message`, `attach` (a list) |
| `use_cases_links` | `links` | `workspace`, `target` |
| `use_cases_search` | `search` | `workspace`, `query` or `like` (a whole use case), `in`, `under`, `group`, `tier`, `state` (lists), `exact`, `full`, `page_size`, or `next` alone |
| `use_cases_show` | `show` | `workspace`, `use_case` |
| `use_cases_save` | `save --file -` | `workspace`, `use_case` (the whole use case, as `show` returns it), `dry_run` |
| `use_cases_remove` | `remove` | `workspace`, `use_case`, `dry_run` |
| `use_cases_apply` | `apply --file -` | `workspace`, `remove` (ids), `save` (whole use cases), `approved_by`, `dry_run` |
| `use_cases_approve` | `approve` | `workspace`, `use_cases` (a list) or `all`, `by`, `dry_run` |
| `use_cases_render` | `render <kind> --file -` | `workspace`, `kind` (intent, brief, proposal or results), `input` (the intent, or the proposal) |
| `use_cases_docs` | `docs` | `query` (a guide's name, or words), `exact`, `page_size`, or `next` alone |

A tool's name says what it acts on, because agents choose tools by name: `validate_files` checks files and runs no test, `verify_tests` gets verdicts from tests, `record_verdict` records one verdict. The commands keep their short names, for people typing them.

Every argument is optional except `step` for `verify`, `use_case`, `route` and `status` for `record`, `use_case` for `show`, `save` and `remove`, `by` for `approve`, and `kind` and `input` for `render`. Each tool's input schema says which values it takes; a value the command line would refuse is refused the same way.

`use_cases_search` is how an agent checks what already exists before it adds a use case: by words, or with `like` and the use case it is about to save. It pages with `next` exactly as the command does (chapter 16 §15), and `like` goes to `search --like -` on stdin.

`use_cases_render` is how an agent shows the person a layout (chapter 21 §7): it passes the intent or the proposal, and shows the returned `text` as it is.

`use_cases_docs` is how an agent learns to use Use Cases, and its quirks, from the guides for the version it is talking to (chapter 16 §16). It needs no workspace.

`use_cases_apply` is how a signed-off proposal reaches the files: the batch goes to `apply --file -` on stdin, and its dry run is what the person approved (chapter 21).

`use_cases_approve`, and `approved_by` on `use_cases_apply`, record a person's sign-off (chapter 21): an agent records only what the person approved, by their name, and the approval sits in the diff they review. Supporting use cases an agent may approve itself only where the person has said it may.

`use_cases_save` passes the use case to `save` on stdin, as JSON. So an agent changes use cases without ever writing YAML, and each change is exactly a person's `save`: one use case's lines, the file the recommended structure gives it, and nothing written if the result would be INVALID (chapter 16 §14). `dry_run` previews it (chapter 16 §17).

**Not tools:** `init` and `hooks` set up a repository and belong to a person. `prune` deletes evidence, which is a person's decision (chapter 12 §30): it is the one command that removes runs, and no agent tool runs it. `record --interactive` needs a terminal, which a tool call never has.

## 4. Results

A tool returns the command's `--json` document twice over: as text, and as structured content. The tool's output schema is the command's published schema (`docs/schemas/output/cli-<command>.schema.json`) with its references copied in, so it stands alone for any host.

| The command | The tool result |
|---|---|
| exit 0 | the document |
| exit 1 (the gate blocked, a verify run with run errors) | the document; it says what needs attention (`gate.passed`, `errors`) |
| exit 2 (refused) | the error document as text, marked as a tool error (`isError`), with no structured content: its shape is not the tool's output |

A tool never changes, adds to or summarises the document. An agent reads exactly what a script reads.

## 5. What it proves

The tools cannot do anything the command line cannot, and cannot skip any rule it applies: each call is the command itself. A verdict an agent records through `use_cases_record_verdict` is recorded exactly as a person's `use-cases record`.

## 6. Final model

```text
host starts:  use-cases mcp
tools:        validate_files · status · verify_tests · record_verdict · links · search · show · save · remove · apply
              approve · render · docs
              (not init, hooks, record --interactive)
each call  =  use-cases <command> --json  →  same document, same schema, same rules
refused    =  isError, with the error document as text
```
