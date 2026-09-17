// The black-box oracle for capsule/runner.yml.
//
// This is the one place a demo capsule stops being prepared material and
// becomes a live, script-led showcase run: `capsule run --execute-commands`
// starts a real showcase run, executes command steps for real, and records
// every step into the showcase ledger. capsule-demos.test.ts covers the
// planning and safety boundary; this file covers what happens once a capsule
// is actually performed.
//
// Self-contained on purpose: a shared oracle file means one edit stales every
// row bound to it.
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, describe, expect, test } from "vitest";
import { runUcJson } from "../helpers/uc-binary";

const tempDirs: string[] = [];
afterAll(() => {
  for (const dir of tempDirs) rmSync(dir, { recursive: true, force: true });
});

const WORKSPACE_CONFIG = `schema_version: 1
workspace_id: probe
component_id: probe
data_root: .
use_cases_dir: use-cases
evidence_dir: evidence
demo_capsules_dir: demo-capsules
showcase_runs_dir: showcase-runs
default_workflow_mode: continuous
`;

// A single command-backed row, approval_policy mode: none, so a passing run
// never has a reason to require sign-off.
const MATRIX_COMMAND_ONLY = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.cmd
    title: Command row
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so a capsule can run a command against it.
    preconditions: [Nothing.]
    trigger: A capsule runs a command.
    scenarios:
      - id: probe.core.cmd.golden_runs
        kind: steps
        steps: [Run the command.]
        observable_outcomes: [The command succeeds.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

// A second row with an observation-only item, so its plan item can never
// receive a verdict without someone actually recording an observation.
const MATRIX_COMMAND_AND_OBSERVATION = `${MATRIX_COMMAND_ONLY}  - id: probe.core.obs
    title: Observation row
    lifecycle: active
    value_tier: core
    journey_role: alternate
    usage_frequency: common
    actor: agent
    intent: Exist so a capsule can leave a pending observation.
    preconditions: [Nothing.]
    trigger: A capsule asks for an observation.
    scenarios:
      - id: probe.core.obs.golden_runs
        kind: steps
        steps: [Observe it.]
        observable_outcomes: [It was seen.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

const CAPSULE_COMMAND_ONLY = `schema_version: 1
capsule_id: capsule.probe.scripted
title: Probe scripted
mode: showcase
description: Probe scripted capsule.
audience: reviewer
timebox_seconds: 600
items:
  - use_case_id: probe.core.cmd
    scenario_ids: [probe.core.cmd.golden_runs]
    runbook:
      - kind: command
        executable: node
        argv: ["-e", "console.log('hi')"]
        working_directory: "."
        expected_exit_codes: [0]
permissions:
  command_execution: true
`;

const CAPSULE_COMMAND_AND_OBSERVATION = `schema_version: 1
capsule_id: capsule.probe.scripted
title: Probe scripted with a pending observation
mode: showcase
description: Probe scripted capsule with one command item and one observation-only item.
audience: reviewer
timebox_seconds: 600
items:
  - use_case_id: probe.core.cmd
    scenario_ids: [probe.core.cmd.golden_runs]
    runbook:
      - kind: command
        executable: node
        argv: ["-e", "console.log('hi')"]
        working_directory: "."
        expected_exit_codes: [0]
  - use_case_id: probe.core.obs
    scenario_ids: [probe.core.obs.golden_runs]
    runbook:
      - kind: observation
        text: Confirm you saw it.
permissions:
  command_execution: true
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(matrix: string, capsule: string): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-capsule-runner-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  mkdirSync(join(dir, "demo-capsules"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), matrix);
  writeFileSync(join(dir, "demo-capsules", "probe.yml"), capsule);
  return { dir, env };
}

function uc(workspace: Workspace, args: string[]) {
  const [command, sub, ...rest] = args;
  return runUcJson([command, sub, "--repo", ".", ...rest], { cwd: workspace.dir, env: workspace.env });
}

interface RunStatus {
  execution_status: string;
  run_outcome: string;
  approval_state: string;
}

