# Presentation Skills Design

Date: 2026-06-24
Status: Reviewed design ready for implementation planning

## Goal

Build an agent-agnostic presentation-skills plugin that helps agents and users keep product behavior, proof, and live demos connected throughout a run of work.

The plugin should replace the old `TEST-MATRIX.md` pattern with a living use-case system. It should work as day-to-day planning and verification infrastructure, not only as a pre-merge checklist. The recommended lifecycle is continuous, but users can choose backfill, showcase-only, audit-only, migration, or other local workflows.

The core product shape is:

```text
product behavior
  -> proof
  -> live presentation
  -> host support
```

## Design Principles

- Guide strongly, enforce only structural truth.
- Keep intended behavior human-readable.
- Keep observed history append-only.
- Treat live showcase as the strongest user-visible acceptance signal for the explicitly demonstrated scope, not as a required workflow for every task and not as a blanket release or merge approval.
- Keep the domain/application core authoritative. The CLI is the normative public JSON/text contract. MCP wraps that CLI contract and must not carry separate behavior.
- Keep one canonical skill source and project it into supported hosts.
- Never claim host support, proof, or sign-off without evidence.
- Do not persist derived summaries that can be recomputed from source events.

Source-of-truth boundary:

```text
plugin_root
  installed presentation-skills code, skills, schemas, host profiles, and bootstrap
  may be read-only or installed in a cache

workspace_root
  target product repository being planned, verified, or showcased

data_root
  configurable presentation-skills data location
  defaults to workspace_root unless repo config chooses another path
```

Data-root boundary:

```text
use-cases/
  intended behavior and sign-off policy

evidence/
  observed proof history

demo-capsules/
  reusable intended showcase recipes

showcase-runs/
  observed live showcase history
```

## Repository Shape

The repo root is the plugin root.

```text
presentation-skills/
  plugin.json
  .claude-plugin/
    plugin.json
  .codex-plugin/
    plugin.json

  .agents/
    skills/
      presentation-showcase/
      presentation-walkthrough/
      use-case-matrix/

  bootstrap/
    presentation-skills.md

  packages/
    ucm-core/
    ucm-cli/
    ucm-mcp/

  schemas/
    v1/

  hosts/
    claude.yml
    codex.yml
    copilot.yml
    opencode.yml

  tests/
    schema/
    conformance/
    fixtures/

  examples/
  docs/
```

The installed plugin must not assume it can write to `plugin_root`. All product data writes go through `data_root`.

Default target workspace data shape:

```text
<data_root>/
  use-cases/
  evidence/
  demo-capsules/
  showcase-runs/
```

Commands resolve roots explicitly:

```text
--plugin-root   installed plugin location, usually auto-detected
--repo          workspace_root target product repo
--data-root     optional override for presentation-skills data
```

Monorepos may also provide component scope so one workspace can contain multiple independent matrices.

## Feature 1: Use-Case Matrix

Purpose: replace `TEST-MATRIX.md` with a living product behavior inventory.

The use-case matrix tracks intended or planned behavior, not just tests. It answers:

```text
What behavior exists or is planned?
Who is it for?
How valuable is it?
Is it a golden path, alternate path, edge case, negative case, or failure case?
Which hosts matter?
What proof exists?
What is still missing?
```

Default storage is sharded YAML:

```text
use-cases/
  <feature-area>/
    <feature>.yml
```

Each feature file can contain multiple use-case variants. Large features may split variants into separate files, but the recommended starting point is one readable feature file with variants inside.

Example:

```yaml
feature:
  id: showcase.live
  title: Live showcase

use_cases:
  - id: showcase.live.golden
    title: Agent performs verified live showcase
    value_tier: golden_path
    journey_role: happy_path
```

Use cases can declare verification and approval policy:

```yaml
verification_policy:
  required_evidence:
    - kind: live_demo
    - kind: command
  default_verifier: user

approval_policy:
  required_approvers:
    - user
  resolution: predefined
  statement: Final acceptance depends on user-visible proof for this item.
```

Supported verifier types:

```text
user
agent
script
both
```

Supported approval resolution:

```text
predefined
ask
```

Script and agent verification can prove an observation, but they do not impersonate user approval. User approval must be recorded as an explicit approval event bound to run scope, repository revision, environment, exclusions, and approval statement.

