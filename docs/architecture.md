# Command architecture: capabilities, composed

This is how the code behind `use-cases` is built, not what it does: the chapters define behaviour. It is the core of the code, because it is what keeps the command line maintainable as commands and options grow.

## 1. Capabilities, not a dispatcher

Each command is a composition of small capabilities. A capability gives every command that has it the same behaviour, written once:

| Capability | Gives a command | Used by |
|---|---|---|
| `Command` | `run` → one document | every command |
| `ReadsWorkspace` | the workspace root: walk up to `root: true`, or `--workspace` (chapter 16 §3) | all but `init` and `--version` |
| `WritesFiles` | `plan` → a list of file changes; one shared writer checks and applies it | `save`, `remove`, `init`, `hooks add/remove` |
| `DryRunnable` | `--dry-run`: check the plan, never apply it | everything with `WritesFiles`, and `prune` |
| `RendersJSON` | `--json`: one document following its published schema | every command |
| `RendersHuman` | people-first output and one `→` hint | every command |
| `Refuses` | a refusal becomes exit 2 with `error.kind` | every command |

```text
save          =  Command + ReadsWorkspace + WritesFiles + DryRunnable + RendersJSON + RendersHuman + Refuses
status        =  Command + ReadsWorkspace + RendersJSON + RendersHuman + Refuses
prune         =  Command + ReadsWorkspace + DryRunnable + RendersJSON + RendersHuman + Refuses
```

`prune` is the one command that deletes from `.use-cases/`; it plans from one read of the store and removes whole run folders under each run's lock (chapter 12 §31), never through the file writer, whose plans are for files people own.

A new command is a new composition; a new cross-cutting option is a new capability that every command adopting it gets unchanged.

## 2. Plan, then write

A command that changes files never writes as it goes. It builds a **plan**: every file it would create, replace or delete, with the new content. One shared writer checks the plan and applies it:

```text
command.plan ──▶ Writer.check ──▶ Writer.apply            (--dry-run stops before apply)
                  │                 │
                  │                 every file staged beside its target first, then each swapped in by
                  │                 rename; a failure part way undoes the renames already done
                  the workspace as it would be after the plan, seen through a view (the real files with the
                  plan's contents laid over them), loaded as every command loads it; INVALID → refused,
                  nothing written
```

- `--dry-run` is "stop before applying", so a preview can never differ from the real run.
- Checking and writing live in the writer, once, for every command.
- The check never copies the workspace and never writes anywhere: a links transformer runs in the real folder, as `validate` runs it, and is sent the use cases as the plan leaves them.
- A refused plan writes nothing, and a plan that fails part way is undone: no file is ever left half changed. A replaced file keeps its permissions.
- Two edits at once never lose one: at write time, under a lock, every file the plan replaces or deletes must still be exactly what was read when planning (and a file it creates must still not exist). Otherwise the plan is refused, "changed since it was read; run it again", and nothing is written.

## 3. Sensible defaults, limited options, our structure enforced

- **Defaults do the right thing.** A command with no options follows the recommended structure (chapter 04) and updates existing files wherever it can.
- **Options are opt-in and few.** An option exists only where a real choice exists, and it can only choose among outcomes that fit the recommended structure. It never opens a way to a layout the design does not recommend.
- **Existing first, new only when needed.** Commands update the file that already holds a thing, and create a new file only when nothing fits yet, at the path and with the prefix the recommended structure gives (chapter 04).

## 4. Stateless

No process keeps state between calls. State lives in files: the repository's authored files and the `.use-cases/` store. The MCP server is a thin wrapper that runs one command per tool call (chapter 20).

## 5. In Swift

The capabilities are protocols composed by each command, with their shared behaviour in protocol extensions. `UseCasesCLI` holds the commands and the runner that builds the command line from them; the plan, its check and the one writer are in `UseCasesCore` (`WritePlan`, `PlanViewing`, `PlanWriting`). How the package is split into modules is ADR 038.

