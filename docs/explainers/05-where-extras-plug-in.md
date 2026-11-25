# 5 · Where extras plug in

**Three places an extra can plug in.**

All optional. Each is a small program or a setting, in any language. The core works without any of them.

```text
┌─ YOUR CODE ──────┐      ╭┄ 1 · TRANSFORMER ┄┄┄┄┄┄┄┄┄┄╮                                      ┌─ CORE ───────┐
│ Sources and      │      ┆ Links                      ┆                links                 │              │
│ tests            │ ───▶ ┆ finds links the core can't ┆ ───────────────────────────────────▶ │              │
│ as they are      │      ┆ see itself, such as from   ┆                                      │              │
└──────────────────┘      ┆ test names                 ┆                                      │              │
                          ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯                                      │ Judges and   │
                                                                                              │ records      │
                                                                                              │              │
╭┄ 3 · RUN COMMAND ╮      ┌─ TEST REPORT ────┐      ╭┄ 2 · TRANSFORMER ╮                      │              │
┆ Start the tests  ┆      │ Written to       │      ┆ Results          ┆  a result per link   │              │
┆ only for --run;  ┆ ───▶ │ {report}         │ ───▶ ┆ reads the report ┆ ───────────────────▶ │              │
┆ a setting, no    ┆      │ in the run's own │      ┆                  ┆                      │              │
┆ code             ┆      │ folder           │      ╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯                      │              │
╰┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄╯      └──────────────────┘                                                └──────────────┘
```

| 1 · Links transformer | 2 · Results transformer | 3 · Run command |
|---|---|---|
| Rarely needed: markers and manual bindings already link code. | One per report format. Never runs anything. | Only for `--run`. With `--start` and `--finish`, you run the tests yourself. |
| *Ours: test-names* | *Ours: junit, go-test-json, cargo-test, swift-testing, swift-test, cucumber-messages, exit-code* | *A line in use-cases-bridge.yml* |

> **Manual checks** need no extra. A person or agent records the verdict straight against the route with `use-cases record`.

*Proven · 506 checks on macOS + Linux · 438 on Windows*

---

Source: slide 5 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
