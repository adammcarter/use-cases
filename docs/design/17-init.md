# 17 — Init

**Phase:** 3 — Core Experience  
**Status:** Specification (locked)

## 1. Purpose

`use-cases init` sets up a repository: from nothing to a first `use-cases status` in one command. It writes base files only. It never writes a test command or anything else specific to the codebase: that is yours to fill in.

```text
use-cases init              the workspace, a worked example, a groups example, a commented bridge
                            settings template, and .use-cases/ in .gitignore
use-cases init --minimal    the workspace file alone (and .use-cases/ in .gitignore)
use-cases init --prefix P   either of the above, with a root prefix (chapter 04)
use-cases init --hooks H    also add git hooks: commit, push, or commit,push (chapter 18)
use-cases init --no-input   ask nothing: flags and defaults decide
use-cases init --dry-run    what it would create; writes nothing (chapter 16 §17)
```

In a terminal, `init` asks what its flags did not already say:

```text
$ use-cases init
Full setup, or minimal? [full]
Root prefix? (blank for none)
Add hooks? commit / push / both / none [none]     (only in a git repository)
```

- Each flag answers its question in advance: `--minimal`, `--prefix`, `--hooks`.
- An existing workspace is asked only about hooks: its kind and prefix are already set. A `--prefix` that differs from its prefix is refused (exit 2), never dropped.
- Every refusal, a bad `--hooks` name included, comes before the first question.
- Outside a terminal (CI, a script, an agent, `--json`), it asks nothing, exactly as with `--no-input`, and never waits for input. Every default adds no hooks: hooks are opt-in (chapter 18).

## 2. What it creates

```text
                          init                               init --minimal
use-cases.yml             root: true                          root: true
use-cases/example.yml     a worked example use case, DRAFT     —
use-case-groups.yml       one example group                    —
use-cases-bridge.yml      a commented template: you add        —
                          your own test command
.gitignore                + .use-cases/ (section 6)            + .use-cases/ (section 6)
```

Every file it writes is valid: `use-cases validate` passes straight after, and the example never blocks a gate.

Then it lists what it did and suggests one next step:

```text
$ use-cases init
created  use-cases.yml
created  use-cases/example.yml      a DRAFT example: fill it in, or delete it
created  use-case-groups.yml
created  use-cases-bridge.yml       a commented template: add your own test command
added    .use-cases/ to .gitignore
→ use-cases status
```

## 3. It never overwrites

- A file that already exists is left exactly as it is and listed as `kept`.
- Run in a folder that is already the workspace root, it adds only what the workspace lacks: the bridge settings template when there are none, and the `.gitignore` line. It never adds the example or the groups file to an existing workspace, because they would change what `status` and the gate report.
- Run inside an existing workspace (a folder below a root), it refuses with exit 2: a second root there would split the workspace (chapter 04). The message names the root it found.
- A `use-cases.yml` here that is not a root (a child scope) is refused the same way.

Running it twice is therefore safe: the second run reports everything as kept.

## 4. The root prefix

`init` writes no root prefix. Use case ids then start at the file prefix (`example.getting-started`). The root `use-cases.yml` carries the option as a comment, and the discovery exclusions as a commented example:

```yaml
schema_version: 1
root: true
# prefix: shop    # optional: a namespace at the front of every use case id.
#                 # Choose it once: changing it later renames every use case.

# discovery:        # optional: folders never searched for use cases or markers,
#   exclude:        # such as build output, or test data that holds marker text as data.
#     - "build/**"
#     - "tests/fixtures/**"
```

The exclusions stay a comment with either form, an example only: which folders hold build output or test data is the codebase's to say (chapter 04), and `init` never fills it in.

`--prefix P` writes `prefix: P` instead, checked against the prefix grammar (chapter 05). Both forms of `init` give the same ids for the same files; they differ only in how much they scaffold.

## 5. Bridge settings: a template, never a command

`use-cases-bridge.yml` holds how `verify --run` runs the tests (chapter 10). `init` writes it as a commented template: valid, with no validations, and one commented example to copy. It never looks at the codebase to guess a test tool, and never fills in a command on anyone's behalf. The transformer catalogue documents each transformer and what its test tool needs.

```yaml
schema_version: 1
# validations:
#   - id: unit-tests
#     report: results.xml
#     run: [your, test, command, "--junit-output={report}"]
#     transformer: junit
```

## 6. `.gitignore`

The results store is generated and not committed (chapter 04). When the workspace root has a `.git` (a folder, or the file a worktree or submodule has) or a `.gitignore`, `init` adds a `.use-cases/` line to `.gitignore`, unless a line already excludes it (`.use-cases`, `.use-cases/`, `/.use-cases`, `/.use-cases/`). Otherwise it adds nothing and suggests excluding `.use-cases/` from whatever version control is in use; a workspace in a subfolder of a git repository gets that note too, naming git.

## 7. The example

`use-cases/example.yml` is a real use case with its own file prefix, left DRAFT on purpose: its `value_tier` is a comment. It teaches every part of the format, shows in `status` as `· draft example.getting-started`, and never blocks a gate. Filling in `value_tier` makes it READY; deleting the file removes it.

`use-case-groups.yml` holds one group, `smoke`, selecting the example (chapter 03), with a comment showing `use-cases status --group smoke --gate`.

## 8. Output and exit codes

The command line is chapter 16's. With `--json`:

```json
{
  "output_version": 1,
  "command": "init",
  "workspace": "/work/shop",
  "created": ["use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml"],
  "kept": [],
  "gitignore": "added",
  "hooks": [],
  "notes": [],
  "dry_run": false
}
```

- `gitignore` is `added`, `present` or `skipped`. `hooks` lists the hooks it added.
- Exit 0 when done; exit 1 when a requested hook was left alone or could not be added (chapter 18 §4); exit 2 when refused (section 3), when `--prefix` is not a valid prefix, or when the workspace as init would leave it is INVALID (architecture.md §2): init writes nothing in that case. A `use-cases.yml` below the folder that is not a scope, such as one in build output, makes it INVALID; the error names how to exclude its folder (chapter 09 §6.2), and the exclusion can be written in the root `use-cases.yml` before init runs.

## 9. Final model

```text
use-cases init [--minimal] [--prefix P]
        |
inside another workspace, or on a child scope?  ── yes ──▶ refused (exit 2)
        |
create what is missing; keep what exists
        |
base files only: the workspace, an example, a group, a bridge template
(never a test command: that is yours to fill in)
        |
.use-cases/ in .gitignore, when version control is there
        |
hooks, only when asked for (chapter 18)
        |
use-cases validate passes · → use-cases status
```
