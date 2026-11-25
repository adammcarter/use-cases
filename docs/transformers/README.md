# Transformer catalogue

Transformers are optional helpers (ring 3). Each one turns one test tool's report into one result per validation link, following the contract in chapter 10 (`../design/10-bridge-settings-and-transformers.md`).

The core knows no language, framework or build tool. Everything tool-specific lives in a transformer, and each transformer is documented here, on its own.

| Transformer | Tool | Job | State |
|---|---|---|---|
| [`junit`](junit.md) | any JUnit-XML writer: pytest, node --test, CTest, Maven Surefire, Gradle | results | built, proven on 5 tools |
| [`go-test-json`](go-test-json.md) | `go test -json` | results | built, proven |
| [`cargo-test`](cargo-test.md) | `cargo test` (console) | results | built, proven |
| [`swift-test`](swift-test.md) | Swift Testing + XCTest | results | built, proven |
| [`swift-testing`](swift-testing.md) | Swift Testing only | results | built, proven |
| [`cucumber-messages`](cucumber-messages.md) | Cucumber message stream (any Cucumber) | results | built, proven |
| [`exit-code`](exit-code.md) | any command: a script that is itself the check | results | built, proven |
| [`test-names`](test-names.md) | tests named after their use cases | links | built, proven |

The bundled transformers ship as one program, `use-cases-transformers`, which the core runs with the transformer's name first; a bridge file names them by that name alone. The results transformers are proven against realistic fixture repos in `fixtures/` by `UseCases/Acceptance/test_languages.py`; `exit-code` and `test-names` by `UseCases/Acceptance/test_helpers.py`. Every request the core sent and every response they returned in those suites is checked against the published contract schemas.

## Writing your own

A transformer is any executable program, in any language: a binary, or a script with a `#!` line and its executable bit set. The core launches it directly:

```text
<program> <job> <request.json> <response.json>
```

- It reads the request and writes the response, both as JSON with `"contract": 1`.
- It is deterministic, never runs tests, and never writes `.use-cases/`.
- It reports one result per validation link it can speak for. The core does all judging.
- It has 120 seconds to answer.
- It ignores request fields it does not know (ADR 015), and reports the four statuses with their fixed meanings (chapter 10 §13): a retried test by its final attempt, an expected failure or a skip as `incomplete`.
- To run on Windows, it ships a `<name>.cmd` (or `.exe`) launcher next to it, as the bundled ones do.
- Relative paths in a report usually start at `output.working_dir`, the folder the command ran in.
- It refuses a request whose `contract` it does not speak, with a non-zero exit. Only contract 1 exists; a later contract is sent only to a transformer that says it speaks it.

The bundled transformers share these rules:

- Globs are written from the workspace root with `/`: `*` and `?` match within one folder name, a `**` folder name matches any number of folders (none included), and `[` is an ordinary character.
- Reports are read as UTF-8; a byte that is not UTF-8 reads as U+FFFD where it stands and nothing else changes. JSON-lines streams split at line feeds only.
- When they search source for a declaration they never enter `.git`, `.use-cases`, `.build`, `.gradle` or `node_modules`, at any depth, nor `build` or `target` directly under the folder being searched. Every other folder is searched.
- A setting with a value they do not know is a settings error: the transformer exits non-zero and the run reports it.

Reference it from `use-cases-bridge.yml` by project-relative path, for example `transformer: tools/read-junit`.

Each entry here should record:
- which tool and report format it reads
- how a test is matched to a link
- which tool behaviour it relies on
- what it cannot see
