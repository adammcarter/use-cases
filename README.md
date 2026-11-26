# A VIP entrance for agents and humans

Use Cases is an abstraction over a codebase in plain English.

Giving agents (and humans!) a VIP entrance into a codebase despite zero context or knowledge of where the code lives.

Behaviours map directly to the code that brings them to life, via tests, source code and even other resources like json files or anything else related to the behaviour.

```text
                 ┌────────────────────────────────────────────┐
                 │ checkout.discount                          │
                 │ "A valid code takes 10% off the basket;    │
                 │  an expired code is refused."              │
                 └─────────────────────┬──────────────────────┘
                                       │ linked
         ┌───────────────────┬─────────┴─────────┬───────────────────┐
         ▼                   ▼                   ▼                   ▼
       tests            source code          resources         anything else
  discount.test.ts      discount.ts          codes.json         a migration
   checkout.snap         basket.ts           prices.md         a config file

     change any of them ──▶ the use case is stale until it is proven again
```

## The problem

Repositories get complicated fast.

Agents write code hundreds of times faster than people, so a codebase can go from new to complex in a few hours.

Use Cases keeps an abstraction layer over the code, so you can understand it, manage it and keep track of changes as they happen.

Agents changing code and running tests can leave blind spots with no humans in the loop, unintentionally breaking other parts of the software/app being developed or falling foul to ‘unit tests pass so it’s fine’.

- **Find the behaviour, then the code.** Pick a use case and follow it to the tests and source that back it. You need no knowledge of the codebase to find the relevant parts, which also makes it easier to judge a repo's safety before you trust it.
- **Fewer tokens spent hunting.** An agent reads a clear statement of what the code does, rather than reading many files and inferring it.
- **Refactor with confidence.** The use cases stay put while the code underneath changes, even in the extreme (JavaScript to Swift, say).

## Behaviour intrinsically linked with the implementation

Agents or humans can find the use case and have immediate access to all the code that directly implements it, despite never seeing the codebase before.

Additionally, the two layers are intrinsically linked, so if any of the underlying implementation details change (the code, the tests or any other linked file), the use case goes stale. It stays stale until the behaviour is proven again, by an agent or a human running the tests, or by someone trying the app/software by hand and recording the result.

This means a behaviour must be explicitly proven on change, so ’the tests passed’ becomes a thing of the past.

Proof can be automated or done by hand, and sign-off is separate from proof. Turn sign-off on and a critical use case can't ship until a person has approved what it promises, and again whenever that promise changes.

```text
  ┌──────────────┐    linked code, tests or files change    ┌──────────────┐
  │  verified    │ ───────────────────────────────────────▶ │  stale       │
  │  ships       │                                          │  blocks ship │
  └──────────────┘ ◀─────────────────────────────────────── └──────────────┘
                       proven again: the tests pass, or
                   a person tries it and records the result

  if the proof fails ──▶ failed, blocks ship until fixed and proven again
```

## Showcases and demos

Because agents have the full understanding of a use case, from the human plain English description and expectations to all of the related code, they can create and run showcases, taking the weight off humans and setting up all their proofs in one go.

The person signing off can physically watch agents take behaviours, plan and run the showcase and prove first hand the behaviour works allowing full confidence in a final shipping app instead of relying on more contrived or limited tests.

A person with little to no ability in software development can design a complex tool with their favourite agent, focusing on the behaviours as an end user instead of being lost in implementation details.

Once the design is finished the human user can leave their laptop alone and agents can take over, write the software and have full confidence they are doing the right thing based on the human approved behaviours.

At the end of the build, the agents can plan and build a showcase to show off all of their new features to the user in the real running app, allowing users to become feature and product designers if they wish without ever having to learn a line of code or software architecture.

## First class citizen tooling

CLI commands and a built-in MCP server are first-class citizens here, so agents have complete control in managing the entire life of a use case with very little effort.

## How it fits together

Three rings. Each works without the rings outside it.

```text
 ┌ 3 HELPERS (optional) ─ result transformers · run commands · use-cases-bridge.yml ┐
 │                                                                                  │
 │  ┌ 2 LINKS (optional) ─ markers in code  OR  file/line bindings in the YAML  ─┐  │
 │  │                                                                            │  │
 │  │  ┌ 1 USE CASES CORE ─ use cases · record · judge · status · results  ─┐    │  │
 │  │  │                                                                    │    │  │
 │  │  └────────────────────────────────────────────────────────────────────┘    │  │
 │  │                                                                            │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 │                                                                                  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

Use cases are YAML files beside your code. Links (marker comments) tie each one to its tests and code. Helpers run your test command and read its report. Only the core judges. The design is in [docs/README.md](docs/README.md).

## Works with your test tool

Keep the tests you have. Use Cases runs your own test command and reads the report it writes.

| Your tests | Read by |
|---|---|
| Any tool that writes JUnit XML: pytest, `node --test`, CTest, Maven Surefire, Gradle and many more | `junit` |
| Go (`go test -json`) | `go-test-json` |
| Rust (`cargo test`) | `cargo-test` |
| Swift (Swift Testing and XCTest) | `swift-test`, `swift-testing` |
| Cucumber, in any language | `cucumber-messages` |
| Any script or command whose exit code is the check | `exit-code` |
| Anything else | your own reader: a small program in any language ([how](docs/transformers/README.md#writing-your-own)) |
| Checks done by hand | `use-cases record`, with screenshots or files kept as evidence |

The readers come with the tool, and the tool's own tests run each language's reader against a sample project in that language. Details are in the [transformer catalogue](docs/transformers/README.md).

# Install

Three routes, one release.

| For | How |
|---|---|
| People and git hooks | Download the release for your platform from [the releases page](https://github.com/adammcarter/use-cases/releases) and put `use-cases` on your PATH: [CI guide](docs/guides/ci-and-hooks.md) shows the steps |
| Agents | In Claude Code, run `/plugin marketplace add adammcarter/use-cases`, then `/plugin install use-cases@use-cases`. The plugin carries the program for your platform and starts it itself: no install step |
| CI | Download the release for your platform from the project's GitHub releases (macOS universal, Linux x86_64 and arm64), one pinned step in your pipeline: [CI guide](docs/guides/ci-and-hooks.md) |

The plugin installs from the release's `use-cases-plugin.zip` through the marketplace in this repository. The plugin and the downloads always come from the same tag.

## Quick start

Set up a repository. In a terminal `init` asks a few questions; it never overwrites.

```text
$ use-cases init
created  use-cases.yml
created  use-cases/example.yml      a DRAFT example: fill it in, or delete it
created  use-case-groups.yml
created  use-cases-bridge.yml       a commented template: add your own test command
added    .use-cases/ to .gitignore
→ use-cases status
```

Write a use case in `use-cases/basket.yml`:

```yaml
prefix: basket
use_cases:
  - id: discounts
    title: Discounts never make a total negative
    value_tier: core
    intent: A discount larger than the basket brings the total to zero, never below.
    scenarios:
      - id: capped-at-zero
        when: [A discount of 5 is applied to a basket of 3.]
        then: [The total is 0.]
    validation:
      - id: unit-tests
        type: { kind: unit }
        covers: [capped-at-zero]
