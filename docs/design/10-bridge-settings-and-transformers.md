# 10 — Bridge Settings + Transformer Contract

**Phase:** 2 — Core Engine  
**Status:** Specification (locked)

## 1. Purpose

Helpers are the optional outer ring. They turn test runs into use-case validation without the use cases ever naming a command, runner, or test tool.

```text
 ┌ 3 HELPERS (optional) ─ result transformers · run commands · use-cases-bridge.yml ┐
 │  ┌ 2 LINKS (optional) ─ markers in code  OR  file/line bindings in the YAML ─┐  │
 │  │  ┌ 1 USE CASES CORE ─ use cases · record · judge · status · results ─┐    │  │
 │  │  └────────────────────────────────────────────────────────────────────┘    │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

This chapter defines:

- the bridge settings file, `use-cases-bridge.yml`;
- the transformer contract: its two jobs, their JSON shapes, and their rules;
- link keys;
- how transformer failures are handled;
- the bundled transformers.

Chapter 13 defines when the core calls transformers. Chapter 14 defines how run commands execute. Chapter 07 defines how the core judges what transformers report.

Examples in this chapter use a small Swift project. Nothing in the rules depends on it: the shapes are the same for any language and tool.

## 2. Core principle

Extras can only hand the core links or results. The honesty rules live in the core, so no extra can weaken them.

```text
transformer reports what happened    core decides what it means
─────────────────────────────────    ─────────────────────────────
"LoginTests.swift:6 passed"          which link contains line 6?
"LoginTests.swift:10 failed"         did every validation link get a result?
"line 35 passed, no link"            worst result wins
                                     stale, didn't run, code changed during the run
```

Every helper is optional. With no bridge settings the core still works: use cases can be written, verdicts recorded with `use-cases record`, and status derived.

## 3. Extension points

There are three extension points. Each is its own program or setting, in any language, swapping one JSON file with the core. Transformers never write `.use-cases/`; a run command writes only its report, at the `{report}` path the core gives it inside the run.

```text
 EXTENSION POINT 1              EXTENSION POINT 2               EXTENSION POINT 3
 Transformer · links            Transformer · results           Run command
 ────────────────────           ─────────────────────           ───────────────
 which code each use case       a test tool's report            what verify --run
 depends on, beyond markers     → a result per link             starts
 and manual bindings            never runs anything             settings only, no code

 in:  use cases                 in:  use cases, links (keyed),  in:  use-cases-bridge.yml
      read-only code path            report, exit code               validations[].run
      settings                       (--run only), working           validations[].working_dir
                                     folder, settings
 out: links (file + lines)      out: results per link,          out: a report (file or folder) at
                                     unlinked tests                  {report}, inside the run

 same input, same answer        same input, same answer         runs in the real project
 read-only, fast                skipped test = incomplete       core fills in {report}
 paths stay in the project      crash = run error, never        nothing else in .use-cases/
                                a failed use case               is ever touched
```

Manual checks need no extra. A person or agent records the verdict against the route with `use-cases record` (chapter 13).

## 4. Bridge settings file

```text
<workspace-root>/use-cases-bridge.yml
```

```text
file absent  -> valid workspace; no helpers set up
file present -> must validate
```

It is root-only in v1. Only the root file is read, and a `use-cases-bridge.yml` in a child scope is INVALID.

Use-case definition files never reference it, and nothing in it changes a route fingerprint (chapter 11).

## 5. File shape

The shape is the same for every language and test tool. This example happens to use a Swift project; any command and transformer fit the same fields.

```yaml
schema_version: 1

links:                      # optional: extra link transformers
  - transformer: <name-or-path>
    settings: {}

validations:
  - id: auth-tests
    report: auth-tests.jsonl      # optional: the file name inside the run's reports folder
    run: [swift, test,
          --experimental-event-stream-output, "{report}",
          --experimental-event-stream-version, "0"]
    transformer: swift-testing
    settings: {}
    timeout_seconds: 900

  - id: web-tests                # a sub-project: the command runs in its own folder
    working_dir: web
    report: web.xml
    run: [./scripts/test, "{report}"]
    transformer: junit
