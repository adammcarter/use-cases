# 3 · Core and optional extras

**Core stands alone. Extras help.**

> "Use cases at its core is completely isolated. Markers in sources and code are optional."

```text
┌─ CORE ─────────────────────────────────┐   ╭┄ OPTIONAL EXTRAS ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮
│ Works alone. Needs nothing else.       │   ┆ Plug in for more value. Use ours, or write your own. ┆
│                                        │   ┆                                                      ┆
│ use case files                         │   ┆ ╭┄ Transformer · links ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮ ┆
│   What it does, and how it's proved    │   ┆ ┆ Links the core can't find itself, for example    ┆ ┆
│ links                                  │   ┆ ┆ from a naming convention.                        ┆ ┆
│   Optional: markers in code, or        │   ┆ ┆ Ours: test-names (tests named after their use    ┆ ┆
│   file/line bindings in the YAML       │   ┆ ┆ cases)                                           ┆ ┆
│ record                                 │   ┆ ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯ ┆
│   A person or agent records a verdict  │   ┆ ╭┄ Transformer · results ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮ ┆
│ status                                 │   ┆ ┆ A test tool's report becomes a result per link.  ┆ ┆
│   Verified, stale, unverified,         │   ┆ ┆ Ours: junit (5 tools), go-test-json, cargo-test, ┆ ┆
│   incomplete, error, failed            │   ┆ ┆ swift-test, swift-testing, cucumber-messages,    ┆ ┆
│ results store                          │   ┆ ┆ exit-code                                        ┆ ┆
│   Evidence: verdicts written by the    │   ┆ ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯ ┆
│   core only, kept with their reports   │   ┆ ╭┄ Run command ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮ ┆
│                                        │   ┆ ┆ What use-cases verify --run starts, in its own   ┆ ┆
│ With core alone you can:               │   ┆ ┆ working folder.                                  ┆ ┆
│ write use cases → link your code       │   ┆ ┆ Settings only — no code to write                 ┆ ┆
│ (optional) → record verdicts → see     │   ┆ ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯ ┆
│ status + freshness                     │   ┆                                                      ┆
└────────────────────────────────────────┘   ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
```

> **The one rule.** Extras can only hand the core links or results. The honesty rules — didn't run, worst wins, stale — live in the core, so no extra can weaken them.

Links are optional: markers in the code, or manual bindings and resources in the use case YAML.

---

Source: slide 3 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
