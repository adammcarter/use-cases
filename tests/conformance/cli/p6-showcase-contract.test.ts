import { spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { describe, expect, test } from "vitest";
import { validateBySchemaId } from "../../../packages/ucm-core/src/schema/index.js";

const repoRoot = resolve(import.meta.dirname, "../../..");

function run(command: string, args: string[]) {
  return spawnSync(command, args, {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
}

function runCli(args: string[]) {
  return run("node", ["packages/ucm-cli/dist/index.js", ...args]);
}

function requireSuccess(result: ReturnType<typeof run>) {
  if (result.status !== 0) {
    throw new Error(
      [
        `command failed with status ${result.status}`,
        `stdout:\n${result.stdout}`,
        `stderr:\n${result.stderr}`
      ].join("\n")
    );
  }
}

describe("P6 showcase CLI contract", () => {
  test("validates, lists, and plans persisted demo capsules", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");

    const validate = runCli(["capsule", "validate", "--repo", workspaceRoot, "--json"]);
    requireSuccess(validate);
    expect(JSON.parse(validate.stdout)).toMatchObject({
      command: "capsule.validate",
      ok: true,
      data: {
        complete: true,
        capsules: [expect.objectContaining({ capsule: expect.objectContaining({ capsule_id: "capsule.showcase.golden" }) })]
      }
    });

    const list = runCli(["capsule", "list", "--repo", workspaceRoot, "--json"]);
    requireSuccess(list);
    expect(JSON.parse(list.stdout)).toMatchObject({
      command: "capsule.list",
      ok: true,
      data: {
        capsules: [
          expect.objectContaining({
            capsule_id: "capsule.showcase.golden",
            mode: "showcase",
            item_count: 1
          })
        ]
      }
    });

    const plan = runCli(["capsule", "plan", "--repo", workspaceRoot, "--capsule", "capsule.showcase.golden", "--json"]);
    requireSuccess(plan);
    expect(JSON.parse(plan.stdout)).toMatchObject({
      command: "capsule.plan",
      ok: true,
      data: {
        outcome: "generated",
        capsule: expect.objectContaining({ capsule: expect.objectContaining({ capsule_id: "capsule.showcase.golden" }) }),
        plan_result: expect.objectContaining({ outcome: "generated" })
      }
    });
  });

  test("runs the live showcase flow without writing summary files", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");

    const start = runCli([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--adhoc",
      "--select",
      "showcase.live.golden",
      "--json"
    ]);
    requireSuccess(start);
    const startPayload = JSON.parse(start.stdout);
    expect(startPayload).toMatchObject({
      command: "showcase.start",
      ok: true,
      complete: true,
      data: {
        schema_version: 1,
        status: {
          execution_status: "prepared_not_performed",
          run_outcome: "prepared_not_performed"
        }
      }
    });
    expect(
      validateBySchemaId(
        "https://use-cases-plugin.dev/schemas/v1/showcase-start-result.schema.json",
        startPayload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });
    const runId = startPayload.data.run_id;

    const observation = runCli([
      "showcase",
      "record-observation",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--item",
      "item.showcase.live.golden",
      "--text",
      "Observed expected live behavior",
      "--json"
    ]);
    requireSuccess(observation);
    const observationPayload = JSON.parse(observation.stdout);
    expect(
      validateBySchemaId(
        "https://use-cases-plugin.dev/schemas/v1/showcase-event-append-result.schema.json",
        observationPayload.data
      )
    ).toMatchObject({ ok: true, diagnostics: [] });

    const verdict = runCli([
      "showcase",
      "record-verdict",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--item",
      "item.showcase.live.golden",
      "--verdict",
      "pass",
      "--actor",
      "user",
      "--json"
    ]);
    requireSuccess(verdict);

    const finish = runCli([
      "showcase",
      "finish",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--json"
    ]);
    requireSuccess(finish);
    expect(JSON.parse(finish.stdout)).toMatchObject({
      command: "showcase.finish",
      ok: true,
      complete: true,
      data: {
        status: {
          execution_status: "completed",
          run_outcome: "passed",
          approval_state: "pending"
        }
      }
    });

    const status = runCli([
      "showcase",
      "status",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--json"
    ]);
    requireSuccess(status);
    expect(JSON.parse(status.stdout)).toMatchObject({
      command: "showcase.status",
      ok: true,
      data: {
        execution_status: "completed",
        run_outcome: "passed",
        items: [
          {
            plan_item_id: "item.showcase.live.golden",
            verdict: "pass",
            verification_state: "requirements_met"
          }
        ]
      }
    });
    expect(summaryFiles(workspaceRoot)).toEqual([]);
  });

  test("starts a showcase from a generated plan file and rejects mutated plan content", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");

    const planResult = runCli([
      "plan",
      "showcase",
      "--repo",
      workspaceRoot,
      "--max-items",
      "1",
      "--host",
      "codex.cli",
      "--generated-at",
      "2026-06-25T12:00:00.000Z",
      "--json"
    ]);
    requireSuccess(planResult);
    const plan = JSON.parse(planResult.stdout).data.plan;
    const planPath = join(workspaceRoot, "presentation-plans", "generated-showcase.json");
    mkdirSync(join(workspaceRoot, "presentation-plans"), { recursive: true });
    writeFileSync(planPath, `${JSON.stringify(plan, null, 2)}\n`);

    const start = runCli([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--plan-file",
      planPath,
      "--idempotency-key",
      "p6:plan-file:start",
      "--json"
    ]);
    requireSuccess(start);
    const startPayload = JSON.parse(start.stdout);
    expect(startPayload).toMatchObject({
      command: "showcase.start",
      ok: true,
      data: {
        event: {
          payload: {
            plan_content_hash: plan.plan_content_hash,
            plan: expect.objectContaining({
              plan_content_hash: plan.plan_content_hash
            })
          }
        }
      }
    });

    const mutatedPath = join(workspaceRoot, "presentation-plans", "mutated-showcase.json");
    writeFileSync(mutatedPath, `${JSON.stringify({ ...plan, audience: "different reviewer" }, null, 2)}\n`);
    const mutated = runCli([
      "showcase",
      "start",
      "--repo",
      workspaceRoot,
      "--plan-file",
      mutatedPath,
      "--idempotency-key",
      "p6:plan-file:mutated",
      "--json"
    ]);

    expect(mutated.status).toBe(1);
    expect(JSON.parse(mutated.stdout)).toMatchObject({
      command: "showcase.start",
      ok: false,
      diagnostics: [expect.objectContaining({ code: "showcase_plan_hash_mismatch" })]
    });
  });

  test("refuses agent approval for a user-required showcase", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const startPayload = JSON.parse(
      runCli([
        "showcase",
        "start",
        "--repo",
        workspaceRoot,
        "--adhoc",
        "--select",
        "showcase.live.golden",
        "--json"
      ]).stdout
    );
    const runId = startPayload.data.run_id;
    const approval = runCli([
      "showcase",
      "approve",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--actor",
      "agent",
      "--statement",
      "Agent cannot approve user-required scope.",
      "--json"
    ]);

    expect(approval.status).toBe(1);
    expect(JSON.parse(approval.stdout)).toMatchObject({
      command: "showcase.approve",
      ok: false,
      complete: false,
      diagnostics: [
        expect.objectContaining({
          code: "showcase.user_required_approval"
        })
      ]
    });
  });

  test("refuses scripted user approval without mutating the showcase ledger", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const startPayload = JSON.parse(
      runCli([
        "showcase",
        "start",
        "--repo",
        workspaceRoot,
        "--adhoc",
        "--select",
        "showcase.live.golden",
        "--json"
      ]).stdout
    );
    const runId = startPayload.data.run_id;
    const planItemId = startPayload.data.status.items[0].plan_item_id;
    requireSuccess(
      runCli([
        "showcase",
        "record-observation",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        planItemId,
        "--text",
        "Observed expected live behavior",
        "--json"
      ])
    );
    requireSuccess(
      runCli([
        "showcase",
        "record-verdict",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        planItemId,
        "--verdict",
        "pass",
        "--json"
      ])
    );
    requireSuccess(runCli(["showcase", "finish", "--repo", workspaceRoot, "--run", runId, "--json"]));
    const ledgerPath = join(workspaceRoot, "showcase-runs", runId, "events.jsonl");
    const before = readFileSync(ledgerPath, "utf8");

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
      complete: false,
      diagnostics: [
        expect.objectContaining({
          code: "showcase.trusted_user_confirmation_required"
        })
      ]
    });
    expect(readFileSync(ledgerPath, "utf8")).toEqual(before);
  });

  test("supports lifecycle commands for pause, resume, decide, reject, and correct", () => {
    requireSuccess(run("corepack", ["pnpm", "build"]));
    const workspaceRoot = fixtureWorkspace("evidence-basic");
    const startPayload = JSON.parse(
      runCli([
        "showcase",
        "start",
        "--repo",
        workspaceRoot,
        "--adhoc",
        "--select",
        "showcase.live.golden",
        "--json"
      ]).stdout
    );
    const runId = startPayload.data.run_id;
    requireSuccess(
      runCli([
        "showcase",
        "record-observation",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--item",
        "item.showcase.live.golden",
        "--text",
        "Observed behavior needing discussion",
        "--json"
      ])
    );

    requireSuccess(
      runCli(["showcase", "pause", "--repo", workspaceRoot, "--run", runId, "--reason", "Pause to inspect output.", "--json"])
    );
    expect(
      JSON.parse(runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]).stdout)
    ).toMatchObject({ data: { execution_status: "paused" } });

    requireSuccess(
      runCli(["showcase", "resume", "--repo", workspaceRoot, "--run", runId, "--reason", "Inspection complete.", "--json"])
    );
    expect(
      JSON.parse(runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]).stdout)
    ).toMatchObject({ data: { execution_status: "running" } });

    const verdict = runCli([
      "showcase",
      "record-verdict",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--item",
      "item.showcase.live.golden",
      "--verdict",
      "fail",
      "--actor",
      "user",
      "--json"
    ]);
    requireSuccess(verdict);
    const verdictEventId = JSON.parse(verdict.stdout).data.event.event_id;

    requireSuccess(
      runCli([
        "showcase",
        "decide",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--verdict-event",
        verdictEventId,
        "--decision",
        "waive_with_reason",
        "--reason",
        "Accepted as a known demo gap.",
        "--actor",
        "user",
        "--json"
      ])
    );
    expect(
      JSON.parse(runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]).stdout)
    ).toMatchObject({ data: { run_outcome: "passed_with_waivers", items: [expect.objectContaining({ verdict: "waived" })] } });

    const finish = runCli(["showcase", "finish", "--repo", workspaceRoot, "--run", runId, "--json"]);
    expect(finish.status).toBe(1);
    expect(JSON.parse(finish.stdout)).toMatchObject({ command: "showcase.finish", ok: true });

    requireSuccess(
      runCli([
        "showcase",
        "correct",
        "--repo",
        workspaceRoot,
        "--run",
        runId,
        "--target-event",
        verdictEventId,
        "--verdict",
        "pass",
        "--reason",
        "Original failure was entered against the wrong criterion.",
        "--json"
      ])
    );

    const reject = runCli([
      "showcase",
      "reject",
      "--repo",
      workspaceRoot,
      "--run",
      runId,
      "--actor",
      "user",
      "--statement",
      "The corrected demo still needs follow-up.",
      "--json"
    ]);
    expect(reject.status).toBe(1);
    expect(JSON.parse(reject.stdout)).toMatchObject({
      command: "showcase.reject",
      ok: false,
      complete: false,
      diagnostics: [
        expect.objectContaining({
          code: "showcase.trusted_user_confirmation_required"
        })
      ]
    });
    expect(JSON.parse(runCli(["showcase", "status", "--repo", workspaceRoot, "--run", runId, "--json"]).stdout)).toMatchObject({
      data: {
        approval_state: "pending"
      }
    });
  });
});

function fixtureWorkspace(name: string): string {
  const workspaceRoot = mkdtempSync(join(tmpdir(), `use-cases-plugin-${name}-`));
  cpSync(join(repoRoot, "tests/fixtures/workspaces", name), workspaceRoot, { recursive: true });
  return workspaceRoot;
}

function summaryFiles(workspaceRoot: string): string[] {
  const root = join(workspaceRoot, "showcase-runs");
  if (!existsSync(root)) {
    return [];
  }
  return readdirSync(root, { recursive: true })
    .map((entry) => String(entry))
    .filter((entry) => /summary\\.(ya?ml|json)$/.test(entry));
}