```

Top level:

```text
schema_version   1            required
links            0..N         optional
validations      0..N         optional
```

Unknown fields and duplicate YAML keys are INVALID.

## 6. `links` entries

```text
transformer   1      bundled name or project-relative program path
settings      0..1   object passed unchanged to the transformer
```

Link transformers add links. They never remove or override markers or manual bindings.

## 7. `validations` entries

```text
id                1      segment grammar (chapter 05), unique in the file
report            0..1   the report's file or folder name inside the run's reports folder
run               0..1   argument vector for --run (chapter 14)
working_dir       0..1   project-relative folder the command runs in; default: the project root
transformer       1      bundled name or project-relative program path
settings          0..1   object passed unchanged to the transformer
timeout_seconds   0..1   positive integer (chapter 14)
```

Rules:

- `id` may not be `record`. That name is reserved for verdicts recorded with `use-cases record` (chapter 12). Using it is INVALID.
- `id` is also the name of the validation's reports folder in every run, so the names Windows reserves for devices (`con`, `prn`, `aux`, `nul`, `com1`–`com9`, `lpt1`–`lpt9`) are INVALID on every system.
- The project never says where reports live. Each verify run owns them: at the start point the core creates `.use-cases/runs/<run-id>/reports/<id>/` (chapter 12), and the tests write there. So a report can never be an earlier run's, and nothing is ever deleted to make sure of it.
- `report` is a name, not a path: 1 to 64 of `A-Z a-z 0-9 . _ -`, not starting with `.` and not ending with `.`, and not a Windows device name with or without an extension. Anything else is INVALID. `report: results.xml` makes `{report}` the file `.../reports/<id>/results.xml`.
- With no `report`, `{report}` is the folder itself. Use this when a tool writes one file per test class (JUnit XML from Maven or Gradle), or when a run needs two outputs, such as a machine report plus the console. The transformer decides how to read what is there. An empty folder is no report.
- `run` is a non-empty array of strings. It is used only by `use-cases verify --run`.
- `working_dir` must be an existing folder inside the workspace and never `.use-cases/` or inside it. A violation is INVALID. It is where the command runs, and it is passed to the transformer, because a tool running in a sub-project usually reports paths relative to that folder. `{report}` is absolute, so it is the same whatever `working_dir` is.
- A validation without `run` is read by `use-cases verify --finish` after `verify --start`, from the report your own test run wrote to the path `--start` printed. Under `--run` it is a run error, because there is no command to run (chapter 13).
- Order in the file is the order `--run` executes (chapter 14).

## 8. The `{report}` placeholder

`{report}` is the only placeholder. It is the absolute path of the validation's report in this run: the report name inside its reports folder, or the folder when there is no name. Inside `run`, the core replaces it; `verify --start` prints it for each validation, for your own test step to use.

```text
{report}   -> <workspace-root>/.use-cases/runs/<run-id>/reports/auth-tests/auth-tests.jsonl
```

There is no other substitution, no interpolation, and no shell expansion. A word in braces is a brace pair holding one bare word: `{`, a letter or underscore, letters, digits or underscores, then `}`, with no `$` before it. A word that is a near miss of `report` is taken for a mistyped placeholder and is INVALID, named: the same word in other letter case, such as `{Report}`, or one edit from it (a letter added, dropped or changed, or two neighbouring letters swapped), such as `{reprot}`, `{reports}` or `{repot}`; a word further off, such as `{port}`, `{repo}` or `{export}`, is text. The message reads `use-cases-bridge.yml: validations/0/run/2: unknown placeholder {reprot}; {report} is the only one`. Every other brace is plain text, passed on as written: a word in braces such as `'{print}'`, `'{name}'`, `'{port}'` or `'/x/{p}'`, `"a || { b; }"`, `"${HOME}"`, `"{ }"`, `"{a b}"` and JSON such as `{"k": 1}` all load and reach the command unchanged, and `${HOME}` is not expanded, because no shell runs unless the command names one.

Report flags are written out explicitly in `run`. Many test tools write no machine-readable report unless asked, so the command asks for one wherever the tool supports it. For example:

```yaml
run: [swift, test, --experimental-event-stream-output, "{report}", --experimental-event-stream-version, "0"]
run: [pytest, tests/, "--junitxml={report}"]
run: [./scripts/test-all, "{report}"]
```

A wrapper script may do the same. A tool that always writes to a fixed place needs one setting that points it at `{report}`, such as a build property the command passes. Whatever writes the report, it must land at `{report}`.

## 9. Transformer resolution

```text
name contains "/"   -> project-relative program path, resolved from the workspace root
otherwise           -> bundled transformer name
```

A program path must resolve inside the workspace. An unknown bundled name is INVALID.

A transformer is an executable program: a compiled binary, or a script with a `#!` line and its executable bit set. The core launches it directly and never chooses an interpreter, so a transformer may be written in any language. A program that cannot be launched is a transformer error that names the program.

