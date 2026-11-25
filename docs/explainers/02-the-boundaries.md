# 2 · The boundaries

**Four boundaries. Data moves one way.**

Use cases and your code never know about each other. The core is the only thing that judges, and the only thing that writes results. Verdicts reach it two ways: recorded by a person or agent, or from test reports through the optional extras.

```text
                                     ┌─ RECORD · ALWAYS THERE ────────┐
                                     │ no extras needed               │
                                     │                                │
                                     │ A person or agent records a    │
                                     │ verdict for one route.         │
                                     │   use-cases record <use case>  │
                                     │   <route> pass                 │
                                     └────────────────────────────────┘
                                                      │
                                                      │  a verdict per route
                                                      ▼
┌─ 1 · USE CASES ────────────┐       ┌─ CORE ─────────────────────────┐       ┌─ 4 · RESULTS STORE ────────┐
│ What it does, its          │       │ Judges and records             │       │ .use-cases/runs/           │
│ scenarios, and which kind  │       │                                │       │ Sealed runs of evidence:   │
│ of check proves it.        │       │ · Reads the use cases          │       │ the core's verdicts, with  │
│ No files, commands or      │       │ · Understands links: markers   │       │ the reports they came      │
│ tools.                     │       │   and manual bindings          │       │ from.                      │
└────────────────────────────┘       │ · Judges every result by one   │       └────────────────────────────┘
                                     │   set of rules                 │
┌─ 2 · YOUR CODE ────────────┐ ────▶ │ · Stamps each result with the  │ ────▶ ┌─ STATUS ───────────────────┐
│ Sources, tests, fixtures.  │       │   code it describes            │       │ verified · stale ·         │
│ Runs exactly as normal.    │       │ · The only writer of results   │       │ unverified · incomplete ·  │
│                            │       │                                │       │ error · failed             │
│ The glue (optional): a //  │       │                                │       └────────────────────────────┘
│ @use-case:… marker, or a   │       │                                │
│ file/line binding in the   │       │                                │
│ YAML                       │       │                                │
└────────────────────────────┘       └────────────────────────────────┘
                                          │                      ▲
                                          │ use cases   a result │
                                          │ + links     per link │
                                          ▼ + report             │
                              ╭┄ 3 · OPTIONAL EXTRAS ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮
                              ┆ Transformers turn a test tool's report into  ┆
                              ┆ a result per link. Run commands start the    ┆
                              ┆ tests for --run.                             ┆
                              ┆ [links] [results] [run]                      ┆
                              ┆                                              ┆
                              ┆ ┌─ BUILT-IN TRANSFORMERS ──────────────────┐ ┆
                              ┆ │ or write your own                        │ ┆
                              ┆ │                                          │ ┆
                              ┆ │ junit · go-test-json · cargo-test ·      │ ┆
                              ┆ │ swift-testing · swift-test ·             │ ┆
                              ┆ │ cucumber-messages · exit-code ·          │ ┆
                              ┆ │ test-names                               │ ┆
                              ┆ │                                          │ ┆
                              ┆ │ junit covers pytest, node --test, CTest, │ ┆
                              ┆ │ Maven and Gradle. test-names finds       │ ┆
                              ┆ │ links; the rest read reports.            │ ┆
                              ┆ └──────────────────────────────────────────┘ ┆
                              ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
```

| Shape | Means |
|---|---|
| solid box | Core, always there; or your code, untouched apart from optional markers |
| dashed box `╭┄╮` | Optional extra, plug in for more |

---

Source: slide 2 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
