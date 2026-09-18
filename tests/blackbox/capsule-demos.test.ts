// The black-box oracle for capsule/demos.yml.
//
// A demo capsule is prepared material: a YAML file that names use-case and
// scenario ids and a runbook to perform them with. The five rows here draw one
// line, over and over, in different ways: a capsule is never itself proof.
// Planning it, validating it, even inspecting it never records an event —
// only a live run (capsule.live_runner, covered in capsule-runner.test.ts)
// does that. These tests check the boundary from the CLI side: what a capsule
// resolves to, what it refuses, and what never changes just because a capsule
// exists.
//
// Self-contained on purpose: a shared oracle file means one edit stales every
// row bound to it.
import { existsSync, mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
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

// One active row a capsule can reference. Reused verbatim (or lightly edited)
// by most scenarios below.
const MATRIX_ALPHA = `schema_version: 1
feature:
  id: probe.core
  name: Probe
  summary: Probe.
use_cases:
  - id: probe.core.alpha
    title: Alpha
    lifecycle: active
    value_tier: core
    journey_role: golden
    usage_frequency: common
    actor: agent
    intent: Exist so a capsule can reference it.
    preconditions: [Nothing.]
    trigger: A capsule references it.
    scenarios:
      - id: probe.core.alpha.golden_runs
        kind: steps
        steps: [Do it.]
        observable_outcomes: [It works.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`;

interface Workspace {
  dir: string;
  env: Record<string, string>;
}

function makeWorkspace(matrix: string = MATRIX_ALPHA): Workspace {
  const dir = mkdtempSync(join(tmpdir(), "uc-capsule-demos-"));
  tempDirs.push(dir);
  const env = { UC_RUN_KEY_FILE: join(dir, "machine", "run-key") };
  mkdirSync(join(dir, "use-cases"), { recursive: true });
  writeFileSync(join(dir, "use-cases.yml"), WORKSPACE_CONFIG);
  writeFileSync(join(dir, "use-cases", "probe.yml"), matrix);
  return { dir, env };
}

function writeCapsule(workspace: Workspace, contents: string, filename = "probe.yml"): void {
  mkdirSync(join(workspace.dir, "demo-capsules"), { recursive: true });
  writeFileSync(join(workspace.dir, "demo-capsules", filename), contents);
}

function uc(workspace: Workspace, args: string[], extraEnv: Record<string, string> = {}) {
  const [command, sub, ...rest] = args;
  return runUcJson([command, sub, "--repo", ".", ...rest], {
    cwd: workspace.dir,
    env: { ...workspace.env, ...extraEnv }
  });
}

interface PlanItem {
  use_case_id: string;
  use_case_title: string;
  scenario_ids: string[];
  use_case_content_hash: string;
  resolved_steps: string[];
  known_gaps: Array<{ code: string; severity: string }>;
}

interface PlanResultData {
  outcome: string;
  plan_result: {
    outcome: string;
    plan: { prepared_not_performed: boolean; plan_content_hash: string; selected_items: PlanItem[] } | null;
    candidate_summary: { considered: number; eligible: number; selected: number; excluded_by_reason: Record<string, number> };
  };
  diagnostics: Array<{ code: string }>;
}

interface RunResultData {
  outcome: string;
  complete: boolean;
  run_id: string | null;
  events_written: string[];
  pending_steps: Array<{ use_case_id: string; reason: string }>;
  command_results: Array<{ stdout: string; stderr: string; exit_code: number | null; matched_expected_exit_code: boolean }>;
  status: { execution_status: string; run_outcome: string; approval_state: string } | null;
  diagnostics: Array<{ code: string }>;
}

interface MatrixStatusData {
  evidence: { ledgers: unknown[]; counts: { aggregates_active: number } };
}

describe("capsule.demos.persisted_smoke_runbook", () => {
  const CAPSULE = `schema_version: 1
capsule_id: capsule.probe.smoke
title: Probe smoke
mode: showcase
description: Probe smoke capsule.
audience: reviewer
timebox_seconds: 600
items:
  - use_case_id: probe.core.alpha
    scenario_ids: [probe.core.alpha.golden_runs]
    runbook:
      - kind: instruction
        text: Do the thing.
      - kind: observation
        text: Confirm it worked.
permissions:
  command_execution: false
`;

  // golden_plan. Validate the capsule file, then generate a plan from it, and
  // confirm the referenced use-case and scenario ids actually resolve against
  // the matrix rather than just being strings sitting in a YAML file.
  test("a persisted capsule validates and plans, resolving its referenced ids against the matrix", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);

    const validated = uc(workspace, ["capsule", "validate"]);
    expect(validated.envelope.ok).toBe(true);
    expect((validated.envelope.data as { complete: boolean }).complete).toBe(true);

    const { envelope } = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const data = envelope.data as unknown as PlanResultData;
    expect(envelope.ok).toBe(true);
    expect(data.plan_result.outcome).toBe("generated");
    const item = data.plan_result.plan?.selected_items[0];
    expect(item?.use_case_id).toBe("probe.core.alpha");
    expect(item?.scenario_ids).toEqual(["probe.core.alpha.golden_runs"]);
  });

  // bad_a_capsule_is_not_proof. Validating and planning a capsule reads and
  // reasons about it, but records nothing. `matrix status` is the CLI's own
  // composed view of proof, so if a capsule counted as evidence it would show
  // up there.
  test("validating and planning a capsule records no evidence, so it is never mistaken for proof", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);

    uc(workspace, ["capsule", "validate"]);
    uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);

    const { envelope } = uc(workspace, ["matrix", "status"]);
    const data = envelope.data as unknown as MatrixStatusData;
    expect(data.evidence.ledgers, "no showcase or evidence ledger was ever written").toEqual([]);
    expect(data.evidence.counts.aggregates_active).toBe(0);
  });

  // edge_the_same_capsule_serves_repeated_demos. Planning is a pure read: the
  // same capsule against an unchanged matrix produces the identical plan, so
  // an agent never has to reselect rows by hand for a repeat demo.
  test("planning the same capsule twice without changes produces an identical plan", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);

    const first = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const second = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const firstData = first.envelope.data as unknown as PlanResultData;
    const secondData = second.envelope.data as unknown as PlanResultData;

    expect(secondData.plan_result.plan?.plan_content_hash).toBe(firstData.plan_result.plan?.plan_content_hash);
    expect(secondData.plan_result.plan).toEqual(firstData.plan_result.plan);
  });
});