Windows cannot run a `#!` script, so on Windows the core looks for `<program>.exe`, then `<program>.cmd`, then `<program>.bat`, then `<program>` itself, and runs a `.cmd` or `.bat` through `cmd.exe`. A transformer that supports Windows ships a launcher next to it; the bundled ones do. The same `transformer:` setting then works on every operating system.

## 10. Invocation

The core invokes a transformer as a separate process:

```text
<program> <job> <request.json> <response.json>
```

```text
job            links | results
request.json   written by the core, read by the transformer
response.json  written by the transformer, read by the core
```

Both files are UTF-8 JSON objects carrying:

```json
{"contract": 1}
```

The core writes both files in a private scratch location, never inside `.use-cases/`.

### How contract 1 evolves

Contract 1 is permanent. A transformer written against it keeps working with every later core, and the reverse:

```text
within contract 1   either side may gain optional fields
                    a receiver ignores every field it does not know
                    no field is removed, made required, or given a new meaning
anything else       contract 2: the core sends it only to a transformer that asks for it,
                    and keeps speaking contract 1 to every other transformer
```

So a transformer never validates a request strictly, and the core ignores unknown response fields. The schemas describe what this version sends; they are closed so a test can check exactly that.

A transformer runs in the workspace root, so the same request gives the same answer wherever the command was started, and has 120 seconds to answer. Bundled transformers follow exactly the same contract and have no special access.

## 11. Links job

Request:

```json
{
  "contract": 1,
  "job": "links",
  "use_cases": [ ...resolved use cases... ],
  "code_root": "<absolute workspace root>",
  "ignore": [ "use-cases.yml", "use-cases-bridge.yml", "use-cases/login.yml" ],
  "settings": {}
}
```

In both jobs, `use_cases` holds every resolved use case whole, in its definition shape (chapter 02), drafts included; a use case's route ids are at `validation[].id`. `ignore` lists the workspace's own Use Cases files, sorted by path, so a links transformer can leave them out of what it reads.

Response:

```json
{
  "contract": 1,
  "links": [
    {
      "use_case": "shop.login.authenticate",
      "route": "unit-tests",
      "binding": "valid-credentials",
      "role": "validation",
      "file": "Tests/AuthTests/LoginTests.swift",
      "range": { "start": 6, "end": 8 }
    }
  ],
  "diagnostics": []
}
```

```text
use_case   1      resolved use-case ID
route      0..1   present for validation links, absent for implementation links
binding    1      segment grammar
role       1      implementation | validation
file       1      workspace-relative path
range      0..1   1-based inclusive line range; absent = whole file
```

Rules:

- read-only: never modifies the workspace;
- deterministic: the same input gives the same output;
- fast: it runs whenever the model is loaded (chapter 09);
- a name it finds for an unknown use case or route is a diagnostic, not a link;
- links name lines; the core turns them into exact bytes (chapter 11) and transformers never see byte offsets.

The core trusts a links transformer for nothing. Every returned link must name a known use case, a known route for a validation link and none for an implementation link, an existing file inside the workspace and outside every excluded folder (chapter 04), and a range inside that file. Any other link is a transformer error, and the workspace cannot be loaded until it is fixed. A binding claimed by two sources (a marker and a transformer, say) is INVALID (chapter 08).

## 12. Link keys

The core assigns every link a key:

```text
<use_case>#[<route>.]<binding>@<file>:<start>
```

Example:

```text
shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6
```

Keys are assigned by the core, never by transformers. A results job addresses results by key.

`<file>` is the link's workspace path exactly as spelled on disk, spaces, `@`, `:` and non-ASCII characters included. A key is split at its first `@` and its last `:`, which the grammar makes unambiguous. Keys are opaque to transformers: they receive keys and echo them back, and never build or parse them.

## 13. Results job

Request:

```json
{
  "contract": 1,
  "job": "results",
  "use_cases": [ ...resolved use cases... ],
  "links": [ { "...": "...", "key": "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6" } ],
  "output": { "report_path": "<absolute report path>", "exit_code": 1, "working_dir": "." },
  "code_root": "<absolute workspace root>",
  "settings": {}
}
```

```text
output.report_path   the report, file or folder, where the tests wrote it inside the run. Read it, never change it
                     and never look around it: the core seals the bytes as read, and a report that changes
                     while it is read gives no results. Its location means nothing
output.exit_code     the run command's exit code, or null when the core does not know it
output.working_dir   the validation's working_dir, relative to code_root; "." for the project root
```