The use-case loader must tolerate damage. Damaged files warn and are skipped; valid files still load. A partial matrix must be clearly reported as partial.

Warning categories:

```text
parse_error
schema_error
duplicate_id
broken_reference
unknown_version
```

Operation rules for damaged or partial matrices:

```text
query/report
  may continue and return complete=false

capsule generation
  may produce a draft or incomplete capsule with warnings

showcase execution
  may proceed only as explicitly partial

ordinary pass/full sign-off
  blocked while relevant integrity damage exists

explicit override
  records accepted_with_known_gaps, never ordinary pass
```

All copies of a duplicate ID are ambiguous. Unknown event versions and corrupt correction events invalidate the affected aggregate until resolved.

Acceptance:

```text
Multiple YAML files load into one matrix.
Duplicate IDs fail validation and do not silently merge.
Broken references are reported with source file paths.
Rows can represent planned, active, deprecated, removed, negative, failure, host-specific, and sign-off-sensitive cases.
Reports point back to source files.
One damaged file does not prevent valid files from loading.
Partial matrices cannot be reported as full coverage.
```

Use-case schema must keep distinct dimensions separate:

```text
value_tier       critical | core | supporting | long_tail
journey_role     golden | alternate | edge | negative | failure
lifecycle        planned | active | deprecated | removed
usage_frequency  common | occasional | rare
freshness        computed from evidence and source changes
```

A use case should include actor, intent, preconditions, trigger, steps or Given/When/Then scenarios, observable outcomes, host applicability, typed source references, verification requirements, tags, demo notes, and review provenance.

Stable IDs are independent of file paths.

## Feature 2: Evidence Capsules

Purpose: store proof history linked to use cases.

Evidence is observed history, so it is append-only. The default human-readable organization mirrors the `use-cases/` structure:

```text
use-cases/showcase/live.yml
evidence/showcase/live.jsonl
```

The mirrored path is an organizational convention, not the canonical relationship. Evidence identity and use-case relationships are by stable IDs. Moving a use-case file must not require rewriting historical evidence.

Evidence records can include:

```text
command output
test result
screenshot
generated artifact
file anchor
URL
manual observation
host smoke result
user sign-off reference
```

Evidence files are append-only. User-facing amend/delete operations append corrective events rather than rewriting history.

Supported event families:

```text
evidence_recorded
evidence_corrected
evidence_voided
evidence_superseded
evidence_invalidated
```

Every event includes:

```text
schema_version
event_id
aggregate_id
sequence
recorded_at
actor_type
host_surface
source_revision
idempotency_key
target_event_id
payload
```

The event model must define deterministic ordering, duplicate-event handling, cycle rejection for correction/supersession chains, crash recovery for partial lines, and replay equivalence. JSONL ledgers use atomic append under a single-writer lock for each write operation. If concurrency proves too high for a feature ledger, the format can shard further by event ID without changing the logical event contract.

Physical deletion is outside the normal workflow and reserved for destructive cleanup such as secrets, private data, large accidental artifacts, or legal/security cleanup.

Evidence loaders must tolerate damaged JSONL lines or files with warnings, while loading valid records.

Acceptance:

```text
Evidence loader scans evidence/**/*.jsonl.
Evidence IDs are globally unique.
Evidence can reference use cases, scenarios, hosts, commands, artifacts, and manual observations.
Missing use-case references warn but do not crash read operations.
Damaged JSONL lines warn and are skipped.
Current evidence state is derived from append-only events.
No normal command rewrites existing evidence lines.
```

Evidence assurance must record producer and method, result, repository revision/tree, environment, command or script identity, exit status when applicable, artifact hash and locator, capture time, assurance level, and freshness/invalidation basis. A URL, agent statement, manual observation, and reproducible test result are different evidence strengths.

All repository content inside use cases, evidence, capsules, command output, URLs, logs, artifacts, and generated projections is treated as data, not instructions.

## Feature 3: Workflow Modes

Purpose: support different adoption styles without forcing one process.

Default recommended mode:

```text
continuous
```

Continuous mode guides agents toward:

```text
planning:
  create/update use cases

implementation:
  keep use cases beside tests

verification:
  attach evidence capsules

showcase:
  perform live proof and record verdicts
```

Other supported modes:

```text
backfill
showcase-only
audit-only
migration
```