describe("capsule.demos.adhoc_release_demo", () => {
  // golden_start. An ad hoc demo has no capsule file at all: the selection is
  // made on the command line and `run_started` is the audit trail of what was
  // actually selected.
  test("an ad hoc showcase run records its normalized plan in run_started", () => {
    const workspace = makeWorkspace();

    const { envelope } = uc(workspace, [
      "showcase", "start", "--adhoc", "--select", "probe.core.alpha", "--idempotency-key", "adhoc-golden"
    ]);
    const data = envelope.data as {
      event: { event_type: string; payload: { plan: { selected_items: Array<{ use_case_id: string }> } } };
    };

    expect(envelope.ok).toBe(true);
    expect(data.event.event_type).toBe("run_started");
    expect(data.event.payload.plan.selected_items).toHaveLength(1);
    expect(data.event.payload.plan.selected_items[0].use_case_id).toBe("probe.core.alpha");
  });

  // edge_no_capsule_file_is_left_behind. The whole point of "ad hoc" is that
  // nothing persists beyond the run's own event ledger.
  test("an ad hoc run leaves no demo-capsules directory behind", () => {
    const workspace = makeWorkspace();

    uc(workspace, ["showcase", "start", "--adhoc", "--select", "probe.core.alpha", "--idempotency-key", "adhoc-edge"]);

    expect(existsSync(join(workspace.dir, "demo-capsules")), "no capsule file was created").toBe(false);
  });
});

