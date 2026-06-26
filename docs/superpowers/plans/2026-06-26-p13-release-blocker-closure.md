# P13 Release Blocker Closure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the five P11/P12 release blockers found by Albus without weakening the plugin architecture or trust model.

**Architecture:** Keep the TypeScript workspace shape: pure core domain modules own trust, hashing, package inspection, and host status semantics; CLI and MCP remain adapters over shared core behavior. MCP must never become an alternate authority path for user approval, and release/package checks must inspect installable artifacts rather than the mutable checkout alone.

**Tech Stack:** TypeScript 6, Node 22+, pnpm 11, Vitest, JSONL ledgers, JSON-RPC stdio MCP server, npm pack/install smoke tests.

## Global Constraints

- Work in the sibling worktree `/Users/admin/repos/presentation-skills-p13-blocker-closure` on branch `feature/p13-blocker-closure`.
- Preserve the existing public CLI envelope shape from P4: `schema_version`, `protocol_version`, `command`, `ok`, `complete`, `data`, `diagnostics`, `context`.
- Never let an agent, script, raw JSONL fixture, or MCP call fabricate trusted user approval.
- Write the failing behavior test before production code for every behavioral change.
- Commit after each logical task once targeted tests and relevant broader checks pass.
- Do not update docs to claim release readiness until all blocker tests and release checks pass.
- Keep generated `dist/` output synchronized through `corepack pnpm build` before release/package verification.

---

## File Structure

- `packages/ucm-core/src/showcase/approvalAuthority.ts`
  - Owns trusted approval authority checks and approval scope construction.
- `packages/ucm-core/src/showcase/planBinding.ts`
  - Owns plan hash validation, plan-file loading, placeholder-hash rejection, and finish-event binding helpers.
- `packages/ucm-core/src/showcase/appendShowcaseEvent.ts`
  - Delegates approval and start-run validation to the new core helpers.
- `packages/ucm-core/src/showcase/replayRun.ts`
  - Ignores/degrades untrusted approval events during replay and exposes diagnostics through status.
- `packages/ucm-core/src/showcase/types.ts`
  - Adds approval/proof-binding payload fields if current event result types need them.
- `packages/ucm-core/src/hosts/conformanceStatus.ts`
  - Owns host executable smoke status derivation and aggregate conformance status.
- `packages/ucm-core/src/hosts/projectHostFiles.ts`
  - Delegates host conformance status to the new module.
- `packages/ucm-core/src/package/inspectPackage.ts`
  - Inspects a real packlist/tarball or installed package root and runs installed CLI/MCP smoke checks.
- `packages/ucm-core/src/index.ts`
  - Exports the new core modules needed by CLI/tests.
- `packages/ucm-cli/src/index.ts`
  - Adds plan-file based `showcase start`, trusted interactive approval gating, and real package doctor integration.
- `packages/ucm-mcp/src/tools.ts`
  - Preserves request-only approval and uses shared core behavior; no direct approval tool is added.
- `tests/conformance/cli/p6-showcase-contract.test.ts`
  - Tightens approval and plan-binding CLI behavior.
- `tests/conformance/mcp/p13-stdio-parity.test.ts`
  - Launches the compiled MCP stdio server and checks real transport parity.
- `tests/conformance/hosts/p13-host-conformance.test.ts`
  - Uses controlled PATH executables for pass, failed, and not_run semantics.
- `tests/release/p13-package-install.test.ts`
  - Packs, inspects, installs, and smokes the installable package.
- `tests/e2e/p11-product-lifecycle.test.ts`
  - Updates the clean example acceptance flow to use real proof bindings and generated plans.
- `examples/basic-product/**`
  - Replaces placeholder hashes and hand-authored approval proof with generated/hash-bound artifacts.
- `docs/security.md`, `docs/showcase.md`, `docs/mcp.md`, `docs/release.md`, `docs/hosts.md`
  - Updated only after implementation proves the trust/security claims.

---

### Task 1: Approval Authority Trust Boundary

**Files:**
- Create: `packages/ucm-core/src/showcase/approvalAuthority.ts`
- Modify: `packages/ucm-core/src/showcase/appendShowcaseEvent.ts`
- Modify: `packages/ucm-core/src/showcase/replayRun.ts`
- Modify: `packages/ucm-core/src/showcase/index.ts`
- Modify: `packages/ucm-cli/src/index.ts`
- Test: `tests/conformance/cli/p6-showcase-contract.test.ts`
- Test: `tests/conformance/mcp/p9-mcp.test.ts`

