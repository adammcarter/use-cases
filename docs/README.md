# Use Cases — design

Use Cases is a behavioural contract that stands alone above your code. Links and helpers are optional rings around it.

```text
 ┌ 3 HELPERS (optional) ─ result transformers · run commands · use-cases-bridge.yml ┐
 │  ┌ 2 LINKS (optional) ─ markers in code  OR  file/line bindings in the YAML ─┐  │
 │  │  ┌ 1 USE CASES CORE ─ use cases · record · judge · status · results ─┐    │  │
 │  │  └────────────────────────────────────────────────────────────────────┘    │  │
 │  └────────────────────────────────────────────────────────────────────────────┘  │
 └──────────────────────────────────────────────────────────────────────────────────┘
```

Each ring works without the rings outside it.

## Decisions

| ADR | Decision |
|---|---|
| [000](ADRs/000-use-cases-stand-alone-in-three-rings.md) | Use cases stand alone in three rings |
| [001](ADRs/001-links-are-optional-in-either-direction.md) | Links are optional, in either direction |
| [002](ADRs/002-ready-never-requires-links.md) | READY never requires links |
| [003](ADRs/003-helpers-report-per-link-and-only-the-core-judges.md) | Helpers report one result per link; only the core judges |
| [004](ADRs/004-every-validation-link-needs-a-result.md) | Every validation link needs a result |
| [005](ADRs/005-tests-run-in-the-real-project-between-start-and-finish.md) | Tests run in the real project, between a start point and a finish point (reports: see 020) |
| [006](ADRs/006-begin-then-validate-or-validate-run.md) | *Superseded by 013* |
| [007](ADRs/007-only-the-core-writes-sealed-run-folders.md) | Only the core writes results, in sealed run folders (reports: see 020) |
| [008](ADRs/008-fingerprints-follow-content-not-helpers.md) | Fingerprints follow content, never helpers |
| [009](ADRs/009-helpers-configured-in-one-root-bridge-file.md) | Helpers are configured in one root file and run as separate programs |
| [010](ADRs/010-the-core-names-no-tool.md) | The core and its contract name no tool |
| [011](ADRs/011-the-schemas-are-the-contract.md) | The published schemas are the contract, enforced on every exchange |
| [012](ADRs/012-discovery-skips-only-the-store-and-version-control-history.md) | Discovery skips only the store and version-control history by default |
| [013](ADRs/013-validate-start-and-finish-are-named.md) | *Superseded by 016* |
| [014](ADRs/014-one-spelling-for-every-path.md) | One spelling for every path, one dialect for every pattern |
| [015](ADRs/015-contract-1-only-grows-by-optional-fields.md) | Contract 1 only grows by optional fields; receivers ignore what they don't know |
| [016](ADRs/016-runs-are-named-locked-and-time-ordered.md) | Started runs are named and locked, and run ids follow time |
| [017](ADRs/017-authored-files-read-one-way.md) | Authored files are read one way, and the root is declared |
| [018](ADRs/018-markers-and-discovery-are-byte-exact.md) | Markers, discovery and symlinks are defined to the byte |
| [019](ADRs/019-four-statuses-with-fixed-meanings.md) | Four statuses with fixed meanings; reports are private copies that never hold code (reports: see 020) |
| [020](ADRs/020-each-run-owns-its-reports.md) | Each run owns its reports, and a run deletes nothing |
| [021](ADRs/021-verify-runs-tests-validate-checks-files.md) | `verify` gets verdicts from tests, `validate` checks the files |
| [022](ADRs/022-one-command-line-for-people-and-scripts.md) | One command line, written for people, with a versioned JSON contract for scripts |
| [023](ADRs/023-the-gate-blocks-anything-that-stopped-being-proven.md) | The gate blocks anything that stopped being proven |
| [024](ADRs/024-init-scaffolds-generously-and-never-overwrites.md) | Init writes generous base files, never a codebase's commands, and never overwrites |
| [025](ADRs/025-hooks-are-opt-in-and-per-clone.md) | Hooks are opt-in and per clone; init asks in a terminal |
| [026](ADRs/026-ci-runs-fresh-with-a-two-step-recipe.md) | CI runs fresh every time, with a two-step recipe and provider examples |
| [027](ADRs/027-agents-get-the-commands-as-tools.md) | Agents get the commands as MCP tools, and nothing more |
| [028](ADRs/028-use-cases-change-through-whole-use-case-commands.md) | Use cases change through three whole-use-case commands, planned before written |
| [029](ADRs/029-search-is-one-pipeline-of-words-filters-fields-and-pages.md) | Search is one pipeline of words, filters, fields and pages, deterministic and offline |
| [030](ADRs/030-guides-ship-with-the-tool-and-are-searched-like-use-cases.md) | Guides ship with the tool, one short page per task, searched like use cases |
| [031](ADRs/031-a-batch-of-use-case-changes-is-applied-all-or-nothing.md) | A batch of use case changes is applied all or nothing, in one fixed order |
| [032](ADRs/032-sign-off-is-recorded-on-the-use-case-and-gated-by-tier.md) | Sign-off is recorded on the use case, pinned to its promise, and gated by tier |
| [033](ADRs/033-the-core-draws-the-layouts-people-read.md) | The core draws the four layouts people read, from one proposal file |
| [034](ADRs/034-the-plugin-ships-the-flow-as-skills-with-a-check-per-step.md) | The plugin ships the flow as skills, with a check for every step |
| [035](ADRs/035-a-showcase-is-planned-performed-and-thrown-away.md) | A showcase is planned, performed and thrown away; what it proved is an ordinary verdict |
| [036](ADRs/036-the-real-build-is-swift-on-macos-and-linux.md) | The real build is Swift, on macOS and Linux for v1 |
| [037](ADRs/037-the-real-build-is-new-held-to-the-approved-design.md) | The real build is a new build, held to exactly the approved design |
| [038](ADRs/038-one-swift-package-four-modules.md) | One Swift package, four modules, dependencies one way |
| [039](ADRs/039-one-release-three-ways-to-install.md) | One release, three ways to install it |

