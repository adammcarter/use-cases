# 7 · How the core judges

**How the core judges.**

Extras only report what happened. Every judgement lives in the core, so every extra is held to the same rules. (The file name is an example from a Swift project; the rules are the same for any language.)

```text
╭┄ EXTRA SAYS ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮
┆ LoginTests.swift line 6 passed               ┆
╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
          │
          ▼
┌─ WHICH LINK? ────────────────────────────────┐
│ valid-credentials, lines 5–7                 │
└──────────────────────────────────────────────┘
          │
          ▼
┌─ ALL HEARD? ─────────────────────────────────┐
│ Every validation link of the route needs a   │
│ result                                       │
└──────────────────────────────────────────────┘
          │
          ▼
┌─ WORST WINS ─────────────────────────────────┐
│ The route takes its worst result             │
└──────────────────────────────────────────────┘
          │
          ▼
┌─ USE CASE ───────────────────────────────────┐
│ Worst of its gating checks                   │
└──────────────────────────────────────────────┘
```

| What happened | What the core says |
|---|---|
| Every validation link got results, and all passed | **verified** |
| Any result failed | **failed** — *decided: even if another link didn't run* |
| A validation link got no result | **no verdict** — "its test didn't run", never a pass |
| A test was skipped, pending, or an expected failure | **incomplete** |
| A test passed only on a retry | **verified** — *decided: the test tool keeps the how and why* |
| A test sits inside no link | Reported as "test not tied to a use case" |
| Linked code or the use case changed between start and finish | **no verdict** — "code changed during the run" |
| Linked code, a linked test, a resource or the intent changed later | **stale** |
| Only the title, or only line endings, changed; or code moved without changing | **still verified** |
| The build broke, or an extra broke | Run error — no use case is marked failed |

```text
BEST TO WORST
┌──────────┬──────────┬────────────┬────────────┬──────────┬──────────┐
│ verified │  stale   │ unverified │ incomplete │  error   │  failed  │
└──────────┴──────────┴────────────┴────────────┴──────────┴──────────┘
```

*Proven · 506 checks on macOS + Linux · 438 on Windows*

---

Source: slide 7 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