**Interfaces:**
- Produces: `requireTrustedUserApprovalAuthority(input): TrustedApprovalDecision`
- Produces: `buildApprovalScope(input): ShowcaseApprovalScope`
- Consumes: existing `appendShowcaseApproval`, `rejectShowcaseApproval`, `replayShowcaseRun`
- Later tasks rely on approval scope containing `plan_content_hash`, `finish_event_id`, and `run_outcome`.

- [ ] **Step 1: Write failing CLI security tests**

Add tests showing:

```ts
const approval = runCli([
  "showcase",
  "approve",
  "--repo",
  workspaceRoot,
  "--run",
  runId,
  "--actor",
  "user",
  "--statement",
  "Script cannot impersonate the user.",
  "--json"
]);

expect(approval.status).toBe(1);
expect(JSON.parse(approval.stdout)).toMatchObject({
  command: "showcase.approve",
  ok: false,
  diagnostics: [expect.objectContaining({ code: "showcase.trusted_user_confirmation_required" })]
});
```

Also assert the ledger file is unchanged after the refused approval.

- [ ] **Step 2: Run the failing test**

Run: `corepack pnpm test -- tests/conformance/cli/p6-showcase-contract.test.ts -t "scripted user approval"`

Expected: FAIL because current CLI accepts `--actor user` and appends `approval_recorded`.

- [ ] **Step 3: Implement approval authority helper**

Create `approvalAuthority.ts` with:

```ts
export type TrustedApprovalAuthority =
  | { kind: "trusted_interactive_cli"; stdinIsTty: boolean; force?: boolean }
  | { kind: "trusted_host_token"; token: string }
  | { kind: "untrusted_automation" };

export function requireTrustedUserApprovalAuthority(input: {
  actorType: ShowcaseActorType;
  authority: TrustedApprovalAuthority;
  userApprovalRequired: boolean;
}): void;
```

Rules:
- `actorType !== "user"` still fails for user-required plans with `showcase.user_required_approval`.
- `actorType === "user"` requires `authority.kind === "trusted_interactive_cli"` and a real TTY-bound confirmation prompt. No ordinary CLI argument can grant trusted user authority.
- MCP has no path to pass trusted authority.

- [ ] **Step 4: Wire CLI approval and rejection**

Change `showcase approve/reject`:
- default actor stays `agent` unless explicitly supplied;
- `--actor user --json` in a noninteractive process returns `showcase.trusted_user_confirmation_required` and appends nothing;
- interactive CLI may prompt on a TTY and then write `capture_method: "trusted_user_interactive_cli"`;
- tests must not use a magic trusted flag to fabricate approval.

- [ ] **Step 5: Degrade untrusted raw JSONL approval on replay**

Update replay to ignore approval events where:
- `actor_type === "user"` but `capture_method !== "trusted_user_interactive_cli"`;
- user-required approval lacks a valid scope;
- approval references no finish event once Task 2 adds that field.

Expose warning diagnostics under `diagnostic_summary` so damaged/tampered ledgers do not bring down status.

- [ ] **Step 6: Run targeted approval tests**