describe("capsule.demos.runner_command_safety", () => {
  function commandCapsule(step: Record<string, unknown>, permitted: boolean): string {
    return [
      "schema_version: 1",
      "capsule_id: capsule.probe.cmd",
      "title: Probe command",
      "mode: showcase",
      "description: Probe command capsule.",
      "audience: reviewer",
      "timebox_seconds: 600",
      "items:",
      "  - use_case_id: probe.core.alpha",
      "    scenario_ids: [probe.core.alpha.golden_runs]",
      "    runbook:",
      `      - kind: command`,
      `        executable: ${JSON.stringify(step.executable)}`,
      `        argv: ${JSON.stringify(step.argv)}`,
      `        working_directory: ${JSON.stringify(step.working_directory)}`,
      `        expected_exit_codes: ${JSON.stringify(step.expected_exit_codes)}`,
      "permissions:",
      `  command_execution: ${permitted}`,
      ""
    ].join("\n");
  }

  // golden_command. Three properties at once, all only checkable by actually
  // running a command: it is not handed to a shell (a shell metacharacter is
  // passed through literally, not expanded), it runs from a working directory
  // resolved inside the repo, and its output is captured into the record.
  test("a permitted command runs without a shell, from inside the repo, with its output recorded", () => {
    const workspace = makeWorkspace();
    writeCapsule(
      workspace,
      commandCapsule(
        {
          executable: "node",
          argv: ["-e", "console.log(process.argv[1]); console.log(process.cwd())", "$(echo pwned)"],
          working_directory: ".",
          expected_exit_codes: [0]
        },
        true
      )
    );

    const { envelope } = uc(workspace, [
      "capsule", "run", "--capsule", "capsule.probe.cmd", "--execute-commands", "--idempotency-key", "safety-golden"
    ]);
    const data = envelope.data as unknown as RunResultData;

    expect(envelope.ok).toBe(true);
    const [result] = data.command_results;
    const [firstLine, secondLine] = result.stdout.trim().split("\n");
    expect(firstLine, "a shell would have expanded $(...); no shell means it comes through literally").toBe(
      "$(echo pwned)"
    );
    expect(secondLine).toBe(realpathSync(workspace.dir));
    expect(result.matched_expected_exit_code).toBe(true);
  });

  // bad_unsafe_commands_do_not_run_by_default. Permission is required at BOTH
  // levels: the capsule must permit command execution, and the caller must
  // separately opt in with --execute-commands. Missing either one refuses to
  // run the command — checked here as two separate refusals.
  test("a command step needs permission from the capsule and a request from the caller, or it does not run", () => {
    const permittedWorkspace = makeWorkspace();
    writeCapsule(
      permittedWorkspace,
      commandCapsule({ executable: "node", argv: ["-e", "1"], working_directory: ".", expected_exit_codes: [0] }, true)
    );
    // The capsule permits it, but the caller never asked for --execute-commands.
    const notRequested = uc(permittedWorkspace, [
      "capsule", "run", "--capsule", "capsule.probe.cmd", "--idempotency-key", "safety-not-requested"
    ]);
    const notRequestedData = notRequested.envelope.data as unknown as RunResultData;
    expect(notRequestedData.command_results, "the command never ran").toEqual([]);
    expect(notRequestedData.pending_steps).toContainEqual(
      expect.objectContaining({ use_case_id: "probe.core.alpha", reason: "command_execution_not_requested" })
    );
    expect(notRequestedData.status?.execution_status).not.toBe("completed");

    const unpermittedWorkspace = makeWorkspace();
    writeCapsule(
      unpermittedWorkspace,
      commandCapsule({ executable: "node", argv: ["-e", "1"], working_directory: ".", expected_exit_codes: [0] }, false)
    );
    // The caller asks for --execute-commands, but the capsule itself never permitted it.
    const notPermitted = uc(unpermittedWorkspace, [
      "capsule", "run", "--capsule", "capsule.probe.cmd", "--execute-commands", "--idempotency-key", "safety-not-permitted"
    ]);
    expect(notPermitted.status).toBe(1);
    expect(notPermitted.envelope.ok).toBe(false);
    const notPermittedData = notPermitted.envelope.data as unknown as RunResultData;
    expect(notPermittedData.outcome).toBe("blocked");
    expect(notPermittedData.run_id, "a blocked run never starts").toBeNull();
    expect(notPermittedData.diagnostics.map((d) => d.code)).toContain("capsule.command_execution_not_permitted");
  });

  // bad_working_directory_outside_the_repo. A capsule cannot point a command
  // at a working directory outside the workspace, no matter what permissions
  // it carries.
  test("a working directory outside the repo is refused rather than resolved", () => {
    const workspace = makeWorkspace();
    writeCapsule(
      workspace,
      commandCapsule({ executable: "node", argv: ["-e", "1"], working_directory: "/tmp", expected_exit_codes: [0] }, true)
    );

    const { envelope, status } = uc(workspace, [
      "capsule", "run", "--capsule", "capsule.probe.cmd", "--execute-commands", "--idempotency-key", "safety-escape"
    ]);
    const data = envelope.data as unknown as RunResultData;

    expect(status, "a cwd escape maps to its own exit code").toBe(4);
    expect(envelope.ok).toBe(false);
    expect(data.outcome).toBe("blocked");
    expect(data.run_id).toBeNull();
    expect(data.diagnostics.map((d) => d.code)).toContain("capsule.command_cwd_escape");
  });

  // edge_output_is_bounded_and_local_state_does_not_leak. Two guarantees at
  // once: captured output cannot grow without bound, and the command does not
  // inherit the caller's whole environment (only a small, explicit allowlist),
  // so a secret sitting in the agent's own env cannot leak through a demo.
  test("captured command output is truncated and the command does not inherit arbitrary local environment variables", () => {
    const workspace = makeWorkspace();
    writeCapsule(
      workspace,
      commandCapsule(
        {
          executable: "node",
          argv: [
            "-e",
            "process.stdout.write('SECRET_LOCAL_VAR=' + (process.env.SECRET_LOCAL_VAR || 'undefined') + '\\n'); process.stdout.write('A'.repeat(50000))"
          ],
          working_directory: ".",
          expected_exit_codes: [0]
        },
        true
      )
    );

    const { envelope } = uc(
      workspace,
      ["capsule", "run", "--capsule", "capsule.probe.cmd", "--execute-commands", "--idempotency-key", "safety-bounded"],
      { SECRET_LOCAL_VAR: "leaked-secret-value" }
    );
    const data = envelope.data as unknown as RunResultData;
    const [result] = data.command_results;

    expect(result.stdout.startsWith("SECRET_LOCAL_VAR=undefined")).toBe(true);
    expect(result.stdout, "the local env var never reached the command").not.toContain("leaked-secret-value");
    expect(result.stdout.endsWith("[truncated]"), "output beyond the cap is truncated, not silently grown").toBe(true);
    expect(result.stdout.length).toBeLessThan(50000);
  });
});

