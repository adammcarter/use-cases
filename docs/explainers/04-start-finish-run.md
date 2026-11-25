# 4 · Start, finish, run

**Start, finish, or run. One pipeline.**

The only difference is who runs the tests. `--run` is `--start`, your run commands, then `--finish`: the same code, with the commands plugged in between.

```text
╭┄ HELPER · WRAPPER ┄┄┄ [use-cases verify --run] ┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮
┆ the same two core steps, with the bridge's run commands plugged in between                           ┆
┆                                                                                                      ┆
┆ ┌─ CORE COMMANDS ─── [use-cases verify --start] [use-cases verify --finish] ─── work on their own ─┐ ┆
┆ │                                                                                                  │ ┆
┆ │ ┌─ --start ──────────────┐      ╭┄ THE TESTS RUN ┄┄┄┄┄┄┄┄┄┄┄┄┄┄╮      ┌─ --finish ─────────────┐ │ ┆
┆ │ │ Note the code, give    │      ┆ Yours, anywhere: terminal,   ┆      │ Read the reports,      │ │ ┆
┆ │ │ the run its own report │      ┆ IDE, CI. Or, under --run,    ┆      │ judge, apply the       │ │ ┆
┆ │ │ folder, print the run  │ ───▶ ┆ each run command as normal.  ┆ ───▶ │ guard, seal the run    │ │ ┆
┆ │ │ id and each {report}   │      ┆ Either way, each writes its  ┆      │ with its reports       │ │ ┆
┆ │ │ path                   │      ┆ report to {report}.          ┆      │                        │ │ ┆
┆ │ └────────────────────────┘      ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯      └────────────────────────┘ │ ┆
┆ └──────────────────────────────────────────────────────────────────────────────────────────────────┘ ┆
╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
          │
          ▼  what --finish does, however the tests ran

┌─ Read the report ┐     ╭┄ Transformer ┄┄┄┄╮     ┌─ Core judges ────┐     ┌─ Results saved ──┐
│ from the run's   │     ┆ reads it in      ┆     │ one set of rules │     │ sealed with its  │
│ own folder       │ ──▶ ┆ place · a result ┆ ──▶ │                  │ ──▶ │ reports          │
└──────────────────┘     ┆ per link         ┆     └──────────────────┘     └──────────────────┘
                         ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯
```

| The one guard | Named, locked runs |
|---|---|
| **Code changed between start and finish? That use case gets no verdict.** | **Several runs can be open at once. Each is finished by its id.** |
| The same for tests the core runs and tests you run. Each run has its own report folder, so a report is always new and nothing is ever deleted. No timestamps decide anything, and no frozen copy: tests run in your real project. | `--finish --run-id` picks one; `--abort` closes a forgotten one. A run being finished is locked, and `--finish` refuses if the bridge settings changed since the start. It never takes a run `--run` opened. |

> **The accepted limit.** An edit made after the start point and undone before the finish point isn't seen: the guard compares two moments. That is the cost of testing in the real project instead of a frozen copy.

Plain `use-cases verify` runs nothing: it names the steps. `use-cases validate` checks your files and runs no test. Sharded CI is one run: one `--start`, every shard writes into the run's report folder, one `--finish`.

*Proven · 506 checks on macOS + Linux · 438 on Windows*

---

Source: slide 4 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