Run: `corepack pnpm test -- tests/conformance/cli/p6-showcase-contract.test.ts tests/conformance/mcp/p9-mcp.test.ts`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/ucm-core/src/showcase packages/ucm-cli/src/index.ts tests/conformance/cli/p6-showcase-contract.test.ts tests/conformance/mcp/p9-mcp.test.ts
git commit -m "Harden trusted showcase approval"
```

---

### Task 2: Real Proof Binding and Generated Plan Starts

**Files:**
- Create: `packages/ucm-core/src/showcase/planBinding.ts`
- Modify: `packages/ucm-core/src/showcase/appendShowcaseEvent.ts`
- Modify: `packages/ucm-cli/src/index.ts`
- Modify: `packages/ucm-core/src/presentation/selectPlan.ts`
- Modify: `examples/basic-product/evidence/by-id/ev/evidence-basic-search.jsonl`
- Modify: `examples/basic-product/showcase-runs/run.basic.product.search/events.jsonl`
- Test: `tests/e2e/p11-product-lifecycle.test.ts`
- Test: `tests/conformance/cli/p6-showcase-contract.test.ts`

**Interfaces:**
- Produces: `loadPresentationPlanFile(path: string): PresentationPlan`
- Produces: `assertNoPlaceholderHashes(planOrEvent: unknown): void`
- Produces: `findLatestFinishEvent(events: ShowcaseEvent[]): ShowcaseEvent | null`
- Consumes: `computePresentationPlanHash`, `computeSemanticHash`, `startShowcaseRun`

- [ ] **Step 1: Write failing proof-binding tests**

Add tests that:
- run `plan showcase --json`;
- write `payload.data.plan` to a temp plan file;
- call `showcase start --plan-file <file> --json`;
- assert `run_started.payload.plan_content_hash === plan.plan_content_hash`;
- assert `run_started.payload.plan.selected_items[0].use_case_content_hash` matches the active use case semantic hash;
- mutate the plan file and assert start fails with `showcase_plan_hash_mismatch`;
- assert all-zero hashes in clean example evidence/showcase files fail validation.

- [ ] **Step 2: Run failing tests**

Run: `corepack pnpm test -- tests/e2e/p11-product-lifecycle.test.ts -t "complete product lifecycle"`

Expected: FAIL because the current E2E starts an ad hoc plan and clean example uses placeholder hashes.

- [ ] **Step 3: Implement plan-file start**

Extend `showcase start`:
- support `--plan-file <path>`;
- keep `--adhoc --select` for convenience;
- load the plan, recompute hash, reject mismatch;
- reject `sha256:0000000000000000000000000000000000000000000000000000000000000000`.

- [ ] **Step 4: Bind approval to finish event**

Update approval payload scope:

```ts
scope: {
  plan_content_hash: plan.plan_content_hash,
  finish_event_id: finish.event_id,
  run_outcome: status.run_outcome,
  known_gap_count: status.known_gaps.length
}
```

Reject approval when the run is not finished or no finish event exists.

- [ ] **Step 5: Regenerate clean example proof artifacts mechanically**

Use the CLI to:
- record evidence so targets contain real `use_case_semantic_hash`;
- generate a plan;
- start from that generated plan;
- record observation/verdict/finish;
- leave user approval pending in automated examples unless a real trusted interactive prompt is exercised by the human.

Do not hand-edit placeholder hashes except to remove stale fixtures. Do not hand-author trusted user approval in JSONL.

- [ ] **Step 6: Run targeted proof-binding tests**

Run: `corepack pnpm test -- tests/e2e/p11-product-lifecycle.test.ts tests/conformance/cli/p6-showcase-contract.test.ts`

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add packages/ucm-core/src/showcase packages/ucm-cli/src/index.ts examples/basic-product tests/e2e/p11-product-lifecycle.test.ts tests/conformance/cli/p6-showcase-contract.test.ts
git commit -m "Bind showcase proof to generated plans"
```

---

### Task 3: Compiled MCP Stdio Lifecycle Parity

**Files:**
- Create: `tests/conformance/mcp/p13-stdio-parity.test.ts`
- Modify: `packages/ucm-mcp/src/tools.ts`
- Modify: `packages/ucm-mcp/src/index.ts` only if stdio framing needs correction.
- Test: `tests/conformance/mcp/p13-stdio-parity.test.ts`

**Interfaces:**
- Produces: test helper `startMcpServer(): { callTool(name,args), close() }`
- Consumes: compiled executable `packages/ucm-mcp/dist/index.js --stdio`

- [ ] **Step 1: Write failing stdio parity tests**

Create tests that spawn:

```ts
spawn(process.execPath, ["packages/ucm-mcp/dist/index.js", "--stdio"], { cwd: repoRoot });
```

Then send newline-delimited JSON-RPC:
- `initialize`;
- `notifications/initialized`;
- `tools/list`;
- `tools/call matrix_validate`;
- `tools/call evidence_status`;
- `tools/call showcase_status`;
- `tools/call evidence_record` with `allow_write: true`, then verify CLI sees the new evidence;
- `tools/call evidence_record` without `allow_write`, verifying no ledger mutation;
- `tools/call showcase_request_approval`, verifying no approval event is appended.

- [ ] **Step 2: Run failing stdio tests**