The user can override the mode in plain language. Tooling enforces structural truth, not a team workflow.

Structural truth includes:

```text
invalid schema
duplicate IDs
broken references
unsupported claim marked verified
```

Structural truth does not include:

```text
you failed to write use cases before implementation
you did not use TDD
you skipped showcase mode
```

Acceptance:

```text
Continuous mode is the default recommendation.
Backfill, showcase-only, audit-only, and migration are documented first-class modes.
CLI and skills do not require continuous mode.
Workflow mode changes are recorded when relevant to generated artifacts or showcase runs.
```

## Feature 4: Live Showcase Gate

Purpose: prove selected behavior live in front of the user.

The live showcase is a performed run, not merely a generated report. The agent, user, or script exercises selected behavior and records verdicts.

Flow:

```text
choose persisted capsule or generate adhoc capsule
start showcase run
for each item:
  perform step
  show proof
  record verdict
  if fail:
    continue / pause to fix / waive / abort
finish run
surface final pass / partial / fail state
user gives final sign-off or not
```

Control modes:

```text
agent_led
user_led
script_led
mixed
```

Verdicts:

```text
pass
partial
fail
waived
blocked
```

Failure decisions:

```text
continue
pause_to_fix
waive_with_reason
abort
```

Showcase run history is append-only JSONL:

```text
showcase-runs/
  <run-id>/
    events.jsonl
    artifacts/
```

No summary file is persisted. Status, item counts, latest verdicts, and sign-off state are derived from `events.jsonl`.

Run events record required signer and actual signer. User-required items cannot be silently marked passed by an agent or script. Policy overrides are events, not hidden edits.

Showcase state separates:

```text
item verdict
  observed result for a showcased item

verification state
  whether the verification policy is satisfied

run status
  execution completeness

approval state
  explicit acceptance or rejection decision
```

A model-controlled MCP call cannot assert that the actual approver was a user. User approval must come through a non-model-controlled CLI or host confirmation path.

If code, data, environment, or relevant artifacts change while a run is paused, the run records a new epoch:

```text
run started at revision A
item demonstrated at revision A
revision changed to B
affected verdicts become stale
required items rerun or explicitly carried forward
approval binds to revision B and known carry-forwards
```

Normal final pass cannot silently span incompatible revisions.

Events should be sufficient to derive:

```text
run status
item status
latest verdict per item
failure decisions
pause/resume state
user sign-off state
which capsule, if any, was used
repository revision and run epoch
approval statement and exclusions
```

Acceptance:

```text
A showcase can run from a persisted capsule.
A showcase can run from an adhoc generated capsule.
Per-item verdicts are append-only events.
Failures ask whether to continue, pause to fix, waive with reason, or abort.
Paused runs can resume from events.
Mistaken verdicts are corrected by new events.
No summary file is required to compute final status.
```

Final states include:

```text
passed
passed_with_waivers
partial
failed
blocked
aborted
incomplete
prepared_not_performed
accepted_with_known_gaps
```

A showcase with no post-start action or observation remains `prepared_not_performed`. A waived item does not count as an ordinary pass.

## Feature 5: Demo Capsules

Purpose: prepare a live showcase run.

The demo capsule is a runbook, not the final demo and not proof. The live showcase is the proof gate.

Two capsule modes:

```text
adhoc capsule
  generated for one run
  not saved
  used immediately

persisted capsule
  reusable showcase recipe
  committed or stored in repo
  used like a smoke test or canonical demo path
```

Persisted capsule storage:

```text
demo-capsules/
  smoke/
    core-showcase.yml
  release/
    pre-merge-showcase.yml
  host-parity/
    all-hosts.yml
```

Persisted capsules reference use-case IDs, not copied use-case content. A showcase run records which capsule, if any, was used.

Adhoc capsules are not saved as reusable recipes, but a run must persist the normalized resolved plan in `run_started` or a linked run-input event:

```text
selected use-case and scenario IDs
resolved steps and order
expected observations
exclusions and reasons
use-case hashes
capsule hash or adhoc marker
repository revision
environment expectations
```

Persisted capsules should include setup, teardown, environment, required permissions, safety constraints, timebox, live steps, expected observable outcomes, and artifact-capture instructions.

Acceptance:

```text
Adhoc capsules can be generated and run without persistence.
Persisted capsules can be saved and reused.
Persisted capsules warn on missing or stale referenced use cases.
Persisted capsules are never treated as proof.
Showcase run events record capsule identity and version/hash when available.
```

Presentation selection contract:

```text
showcase
  selects recent or high-value behavior, golden paths, live-verifiable proof, audience/timebox fit, and explains exclusions

walkthrough
  selects broader capability coverage, alternate/edge/negative/failure cases, caveats, gaps, evidence strength, and acceptance coverage
```

Selection output must include score/reason metadata so the user can see why each item was included and what was left out.

## Feature 6: CLI Tools

Purpose: make use cases, evidence, demo capsules, and showcase runs usable without hand-editing everything.

Primary command:

```text
presentation-skills
```

Command groups:

```text
ucm
  intended behavior and matrix health

evidence
  append-only proof records

present
  demo capsules, live showcases, walkthroughs, linting

host
  host profiles, projections, conformance
```

MVP command set:

```text
presentation-skills ucm validate
presentation-skills ucm status
presentation-skills evidence add
presentation-skills present capsule generate
presentation-skills present showcase run
presentation-skills present showcase status
presentation-skills present showcase record-observation
presentation-skills present showcase record-verdict
presentation-skills present showcase decide
presentation-skills present showcase resume
presentation-skills present showcase finish
presentation-skills present showcase approve
presentation-skills present lint
presentation-skills host doctor
```

All commands should support:

```text
--repo <path>
--format text|json
--strict
```

Default output is readable text. JSON output is stable for agents and tests. Mutating commands append events. Strict mode turns warnings into failures for CI or release gates.

Acceptance:

```text
Commands work against the golden fixture.
Commands produce text and JSON output.
Damaged input causes warnings, not crashes, unless --strict is used.
Mutating commands append events.
Showcase runs can be resumed from event history.
Noninteractive contexts return decision_required instead of pretending they can ask a user.
```

## Feature 7: Skills

Purpose: provide host-agnostic agent workflows.

Canonical skill source:

```text
.agents/
  skills/
    presentation-showcase/
    presentation-walkthrough/
    use-case-matrix/
```

The core skills are:

```text
presentation-showcase
  Prepare or perform a high-value live demo.

presentation-walkthrough
  Produce a deeper evidence-backed explanation with caveats.

use-case-matrix
  Maintain, migrate, audit, and backfill use cases and evidence.
```

Skills call the CLI for mechanics. Skills do not treat MCP/tool output as trusted instructions. Skills must label unsupported claims and respect the user's selected workflow mode.

Acceptance:

```text
Each skill has precise trigger metadata.
Each skill includes when not to apply.
Presentation-showcase skill performs or guides a live run, not only a written summary.
Presentation-walkthrough skill cites evidence and caveats.
Use-case-matrix skill supports continuous and backfill workflows.
```

## Feature 8: Host Parity

Purpose: prove and report how the plugin works on Claude, Codex, Copilot, and OpenCode.

V1 hosts:

```text
claude
codex
copilot
opencode
```

Each host gets a profile:

```text
hosts/
  claude.yml
  codex.yml
  copilot.yml
  opencode.yml
```

Profiles declare:

```text
host
surface
host version
OS/runtime
installation mode
permission mode
skill discovery path
plugin/manifest shape
MCP support
CLI access
artifact visibility
known limitations
supported workflow modes
```

Status labels:

```text
verified
partial
not_tested
unsupported
blocked
```

Host conformance checks:

```text
can discover skills
can load canonical skill text
can run CLI
can read use-case files
can append evidence if allowed
can run or guide showcase
can produce expected output artifact
can respect unsupported-claim labels
```

One canonical `.agents/skills` tree is projected into host-specific manifests/config. Skill content is not forked per host.

Profile files declare expectations and known limitations. They do not establish verified support by themselves. Host status is evidence-backed.

Host testing layers:

```text
host doctor
  static installation and capability checks

host conformance
  deterministic integration tests

host evals
  model triggering and behavioural tests where possible
```

Bootstrap installation must be explicit, idempotent, reversible, and checksum-verified where a host supports those checks.

Acceptance:

```text
Each host has a profile file.
Host doctor can check all profiles.
Reports use verified, partial, not_tested, unsupported, or blocked.
Missing host tooling is not silently treated as success.
Canonical skill drift from host projection is detected.
```