Each link carries `key`, `source`, `use_case`, `route` (validation links only), `binding`, `role`, `file` and `range` (whole-file links run from line 1 to the last line holding any bytes; an empty file is 1 to 1, chapter 08): lines, never bytes.

Response:

```json
{
  "contract": 1,
  "results": [
    {
      "link": "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6",
      "status": "pass",
      "tests": ["AuthTests.LoginTests/validCredentialsAuthenticate()"]
    }
  ],
  "unlinked": [
    { "test": "AuthTests.LoginTests/notTiedToAnyUseCase()", "file": "Tests/AuthTests/LoginTests.swift", "line": 35, "status": "pass" }
  ],
  "diagnostics": []
}
```

```text
results[].link       1      a core-assigned key from the request
results[].status     1      pass | fail | error | incomplete
results[].tests      0..1   opaque test IDs
results[].message    0..1   string
unlinked             0..N   tests inside no link: { test, file, line, status }; file and line may be null
diagnostics          0..N   strings, for people; never verdicts
```

There is no report time. The core never asks when a report was written; the start point makes that question unnecessary (chapter 13).

The four statuses mean the same thing from every transformer, and they are the only four, forever:

| Status | The test... |
|---|---|
| `pass` | ran, and its final attempt passed. A test retried until it passed is a `pass`; each retry of a test counts by its final attempt |
| `fail` | ran, and its final attempt failed |
| `error` | could not be judged: the test itself broke, not the behaviour |
| `incomplete` | did not show the behaviour works: skipped for any reason, an expected failure (xfail, known issue), pending, or undefined |

Use cases record that a behaviour is validated, not how. Why a test was skipped, how many attempts it took and how long it ran stay in the test tool's report, which the run keeps byte-exact in its `reports/` folder. A transformer may put a short note for people in `message`; it never changes which of the four a test is.

Rules:

- one result per validation link it can speak for, never a verdict per route;
- when several tests fall inside one link, report the worst: fail > error > incomplete > pass;
- a test inside no link goes in `unlinked`;
- deterministic: the same input gives the same output;
- never runs anything and never writes `.use-cases/`;
- a relative path inside the report usually starts at `output.working_dir`; a transformer resolves it there unless its settings say otherwise.

## 14. Transformer errors

Any of these is a transformer error:

```text
the program cannot be launched
no answer within 120 seconds
non-zero exit
missing or malformed response.json
missing or unsupported "contract"
a result naming anything but a validation-link key from the request
a status outside pass | fail | error | incomplete
a links-job link the core cannot place (section 11)
```

A results-job error is a run-level error (chapter 12). No route receives a verdict from that transformer's source. It never makes a route `failed`. A links-job error stops the model from loading, because the link set it would produce is unknown.

Results from other validations in the same run are unaffected.

## 15. Determinism and trust

Transformers are trusted local programs, like test tools. The core does not sandbox them.

The core never relies on a transformer to apply judgement. "Did every validation link get a result?", "worst wins", staleness, and every no-verdict reason are applied by the core (chapter 07, chapter 13).

## 16. Bundled transformers

The core and this contract know no language, test framework or build tool. Support for a particular tool lives entirely in a transformer.

Use Cases may ship ready-made transformers for common tools. They follow exactly this contract and have no special access. Each one is documented on its own in the transformer catalogue (`docs/transformers/`), including the tool behaviour it depends on.

The current list is in the catalogue's README.

A repository can use a bundled transformer, write its own, or use none.

## 17. Relationship to use cases

```text
use-case YAML                         use-cases-bridge.yml
─────────────                         ────────────────────
behaviour, scenarios, routes          run commands
route kinds, coverage, gating         report names
manual procedures                     transformers
optional links (bindings, resources)  transformer settings
```

Nothing crosses in either direction. Moving to another test tool changes only the bridge settings.

## 18. Diagnostics

Invalid:

- malformed YAML, unknown fields, duplicate keys
- unsupported `schema_version`
- a bridge file outside the root
- duplicate or malformed validation IDs
- a `report` that is a path, or not a portable name (section 7)
- a validation id Windows reserves for a device
- a `working_dir` that is missing, escapes the workspace, or is `.use-cases/` or inside it
- an empty or non-string `run`
- an unknown bundled transformer name, or a program path outside the workspace

Warnings:

- `validations: []`
- a validation with no `run` (it can only be read after `verify --start`)

## 19. Final model

```text
           use-cases-bridge.yml
            /               \
      links[]            validations[]
         |                /        \
  links job          run (--run)   report
         |                \        /
         v                 v      v
   extra links         results job
         \                  |
          \                 v
           +-----> core judges (chapter 07)
```
