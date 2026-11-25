# 1 · Core, helpers, codebase

**One codebase. Two parts that stand alone, one optional helper.**

Use cases, helper settings and your code are all files in your repository, committed together. Inside it, your use cases and your code never depend on each other; the helpers are optional.

```text
╔═ YOUR CODEBASE · ONE GIT REPOSITORY ═══ shipped and committed together ══════════════════════════════════════════╗
║                    ┄┄ links (optional): markers in code, or file/line bindings in the YAML ┄┄                    ║
║                                                                                                                  ║
║ ┌─ USE CASES CORE ─────────────┐            ╭┄ HELPERS · OPTIONAL ┄┄┄┄┄┄┄╮            ┌─ YOUR CODE ────────────┐ ║
║ │ The behaviour contract       │            ┆ The bridge                 ┆            │ Code and tests         │ ║
║ │                              │            ┆                            ┆            │                        │ ║
║ │ · use case files: behaviour, │            ┆ [use-cases-bridge.yml]     ┆            │ · sources, tests,      │ ║
║ │   and how it's proved        │            ┆ [run commands]             ┆            │   fixtures             │ ║
║ │ · record a verdict by hand   │            ┆ [transformers]             ┆            │ · your own test tools, │ ║
║ │   or by agent                │  results   ┆                            ┆    test    │   run as normal        │ ║
║ │ · judge every result by one  │  per link  ┆ Runs your tests as normal, ┆  reports   │ · any language, any    │ ║
║ │   set of rules               │◀┄┄┄┄┄┄┄┄┄  ┆ reads their reports, and   ┆◀┄┄┄┄┄┄┄┄┄  │   size                 │ ║
║ │ · status and freshness       │            ┆ hands the core one result  ┆            │                        │ ║
║ │ · the results store:         │            ┆ per link. Any language,    ┆            │ Untouched, apart from  │ ║
║ │   verdicts written by the    │            ┆ any tool.                  ┆            │ optional markers       │ ║
║ │   core only                  │            ┆                            ┆            │                        │ ║
║ │                              │            ┆ Knows both sides; neither  ┆            │                        │ ║
║ │ Knows nothing about tools or │            ┆ side needs it              ┆            │                        │ ║
║ │ commands                     │            ┆                            ┆            │                        │ ║
║ └──────────────────────────────┘            ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯            └────────────────────────┘ ║
║                                                                                                                  ║
║ Committed: use case files, use-cases.yml, use-cases-bridge.yml, markers, your code.                              ║
║ Generated locally, not committed: the results store .use-cases/.                                                 ║
╚══════════════════════════════════════════════════════════════════════════════════════════════════════════════════╝
```

| Core alone | + links | + helpers |
|---|---|---|
| Write use cases, record verdicts by hand or by agent, see status. | Markers or manual bindings tie use cases to code. Edit linked code and the use case goes stale. | Verdicts come from your test runs automatically. Remove them and both sides still work. |

> **Nothing depends on the helper.** Helpers hand results to the core. Links connect code and use cases, in either direction. The core needs neither, and your code never needs Use Cases. All of it lives, and ships, in one repository.

---

Source: slide 1 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