interface RunResultData {
  outcome: string;
  complete: boolean;
  run_id: string;
  events_written: string[];
  pending_steps: Array<{ use_case_id: string; reason: string }>;
  status: RunStatus | null;
}

/** The event types recorded in a run's own showcase-runs ledger, in order. */
function ledgerEventTypes(workspace: Workspace, runId: string): string[] {
  const raw = readFileSync(join(workspace.dir, "showcase-runs", runId, "events.jsonl"), "utf8");
  return raw
    .trim()
    .split("\n")
    .map((line) => (JSON.parse(line) as { event_type: string }).event_type);
}

//: @use-case:capsule.live_runner.scripted#blackbox
describe("capsule.live_runner.scripted", () => {
  // golden_cli. Running the capsule with --execute-commands and a stable
  // idempotency key performs a real showcase run: it starts the run from the
  // capsule's plan, executes the command for real, and records the whole
  // sequence — start, the command action, its observation, its verdict, and
  // the finish — as the showcase ledger's own events, in order.
  test("running a command-backed capsule records a full run_started..run_finished ledger and passes", () => {
    const workspace = makeWorkspace(MATRIX_COMMAND_ONLY, CAPSULE_COMMAND_ONLY);

    const { envelope } = uc(workspace, [
      "capsule", "run", "--capsule", "capsule.probe.scripted", "--execute-commands", "--idempotency-key", "runner-golden"
    ]);
    const data = envelope.data as unknown as RunResultData;

    expect(envelope.ok).toBe(true);
    expect(data.complete).toBe(true);
    expect(data.status?.execution_status).toBe("completed");
    expect(data.status?.run_outcome).toBe("passed");
    expect(ledgerEventTypes(workspace, data.run_id)).toEqual([
      "run_started",
      "action_recorded",
      "observation_recorded",
      "verdict_recorded",
      "run_finished"
    ]);
  });

  // bad_pending_observations_block_the_finish. A second item needs a runtime
  // observation that nothing in this run ever supplies. `capsule run` itself
  // must not silently call the run finished and passed — and even an explicit
  // `showcase finish` must not report it as passed while that observation is
  // still outstanding.
  test("a run with an unresolved observation never reports passed, even when explicitly finished", () => {
    const workspace = makeWorkspace(MATRIX_COMMAND_AND_OBSERVATION, CAPSULE_COMMAND_AND_OBSERVATION);

    const { envelope } = uc(workspace, [
      "capsule", "run", "--capsule", "capsule.probe.scripted", "--execute-commands", "--idempotency-key", "runner-pending"
    ]);
    const data = envelope.data as unknown as RunResultData;

    expect(data.complete, "the run cannot be complete while an observation is outstanding").toBe(false);
    expect(data.pending_steps).toContainEqual(
      expect.objectContaining({ use_case_id: "probe.core.obs", reason: "runtime_observation_required" })
    );
    expect(data.status?.execution_status, "capsule run does not auto-finish a run with pending steps").not.toBe(
      "completed"
    );

    const finish = uc(workspace, ["showcase", "finish", "--run", data.run_id]);
    const finishStatus = (finish.envelope.data as { status: RunStatus }).status;
    expect(finishStatus.run_outcome, "finishing early never manufactures a passed outcome").not.toBe("passed");
  });

  // edge_no_user_approval_unless_the_row_requires_it. The selected row's
  // approval_policy is mode: none, so a passing scripted run must reach
  // approval_state "not_required" on its own — nothing in this test ever
  // calls `showcase approve`.
  test("a passing run never records user approval for a row that does not require it", () => {
    const workspace = makeWorkspace(MATRIX_COMMAND_ONLY, CAPSULE_COMMAND_ONLY);

    const { envelope } = uc(workspace, [
      "capsule", "run", "--capsule", "capsule.probe.scripted", "--execute-commands", "--idempotency-key", "runner-approval"
    ]);
    const data = envelope.data as unknown as RunResultData;

    expect(data.status?.run_outcome).toBe("passed");
    expect(data.status?.approval_state).toBe("not_required");
  });
});
//: @use-case:end capsule.live_runner.scripted#blackbox