Run: `corepack pnpm test -- tests/conformance/mcp/p13-stdio-parity.test.ts`

Expected: FAIL if compiled stdio invocation, lifecycle parity, or write gating is incomplete.

- [ ] **Step 3: Fix MCP behavior through shared core only**

Adjust MCP handlers only where needed:
- keep all writes behind `allow_write`;
- preserve domain-negative errors as structured envelopes, not transport errors;
- ensure approval request returns instructions only;
- never add `showcase_approve`.

- [ ] **Step 4: Run MCP tests**

Run: `corepack pnpm test -- tests/conformance/mcp/p9-mcp.test.ts tests/conformance/mcp/p13-stdio-parity.test.ts`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add packages/ucm-mcp tests/conformance/mcp
git commit -m "Verify compiled MCP stdio lifecycle parity"
```

---

### Task 4: Host Conformance Status Semantics

**Files:**
- Create: `packages/ucm-core/src/hosts/conformanceStatus.ts`
- Modify: `packages/ucm-core/src/hosts/projectHostFiles.ts`
- Modify: `packages/ucm-core/src/hosts/index.ts`
- Modify: `packages/ucm-cli/src/index.ts`
- Test: `tests/conformance/hosts/p8-hosts.test.ts`
- Test: `tests/conformance/hosts/p13-host-conformance.test.ts`
- Test: `tests/e2e/p11-product-lifecycle.test.ts`

**Interfaces:**
- Produces: `deriveHostConformance(input): { ok: boolean; complete: boolean; support_status: HostSupportStatus; diagnostics: Diagnostic[] }`
- Produces: `runExecutableSmoke(profile, envPath?: string): HostExecutableSmoke`
- Consumes: current `runHostConformance`

- [ ] **Step 1: Write controlled PATH tests**

Create temp PATH directories containing:
- no executable for `not_run`;
- a fake executable exiting `0`;
- a fake executable exiting `1`.

Assert:
- no executable returns `not_run`, exact reason code `executable_not_found`, command exit remains non-release-proof but not a process crash;
- fake exit `0` returns `passed`;
- fake exit `1` returns `failed`, `ok: false`, `complete: false`, and command exit `1`;
- static projection pass plus executable fail is not `verified_with_evidence`.

- [ ] **Step 2: Run failing host tests**

Run: `corepack pnpm test -- tests/conformance/hosts/p13-host-conformance.test.ts`

Expected: FAIL because current single-host CLI returns ok/complete true even with failed executable smoke.

- [ ] **Step 3: Implement shared host status derivation**

Move status rules into `conformanceStatus.ts`:
- missing executable -> `not_run`, diagnostic severity `warning`, no verified support;
- unavailable subcommand output -> `not_run`, diagnostic severity `warning`;
- executable run failure -> `failed`, diagnostic severity `error`;
- failed smoke makes `ok` and `complete` false;
- evidence IDs are required for `verified_with_evidence`.

- [ ] **Step 4: Wire CLI aggregation**

For `host conformance --host` and `--all`:
- use derived `ok`/`complete`;
- return exit `1` on failed executable smoke;
- keep missing executables as `not_run` with exact reasons and no evidence-backed claim.

- [ ] **Step 5: Run host tests**

Run: `corepack pnpm test -- tests/conformance/hosts/p8-hosts.test.ts tests/conformance/hosts/p13-host-conformance.test.ts tests/e2e/p11-product-lifecycle.test.ts`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/ucm-core/src/hosts packages/ucm-cli/src/index.ts tests/conformance/hosts tests/e2e/p11-product-lifecycle.test.ts
git commit -m "Correct host conformance status semantics"
```

---

### Task 5: Real Tarball/Install Package Doctor

**Files:**
- Create: `packages/ucm-core/src/package/inspectPackage.ts`
- Modify: `packages/ucm-core/src/index.ts`
- Modify: `packages/ucm-cli/src/index.ts`
- Modify: `tests/release/p12-release.test.ts`
- Create: `tests/release/p13-package-install.test.ts`
- Modify: `docs/release.md`

**Interfaces:**
- Produces: `inspectPackageArtifact(options): PackageInspectionResult`
- Produces: `runInstalledPackageSmoke(options): PackageSmokeResult`
- Consumes: `PUBLIC_SCHEMA_IDS`, package manifests, installed CLI/MCP entrypoints.

