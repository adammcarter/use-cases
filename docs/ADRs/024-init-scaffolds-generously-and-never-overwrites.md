# ADR 024: Init writes generous base files, never a codebase's commands, and never overwrites

## Status

Accepted - 2026-09-27

## Context

`use-cases init` is the first thing anyone runs. The owner asked for it to be "as helpful as possible": a clean init bootstraps template files with examples, and `--minimal` gives the bare minimum. They also set its limit: "we are writing base files but we are not filling in the specific codebase commands on behalf of users."

Generous scaffolding carries two risks:

- an example use case would show up in `status` and in the gate as if it were real work;
- a default root prefix, such as the folder name or `app`, becomes permanent: changing it later renames every use case and cuts it off from its evidence.

## Decision

- `init` writes base files: the root `use-cases.yml`, a worked example (`use-cases/example.yml`), an example group, a commented bridge settings template, and `.use-cases/` in `.gitignore` when version control is there. `init --minimal` writes the root file (and the `.gitignore` line) alone.
- **It never writes anything specific to the codebase.** It does not look for a test tool and never fills in a test command. The bridge settings are a valid, empty template with one commented example; the person adds their own command.
- **No root prefix by default**, in either form, so both give the same ids for the same files. The option is a comment in the root file; `--prefix` writes one.
- **The example is DRAFT on purpose** (its `value_tier` is a comment), so it teaches the whole format, shows in `status`, and never blocks a gate.
- **It never overwrites.** Existing files are kept. An existing workspace gains only the bridge template and the `.gitignore` line, never the example. Inside a workspace, or on a child scope, it refuses.
- Every file `init` writes passes `use-cases validate`.

## Consequences

- Good: from an empty folder to `status` in one command, with every part of the format shown by example.
- Good: nothing runs, and nothing is guessed about the codebase; the person decides how their tests run.
- Good: running `init` again, or in a half-set-up repository, is always safe.
- Cost: getting verdicts from tests needs one more step after `init`: writing the test command into `use-cases-bridge.yml`, with the transformer catalogue as the guide.

## Considered Options

- **Recognise the test tool and write its command:** saves a step, but writes codebase-specific commands on the person's behalf, which the owner ruled out.
- **A real, READY example:** more realistic, but it would count in the gate until someone deleted it.
- **`app` or the folder name as the default prefix:** placeholders stick, and a later change renames everything.

## Confirmation

- `test_init.py`: an empty folder, `--minimal`, the prefix rules, never overwriting, an existing workspace, refusals, `.gitignore`, and, in all nine fixture repos, a bridge template with no command and nothing for `verify --run` to run.

## Related Links

- `docs/design/17-init.md`
- ADR 022 (the command line)
