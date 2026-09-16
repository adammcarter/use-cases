---
name: init
description: Use once in a repo that has decided to be use-case driven — runs uc init to scaffold the matrix, record the decision in AGENTS.md, vend a sample row and wire the git hooks, then hands straight over to the use-case-driven-development loop.
---

# Init

One command takes a repo from nothing to inside the loop. Run it from the repo
root:

```sh
uc init --repo .
```

`uc init` writes, in one go:

- `use-cases.yml` and `use-cases/example.yml` — the workspace and a worked
  sample row (golden, bad and edge scenarios, every field explained). Copy the
  sample for the first real row, then delete it.
- `AGENTS.md` — the `## Use-case driven development` section with `yes` and
  today's date, a signpost to this plugin's skills, and the instruction that
  agents follow them. An existing file is appended to, never rewritten.
- `.githooks/pre-commit` and `.githooks/pre-push`, with `core.hooksPath`
  pointing at them. pre-commit blocks on an invalid matrix, ledger or marker;
  pre-push only reports. A repo that already routes hooks elsewhere keeps its
  directory and its scripts; the use-cases block is appended.

Then read `AGENTS.md` back and confirm the section is there, and add
`.githooks/` and `AGENTS.md` to the same commit as the scaffold — the record
lands with the work.

## Already initialised

If `uc init` is blocked because `use-cases.yml` already exists, nothing needs
scaffolding. Read the recorded answer in `AGENTS.md` (a `no` is as binding as a
`yes`) and go straight to the loop.

## Hand-off

Now load and follow the `use-case-driven-development` skill
(`/use-cases:use-case-driven-development`): it is FRAME's first move on this
repo from here on.
