# 01 — Core Foundation

## Core values

- Behaviour first
- Verifiable
- Traceable
- Agnostic
- Fast
- Scalable
- Honest

## Use cases stand alone

Use Cases is the human/agent-level behavioural contract above implementation and test code.

A use case says what the product does and how each behaviour is proved. It never names a command, a runner or a test tool.

```text
Use case
   |
   +-- behaviour     (intent, scenarios)
   +-- validation    (routes: kind of check, what it covers, gating, optional manual steps)
   +-- links         (optional: which code it depends on)
```

## The three rings

```text
 ┌ 3 HELPERS (optional) ─ result transformers · run commands · use-cases-bridge.yml ┐
 │  ┌ 2 LINKS (optional) ─ markers in code  OR  file/line bindings in the YAML ─┐  │
 │  │  ┌ 1 USE CASES CORE ─ use cases · record · judge · status · results ─┐    │  │
 │  │  └────────────────────────────────────────────────────────────────────┘    │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

Each ring works without the rings outside it.

| Rings in use | What you get |
|---|---|
| Core alone | Write use cases, record verdicts by hand or by agent, see status |
| + links | Freshness: editing linked code makes a use case stale |
| + helpers | Automatic verdicts from your test runs |

The rings show what each layer needs, not where files live. Use case files and `.use-cases/` sit in the repo folder but belong to the core.

## Ring 1 — the core

The core:

- reads the use cases
- understands both kinds of link (markers and manual bindings)
- records verdicts
- judges every result by one set of rules
- stamps each result with a fingerprint of what it describes
- derives status
- is the only writer of results in `.use-cases/runs/`; your tests only add their reports to an open run's `reports/` folder

The core assumes no particular actor, language, framework, architecture, test system, package system, or Git model.

## Ring 2 — links

Links connect a use case to repository reality. They are optional, and they work in either direction.

```text
 use case YAML ── manual binding: file + lines ──▶ code    (code stays untouched)
 code ── @use-case: marker ──▶ use case                     (no YAML entry needed)

 neither?  the core still works: write use cases, record verdicts, see status
```

Placement defines role:

```text
use case link             -> implementation
validation route link     -> validation for that route
```

- Implementation links feed freshness only.
- Validation links sit around the tests that prove a route. Each one expects a result when tests run.
- Resources (fixtures, schemas, golden files) belong to a route and feed freshness only.

Link details are defined in `08 — Links: markers and manual bindings`.

## Ring 3 — helpers

Helpers are optional and configured in one root file, `use-cases-bridge.yml`.

| Helper | Job |
|---|---|
| Transformer · links | Adds links the core cannot find itself |
| Transformer · results | Turns a test tool's report into one result per validation link |
| Run command | What `use-cases verify --run` starts: whatever command runs your tests |

Transformers never run tests and never write results. Helpers only hand the core links or results. The honesty rules live in the core, so no helper can weaken them.

Helpers are defined in `10 — Bridge settings + transformer contract`, `13 — Verify flow`, `14 — Run commands`.

## The four boundaries

Data moves one way. Use cases and code never need each other, and only the core judges and writes results.

The boundaries are numbered separately from the rings. Boundaries 1 (use cases) and 4 (results store) belong to ring 1. Boundary 2 is your code, reached through ring 2's links. Boundary 3 is ring 3, the helpers.

```text
 1 USE CASES ──────┐                                        ┌──▶ 4 RESULTS STORE
   behaviour, how  │                                        │      .use-cases/runs/
   it's proved     ├──▶ CORE ── use cases + links ──▶ 3 HELPERS
                   │    judges        + report          (optional)
 2 YOUR CODE ──────┘    and records ◀── a result per ──┘    │
   sources, tests,                      link                └──▶ STATUS
   fixtures (links optional)                                     verified · stale · unverified
                                                                 incomplete · error · failed
```

| Boundary | Knows about | Never touches |
|---|---|---|
| 1 Use cases | behaviour and how it's proved | commands, runners, test tools |
| 2 Your code | nothing, apart from optional marker comments | use case files, results |
| 3 Helpers | use cases, links, reports | results; a run command writes only its report, at the `{report}` path the core gives it |
| 4 Results store | verdicts written by the core only, beside the reports they came from | — |

## Core and optional extras

```text
 CORE — works alone, needs nothing else        OPTIONAL EXTRAS — plug in for more value
 ─────────────────────────────────────         ──────────────────────────────────────────
 use case files   what it does + how proved     transformer · links    more links, beyond
 links            markers or manual bindings                           markers and bindings
                  (optional, understood here)   transformer · results  a test tool's report →
 record           a person or agent records                            a result per link
                  a verdict                                            (bundled, or yours)
 status           verified / stale / failed …   run command            what `verify --run`
 results store    evidence, core writes it                             starts
```

The one rule: extras can only hand the core links or results. The honesty rules — didn't run, worst wins, stale — live in the core.

## Behaviour and validation are designed together

```text
Agree behaviour
      +
Agree how it will be validated
      |
      v
RED -> GREEN -> REFACTOR -> VERIFY
```

## Validation

```text
Type      = what kind of coverage
Procedure = optional plain-language steps anyone can perform
Result    = universal outcome
```

Type is classification only. A procedure does not encode who performs it: a human, agent, automation, or future actor.

Universal result outcomes:

```text
pass
fail
incomplete
error
```

Validation is defined in `06 — Validation Model`.

## Store results, derive state

Authoritative status is never authored.

```text
definitions
+ links
+ current content
+ results
      |
      v
 core judges
      |
      v
derived state
```

Generated runtime data belongs under the root `.use-cases/` directory.

## Actor agnosticism

```text
Humans      Automation      Agents
   \           |           /
    \          |          /
      Actor-agnostic core
```

Agent tooling may provide first-class MCP tools, skills, and workflows over the same core.

## Adoption

Partial adoption is valid, ring by ring and use case by use case.

Use Cases models higher-level observable behaviour, not every function or line in a repository.

The system must scale from tiny scripts to large mixed-language legacy repositories.
