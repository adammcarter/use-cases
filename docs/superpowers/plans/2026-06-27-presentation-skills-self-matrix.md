# Presentation Skills Self Matrix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a complete product-level use-case matrix for Presentation Skills itself so the repo can dogfood planning, acceptance, and live showcase flows from its own rows.

**Architecture:** Keep the existing primitive rows unchanged as low-level proof support, and add product-level rows under `use-cases/presentation-skills/` split by feature area. Add one persisted feature-tour capsule that references the new golden rows but remains a runbook until performed. No code changes are planned unless validation exposes a schema or selection defect.

**Tech Stack:** YAML v1 use-case files, JSON schema validation, `presentation-skills` CLI, Corepack `pnpm@11.9.0`.

## Global Constraints

- Use ASCII in edited files.
- Use cases are not proof; evidence and showcase ledgers are proof only after events are recorded.
- Deferred future ideas must be `lifecycle: planned`, not active acceptance rows.
- User sign-off rows must require user approval or conditional user participation.
- Host rows must not claim live Claude, Codex, Copilot, or OpenCode support unless evidence exists.
- Validate with `corepack pnpm cli -- matrix validate --repo . --json`.
- Showcase selection must improve from primitive mechanics to product-level golden paths.

---

### Task 1: Product-Level Use-Case Shards

**Files:**
- Create: `use-cases/presentation-skills/lifecycle.yml`
- Create: `use-cases/presentation-skills/matrix.yml`
- Create: `use-cases/presentation-skills/evidence.yml`
- Create: `use-cases/presentation-skills/planning.yml`
- Create: `use-cases/presentation-skills/showcase.yml`
- Create: `use-cases/presentation-skills/capsules.yml`
- Create: `use-cases/presentation-skills/mcp.yml`
- Create: `use-cases/presentation-skills/hosts.yml`
- Create: `use-cases/presentation-skills/migration.yml`
- Create: `use-cases/presentation-skills/release.yml`
- Create: `use-cases/presentation-skills/future.yml`

**Interfaces:**
- Consumes: existing use-case schema in `schemas/v1/use-case-file.schema.json`.
- Produces: 52 active `presentation_skills.*` use cases and 11 planned future rows.

- [ ] **Step 1: Add active lifecycle rows**

Create `use-cases/presentation-skills/lifecycle.yml` with active rows for:

```text
presentation_skills.lifecycle.continuous_loop
presentation_skills.lifecycle.workflow_modes
presentation_skills.lifecycle.agent_matrix_stewardship
presentation_skills.lifecycle.user_feature_printout
presentation_skills.lifecycle.opt_out_or_tiny_change
```

- [ ] **Step 2: Add active matrix, evidence, and planning rows**

Create the matrix, evidence, and planning shards with active rows from the recovered Albus taxonomy. Each row must include `actor`, `intent`, `preconditions`, `trigger`, at least one runnable `steps` scenario, `observable_outcomes`, `host_applicability`, `verification_policy`, and `approval_policy`.

- [ ] **Step 3: Add active showcase, capsules, MCP, host, migration, and release rows**

Create the remaining active shards. Rows that depend on subjective user judgment must use `verification_policy.mode: requirements` or `approval_policy.mode: predefined` as appropriate.

- [ ] **Step 4: Add planned future rows**

Create `use-cases/presentation-skills/future.yml` with planned rows for:

```text
presentation_skills.hosts.behavioral_host_evals
presentation_skills.hosts.trusted_host_confirmation_path
presentation_skills.evidence.signed_audit_log
presentation_skills.evidence.destructive_secret_purge
presentation_skills.matrix.git_diff_auto_mapping
presentation_skills.matrix.advanced_monorepo_scoping
presentation_skills.mcp.direct_user_approval_write
presentation_skills.mcp.host_projection_conformance_tools
presentation_skills.planning.freshness_hard_gate_auto_selection
presentation_skills.capsules.multi_machine_runner
presentation_skills.release.registry_publish_channel
```

- [ ] **Step 5: Validate the matrix**

Run:

```bash
corepack pnpm cli -- matrix validate --repo . --json
corepack pnpm cli -- matrix list --repo . --json
```

Expected: validation is complete and clean; list includes 75 total rows: 12 existing primitive rows, 52 new active product rows, and 11 planned future rows.

### Task 2: Feature-Tour Demo Capsule

**Files:**
- Create: `demo-capsules/presentation-skills-feature-tour.yml`

**Interfaces:**
- Consumes: active product rows from Task 1.
- Produces: persisted smoke/showcase runbook for the product-level demo.

- [ ] **Step 1: Add a persisted feature-tour capsule**

Create a capsule with these ordered items:

```text
presentation_skills.matrix.product_inventory
presentation_skills.planning.showcase_selection
presentation_skills.evidence.product_proof_map
presentation_skills.showcase.live_acceptance_flow
presentation_skills.showcase.status_separation
presentation_skills.mcp.cli_contract_transport
presentation_skills.mcp.approval_request_only
presentation_skills.hosts.conformance_status_truth
presentation_skills.release.installable_artifact_provenance
presentation_skills.release.self_dogfood_evidence_bundle
```

- [ ] **Step 2: Validate capsule planning and selection**

Run:

```bash
corepack pnpm cli -- capsule validate --repo . --capsule capsule.presentation_skills.feature_tour --json
corepack pnpm cli -- capsule plan --repo . --capsule capsule.presentation_skills.feature_tour --json
corepack pnpm cli -- plan showcase --repo . --max-items 10 --json
```

Expected: the capsule validates, produces a prepared plan, and showcase selection favors `presentation_skills.*` golden rows over primitive rows.

### Task 3: Dogfood Showcase Evidence

**Files:**
- Create: `showcase-runs/run.presentation_skills_self_matrix_<id>/events.jsonl`
- Create: evidence JSONL entries only if command output is safe to summarize.

**Interfaces:**
- Consumes: matrix rows and feature-tour capsule from Tasks 1 and 2.
- Produces: performed showcase run status for agent-verifiable rows; user approval remains unclaimed unless the user explicitly signs off.

- [ ] **Step 1: Run the feature-tour capsule without fabricating user approval**

Run:

```bash
corepack pnpm cli -- capsule run --repo . --capsule capsule.presentation_skills.feature_tour --idempotency-key self-matrix:feature-tour --json
```

Expected: a showcase run starts and records instruction observations as prepared/performed events, but any rows requiring user judgment remain pending or approval-required.

- [ ] **Step 2: Inspect run status**

Run:

```bash
corepack pnpm cli -- showcase status --repo . --run <run-id> --json
```

Expected: status is derived from JSONL events, not a summary file; no user approval is present unless confirmed by the user.

### Task 4: Release Gate Snapshot

**Files:**
- No source files expected.

**Interfaces:**
- Consumes: all previous tasks.
- Produces: final merge readiness evidence.

- [ ] **Step 1: Run targeted checks**

Run:

```bash
corepack pnpm cli -- matrix validate --repo . --json
corepack pnpm cli -- plan showcase --repo . --max-items 10 --json
corepack pnpm test -- tests/schema/matrix-cli.test.ts tests/conformance/cli/p5-plan-contract.test.ts
git status --branch --short
```

Expected: all checks pass and git shows only intentional files before commit.

- [ ] **Step 2: Commit the product matrix**

Run:

```bash
git add docs/superpowers/plans/2026-06-27-presentation-skills-self-matrix.md use-cases/presentation-skills demo-capsules/presentation-skills-feature-tour.yml
git commit -m "feat: add presentation skills self matrix"
```

Expected: one logical commit containing the new self-matrix and feature-tour capsule.
