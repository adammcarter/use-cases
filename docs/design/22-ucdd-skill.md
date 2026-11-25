# 22 — The Use-Case-Driven Development Skill

**Phase:** 4 — Agent Layer  
**Status:** Specification (locked)

## 1. Purpose

Chapter 21 says what an agent does with a person, use case first. This chapter says how it is packaged, so an agent in any repo actually does it: the plugin's skills, what each holds, and the check that ends every step of the flow.

## 2. What the plugin ships

```text
use-cases plugin
├─ setup            step 0, once per repo: asks, then the AGENTS.md block,
│                   the sign-off gate and the hooks, each only on a yes
├─ skill: use-case-driven-development
│                   the flow (chapter 21), one part per step, each with its check
├─ skill: adopting  bringing an existing repo in, one small area at a time
├─ skill: showcase  step 7, seeing it (chapter 23)
└─ the MCP server   the tools (chapter 20)
```

- **No file-structure skill.** `save` and `apply` already keep the recommended layout (chapter 04), so there is nothing for an agent to remember.
- **No global start-up text.** The skill applies where AGENTS.md says the repo works use-case first, and nowhere else.
- **No planning agents yet.** The skill drives the flow; dedicated agents can follow once it has been used for real.
- Each skill holds its name, what it is for, the agreed table below, and the steps an agent follows: what to ask the person and when, the commands and tools with their arguments, and what never to do.

## 3. Setup (step 0)

Asks four things, one at a time, and changes nothing the person has not said yes to:

| Asks | On yes |
|---|---|
| Work use-case first in this repo? | the fixed, marked, versioned block in AGENTS.md (chapter 21 §4) |
| Set up Use Cases here? (no workspace yet) | `use-cases init` (chapter 17) |
| Hold the gate for unapproved changes? | `sign_off: required` in the root `use-cases.yml` (chapter 21 §6) |
| Add the git hooks? | `use-cases hooks add` (chapter 18) |

Before the first question, setup checks that `use-cases` is on the PATH. If it is not, setup says so and offers the release download, which is the same release the plugin carries (ADR 039): the build for the person's platform from the project's releases page. The release writes the publishing account into the link in the skill it ships, and packaging fails if a placeholder is left. It installs nothing until the person says yes.

The plugin's tools work either way, because the plugin starts its own copy of the program. `init` and `hooks` are not tools (chapter 20 §3): setup runs them as commands, with the `use-cases` on the PATH, never the plugin's own copy, whose path a hook would remember (chapter 18) and which changes with every plugin version. If the person declines the install, setup skips questions 2 and 4 and says why.

**The AGENTS.md block** is this, exactly, between its two marker lines:

```markdown
<!-- use-cases:begin v1 -->
## Use Cases

This repository works use case first. Behaviour is agreed as use cases before tests and code are written, and each change is proven by the Use Cases commands. The use cases are YAML files in each scope's use cases folder: the use_cases_dir its use-cases.yml names, use-cases/ by default. Agents follow the use-case-driven-development skill of the Use Cases plugin. The tool's own guides are listed by: use-cases docs
<!-- use-cases:end v1 -->
```

- The markers carry the block's version, `vN`. Setup replaces a block between a `use-cases:begin vN` line and a `use-cases:end vN` line in place, whatever its `N`, and touches nothing outside it; the use-case-driven-development skill recognises the block whatever its `N`.
- The setup skill carries this text exactly.

## 4. Use-case-driven development: each step's check

The flow of chapter 21. A step ends when its check's output shows it is done, and the agent reports that output: it never claims a step on its own word.

| Step | The agent | The check: the command, and what it must show |
|---|---|---|
| 0 | confirms the repo works use-case first | AGENTS.md has the block; otherwise it offers setup |
| 2 Intent | asks only what is missing: what, why, who | `render intent` draws it; the person confirms it |
| 3 Discover | `search --like` each golden path, `show`, `links`, then reads the code as usual | what it found is in the brief, changed or untouched: nothing found is silently dropped |
| 4 Brief | writes the proposal file (the six fits) | `render brief` and `apply --dry-run` both succeed: every change is valid before the person sees it |
| 5 Sign-off | shows `render proposal`; the person chooses; it records their answer | `apply --approved-by NAME` succeeds, and `show` reads `approved` for each saved use case |
| 6 Red | writes the tests, marked | `links` shows the tests; `verify` shows the route **failed**: a real failure, never error (a build or run problem) |
| Can it fail? | where a test passes before the change, plants a defect | `verify` turns the route **failed**; the defect is then reverted |
| Green | writes the code, marked | `links` shows the code; `verify` shows **verified** |
| Refactor | reshapes the code, and moves its markers with any code it moves | `verify` still shows **verified**, with the same links, and `status` shows no empty marked region |
| 7 See it | the showcase skill | chapter 23 |
| 8 Prove | the CI recipe (chapter 19) | `status --gate` passes; `render results` is what the person sees |

For every step:

- **Ask with choices.** Where the host has a choice prompt (approve, change, talk it through), the agent uses it; otherwise it asks in plain words.
- **Plain words, ids last,** through the four layouts (chapter 21 §7).
- **The fast path and a change of no behaviour** take steps 2 and 3, choose their route after discover (chapter 21 §3), skip steps 4 and 5, and still meet the checks of step 6. A fast-path change to a critical use case is recorded on the person's yes, with `approve` and their name.

## 5. Adopting

Brings a repo that has code but no use cases in, starting small. It describes what the code does today, not what it should do; changing behaviour is a normal request afterwards.

```text
pick one small, well-tested area ──▶ describe it as use cases (every fit: new)
  ──▶ the person signs off ──▶ mark the existing tests and code ──▶ verify: verified
  ──▶ the next area, when the person chooses; partial adoption is valid
```

One area at a time, so the person is never asked to sign off a whole codebase at once. `approve --all` is for a repo that already has use cases and is turning the sign-off gate on.

## 6. What it proves

The skills are text, so their proof is that every check can be met, and that they name nothing that does not exist:

- **The whole flow on a real repo** (`test_flow.py`): a proposal drawn, signed off and applied; a marked test failing for real; a planted defect caught; the code marked and verified; a refactor still verified; the gate passing; the results drawn.
- **Every command and flag a skill names exists** (`test_docs.py`), as for the guides.

## 7. Final model

```text
setup        once per repo, asks first: AGENTS.md · init · sign-off gate · hooks
ucdd skill   the flow; every step ends on a command's output, never the agent's word
adopting     one small area at a time, as it is today
showcase     step 7, chapter 23
```
