# ADR 025: Hooks are opt-in and per clone; init asks in a terminal

## Status

Accepted - 2026-09-28

## Context

Git hooks can run a Use Cases check at commit or push, so nobody has to remember it. The owner set the terms: "we're designing hooks people can OPT IN to but its not on by default", added through a `hooks` command or by `init`, which could itself be "a wizard style interactive by default (with a possible non-interactive arg)".

Where a hook lives decides who it affects. A shared, committed hooks folder reaches everyone but takes over the repository's hooks and breaks hook managers (husky, lefthook, pre-commit). Writing into a hook manager's configuration is tool-specific guessing, which init has already ruled out (ADR 024).

## Decision

- **Two hooks, both opt-in:** `commit` runs `use-cases validate` (pre-commit); `push` runs `use-cases status --gate` (pre-push). Nothing is added unless someone asks.
- **`use-cases hooks`** lists them; `hooks add` and `hooks remove` change them, at any time.
- **Per clone:** a hook is a small script in this clone's git hooks folder. It is not committed and changes no git configuration.
- **Never passes without checking:** the hook runs `use-cases` from the PATH, or else the `use-cases` that added it (its full path remembered); if neither is there it stops, saying why and how to go on. Use Cases recognises its own hook whichever `use-cases` added it.
- **Never overwrites:** a different hook file, or a hook manager (`core.hooksPath`), is left alone; Use Cases prints the one line to add and exits 1. `remove` takes out only the exact file it wrote.
- **`init` asks in a terminal:** full or minimal, a root prefix, and which hooks, each skipped when a flag (`--minimal`, `--prefix`, `--hooks`) already answered it. `--no-input` asks nothing; outside a terminal it asks nothing and never waits. Every default adds no hooks.
- Asking stays opt-in for `record` (`--interactive`). `init` is the exception: it runs once, by a person.

## Consequences

- Good: the checks are one command away, and nobody gets a hook they did not choose.
- Good: no repository's existing hooks or hook manager are ever disturbed.
- Good: `init` guides a person through its choices, and scripts and agents are never stuck at a prompt.
- Cost: hooks are not shared: each person adds them on their own clone. A team that wants them everywhere adds the printed line to its hook manager.
- Cost: `init` and `record` differ in whether they ask by default; the chapters say why.
- Cost: the push hook reads stored verdicts, so it blocks a push whose use cases are stale until they are verified again.

## Considered Options

- **Hooks on by default:** always-on checks, but the owner ruled them out: people disable hooks they did not choose.
- **A committed, shared hooks folder:** reaches everyone, but takes over every hook and breaks hook managers.
- **Writing into husky, lefthook or pre-commit:** fits their users, but guesses at the codebase's tooling.
- **A non-interactive `init` with flags only:** simplest, but less helpful to the person running it once.

## Confirmation

- `test_hooks.py`: nothing without asking, add and remove, per clone and never committed, another hook or a hook manager left alone, an edited hook no longer removed, not a git repository, a workspace in a subfolder, a real commit stopped by an invalid workspace, a real push stopped by a blocked gate, and init's wizard in a real terminal (its answers, its defaults, and flags answering in advance).

## Related Links

- `docs/design/18-hooks.md`, `docs/design/17-init.md`
- ADR 022 (the command line), ADR 024 (init)
