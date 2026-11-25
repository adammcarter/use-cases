---
name: setup
description: Use once per repo, when the person wants it to work use case first. Asks four questions, one at a time, and changes nothing the person has not said yes to.
---

# Setup

Step 0 of working use case first. It runs once per repository. It asks four things, one at a time, and changes nothing the person has not said yes to.

| Asks | On yes |
|---|---|
| Work use-case first in this repo? | adds the fixed, marked, versioned block to AGENTS.md |
| Set up Use Cases here? (no workspace yet) | `use-cases init` |
| Hold the gate for unapproved changes? | `sign_off: required` in the root `use-cases.yml` |
| Add the git hooks? | `use-cases hooks add commit push` |

## Before the first question

Check that `use-cases` is on the PATH (`command -v use-cases`).

- If it is, carry on.
- If it is not, tell the person, and offer the release download: the build for their platform from `https://github.com/OWNER/use-cases/releases`, unpacked with `use-cases` linked into a folder on the PATH. Install nothing until they say yes.
- The plugin's own tools work either way: the plugin starts its own copy of the program. But questions 2 and 4 run `use-cases init` and `use-cases hooks`, which are commands, not tools: they need `use-cases` on the PATH. Never run them through the plugin's own copy: a hook remembers the program that added it, and that path changes with every plugin version.

## 1. Work use-case first in this repo?

Say what it means in two or three plain lines: behaviour is agreed as use cases before any test or code, each change is proven by commands, and the person signs off behaviour by reading use cases, never code.

On yes, add this block to `AGENTS.md` at the repository root (create the file if there is none), exactly as written:

```markdown
<!-- use-cases:begin v1 -->
## Use Cases

This repository works use case first. Behaviour is agreed as use cases before tests and code are written, and each change is proven by the Use Cases commands. The use cases are YAML files in each scope's use cases folder: the use_cases_dir its use-cases.yml names, use-cases/ by default. Agents follow the use-case-driven-development skill of the Use Cases plugin. The tool's own guides are listed by: use-cases docs
<!-- use-cases:end v1 -->
```

- If a block is already there, between a line `<!-- use-cases:begin vN -->` and a line `<!-- use-cases:end vN -->` (any version `N`), replace it in place with this one, and touch nothing outside it.
- Never edit anything else in `AGENTS.md`.
- On no, leave `AGENTS.md` alone and go on to the next question.

## 2. Set up Use Cases here?

Ask only when there is no workspace yet: `use-cases validate` says there is no `use-cases.yml` with `root: true` in this folder or above. Otherwise say it is already set up and skip to question 3.

This step needs `use-cases` on the PATH. If it is not there because the person declined the install, do not run it: say that setting up needs the `use-cases` command in their terminal, and go on to question 3.

On yes, ask two small things, one at a time, each with its default:

1. **Full or minimal?** Full (the default) adds a worked example, a groups file and a commented template for the test command. Minimal writes only `use-cases.yml`.
2. **A root prefix?** None by default. A prefix (such as `shop`) goes in front of every use case id. It is chosen once: changing it later renames every use case.

Then run one command, asking nothing more of it. Full, with no prefix (the defaults):

```text
use-cases init --no-input
```

Minimal, with the prefix `shop`:

```text
use-cases init --no-input --minimal --prefix shop
```

Add `--minimal` only for minimal, and `--prefix` only for a prefix. Show the person its output as it is. `init` never overwrites: a file already there is listed as `kept`.

`init` never writes the command that runs the tests, and neither do you on your own. `use-cases verify --run` needs one in `use-cases-bridge.yml`:

- After a full `init`, that file is there as a commented template: tell the person it needs their test command.
- After a minimal one, there is no such file yet: tell the person it is needed before `use-cases verify --run` can run anything.

If they want help, propose the lines, show them, and write them only on a yes (`use-cases docs verifying` describes the file).

## 3. Hold the gate for unapproved changes?

Explain it plainly: with it on, a use case whose promise changed and was not signed off holds the gate. A critical one blocks; core and supporting ones warn; a strict gate blocks all three. Drafts never block.

On yes, add one line to the root `use-cases.yml`, and check the file with `use-cases validate`:

```yaml
sign_off: required
```

If the repository already has use cases, check which are not approved as they read now: run `use-cases approve --all --by NAME --dry-run` and show the person what it prints. Each use case it lists as `would approve` is not approved yet; a critical one of those blocks the gate at once. It prints `nothing needs approval` when there is no use case. Offer the catch-up: the person reviews those use cases, and then, on their yes and with their name, `use-cases approve --all --by NAME`. Never approve with your own name.

## 4. Add the git hooks?

This step needs `use-cases` on the PATH, as question 2 does. If it is not there because the person declined the install, do not run it: say that the hooks run the `use-cases` command, so they need it installed, and skip this step.

Explain them: the commit hook runs `use-cases validate` before each commit (fast, no tests); the push hook runs `use-cases status --gate` before each push (no tests: it reads the verdicts already kept). They belong to this clone only and are never committed.

On yes, add the ones they chose. Both:

```text
use-cases hooks add commit push
```

Only the commit hook:

```text
use-cases hooks add commit
```

Only the push hook:

```text
use-cases hooks add push
```

If it exits 1, a hook file of another tool is there, or a hook manager owns the hooks. Nothing was overwritten: show the person the line it printed, for them to add where it says.

## When it is done

Report what changed, file by file, and what was left as it was. Then carry on with the use-case-driven-development skill.

## Never

- Never ask more than one question at a time, and never change anything before its yes.
- Never write a test command, approve a use case, or install anything without the person's yes.
- Never run a baseline `use-cases verify --run` unasked: verdicts are like test results, and a fresh checkout without any is normal.
- Never commit for the person, and never commit `.use-cases/`.