- [ ] **Step 1: Write failing package install tests**

Tests must:
- run `corepack pnpm pack --json --pack-destination <tmp>`;
- inspect the real tarball entries;
- install the tarball into a temp project;
- run installed CLI `schema list --json`;
- run installed MCP stdio `initialize` and `tools/list`;
- assert all required skills, schemas, manifests, bootstrap files, host profiles, CLI, MCP, README, changelog, and release docs are present;
- assert no `.albus`, `.Codex`, `.cowork-receipts`, `node_modules`, `coverage`, local absolute paths, or secret-looking fixture values are present.

- [ ] **Step 2: Run failing package tests**

Run: `corepack pnpm test -- tests/release/p13-package-install.test.ts`

Expected: FAIL because `doctor package` currently checks the checkout, not a tarball/install.

- [ ] **Step 3: Implement package inspector**

Implement `inspectPackage.ts` with:
- tarball entry listing through `tar -tf` or `npm pack --json` output;
- installed root inspection;
- bin executable mode checks;
- manifest reference resolution inside the inspected root;
- required packaged path checks for every plugin-critical asset;
- text scan for forbidden local/session paths.

- [ ] **Step 4: Wire CLI doctor package**

Support:
- `doctor package --json` builds/inspects current checkout pack output by default;
- `doctor package --tarball <path> --json` inspects an explicit tarball;
- `doctor package --installed-root <path> --json` inspects an installed root.

The command should fail if the inspected artifact is not release-sound.

- [ ] **Step 5: Run release tests**

Run: `corepack pnpm test -- tests/release/p12-release.test.ts tests/release/p13-package-install.test.ts`

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add packages/ucm-core/src/package packages/ucm-core/src/index.ts packages/ucm-cli/src/index.ts tests/release docs/release.md
git commit -m "Inspect installable package artifacts"
```

---

### Task 6: Documentation, Matrix, and Final Verification

**Files:**
- Modify: `docs/security.md`
- Modify: `docs/showcase.md`
- Modify: `docs/mcp.md`
- Modify: `docs/hosts.md`
- Modify: `docs/release.md`
- Modify: `docs/acceptance.md`
- Modify: `use-cases/showcase/live.yml`
- Modify: `use-cases/mcp/wrapper.yml`
- Modify: `use-cases/hosts/projections.yml`

**Interfaces:**
- Consumes: final behavior and verification outputs from Tasks 1-5.
- Produces: updated acceptance matrix and release notes matching reality.

- [ ] **Step 1: Update docs only to match proven behavior**

Docs must state:
- user approval requires trusted interactive CLI confirmation or future host token;
- MCP is request-only for user approval;
- generated plans are prepared material until run events exist;
- host `not_run` is not verified support;
- package doctor inspects installable artifacts.

- [ ] **Step 2: Update dogfood use cases**

Update use cases for:
- approval authority;
- generated-plan proof binding;
- MCP stdio parity;
- host pass/fail/not_run semantics;
- tarball/install package doctor.

- [ ] **Step 3: Run full verification**

Run serially:

```bash
corepack pnpm test
corepack pnpm typecheck
corepack pnpm build
corepack pnpm cli -- doctor package --json
corepack pnpm cli -- matrix validate --repo . --json
corepack pnpm cli -- matrix list --repo . --json
corepack pnpm pack --dry-run
git diff --check
```

Expected:
- all tests pass;
- typecheck/build pass;
- package doctor is complete with no diagnostics;
- project matrix remains complete and meaningful;
- dry-run package contains required assets and no forbidden local state;
- no whitespace errors.

- [ ] **Step 4: Commit**

```bash
git add docs use-cases
git commit -m "Document release blocker closure"
```

- [ ] **Step 5: Final history check**

Run:

```bash
git status --short
git log --oneline --decorate -8
```

Expected: clean tree with logical commits on `feature/p13-blocker-closure`.

---

## Self-Review

- Spec coverage: all five Albus blockers map to Tasks 1-5, with Task 6 covering docs/matrix/final acceptance.
- Placeholder scan: no forbidden placeholder markers or unspecified test steps remain.
- Type consistency: new module names and function names are introduced before use by later tasks.
- Scope check: the five fixes are related release-blocker closure work and are split into independently reviewable commits.
