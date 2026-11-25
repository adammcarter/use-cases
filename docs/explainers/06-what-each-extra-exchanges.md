# 6 · What each extra exchanges

**What each extra gets, and gives back.**

The detail behind the three plug-in points. Read across a row.

```text
┌──────────────────────┬────────────────────────────┬────────────────────────────┬────────────────────────────────┐
│ EXTRA                │ GETS                       │ GIVES BACK                 │ MUST                           │
├──────────────────────┼────────────────────────────┼────────────────────────────┼────────────────────────────────┤
│ 1 · Links            │ Use cases                  │ Links: use case, route,    │ Same input, same answer        │
│ transformer          │ A read-only path to your   │ file, lines                │ Read-only and fast             │
│ finds extra links    │ code                       │ { "file": "…Tests.swift",  │ Names lines, never bytes       │
│                      │ Its own settings           │   "range": { "start": 5,   │ The core checks every link it  │
│                      │                            │              "end": 7 } }  │ returns                        │
├──────────────────────┼────────────────────────────┼────────────────────────────┼────────────────────────────────┤
│ 2 · Results          │ Use cases                  │ One status per link        │ Only pass, fail, error,        │
│ transformer          │ Links, each with a key     │ { "link": "…",             │ incomplete                     │
│ reads a report       │ from the core              │   "status": "pass" }       │ A retry counts by its final    │
│                      │ The report, read in place  │ Tests inside no link       │ attempt                        │
│                      │ The exit code, or null     │ Notes for people           │ Skipped, pending or expected-  │
│                      │ The working folder         │                            │ to-fail: incomplete            │
│                      │ Its own settings           │                            │ A crash is a run error, never  │
│                      │                            │                            │ a failed use case              │
├──────────────────────┼────────────────────────────┼────────────────────────────┼────────────────────────────────┤
│ 3 · Run command      │ A {report} path in the     │ A report at {report}       │ Runs in your real project      │
│ starts the tests     │ run's own folder           │                            │ report is only a file name     │
│                      │ Its working folder         │                            │ On Windows, mvn finds mvn.cmd  │
└──────────────────────┴────────────────────────────┴────────────────────────────┴────────────────────────────────┘
```

| Every transformer | Contract 1 is permanent |
|---|---|
| Its own program, in any language: `program job request.json response.json`. One JSON file in, one out. It writes nothing else, and the core trusts it for nothing. | Either side may add optional fields; each ignores what it doesn't know. Transformers written today keep working. |

*Proven · 506 checks on macOS + Linux · 438 on Windows*

---

Source: slide 6 of the [Use Cases Bridge Contract canvas](https://claude.ai/artifact/TLbJK1GoogFUgZTCLX6YW6) (private until you share it from its Share menu).
