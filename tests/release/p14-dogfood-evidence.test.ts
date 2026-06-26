import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { resolve } from "node:path";
import { beforeAll, describe, expect, test } from "vitest";

const repoRoot = resolve(import.meta.dirname, "../..");

beforeAll(() => {
  const result = spawnSync("corepack", ["pnpm", "build"], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  if (result.status !== 0) {
    throw new Error(result.stderr || result.stdout);
  }
}, 60_000);

describe("P14 v1 release dogfood evidence", () => {
  test("exposes v1 release rows in the living use-case matrix", () => {
    const listed = runCliJson(["matrix", "list", "--repo", repoRoot, "--json"]);

    expect(listed.status).toBe(0);
    expect((listed.payload.data.use_cases as Array<{ id: string }>).map((item) => item.id)).toEqual([
      "capsule.live_runner.scripted",
      "evidence.core.record",
      "hosts.projections.all",
      "hosts.projections.static_conformance",
      "matrix.core.mutate",
      "matrix.core.validate",
      "mcp.use_case_mutation.safe",
      "mcp.wrapper.parity",
      "migration.test_matrix.draft",
      "release.ci_gate.sequential",
      "release.package.installable_artifact",
      "showcase.live.user_signoff"
    ]);
  });

  test("commits mechanical dogfood proof without claiming user approval", () => {
    expect(existsSync(resolve(repoRoot, "demo-capsules", "v1-release-smoke.yml"))).toBe(true);

    const capsules = runCliJson(["capsule", "list", "--repo", repoRoot, "--json"]);
    expect(capsules.status).toBe(0);
    expect(capsules.payload.data.capsules).toEqual(
      expect.arrayContaining([
        expect.objectContaining({
          capsule_id: "capsule.v1.release_smoke",
          item_count: 1
        })
      ])
    );

    const evidence = runCliJson(["evidence", "status", "--repo", repoRoot, "--json"]);
    expect(evidence.status).toBe(0);
    expect(evidence.payload.data.integrity.state).toBe("clean");

    const targetIds = new Set<string>();
    for (const aggregate of evidence.payload.data.aggregates as Array<{ target_links: Array<{ use_case_id: string }> }>) {
      for (const link of aggregate.target_links) {
        targetIds.add(link.use_case_id);
      }
    }
    expect([...targetIds].sort()).toEqual(expect.arrayContaining([
      "capsule.live_runner.scripted",
      "hosts.projections.static_conformance",
      "matrix.core.mutate",
      "release.ci_gate.sequential",
      "release.package.installable_artifact"
    ]));

    const showcase = runCliJson([
      "showcase",
      "status",
      "--repo",
      repoRoot,
      "--run",
      "run.p14_v1_release_smoke_start",
      "--json"
    ]);
    expect(showcase.status).toBe(0);
    expect(showcase.payload.data).toMatchObject({
      execution_status: "completed",
      run_outcome: "passed",
      approval_state: "not_required",
      known_gaps: []
    });
    const runLedger = readFileSync(resolve(repoRoot, "showcase-runs", "run.p14_v1_release_smoke_start", "events.jsonl"), "utf8");
    expect(runLedger).not.toContain(repoRoot);
  });
});

function runCliJson(args: string[]) {
  const result = spawnSync("node", ["packages/ucm-cli/dist/index.js", ...args], {
    cwd: repoRoot,
    encoding: "utf8",
    env: { ...process.env, COREPACK_ENABLE_DOWNLOAD_PROMPT: "0" }
  });
  return {
    status: result.status,
    payload: result.stdout ? JSON.parse(result.stdout) : null,
    stderr: result.stderr
  };
}