describe("capsule.demos.stale_reference_warning", () => {
  const CAPSULE = `schema_version: 1
capsule_id: capsule.probe.smoke
title: Probe smoke
mode: showcase
description: Probe smoke capsule.
audience: reviewer
timebox_seconds: 600
items:
  - use_case_id: probe.core.alpha
    scenario_ids: [probe.core.alpha.golden_runs]
    runbook:
      - kind: instruction
        text: Do the thing.
      - kind: observation
        text: Confirm it worked.
permissions:
  command_execution: false
`;

  // golden_validate. Whatever a capsule has to report about its references,
  // it reports through `capsule plan` — which only reads and reasons, and
  // never runs anything — before `capsule run` is ever invoked. This test
  // grows the matrix (a sibling row is added, as happens over the life of a
  // real feature file) and confirms the capsule keeps planning cleanly from
  // that read-only path.
  //
  // NOTE: the row's own step text says "validate the capsule", but
  // `capsule validate` only checks a capsule file's own schema — it does not
  // check whether the use-case/scenario ids it references still resolve
  // (confirmed empirically: validate stays ok/diagnostics-empty even when a
  // referenced row is later removed). Reference resolution is reported by
  // `capsule plan`, which is what this test exercises instead.
  test("capsule plan reports reference health without ever running the capsule", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);
    const grownMatrix = MATRIX_ALPHA.replace(
      "verification_policy:\n      mode: none\n    approval_policy:\n      mode: none\n",
      `verification_policy:
      mode: none
    approval_policy:
      mode: none
  - id: probe.core.beta
    title: Beta
    lifecycle: active
    value_tier: supporting
    journey_role: alternate
    usage_frequency: rare
    actor: agent
    intent: A sibling row added later, unrelated to the capsule.
    preconditions: [Nothing.]
    trigger: Nothing.
    scenarios:
      - id: probe.core.beta.golden_runs
        kind: steps
        steps: [Do it.]
        observable_outcomes: [It works.]
    observable_outcomes: [It exists.]
    host_applicability:
      - host_surface: codex.cli
        supported: true
    verification_policy:
      mode: none
    approval_policy:
      mode: none
`
    );
    writeFileSync(join(workspace.dir, "use-cases", "probe.yml"), grownMatrix);

    const { envelope } = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const data = envelope.data as unknown as PlanResultData;

    expect(envelope.ok).toBe(true);
    expect(data.plan_result.outcome).toBe("generated");
    expect(data.diagnostics).toEqual([]);
  });

  // bad_missing_row_reference. Remove the row a capsule references (the
  // matrix must stay schema-complete, so a sibling row takes its place) and
  // confirm the capsule is reported as broken rather than performed.
  test("a capsule pointing at a missing row is reported as unrunnable rather than run", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);
    const rowRemoved = MATRIX_ALPHA.replace(/probe\.core\.alpha/g, "probe.core.other");
    writeFileSync(join(workspace.dir, "use-cases", "probe.yml"), rowRemoved);

    const planned = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const planData = planned.envelope.data as unknown as PlanResultData;
    expect(planData.plan_result.outcome).toBe("no_eligible_items");
    expect(planData.plan_result.plan).toBeNull();
    expect(planData.plan_result.candidate_summary.eligible).toBe(0);

    const run = uc(workspace, ["capsule", "run", "--capsule", "capsule.probe.smoke", "--idempotency-key", "stale-missing"]);
    const runData = run.envelope.data as unknown as RunResultData;
    expect(run.envelope.ok, "a capsule that cannot resolve its row is never run").toBe(false);
    expect(runData.outcome).toBe("blocked");
    expect(runData.run_id).toBeNull();
    expect(runData.events_written).toEqual([]);
  });

  // edge_semantically_changed_row. A capsule stores only ids, never a copy of
  // the row's content, so it cannot drift: every plan re-resolves the row's
  // CURRENT title, steps and content hash from the matrix as it stands right
  // now.
  test("changing a referenced row's meaning is reflected immediately, with no stale cached content", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);
    const before = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const beforeItem = (before.envelope.data as unknown as PlanResultData).plan_result.plan?.selected_items[0];

    const changed = MATRIX_ALPHA
      .replace("title: Alpha", "title: Alpha renamed")
      .replace("steps: [Do it.]", "steps: [Do something entirely different now.]");
    writeFileSync(join(workspace.dir, "use-cases", "probe.yml"), changed);

    const after = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const afterItem = (after.envelope.data as unknown as PlanResultData).plan_result.plan?.selected_items[0];

    expect(afterItem?.use_case_title).toBe("Alpha renamed");
    expect(afterItem?.resolved_steps).toEqual(["Do something entirely different now."]);
    expect(afterItem?.use_case_content_hash, "content hash moves with the row's real content").not.toBe(
      beforeItem?.use_case_content_hash
    );
  });
});