```

Tell it how to run your tests in `use-cases-bridge.yml` (the tool never guesses this):

```yaml
schema_version: 1

validations:
  - id: unit-tests
    report: results.xml
    run: [sh, tests/total-test.sh, "{report}"]
    transformer: junit
    settings: { find: file-name }
```

Wrap the test and the code with marker comments (the full example is in the [getting started guide](docs/guides/getting-started.md)):

```sh
# @use-case:basket.discounts#unit-tests.capped-at-zero
...the test...
# @use-case:end basket.discounts#unit-tests.capped-at-zero
```

Then check, link, verify:

```text
$ use-cases validate
✓ valid · 1 use case (1 ready, 0 draft) · 2 links · 1 file
→ use-cases status

$ use-cases links
basket.discounts  implementation         src/total.sh:5-6
basket.discounts  validation unit-tests  tests/total-test.sh:8-9

$ use-cases verify --run
run 01a20e36 · 1 verdict (1 pass) · 0 run errors
→ use-cases status --gate

$ use-cases status
✓ verified    basket.discounts

1 use case · 1 verified

$ use-cases status --gate
gate: clear
```

A failing test is a verdict, not a failed command. Find what exists before adding something new:

```text
$ use-cases search discount
✓ verified    basket.discounts  Discounts never make a total negative  id: "basket.discounts"

1 match
→ use-cases show basket.discounts
```

## Using it with an agent

The plugin gives an agent the commands as MCP tools and four skills that drive the flow. Each step of the flow ends on a command's output, never on the agent's word.

| Skill | What it does |
|---|---|
| `setup` | Once per repo: asks four questions, one at a time, and changes nothing without a yes |
| `use-case-driven-development` | The flow on every change: intent, discover, brief, sign-off, red, green, refactor, prove |
| `adopting` | Brings an existing repo in one small, well-tested area at a time, describing what the code does today |
| `showcase` | Plans, performs and shows what the user will see, and keeps what it proved as an ordinary verdict |

# FAQ

## Why not just use TDD?

Use Cases is an abstraction over a whole codebase, in natural language. It covers more than tests and source: anything that feeds into how the code works, such as JSON or Markdown resource files.

Tests can capture behaviour as codified documentation, but only a subset of it, and they give no plain-English instructions for manual testing by a person or an agent. People and agents would rather not read code to find out what it does; English is easier to think about without the mental load of translating. The code often does hold the behaviour, but mostly in a test's name, not its body.

Most of that value is lost in a refactor or a large change, because tests do not compile without the source behind them. Use cases sit a layer above the code, so you can wipe an entire codebase and every behaviour is still there in plain English, with nothing to convert and nothing that has to compile. People and agents can delete and rewrite whole codebases against use cases, without translating tests back into English or keeping commented-out tests around while they fail to build.

## Why not just use BDD?

BDD and Use Cases agree that behaviour should be written in plain words first. They differ in where it lives.

A BDD scenario is a program: Gherkin is matched to step definitions and run by one framework, in one language. Rewrite the code or change the tool, and the scenarios and steps go with them. A use case is plain-English behaviour above any test tool. It is linked to tests in whatever language and framework you already use, and it does not execute anything itself.

It also covers more. A use case can be backed by unit tests, snapshots, a manual walkthrough, or a resource file that is not a test at all, and it can carry instructions for a person or an agent to try it. If you already have a BDD suite, keep it: [fixtures/bdd](fixtures/bdd) shows a Cucumber suite linked as just another test tool, with the use case on top and a marker around each scenario. Its use cases are verified by the Cucumber run, and go stale when the scenario or the code it covers changes.

# Docs

- [Getting started](docs/guides/getting-started.md)
- [Writing use cases](docs/guides/writing-use-cases.md) · [Finding use cases](docs/guides/finding.md) · [Linking](docs/guides/linking.md)
- [Verifying](docs/guides/verifying.md) · [Reading status](docs/guides/reading-status.md) · [CI and hooks](docs/guides/ci-and-hooks.md) · [Quirks](docs/guides/quirks.md)
- [Design index](docs/README.md): the chapters and decisions
- The guides also ship with the tool: `use-cases docs <words>`

What is planned but not built is in [ROADMAP.md](ROADMAP.md).

# Licence

MIT. See [LICENSE](LICENSE).