## 6. Choices of the Swift build

Choices of the build, not of the design: each keeps the behaviour exactly as the chapters say.

| Choice | Why |
|---|---|
| **YAML is read with Yams** (libyaml), pinned. Our own code adds what the design needs on top: the two-version check on plain values, duplicate keys, the comment rule, positions. | A YAML reader is large and libyaml is the standard one; it keeps per-value style, raw text and start positions, and refuses duplicate keys. |
| **Every JSON Schema check is our own checker**, Draft 2020-12 for exactly the keywords the published schemas use; a schema with a keyword it does not know is refused, never skipped. It reads copies of the schemas bundled with the build. Two tests stop drift: the copies match `docs/schemas/` byte for byte, and the samples of `docs/schemas/engine/validate.py` give the same verdicts. | Full control of the messages; the Swift libraries available either lag the standard or pull in a large dependency and still need their messages rewritten. |
| **SHA-256 comes from swift-crypto**, pinned. | Apple's package: CryptoKit on macOS, BoringSSL on Linux, one answer on both; checked against the published test digests. |
| **The bundled transformers are one program, `use-cases-transformers`**, shipped beside `use-cases`. A bundled name in the bridge settings is that program in the folder of the running `use-cases`, found by its real path, run with the transformer's name first: `use-cases-transformers <name> <job> <request> <response>`. Any other transformer is the project's own program (chapter 10 §9). | Installing needs no other language runtime, so every system runs the same programs; each is still a separate program with no special access (chapter 10 §16). |
| **Commands and transformers start in a session and process group of their own**, with every signal at its default, stdin closed and no inherited descriptors; their output goes to a file, not a pipe. Linux needs glibc 2.34 or later. | Stopping a run stops everything it started, and a test that leaves a background process behind cannot hang the run. |
| **The `docs` guides are bundled from `docs/guides/`**, with a test that the bundled copies match byte for byte, as the schemas are. | One source for the guide text; the build cannot drift from it. |
| **Wording the suite pins is matched exactly.** | Chapter 16 §4 leaves human wording free, so matching the suite's phrases is allowed and keeps one acceptance suite. |
| **The package needs Swift 6.2**; CI builds it with the Swift of the macOS runner's Xcode and with the official `swift:6.4.2-noble` image on Linux. | Test names written as sentences need 6.2. |

**A designed command this build does not answer** gets one line on stderr, "use-cases <command> is not built yet", exit 3 and nothing on stdout, so nothing mistakes it for an answer; the help still lists every designed command (chapter 16 §2). Every command chapter 16 designs is built, so no command answers this way today.

## 7. How it is tested

- **Unit tests**, one test module per module (ADR 038), run with `swift test --package-path UseCases`.
- **The acceptance suite**, `UseCases/Acceptance/`, runs `use-cases` as a program, the way a person or a script does, in real projects in several languages (`fixtures/`). After every test it checks every `--json` document the build printed, every file it wrote to a results store, and every request and response it exchanged with a transformer against the published schemas (ADR 011). It is pointed at a build by two variables, and refuses to run without them:

```sh
BIN="$(swift build --package-path UseCases --show-bin-path)"
USE_CASES_UNDER_TEST="$BIN/use-cases" USE_CASES_TRANSFORMERS_UNDER_TEST="$BIN/use-cases-transformers" \
  uv run --python 3.12 --with pyyaml --with pytest --with 'jsonschema[format]' \
  pytest UseCases/Acceptance -q -p no:cacheprovider -rs
```

  The fixture projects need their own tools: Python, Node, Go, Rust, a JDK with Maven and Gradle, CMake and a C compiler (`UseCases/scripts/ci-linux-toolchains` installs them on Linux).
- **The schemas and the chapters' examples** are checked by `docs/schemas/engine/validate.py` (`uv run --with 'jsonschema[format]' --with pyyaml python docs/schemas/engine/validate.py`).