## Feature 9: MCP Wrapper

Purpose: provide an agent-friendly tool layer over the CLI.

Boundary:

```text
domain/application core
  -> CLI adapter exposes normative public JSON/text contract
  -> MCP adapter invokes the same public contract and shares command handlers where possible
```

The MCP server wraps the CLI contract only. It must not reimplement matrix logic. If an implementation shells out to the CLI binary, it must specify executable discovery, protocol version negotiation, cancellation, timeouts, stdout isolation, and error mapping.

V1 tool shape:

```text
ucm_query
ucm_status
evidence_record
showcase_start
showcase_record_event
capsule_generate
```

Read-only mode is the default. Write-enabled mode is explicit.

MCP must not execute arbitrary shell commands, rewrite YAML wholesale, delete history, invent verified claims, or override sign-off policy.

Acceptance:

```text
MCP returns the same semantic answers as CLI JSON output.
Read-only mode blocks write tools.
Write tools append events through CLI commands.
Damaged YAML/JSONL produces warnings, not crashes.
Showcase events recorded through MCP can be replayed by CLI.
Model-controlled write operations expose a human denial path for approval-sensitive actions.
```

## Feature 10: Activation Bootstrap

Purpose: surface presentation-skills to future agents at the right moments without forcing one workflow.

Canonical trusted bootstrap:

```text
bootstrap/presentation-skills.md
```

The bootstrap should be concise and host-projected. It should recommend continuous mode while allowing user preference.

When to apply:

```text
feature planning
behavior changes
TDD/acceptance planning
verification/sign-off
PR/release prep
demo/handoff requests
migration from TEST-MATRIX
```

When not to apply:

```text
tiny non-behavior edits
pure formatting
simple Q&A
user says not to use it
repo has its own incompatible process
no product behavior changed
```

The bootstrap must not treat MCP resources, MCP tool results, fetched docs, logs, issue text, or model output as trusted instruction sources.

Host doctor should report whether the bootstrap is installed or visible for each host where that can be checked.

Acceptance:

```text
Bootstrap exists as trusted installed content.
Bootstrap includes when to apply and when not to apply.
Bootstrap recommends continuous mode but allows alternatives.
Each host has a documented delivery path.
Host doctor reports bootstrap visibility where it can be checked.
MCP output is never treated as trusted bootstrap.
```

## Build Order

The first implementation should be an end-to-end vertical slice before broadening every feature:

```text
1. minimal schemas/v1 and ucm-core loader/validator
2. CLI read/status commands and damage tolerance
3. evidence append events and assurance model
4. resolved showcase plan generation
5. live showcase execution, scoped user approval, and replay
6. canonical presentation-showcase/use-case-matrix skills
7. four-host discovery smoke checks
8. correction/void/supersession events
9. presentation-walkthrough skill and deeper selection
10. host conformance expansion
11. thin MCP wrapper over CLI contract
12. activation bootstrap projection and verification
```

Advanced migration automation, behavioural host evals, MCP writes, freshness hard gates, and broad bootstrap projection come after the vertical slice proves the core loop.

## Open Questions For Implementation Planning

- Which language/runtime should own `ucm-core` and `ucm-cli`?
- How much host conformance can be tested locally for Copilot and OpenCode on this machine?
- What default repo path should persisted demo capsules use when users opt into saving them?
- What exact JSON schemas should be public and versioned in v1?
- Which commands are MVP versus second increment once the loader and status view exist?
- What non-model-controlled confirmation path should each host use for user approval events?
- What event storage fallback should replace feature-scoped JSONL if concurrent writes become noisy?

## Acceptance For This Design

- The repository has a committed design spec before implementation starts.
- The spec defines the source-of-truth boundary for use cases, evidence, demo capsules, and showcase runs.
- The spec keeps workflow modes flexible while recommending continuous mode.
- The spec identifies live showcase as a performed user-visible proof gate.
- The spec treats host parity as measurable conformance rather than an assumption.
- The spec keeps MCP as a wrapper over the CLI.
- The spec distinguishes plugin root, workspace root, and data root.
- The spec prevents damaged relevant data from yielding ordinary pass or full sign-off.
- The spec prevents model-controlled tools from fabricating user approval.
- The spec records revision/environment scope for showcase approval.