describe("capsule.demos.runbook_not_proof", () => {
  const CAPSULE = `schema_version: 1
capsule_id: capsule.probe.smoke
title: Probe smoke
mode: showcase
description: Probe smoke capsule.
audience: reviewer
timebox_seconds: 600
items:
  - use_case_id: probe.core.alpha
    scenario_ids: [probe.core.alpha.golden_runs]
    runbook:
      - kind: instruction
        text: Do the thing.
      - kind: observation
        text: Confirm it worked.
permissions:
  command_execution: false
`;

  // golden_guard. The plan describes itself, explicitly, as prepared and not
  // performed — it is not left for the reader to infer.
  test("a generated capsule plan describes itself as prepared, not performed", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);

    const { envelope } = uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    const data = envelope.data as unknown as PlanResultData;
    const plan = data.plan_result.plan;

    expect(plan?.prepared_not_performed).toBe(true);
    expect(plan?.selected_items[0].known_gaps).toContainEqual(
      expect.objectContaining({ code: "prepared_not_performed", severity: "info" })
    );
  });

  // bad_a_capsule_never_becomes_evidence. Validate it, plan it, inspect it —
  // never run it — then ask the workspace's own composed proof view whether
  // anything counts. It must not.
  test("a capsule that is only validated and planned never counts toward proof or readiness", () => {
    const workspace = makeWorkspace();
    writeCapsule(workspace, CAPSULE);

    uc(workspace, ["capsule", "validate"]);
    uc(workspace, ["capsule", "plan", "--capsule", "capsule.probe.smoke"]);
    uc(workspace, ["capsule", "list"]);

    const { envelope } = uc(workspace, ["matrix", "status"]);
    const data = envelope.data as unknown as MatrixStatusData;
    expect(data.evidence.counts.aggregates_active, "no showcase run event was ever recorded").toBe(0);
    expect(data.evidence.ledgers).toEqual([]);
  });
});