## Where things are

| Ring | Chapter | Covers |
|---|---|---|
| all | [01 Foundation](design/01-core-foundation.md) | the rings, the four boundaries, core vs extras |
| 1 core | [02 Use-case schema](design/02-use-case-schema.md) | the authored use case, and INVALID / DRAFT / READY |
| 1 core | [03 Groups](design/03-use-case-groups.md) | named subsets for status views and gates |
| 1 core | [04 Workspace structure](design/04-workspace-structure.md) | scopes, files, `.use-cases/`, and where the bridge file lives |
| 1 core | [05 Identity & ID grammar](design/05-identity-and-id-grammar.md) | every ID, marker ID and link key |
| 1 core | [06 Validation model](design/06-validation-model.md) | routes, procedures, resources, the result contract |
| 1 core | [07 Verification state](design/07-verification-state-model.md) | how the core judges, and route and use-case status |
| 2 links | [08 Links](design/08-links.md) | markers and manual bindings, both optional |
| 1 core | [09 Workspace loading](design/09-workspace-loading.md) | the loader and the mutable Workspace Model |
| 3 helpers | [10 Bridge settings + transformer contract](design/10-bridge-settings-and-transformers.md) | `use-cases-bridge.yml` and the transformer JSON contract |
| 1 core | [11 Fingerprints + freshness](design/11-fingerprints-and-freshness.md) | route fingerprints, exact encoding, test vectors |
| 1 core | [12 Results storage](design/12-results-storage.md) | run folders, records, sealing |
| 1 + 3 | [13 Verify flow](design/13-verify-flow.md) | `verify --start`, `--finish`, `--run`, `record`, and the one guard |
| 3 helpers | [14 Run commands](design/14-run-commands.md) | how `--run` launches commands |
| 1 core | [15 Impact + explanations](design/15-impact-and-explanations.md) | why a route is stale, or has no verdict |
| all | [16 CLI surface](design/16-cli-surface.md) | the `use-cases` command: output, `--json`, exit codes, status, the gate, search, show / save / remove / apply, approve, `--dry-run`, docs |
| all | [17 Init](design/17-init.md) | `use-cases init`: a workspace from nothing, base files only |
| all | [18 Hooks](design/18-hooks.md) | opt-in git hooks for this clone: `validate` on commit, the gate on push |
| all | [19 CI](design/19-ci.md) | the two-step CI recipe, your own test step, sharded tests; provider examples in [ci/](ci/README.md) |
| agents | [20 MCP tools](design/20-mcp-tools.md) | `use-cases mcp`: the commands as tools for AI agents |
| agents | [21 Agent workflows](design/21-agent-workflows.md) | locked: the flow from a request to proven code, fitting new use cases in, sign-off by tier, and the four layouts people read |
| agents | [22 UCDD skill](design/22-ucdd-skill.md) | locked: what the plugin ships, and the check that ends every step of the flow |
| agents | [23 Showcases](design/23-showcases.md) | locked: showcases planned on axes, performed, thrown away; what they proved kept as verdicts |

- Schemas are in [schemas/authored](schemas/authored/README.md) (the files people write), [schemas/engine](schemas/engine/README.md) (what the core stores, exchanges with transformers and fingerprints) and [schemas/output](schemas/output/README.md) (`--json` output).
- Specific transformers (for example Swift Testing) are documented one per file in the [transformer catalogue](transformers/README.md). The core and chapter 10's contract name no tool.
- Three example repos (Swift, Python, legacy mixed) are in [examples/](examples/), and short explainers of the core ideas in [explainers/](explainers/).
- The survey of sessions using today's plugin that informed the agent layer is in [research/plugin-survey.md](research/plugin-survey.md).
- How the code is built (composed capabilities, plan then write, the choices of the Swift build) and how it is tested are in [architecture.md](architecture.md).

## Checking the specs

```sh
uv run --with 'jsonschema[format]' --with pyyaml python docs/schemas/engine/validate.py
```

It checks every schema against positive and negative samples, every published chapter example, every example and fixture YAML file, and the five fingerprint vectors. The command line itself is held to the schemas by its acceptance suite, `UseCases/Acceptance/` ([architecture.md](architecture.md) §7).

## Locked

The chapters, schemas and ADRs above are the contract for the core (ring 1), links (ring 2), the transformer layer (ring 3), the command line people and CI use, and the agent layer. A change to them is a new decision: a new ADR, then the chapter, schema and `validate.py` together.

## Building on it

- **A new test tool** is a new results transformer (chapter 10), documented in `transformers/`. No core change.
- **A new way to link code** is a links transformer (chapter 10) or a new core link kind (chapter 08).
- **A new command or experience** belongs with the command line (chapters 16–19) and sits on chapter 13's flow.
- **Anything that judges** belongs in the core (chapter 07). Helpers only hand the core links or results.

Chapters describe the current design as if it had always been this way, with no history in them. Decisions live in ADRs: a changed decision is a new ADR that supersedes the old one, and the chapter is rewritten to match.
